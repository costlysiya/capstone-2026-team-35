import 'package:flutter/material.dart';

class MaskingHelper {
  // Checks if a string contains any keywords (case-insensitive)
  static bool _containsKeywords(String text, List<String> keywords) {
    final lower = text.toLowerCase();
    return keywords.any((kw) => lower.contains(kw.toLowerCase()));
  }

  // Utility to mask digits in a string while keeping delimiters
  static String _maskDigits(String input) {
    return input.replaceAll(RegExp(r'\d'), '*');
  }

  // Utility to mask all characters except whitespace and specific symbols
  static String _maskAll(String input) {
    return input.replaceAll(RegExp(r'[^\s\-]'), '*');
  }

  // Check if a line is a candidate for MRZ (Machine Readable Zone)
  // OCR 인식 에러(소문자 판독, 기호/점 등 잡음 포함)에 유연하게 대처할 수 있도록 개선
  static bool _isCandidateMrz(String l) {
    final clean = l.replaceAll(RegExp(r'\s+'), '');
    if (clean.length < 30 || clean.length > 50) return false;

    // 알파벳(대소문자), 숫자, '<' 기호의 개수를 셉니다.
    final mrzCharsCount = clean.replaceAll(RegExp(r'[^A-Za-z0-9<]'), '').length;
    
    // 전체 글자 중 80% 이상이 MRZ 구성 문자라면 잡음이 섞인 MRZ 라인으로 판단합니다.
    return (mrzCharsCount / clean.length) >= 0.80;
  }

  static String mask(String text) {
    if (text.trim().isEmpty) return text;

    // 1. Identify document types by scanning the whole text
    // 여권 단어 외에도 하단 판독 영역의 '<' 패턴이 발견되면 여권으로 인식하도록 함
    final isPassport = _containsKeywords(text, ['여권', 'passport', '여권번호', 'passport no']) ||
        text.contains('<<<<') ||
        text.contains('<<<');
    
    final isLicense = _containsKeywords(text, ['운전면허증', 'driver’s license', "driver's license"]);
    final isRrnDoc = _containsKeywords(text, ['주민등록증']); // For address and dates of ID cards
    final isIdCard = isLicense || isRrnDoc;

    List<String> lines = text.split('\n');
    bool hasCardNumber = false;

    // --- Line-by-line processing ---
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // --- 주민등록번호 (RRN) ---
      // Pattern: \d{6}-[1-4]\d{6}
      final rrnRegex = RegExp(r'\d{6}-[1-4]\d{6}');
      line = line.replaceAllMapped(rrnRegex, (match) => '******-*******');

      // --- 카드 번호 (Card Number) ---
      // Pattern: \d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}
      final cardRegex = RegExp(r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b');
      if (cardRegex.hasMatch(line)) {
        hasCardNumber = true;
        line = line.replaceAllMapped(cardRegex, (match) => _maskDigits(match.group(0)!));
      }

      // --- CVC 관련 번호 (CVC / CVV / Security Code) ---
      // Pattern: (CVC|CVV|보안코드|보안\s?카드)\s*[:.\-]?\s*([0-9]{3})\b
      final cvcRegex = RegExp(
        r'(CVC|CVV|보안코드|보안\s?카드)\s*[:.\-]?\s*([0-9]{3})\b',
        caseSensitive: false,
      );
      line = line.replaceAllMapped(cvcRegex, (match) {
        final matchedString = match.group(0)!;
        final cvcVal = match.group(2)!;
        final maskedVal = '***';
        return matchedString.replaceFirst(cvcVal, maskedVal);
      });

      // --- 쿠폰 코드 (Coupon Code) ---
      // Pattern: \b\d{12}\b|\b\d{14}\b|\b\d{16}\b
      final couponRegex = RegExp(r'\b\d{12}\b|\b\d{14}\b|\b\d{16}\b');
      line = line.replaceAllMapped(couponRegex, (match) => _maskDigits(match.group(0)!));

      // --- 계좌번호 (Account Number) ---
      // Pattern: \b\d{3,6}-\d{2,6}-\d{3,6}\b
      final accountRegex = RegExp(r'\b\d{3,6}-\d{2,6}-\d{3,6}\b');
      line = line.replaceAllMapped(accountRegex, (match) => _maskDigits(match.group(0)!));

      // --- 휴대폰 번호 (Phone Number) ---
      // Pattern: 010-[0-9]{3,4}-[0-9]{4}|010[0-9]{7,8}
      final phoneRegex = RegExp(r'\b010-\d{3,4}-\d{4}\b|\b010\d{7,8}\b');
      line = line.replaceAllMapped(phoneRegex, (match) {
        final val = match.group(0)!;
        if (val.contains('-')) {
          final parts = val.split('-');
          return '010-${'*' * parts[1].length}-${'*' * parts[2].length}';
        } else {
          return '010${'*' * (val.length - 3)}';
        }
      });

      // --- 여권 관련 날짜 마스킹 (여권 정보 검출되었을 때만) ---
      if (isPassport) {
        // 여권 날짜 패턴
        final passportDateRegex = RegExp(
          r'\b\d{2}\s?\d{1,2}월\s?/\s?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\s?\d{4}\b',
          caseSensitive: false,
        );
        line = line.replaceAllMapped(passportDateRegex, (match) => _maskAll(match.group(0)!));
      }

      // --- 운전면허증 관련 마스킹 (키워드 탐지 시) ---
      if (isLicense) {
        final licenseRegex = RegExp(
          r'\b(\d{2}|서울|부산|경기|강원|충북|충남|전북|전남|경북|경남|제주|인천|대구|대전|울산|광주)[-\s]?\d{2}[-\s]?\d{6}[-\s]?\d{2}\b',
        );
        line = line.replaceAllMapped(licenseRegex, (match) => _maskDigits(match.group(0)!));
      }

      // --- 주민등록증/운전면허증인 경우 주소 및 날짜 마스킹 ---
      if (isIdCard) {
        // 주소 패턴
        final addressRegex = RegExp(
          r'\b(서울시|부산시|대구시|인천시|광주시|대전시|울산시|세종시|경기도|강원도|충청북도|충청남도|전라북도|전라남도|경상북도|경상남도|제주도|서울|부산|경기|강원|충북|충남|전북|전남|경북|경남|제주|인천|대구|대전|울산|광주)\s[가-힣0-9\s\-]+(시|군|구|읍|면|동|로|길|번지)\b',
        );
        line = line.replaceAllMapped(addressRegex, (match) => _maskAll(match.group(0)!));

        // 날짜 패턴
        final idDateRegex = RegExp(
          r'\b\d{4}\.\d{2}\.\d{2}\b|\b\d{4}\.\d{2}\.\d{2}\s*~\s*\d{4}\.\d{2}\.\d{2}\b',
        );
        line = line.replaceAllMapped(idDateRegex, (match) => _maskDigits(match.group(0)!));
      }

      lines[i] = line;
    }

    // --- 여권 맨 아래 판독 영역 (MRZ) 마스킹 (블록 매칭 방식) ---
    // 첫 번째 줄과 두 번째 줄이 서로 인접해 있는 특성을 활용하여 꺾쇠(<)가 한쪽에만 있어도 세트로 마스킹 처리합니다.
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_isCandidateMrz(line)) {
        bool shouldMask = line.contains('<');
        if (!shouldMask && i > 0 && _isCandidateMrz(lines[i - 1]) && lines[i - 1].contains('<')) {
          shouldMask = true;
        }
        if (!shouldMask && i < lines.length - 1 && _isCandidateMrz(lines[i + 1]) && lines[i + 1].contains('<')) {
          shouldMask = true;
        }
        if (shouldMask) {
          lines[i] = '*' * line.length;
        }
      }
    }

    // --- 여권 번호에 대한 세밀한 라인 범위 처리 및 전체 적용 (Fallback) ---
    if (isPassport) {
      final passportKeywords = ['여권', 'passport', '여권번호', 'passport no'];
      // 여권번호 패턴 (공백 포함 여부 대응 및 접두사 문자 범위 확장 A-Z)
      final passportNoRegex = RegExp(
        r'\b[A-Z]\s?[A-Z0-9]{8}\b',
        caseSensitive: false,
      );

      bool maskedByKeywordRange = false;

      // 1. 우선 사용자가 지정한 대로 키워드 근처 라인 마스킹을 수행합니다.
      for (int i = 0; i < lines.length; i++) {
        final currentLine = lines[i];
        bool hasKeyword = _containsKeywords(currentLine, passportKeywords);
        
        if (hasKeyword) {
          lines[i] = lines[i].replaceAllMapped(passportNoRegex, (match) {
            maskedByKeywordRange = true;
            return '*' * match.group(0)!.length;
          });
          
          if (i + 1 < lines.length) {
            lines[i + 1] = lines[i + 1].replaceAllMapped(passportNoRegex, (match) {
              maskedByKeywordRange = true;
              return '*' * match.group(0)!.length;
            });
          }
        }
      }

      // 2. 만약 키워드가 멀리 떨어져 있어서 위의 라인 범위 내에서 여권번호가 마스킹되지 않은 경우,
      //    이미 여권 문서임이 확정되었으므로 전체 문서에서 발견되는 여권번호 매칭 항목들을 강제로 마스킹합니다.
      if (!maskedByKeywordRange) {
        for (int i = 0; i < lines.length; i++) {
          lines[i] = lines[i].replaceAllMapped(passportNoRegex, (match) => '*' * match.group(0)!.length);
        }
      }
    }

    // --- 카드 번호 검출 시 근처 CVC 탐색 및 마스킹 ---
    if (hasCardNumber) {
      final standalone3DigitRegex = RegExp(r'\b\d{3}\b');
      for (int i = 0; i < lines.length; i++) {
        lines[i] = lines[i].replaceAllMapped(standalone3DigitRegex, (match) => '***');
      }
    }

    return lines.join('\n');
  }
}
