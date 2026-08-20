import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'ner_tokenizer.dart';

class NerClassifier {
  static final NerClassifier _instance = NerClassifier._internal();
  factory NerClassifier() => _instance;
  NerClassifier._internal();

  late Interpreter _interpreter;
  late NerTokenizer _tokenizer;
  late Map<String, String> _labelMap;
  bool _isLoaded = false;
  
  static const int maxSeqLength = 128;
  
  Future<void> initialize() async {
    // 1. 모델 로드
    final options = InterpreterOptions();
    _interpreter = await Interpreter.fromAsset('assets/ner_model.tflite', options: options);
    
    // 2. 토크나이저 초기화
    _tokenizer = NerTokenizer();
    await _tokenizer.loadVocab('assets/vocab.txt');
    
    // 3. 라벨 맵 로드
    final labelStr = await rootBundle.loadString('assets/label_map.json');
    final Map<String, dynamic> rawLabelMap = jsonDecode(labelStr);
    _labelMap = rawLabelMap.map((key, value) => MapEntry(key.toString(), value.toString()));
    
    _isLoaded = true;
    debugPrint('🚀 [소생 앱] 온디바이스 NER 마스킹 모델 로드 성공!');
  }
  
  String maskPii(String text) {
    if (!_isLoaded) return text;
    if (text.trim().isEmpty) return text;
    
    final tokenInfos = _tokenizer.tokenize(text, maxSeqLength: maxSeqLength);
    final inputIds = tokenInfos.map((e) => e.id).toList();
    
    // BERT 입력을 위한 텐서 준비: input_ids, attention_mask, token_type_ids
    var inputIdsTensor = [inputIds];
    var attentionMask = [inputIds.map((id) => id == 0 ? 0 : 1).toList()];
    var tokenTypeIds = [List.filled(maxSeqLength, 0)];
    
    // 출력 텐서 준비 [1, 128, NUM_CLASSES]
    final numClasses = _labelMap.length;
    var outputLogits = List.generate(1, (_) => List.generate(maxSeqLength, (_) => List.filled(numClasses, 0.0)));
    
    // 추론 실행
    _interpreter.runForMultipleInputs(
      [inputIdsTensor, attentionMask, tokenTypeIds],
      {0: outputLogits}
    );
    
    // 마스킹 처리할 오프셋 리스트 수집
    List<List<int>> rangesToMask = [];
    
    final logits = outputLogits[0];
    for (int i = 0; i < maxSeqLength; i++) {
      if (inputIds[i] == 0) continue; // 패딩 무시
      if (inputIds[i] == 2 || inputIds[i] == 3) continue; // CLS, SEP 무시
      
      final tokenLogits = logits[i];
      int maxIdx = 0;
      double maxVal = tokenLogits[0];
      for (int j = 1; j < numClasses; j++) {
        if (tokenLogits[j] > maxVal) {
          maxIdx = j;
          maxVal = tokenLogits[j];
        }
      }
      
      final label = _labelMap[maxIdx.toString()] ?? 'O';
      
      // 민감정보 라벨 (B-PER, I-PER, B-PHONE 등)
      if (label.startsWith('B-') || label.startsWith('I-')) {
        final entityType = label.substring(2);
        // 마스킹할 엔티티 종류 정의 (이름, 전화번호 등)
        if (['PER', 'PHONE', 'ORG', 'LOC'].contains(entityType)) {
          final start = tokenInfos[i].startOffset;
          final end = tokenInfos[i].endOffset;
          if (start != -1 && end != -1) {
            rangesToMask.add([start, end]);
          }
        }
      }
    }
    
    // 겹치거나 인접한 범위 병합
    if (rangesToMask.isEmpty) return text;
    
    rangesToMask.sort((a, b) => a[0].compareTo(b[0]));
    List<List<int>> mergedRanges = [rangesToMask[0]];
    
    for (int i = 1; i < rangesToMask.length; i++) {
      final current = rangesToMask[i];
      final previous = mergedRanges.last;
      
      if (current[0] <= previous[1] + 1) {
        previous[1] = current[1] > previous[1] ? current[1] : previous[1];
      } else {
        mergedRanges.add(current);
      }
    }
    
    // 역순으로 치환하여 인덱스 꼬임 방지
    String maskedText = text;
    for (int i = mergedRanges.length - 1; i >= 0; i--) {
      final start = mergedRanges[i][0];
      final end = mergedRanges[i][1];
      if (start >= 0 && end <= maskedText.length) {
        final maskStr = '*' * (end - start);
        maskedText = maskedText.replaceRange(start, end, maskStr);
      }
    }
    
    return maskedText;
  }
}
