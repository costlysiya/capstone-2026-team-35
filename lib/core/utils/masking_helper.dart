
import 'package:flutter/foundation.dart';
import 'package:soseang_app/core/utils/ner_classifier.dart';
import 'package:soseang_app/core/utils/crypto_helper.dart';

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
    // OCR이 MRZ를 짧게 끊어서 인식할 수 있으므로 최소 길이를 10으로 대폭 낮춤
    if (clean.length < 10 || clean.length > 60) return false;

    // 알파벳(대소문자), 숫자, '<' 기호의 개수를 셉니다.
    final mrzCharsCount = clean.replaceAll(RegExp(r'[^A-Za-z0-9<]'), '').length;
    
    // 꺾쇠(<)가 2개 이상 포함되어 있거나, 전체 글자의 70% 이상이 MRZ 문자면 통과
    bool hasBrackets = clean.split('<').length - 1 >= 2;
    return hasBrackets || (mrzCharsCount / clean.length) >= 0.70;
  }

  // Removes system status bar (time, date, battery, carriers) at the very top of screenshots
  static String _cleanStatusBar(String text) {
    List<String> lines = text.split('\n');
    List<String> cleanedLines = [];

    final timePat = RegExp(r'\b\d{1,2}:\d{2}\b');
    final datePat = RegExp(r'\d{1,2}월\s?\d{1,2}일');
    final dayPat = RegExp(r'(월|화|수|목|금|토|일)요일');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      // 이미지 최상단 1~2개 행에 대해서만 상단바 여부를 판정하여 스킵합니다.
      if (i < 2) {
        bool isStatusBar = line.length < 35 && (
          timePat.hasMatch(line) || 
          datePat.hasMatch(line) || 
          dayPat.hasMatch(line) ||
          line.contains('SKT') ||
          line.contains('KT') ||
          line.contains('LGU') ||
          line.contains('U+')
        );
        if (isStatusBar) {
          continue; // 상단바 정보 제외
        }
      }
      cleanedLines.add(lines[i]);
    }
    return cleanedLines.join('\n');
  }

  static String _normalizeGifticon(String text) {
    final lines = text.split('\n');
    
    // 1. 유효기간 추출 (2자리 연도 YY.MM.DD 및 YY/MM/DD 포맷까지 대응)
    String expiryDate = "";
    final datePat1 = RegExp(r'\b(\d{2}|\d{4})[.\-/]\d{1,2}[.\-/]\d{1,2}\b');
    final datePat2 = RegExp(r'(\d{2}|\d{4})년\s?\d{1,2}월\s?\d{1,2}일');
    
    final fullTextCleaned = text.replaceAll('\n', ' ');
    final m1 = datePat1.firstMatch(fullTextCleaned);
    if (m1 != null) {
      expiryDate = m1.group(0)!;
    } else {
      final m2 = datePat2.firstMatch(fullTextCleaned);
      if (m2 != null) {
        expiryDate = m2.group(0)!;
      }
    }

    // 2. 브랜드(교환처/사용처) 추출
    String brand = "";
    final exchangePat = RegExp(r'(교환처|사용처)\s*[:：]?\s*(.*)');
    for (var line in lines) {
      final m = exchangePat.firstMatch(line);
      if (m != null) {
        final val = m.group(2)!.trim();
        if (val.isNotEmpty) {
          brand = val;
          break;
        }
      }
    }

    if (brand.isEmpty) {
      const brands = [
        '스타벅스', '배스킨라빈스', '투썸플레이스', '설빙', '메가커피', '이디야', '컴포즈',
        '굽네치킨', '교촌치킨', 'bhc', 'bbq', '올리브영', '다이소', '이마트', '신세계',
        'cu', 'gs25', '세븐일레븐', '요기요', '배달의민족', '아웃백', '공차', '던킨',
        '파리바게뜨', '뚜레쥬르', '맥도날드', '롯데리아', '버거킹', '스타벅스커피'
      ];
      for (var b in brands) {
        if (fullTextCleaned.toLowerCase().contains(b.toLowerCase())) {
          brand = (b == 'bhc' || b == 'cu' || b == 'gs25' || b == 'bbq') ? b.toUpperCase() : b;
          break;
        }
      }
    }

    // 3. 상품명 추출 (라벨 우선 탐색 및 후보군 필터링)
    String productName = "";
    final productNameRegex = RegExp(r'상품명\s*[:：]?\s*(.*)');
    for (var line in lines) {
      final m = productNameRegex.firstMatch(line);
      if (m != null) {
        final extracted = m.group(1)!.trim();
        if (extracted.isNotEmpty) {
          productName = extracted;
          break;
        }
      }
    }

    if (productName.isEmpty) {
      List<String> candidates = [];
      final barcodePat = RegExp(r'\d{8,}');
      final noticeKeywords = [
        '유의사항', '사용안내', '바코드', '환불', '잔액', '매장', '교환', '고객센터', '주문번호',
        '쿠폰번호', '발행일', '선물', '받은', '보낸', '결제', '쿠폰', '사용처', '교환처', '안내',
        '원', '￦', '카카오톡', '선물하기', 'gifticon', 'coupon', '주문', '금액', '교환수량',
        '수량', '개', '시럽'
      ];

      for (var line in lines) {
        final clean = line.trim();
        if (clean.isEmpty) continue;
        
        if (expiryDate.isNotEmpty && clean.contains(expiryDate)) continue;
        if (brand.isNotEmpty && clean.toLowerCase().contains(brand.toLowerCase())) continue;
        if (barcodePat.hasMatch(clean.replaceAll(RegExp(r'\s+|-'), ''))) continue;
        
        bool isNotice = false;
        for (var kw in noticeKeywords) {
          if (clean.toLowerCase().contains(kw)) {
            isNotice = true;
            break;
          }
        }
        if (isNotice) continue;

        if (clean.length >= 3 && clean.length <= 30) {
          candidates.add(clean);
        }
      }

      if (candidates.isNotEmpty) {
        productName = candidates.first;
      } else {
        productName = "기프티콘 상품";
      }
    }

    return '''[기프티콘]
교환처: ${brand.isNotEmpty ? brand : "기타/교환처"}
상품명: $productName
유효기간: ${expiryDate.isNotEmpty ? expiryDate : "정보 없음"}''';
  }

  static String mask(String text) {
    if (text.trim().isEmpty) return text;
    
    text = _cleanStatusBar(text);
    if (text.trim().isEmpty) return text;

    // ⚠️ 기프티콘 원본 텍스트 절단 방지:
    // _normalizeGifticon()으로 텍스트를 3줄로 임의 축약하면 원본의 상호명/상품명이 잘려나가
    // LLM이 원본을 보지 못하고 예제(스타벅스, 도미노피자 등)를 환각하는 치명적인 버그가 발생하므로,
    // 원본 OCR 텍스트 전체를 보존하여 LLM에 전달하도록 합니다.
    // final isGifticonText = ...
    // if (isGifticonText) return _normalizeGifticon(text);

    // 1. Identify document types by scanning the whole text
    // 여권 단어 외에도 하단 판독 영역의 '<' 패턴이 발견되면 여권으로 인식하도록 함
    final isPassport = _containsKeywords(text, ['여권', 'passport', '여권번호', 'passport no']) ||
        text.contains('<<<<') ||
        text.contains('<<<');
    
    final isLicense = _containsKeywords(text, ['운전면허증', 'driver’s license', "driver's license"]);
    final isRrnDoc = _containsKeywords(text, ['주민등록증']); // For address and dates of ID cards
    final isIdCard = isLicense || isRrnDoc;

    // 🚀 1. 온디바이스 NER AI 모델을 통한 문맥 기반 1차 마스킹 (이름, 조직, 위치 등)
    // 정규식으로 잡기 힘든 변형된 형태의 개인정보를 AI가 미리 차단(암호화)합니다.
    text = NerClassifier().maskPii(text);

    List<String> lines = text.split('\n');
    bool hasCardNumber = false;

    // --- Line-by-line processing ---
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // --- 주민등록번호 (RRN) ---
      // Pattern: 앞 6자리, 하이픈/공백(선택), 뒤 1~8 시작하는 7자리 (외국인 포함)
      final rrnRegex = RegExp(r'\b\d{6}[-\s]?[1-8]\d{6}\b');
      line = line.replaceAllMapped(rrnRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));

      // --- 카드 번호 (Card Number) ---
      // Pattern: 14~16자리 카드 번호 유연한 탐지 (아멕스 등 포함)
      final cardRegex = RegExp(r'\b\d{4}[-\s]?\d{4,6}[-\s]?\d{4,5}(?:[-\s]?\d{1,4})?\b');
      if (cardRegex.hasMatch(line)) {
        // Hybrid Matching: 16자리 표준이 아니면 주변(전체 텍스트)에 카드 키워드가 있는지 확인
        final cardKeywords = ['카드', 'card', '신용', '체크', '비자', 'visa', 'master', 'amex'];
        final isLikelyCard = _containsKeywords(text, cardKeywords) || RegExp(r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b').hasMatch(line);
        if (isLikelyCard) {
          hasCardNumber = true;
          line = line.replaceAllMapped(cardRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));
        }
      }

      // --- CVC 관련 번호 (CVC / CVV / Security Code) ---
      // Pattern: (CVC|CVV|보안코드|보안\s?카드)\s*[:.\-]?\s*([0-9]{3,4})\b (아멕스 4자리 대응)
      final cvcRegex = RegExp(
        r'(CVC|CVV|보안코드|보안\s?카드)\s*[:.\-]?\s*([0-9]{3,4})\b',
        caseSensitive: false,
      );
      line = line.replaceAllMapped(cvcRegex, (match) {
        final matchedString = match.group(0)!;
        final cvcVal = match.group(2)!;
        final maskedVal = CryptoHelper().encryptSensitive(cvcVal);
        return matchedString.replaceFirst(cvcVal, maskedVal);
      });

      // --- 쿠폰 코드 (Coupon Code) ---
      // Pattern: \b\d{12,16}\b (12~16자리 바코드 유연한 허용)
      final couponRegex = RegExp(r'\b\d{12,16}\b');
      if (couponRegex.hasMatch(line)) {
        // Hybrid Matching: 주변에 바코드/쿠폰 키워드가 있을 때만 마스킹 (숫자 오탐지 방지)
        if (_containsKeywords(text, ['기프티콘', '쿠폰', '바코드', '교환권', '모바일상품권', '선물하기'])) {
          line = line.replaceAllMapped(couponRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));
        }
      }

      // --- 계좌번호 (Account Number) ---
      // Pattern: 하이픈 2~4개까지 대응 가능
      final accountRegex = RegExp(r'\b\d{2,6}(?:-\d{2,6}){1,4}\b');
      if (accountRegex.hasMatch(line)) {
        // Hybrid Matching: 주변에 은행 관련 키워드가 있을 때만 마스킹
        final bankKeywords = ['은행', '계좌', '입금', '출금', '신한', '국민', '우리', '하나', '농협', '기업', '카카오뱅크', '토스'];
        if (_containsKeywords(text, bankKeywords)) {
          line = line.replaceAllMapped(accountRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));
        }
      }

      // --- 휴대폰 번호 (Phone Number) ---
      // Pattern: 01X, 02 등 다양한 지역번호 및 구번호 허용
      final phoneRegex = RegExp(r'(?:^|[^0-9])(0\d{1,2}[-\s]?\d{3,4}[-\s]?\d{4})(?:[^0-9]|$)');
      line = line.replaceAllMapped(phoneRegex, (match) {
        final val = match.group(1)!;
        String maskedVal = CryptoHelper().encryptSensitive(val);
        return match.group(0)!.replaceFirst(val, maskedVal);
      });

      // --- 예매/예약 번호 (Reservation/Ticket Number) ---
      final reservationRegex = RegExp(r'(예매번호|예약번호|티켓번호|예매|예약|티켓)\s*[:\-]?\s*([A-Za-z0-9]{6,15})\b');
      line = line.replaceAllMapped(reservationRegex, (match) {
        final keyword = match.group(1)!;
        final resNum = match.group(2)!;
        final separator = match.group(0)!.substring(keyword.length, match.group(0)!.length - resNum.length);
        final maskedVal = CryptoHelper().encryptSensitive(resNum);
        return '$keyword$separator$maskedVal';
      });

      // --- 여권 관련 날짜 마스킹 (여권 정보 검출되었을 때만) ---
      if (isPassport) {
        // 여권 날짜 패턴
        final passportDateRegex = RegExp(
          r'\b\d{2}\s?\d{1,2}월\s?/\s?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\s?\d{4}\b',
          caseSensitive: false,
        );
        line = line.replaceAllMapped(passportDateRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));
      }

      // --- 운전면허증 관련 마스킹 (키워드 탐지 시) ---
      if (isLicense) {
        final licenseRegex = RegExp(
          r'\b(\d{2}|서울|부산|경기|강원|충북|충남|전북|전남|경북|경남|제주|인천|대구|대전|울산|광주)[-\s]?\d{2}[-\s]?\d{6}[-\s]?\d{2}\b',
        );
        line = line.replaceAllMapped(licenseRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));
      }

      // --- 주민등록증/운전면허증인 경우 주소 및 날짜 마스킹 ---
      if (isIdCard) {
        // 주소 패턴
        final addressRegex = RegExp(
          r'\b(서울시|부산시|대구시|인천시|광주시|대전시|울산시|세종시|경기도|강원도|충청북도|충청남도|전라북도|전라남도|경상북도|경상남도|제주도|서울|부산|경기|강원|충북|충남|전북|전남|경북|경남|제주|인천|대구|대전|울산|광주)\s[가-힣0-9\s\-]+(시|군|구|읍|면|동|로|길|번지)\b',
        );
        line = line.replaceAllMapped(addressRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));

        // 날짜 패턴
        final idDateRegex = RegExp(
          r'\b\d{4}\.\d{2}\.\d{2}\b|\b\d{4}\.\d{2}\.\d{2}\s*~\s*\d{4}\.\d{2}\.\d{2}\b',
        );
        line = line.replaceAllMapped(idDateRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));
      }

      lines[i] = line;
    }

    // --- 여권 맨 아래 판독 영역 (MRZ) 마스킹 (블록 매칭 방식) ---
    // 첫 번째 줄 and 두 번째 줄이 서로 인접해 있는 특성을 활용하여 꺾쇠(<)가 한쪽에만 있어도 세트로 마스킹 처리합니다.
    List<bool> maskFlags = List.filled(lines.length, false);
    for (int i = 0; i < lines.length; i++) {
      if (_isCandidateMrz(lines[i])) {
        if (lines[i].contains('<')) {
          maskFlags[i] = true;
        } else if (i > 0 && _isCandidateMrz(lines[i - 1]) && lines[i - 1].contains('<')) {
          maskFlags[i] = true;
        } else if (i < lines.length - 1 && _isCandidateMrz(lines[i + 1]) && lines[i + 1].contains('<')) {
          maskFlags[i] = true;
        }
      }
    }
    
    for (int i = 0; i < lines.length; i++) {
      if (maskFlags[i]) {
        lines[i] = CryptoHelper().encryptSensitive(lines[i]);
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
            return CryptoHelper().encryptSensitive(match.group(0)!);
          });
          
          if (i + 1 < lines.length) {
            lines[i + 1] = lines[i + 1].replaceAllMapped(passportNoRegex, (match) {
              maskedByKeywordRange = true;
              return CryptoHelper().encryptSensitive(match.group(0)!);
            });
          }
        }
      }

      // 2. 만약 키워드가 멀리 떨어져 있어서 위의 라인 범위 내에서 여권번호가 마스킹되지 않은 경우,
      //    이미 여권 문서임이 확정되었으므로 전체 문서에서 발견되는 여권번호 매칭 항목들을 강제로 마스킹합니다.
      if (!maskedByKeywordRange) {
        for (int i = 0; i < lines.length; i++) {
          lines[i] = lines[i].replaceAllMapped(passportNoRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));
        }
      }
    }

    // --- 카드 번호 검출 시 근처 CVC 탐색 및 마스킹 ---
    if (hasCardNumber) {
      final standalone3DigitRegex = RegExp(r'\b\d{3}\b');
      for (int i = 0; i < lines.length; i++) {
        lines[i] = lines[i].replaceAllMapped(standalone3DigitRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));
      }
    }

    return lines.join('\n');
  }

  static bool hasSensitivePatterns(String text) {
    if (text.trim().isEmpty) return false;
    
    final lowerText = text.toLowerCase();
    int score = 0;

    // --- 1. RRN (주민등록번호) 검사 ---
    final rrnHyphenRegex = RegExp(r'\b\d{6}-[1-8]\d{6}\b');
    final rrnLooseRegex = RegExp(r'\b\d{6}\s?[1-8]\d{6}\b');
    if (rrnHyphenRegex.hasMatch(text)) {
      score += 10;
    } else if (rrnLooseRegex.hasMatch(text)) {
      score += 5;
    }

    // --- 2. 카드 번호 및 CVC 검사 ---
    final cardRegex = RegExp(r'\b\d{4}[-\s]?\d{4,6}[-\s]?\d{4,5}(?:[-\s]?\d{1,4})?\b');
    if (cardRegex.hasMatch(text)) {
      if (RegExp(r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b').hasMatch(text)) {
        score += 10; // 표준 16자리
      } else if (['카드', 'card', '신용', '체크', '비자', 'visa', 'master', 'amex'].any((k) => lowerText.contains(k))) {
        score += 8; // 비표준이지만 카드 키워드 있음
      } else {
        score += 3; // 단순 숫자 배열 가능성
      }
    }
    
    final cvcRegex = RegExp(r'(cvc|cvv|보안코드|보안\s?카드)\s*[:.\-]?\s*([0-9]{3})\b', caseSensitive: false);
    if (cvcRegex.hasMatch(text)) {
      score += 8;
    }

    // --- 3. 휴대폰 번호 검사 ---
    final phoneRegex = RegExp(r'(?:^|[^0-9])(010-\d{3,4}-\d{4}|010\d{7,8})(?:[^0-9]|$)');
    if (phoneRegex.hasMatch(text)) {
      score += 5;
    }

    // --- 3.5. 예매/예약 번호 검사 ---
    final reservationRegex = RegExp(r'(예매번호|예약번호|티켓번호|예매|예약|티켓)\s*[:\-]?\s*([A-Za-z0-9]{6,15})\b');
    if (reservationRegex.hasMatch(text)) {
      score += 5;
    }

    // --- 4. 계좌번호 검사 (날짜 포맷 제외 처리) ---
    final accountRegex = RegExp(r'\b\d{3,6}-\d{2,6}-\d{3,6}\b');
    final dateRegex = RegExp(r'\b\d{4}[.\-/]\d{1,2}[.\-/]\d{1,2}\b');
    for (var match in accountRegex.allMatches(text)) {
      final matchedStr = match.group(0)!;
      // 만약 계좌번호로 검출된 텍스트가 날짜 패턴에 완전히 매칭된다면 점수 부여하지 않음 (오탐 방지)
      if (!dateRegex.hasMatch(matchedStr)) {
        score += 5;
        break;
      }
    }

    // --- 5. 여권 (Passport) 컨텍스트 매칭 ---
    final hasPassportKeywords = ['여권', 'passport', '여권번호', 'passport no'].any((k) => lowerText.contains(k));
    final hasPassportNo = RegExp(r'\b[A-Z]\s?[A-Z0-9]{8}\b', caseSensitive: false).hasMatch(text);
    final hasMrzPattern = lowerText.contains('<<<<') || lowerText.contains('<<<');
    
    if (hasMrzPattern) {
      score += 10;
    } else if (hasPassportKeywords && hasPassportNo) {
      score += 8;
    }

    // --- 6. 운전면허증 (Driver\'s License) 컨텍스트 매칭 ---
    final hasLicenseKeywords = ['운전면허증', 'driver\'s license', 'driver’s license'].any((k) => lowerText.contains(k));
    final hasLicenseNo = RegExp(r'\b\d{2}[-\s]?\d{2}[-\s]?\d{6}[-\s]?\d{2}\b').hasMatch(text);
    if (hasLicenseKeywords && hasLicenseNo) {
      score += 8;
    }

    // --- 7. 기프티콘 / 쿠폰 컨텍스트 매칭 ---
    final hasGifticonKeywords = ['기프티콘', '쿠폰', '바코드', '교환권', '모바일상품권', '모바일쿠폰', '선물하기', '교환처'].any((k) => lowerText.contains(k));
    final hasExpiryKeywords = ['사용기한', '유효기간', '만료일', '까지'].any((k) => lowerText.contains(k));
    final hasCouponNo = RegExp(r'\b\d{12}\b|\b\d{14}\b|\b\d{16}\b').hasMatch(text);
    final hasDatePattern = RegExp(r'\b(\d{2}|\d{4})[.\-/]\d{1,2}[.\-/]\d{1,2}\b').hasMatch(text) ||
                           RegExp(r'\b(\d{2}|\d{4})년\s?\d{1,2}월\s?\d{1,2}일\b').hasMatch(text);

    // 단순 단어가 아니라, 기프티콘 키워드와 바코드 번호 혹은 유효기간 정보가 복합적으로 있을 때만 점수 가산
    if (hasGifticonKeywords && (hasCouponNo || (hasExpiryKeywords && hasDatePattern))) {
      score += 6;
    }

    print('🛡️ 민감 정보 평가 점수: $score (임계값: 5)');
    return score >= 5;
  }

  static Map<String, List<String>> extractOriginalSensitiveInfo(String text) {
    Map<String, List<String>> info = {
      'rrn': [],
      'card': [],
      'cvc': [],
      'phone': [],
      'account': [],
      'passport': [],
      'license': [],
      'coupon': [],
      'reservation': [],
    };

    if (text.trim().isEmpty) return info;

    // RRN (주민등록번호)
    final rrnRegex = RegExp(r'\b\d{6}-[1-4]\d{6}\b|\b\d{6}\s?[1-4]\d{6}\b');
    info['rrn']!.addAll(rrnRegex.allMatches(text).map((m) => m.group(0)!));

    // Card (카드번호)
    final cardRegex = RegExp(r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b');
    info['card']!.addAll(cardRegex.allMatches(text).map((m) => m.group(0)!));

    // CVC
    final cvcRegex = RegExp(r'(CVC|CVV|보안코드|보안\s?카드)\s*[:.\-]?\s*([0-9]{3})\b', caseSensitive: false);
    info['cvc']!.addAll(cvcRegex.allMatches(text).map((m) => m.group(2)!));

    // Phone (휴대폰번호)
    final phoneRegex = RegExp(r'(?:^|[^0-9])(010-\d{3,4}-\d{4}|010\d{7,8})(?:[^0-9]|$)');
    info['phone']!.addAll(phoneRegex.allMatches(text).map((m) => m.group(1)!));

    // Account (계좌번호)
    final accountRegex = RegExp(r'\b\d{3,6}-\d{2,6}-\d{3,6}\b');
    final dateRegex = RegExp(r'\b\d{4}[.\-/]\d{1,2}[.\-/]\d{1,2}\b');
    for (var match in accountRegex.allMatches(text)) {
      final matchedStr = match.group(0)!;
      if (!dateRegex.hasMatch(matchedStr)) {
        info['account']!.add(matchedStr);
      }
    }

    // Reservation (예매/예약 번호)
    final reservationRegex = RegExp(r'(예매번호|예약번호|티켓번호|예매|예약|티켓)\s*[:\-]?\s*([A-Za-z0-9]{6,15})\b');
    info['reservation']!.addAll(reservationRegex.allMatches(text).map((m) => m.group(2)!));

    // Passport (여권번호) - 여권 관련 키워드가 있을 경우에만 추출
    final lowerText = text.toLowerCase();
    final hasPassportKeywords = ['여권', 'passport', '여권번호', 'passport no'].any((k) => lowerText.contains(k));
    if (hasPassportKeywords || lowerText.contains('<<<<') || lowerText.contains('<<<')) {
      final passportNoRegex = RegExp(r'\b[A-Z]\s?[A-Z0-9]{8}\b', caseSensitive: false);
      info['passport']!.addAll(passportNoRegex.allMatches(text).map((m) => m.group(0)!));
    }

    // License (운전면허증 번호)
    final licenseRegex = RegExp(r'\b(\d{2}|서울|부산|경기|강원|충북|충남|전북|전남|경북|경남|제주|인천|대구|대전|울산|광주)[-\s]?\d{2}[-\s]?\d{6}[-\s]?\d{2}\b');
    info['license']!.addAll(licenseRegex.allMatches(text).map((m) => m.group(0)!));

    // Coupon (기프티콘/바코드 등 쿠폰번호)
    final couponRegex = RegExp(r'\b\d{12}\b|\b\d{14}\b|\b\d{16}\b');
    info['coupon']!.addAll(couponRegex.allMatches(text).map((m) => m.group(0)!));

    // 빈 리스트 제거
    info.removeWhere((key, value) => value.isEmpty);

    return info;
  }

  static String unmask(String text, Map<String, dynamic>? originalInfo) {
    // 기존에는 originalInfo를 사용해 ***를 다시 텍스트로 치환했지만,
    // 이제는 종단간 암호화(E2EE) 방식이므로 CryptoHelper를 통해
    // 문자열 내의 [ENC:...] 패턴을 복호화하여 반환합니다.
    return CryptoHelper().decryptText(text);
  }
}
