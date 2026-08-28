import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class OnDeviceTextClassifier {
  Interpreter? _interpreter;
  Map<String, int>? _vocab;
  List<double>? _idf;
  Map<int, String>? _labelMap;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // 1. 에셋 로드 및 TFLite 인터프리터 초기화
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/classifier_demo.tflite');
      
      final vocabStr = await rootBundle.loadString('assets/vocab.json');
      _vocab = Map<String, int>.from(json.decode(vocabStr));
      
      final idfStr = await rootBundle.loadString('assets/idf.json');
      _idf = List<double>.from(json.decode(idfStr));
      
      final labelMapStr = await rootBundle.loadString('assets/classifier_label_map.json');
      final tempMap = Map<String, dynamic>.from(json.decode(labelMapStr));
      _labelMap = tempMap.map((key, value) => MapEntry(int.parse(key), value.toString()));
      
      _isInitialized = true;
      print("🚀 [소생 앱] 온디바이스 분류 모델 로드 및 초기화 성공!");
    } catch (e) {
      print("❌ [소생 앱] 온디바이스 분류 모델 초기화 실패: $e");
    }
  }

  // 2. 한국어 텍스트 전처리 및 어절 TF-IDF 계산 (파이썬 clean_text & Vectorizer 이식)
  List<double> _preprocessToTfidf(String text) {
    if (!_isInitialized) return [];

    // 가. 특수문자 제거 및 소문자 정제
    final cleaned = text.replaceAll(RegExp(r'[^가-힣a-zA-Z0-9\s]'), ' ')
                        .replaceAll(RegExp(r'\s+'), ' ')
                        .trim()
                        .toLowerCase();
    
    // 나. 공백 기준 분리 후 단어별 Character N-gram (char_wb 방식) 추출
    final tokens = cleaned.split(' ');
    
    // 다. 단어 빈도(TF) 딕셔너리 구축 (Bi-gram, Tri-gram)
    final tfMap = <String, int>{};
    for (var word in tokens) {
      if (word.isEmpty) continue;
      final padded = ' $word '; // char_wb 는 단어 경계를 공백으로 패딩함
      
      // 2-grams
      for (int i = 0; i < padded.length - 1; i++) {
        final ngram = padded.substring(i, i + 2);
        if (_vocab!.containsKey(ngram)) {
          tfMap[ngram] = (tfMap[ngram] ?? 0) + 1;
        }
      }
      
      // 3-grams
      for (int i = 0; i < padded.length - 2; i++) {
        final ngram = padded.substring(i, i + 3);
        if (_vocab!.containsKey(ngram)) {
          tfMap[ngram] = (tfMap[ngram] ?? 0) + 1;
        }
      }
    }
    
    // 라. 단어 사전에 기반해 TF-IDF 가중치 연산
    final vocabSize = _vocab!.length;
    final tfidfVector = List<double>.filled(vocabSize, 0.0);
    
    tfMap.forEach((token, count) {
      final idx = _vocab![token]!;
      tfidfVector[idx] = count * _idf![idx];
    });
    
    // 마. L2 정규화 (L2 Normalization)
    double sumOfSquares = 0.0;
    for (var val in tfidfVector) {
      sumOfSquares += val * val;
    }
    double norm = sqrt(sumOfSquares);
    
    if (norm > 0) {
      for (int i = 0; i < vocabSize; i++) {
        tfidfVector[i] = tfidfVector[i] / norm;
      }
    }
    
    return tfidfVector;
  }

  // 3. TFLite 기반 추론 실행
  String classify(String rawText) {
    if (!_isInitialized || _interpreter == null) {
      return "MEMO";
    }

    // 전처리 완료된 1D 벡터 획득
    final tfidfVector = _preprocessToTfidf(rawText);
    if (tfidfVector.isEmpty) return "MEMO"; // 폴백 기본값

    // 모델 입력 형상에 맞춘 다차원 리스트 구성 [1, vocabSize]
    final input = [tfidfVector];
    
    // 출력 버퍼 준비: [1, 4] (4대 카테고리 확률값)
    final output = List<double>.filled(4, 0.0).reshape([1, 4]);
    
    // TFLite 실행
    _interpreter!.run(input, output);
    
    final probs = output[0] as List<double>;
    
    // 최댓값 인덱스(ArgMax) 찾기
    int maxIdx = 0;
    double maxProb = -1.0;
    for (int i = 0; i < probs.length; i++) {
      if (probs[i] > maxProb) {
        maxProb = probs[i];
        maxIdx = i;
      }
    }
    
    // 예측 라벨 리턴
    return _labelMap?[maxIdx] ?? "MEMO";
  }

  void dispose() {
    _interpreter?.close();
  }
}
