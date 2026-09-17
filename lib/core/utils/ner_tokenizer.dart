import 'package:flutter/services.dart';

class TokenInfo {
  final int id;
  final int startOffset;
  final int endOffset;
  TokenInfo(this.id, this.startOffset, this.endOffset);
}

class NerTokenizer {
  late Map<String, int> _vocab;
  late int _unkTokenId;
  late int _clsTokenId;
  late int _sepTokenId;
  late int _padTokenId;

  bool _isLoaded = false;

  Future<void> loadVocab(String assetPath) async {
    final vocabStr = await rootBundle.loadString(assetPath);
    final lines = vocabStr.split('\n');

    _vocab = {};
    for (int i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        _vocab[token] = i;
      }
    }

    _unkTokenId = _vocab['[UNK]'] ?? 1;
    _clsTokenId = _vocab['[CLS]'] ?? 2;
    _sepTokenId = _vocab['[SEP]'] ?? 3;
    _padTokenId = _vocab['[PAD]'] ?? 0;

    _isLoaded = true;
  }

  List<TokenInfo> tokenize(String text, {int maxSeqLength = 128}) {
    if (!_isLoaded) throw Exception("Vocabulary not loaded.");

    List<TokenInfo> outputTokens = [];
    outputTokens.add(TokenInfo(_clsTokenId, 0, 0));

    // 정규식 매치를 사용해 공백과 단어 모두 순회하여 원래 인덱스를 유지
    final RegExp wordRegExp = RegExp(r'\S+');
    final matches = wordRegExp.allMatches(text);

    for (final match in matches) {
      final word = match.group(0)!;
      final start = match.start;

      final subTokens = _wordPieceTokenize(word, start);
      outputTokens.addAll(subTokens);
    }

    outputTokens.add(TokenInfo(_sepTokenId, text.length, text.length));

    if (outputTokens.length > maxSeqLength) {
      outputTokens = outputTokens.sublist(0, maxSeqLength);
      outputTokens[maxSeqLength - 1] = TokenInfo(
        _sepTokenId,
        text.length,
        text.length,
      );
    } else {
      while (outputTokens.length < maxSeqLength) {
        outputTokens.add(TokenInfo(_padTokenId, -1, -1));
      }
    }

    return outputTokens;
  }

  List<TokenInfo> _wordPieceTokenize(String word, int globalStart) {
    List<TokenInfo> outputTokens = [];
    bool isBad = false;
    int start = 0;

    while (start < word.length) {
      int end = word.length;
      int? curTokenId;

      while (start < end) {
        String substr = word.substring(start, end);
        if (start > 0) {
          substr = '##$substr';
        }

        if (_vocab.containsKey(substr)) {
          curTokenId = _vocab[substr];
          break;
        }
        end--;
      }

      if (curTokenId == null) {
        isBad = true;
        break;
      }

      outputTokens.add(
        TokenInfo(curTokenId, globalStart + start, globalStart + end),
      );
      start = end;
    }

    if (isBad) {
      return [TokenInfo(_unkTokenId, globalStart, globalStart + word.length)];
    }
    return outputTokens;
  }
}
