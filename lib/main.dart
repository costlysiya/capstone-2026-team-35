import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; 
import 'package:flutter_riverpod/legacy.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'core/storage/app_storage.dart';
import 'core/utils/masking_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStorage.initDirectories();
  runApp(const ProviderScope(child: MyApp()));
}

// 대기열 및 선택 인덱스 관리
final pickedImagesProvider = StateProvider<List<XFile>>((ref) => []);
final activeImageIndexProvider = StateProvider<int>((ref) => 0);

final ocrStatusProvider = StateProvider<String>((ref) => 'idle'); 
final extractedTextProvider = StateProvider<String>((ref) => '');

// 카테고리 세팅 (0: 일정, 1: 장소, 2: 위시, 3: 메모)
final selectedCategoryProvider = StateProvider<int>((ref) => 3);
// 일정 카테고리 내부 세부 분류 (0: 일반 일정, 1: 기프티콘)
final selectedSubCategoryProvider = StateProvider<int>((ref) => 0);

// AI 분석에서 응답받은 원본 가변 필드들 및 다중 항목 페이징 상태
final aiResponseFieldsProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
final currentItemIndexProvider = StateProvider<int>((ref) => 0);

// [사이드 메뉴 상태] 'home', 'cat_0_0'(일반일정), 'cat_0_1'(기프티콘), 'cat_1', 'cat_2', 'cat_3'
final currentMenuProvider = StateProvider<String>((ref) => 'home');

// ✍️ 입력 컨트롤러들
final titleControllerProvider = Provider((ref) => TextEditingController());
final contentControllerProvider = Provider((ref) => TextEditingController());
final scheduleDateProvider = Provider((ref) => TextEditingController());   
final placeLocationProvider = Provider((ref) => TextEditingController()); 

// 전역 데이터 보관함
final savedCardsProvider = StateProvider<List<Map<String, dynamic>>>((ref) => []);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '소생 앱',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _clearAllFields(WidgetRef ref) {
    ref.read(titleControllerProvider).clear();
    ref.read(contentControllerProvider).clear();
    ref.read(scheduleDateProvider).clear();
    ref.read(placeLocationProvider).clear();
  }

  // 갤러리에서 대량 가져오기 (최대 50장)
  Future<void> _pickMultiImages(WidgetRef ref) async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    
    if (images.isNotEmpty) {
      ref.read(pickedImagesProvider.notifier).state = images.take(50).toList();
      ref.read(activeImageIndexProvider.notifier).state = 0;
      ref.read(ocrStatusProvider.notifier).state = 'idle';
      ref.read(extractedTextProvider.notifier).state = '';
      _clearAllFields(ref);
    }
  }

  // 현재 선택된 사진 1장만 대기열에서 삭제하는 기능
  void _removeActiveImage(WidgetRef ref) {
    final images = ref.read(pickedImagesProvider);
    final activeIndex = ref.read(activeImageIndexProvider);

    if (images.isEmpty) return;

    final updatedImages = List<XFile>.from(images)..removeAt(activeIndex);
    ref.read(pickedImagesProvider.notifier).state = updatedImages;
    ref.read(ocrStatusProvider.notifier).state = 'idle';
    _clearAllFields(ref);

    if (updatedImages.isNotEmpty) {
      if (activeIndex >= updatedImages.length) {
        ref.read(activeImageIndexProvider.notifier).state = updatedImages.length - 1;
      }
    } else {
      ref.read(activeImageIndexProvider.notifier).state = 0;
    }
  }

  // 단수 이미지 OCR 추출 (기본 텍스트 매핑만 수행, 서버 전송 없음)
  Future<void> _runSingleOCR(WidgetRef ref, XFile image) async {
    ref.read(ocrStatusProvider.notifier).state = 'loading';
    _clearAllFields(ref);

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      if (recognizedText.text.trim().isEmpty) {
        ref.read(extractedTextProvider.notifier).state = "⚠️ 글자가 없는 이미지입니다.";
        ref.read(titleControllerProvider).text = "새로운 소생 카드";
      } else {
        print('🔍 [OCR Raw Text]\n${recognizedText.text}');
        
        // 마스킹 처리를 건너뛰고 사용자가 바로 볼 수 있도록 원본 OCR 추출 텍스트 매핑
        ref.read(extractedTextProvider.notifier).state = recognizedText.text;
        ref.read(contentControllerProvider).text = recognizedText.text;
        
        // 첫 줄을 제목 기본값으로 설정
        final firstLine = recognizedText.text.split('\n').first.trim();
        ref.read(titleControllerProvider).text = firstLine.isNotEmpty ? firstLine : "새로운 소생 카드";

        // 로컬 룰베이스 분류기로 카테고리 즉시 판정 (서버 전송 없음, 완전히 안전)
        final String lowerText = recognizedText.text.toLowerCase();
        
        int scheduleScore = 0;
        int placeScore = 0;
        int wishlistScore = 0;
        int memoScore = 0;

        // 1. SCHEDULE 키워드 점수화
        final scheduleKeywords = [
          '유효기간', '사용기한', '만료일', '까지', '예약', '구독', '결제일', '약속',
          '오전', '오후', '내일', '모레', '이번주', '다음주', '출발', '도착', '탑승', 
          '체크인', '마감', 'D-'
        ];
        for (var kw in scheduleKeywords) {
          if (lowerText.contains(kw.toLowerCase())) scheduleScore += 2;
        }
        if (lowerText.contains('년') || lowerText.contains('월') || lowerText.contains('일')) scheduleScore += 1;
        if (lowerText.contains('시') || lowerText.contains('분')) scheduleScore += 1;

        // 2. PLACE 키워드 점수화
        final placeKeywords = [
          '맛집', '카페', '식당', '평점', '리뷰', '영업시간', '주소', '지도', 
          '네이버지도', '카카오맵', '구글맵', '위치', '거리', '도보', '차량', '길찾기'
        ];
        for (var kw in placeKeywords) {
          if (lowerText.contains(kw.toLowerCase())) placeScore += 2;
        }
        final addressSuffixes = ['역', '동', '길', '로', '구'];
        for (var suffix in addressSuffixes) {
          if (RegExp('$suffix\\b').hasMatch(lowerText) || RegExp('$suffix\\s').hasMatch(lowerText)) {
            placeScore += 1;
          }
        }

        // 3. WISHLIST 키워드 점수화
        final wishlistKeywords = [
          '원', '₩', '할인', '쿠팡', '네이버쇼핑', '장바구니', '사이즈', '배송', 
          '무신사', '올리브영', '찜', '위시리스트', '품절', '재입고', '옵션', '할부', '적립', '포인트'
        ];
        for (var kw in wishlistKeywords) {
          if (lowerText.contains(kw.toLowerCase())) wishlistScore += 2;
        }

        // 4. MEMO 키워드 점수화
        final memoKeywords = [
          '재료', '만드는 법', '조리', 'QR', '리디북스', '카카오페이지', '네이버시리즈', 
          '웹소설', '체크리스트', '할 일', 'TODO', '메모', '참고', '기록', '출처', '제목', '챕터'
        ];
        for (var kw in memoKeywords) {
          if (lowerText.contains(kw.toLowerCase())) memoScore += 2;
        }

        int finalCategory = 3; // 기본값 MEMO
        int maxScore = 0;

        // 동점인 경우 우선순위: SCHEDULE > PLACE > WISHLIST > MEMO
        if (memoScore > maxScore) { maxScore = memoScore; finalCategory = 3; }
        if (wishlistScore > maxScore) { maxScore = wishlistScore; finalCategory = 2; }
        if (placeScore > maxScore) { maxScore = placeScore; finalCategory = 1; }
        if (scheduleScore > maxScore) { maxScore = scheduleScore; finalCategory = 0; }

        final isIDCard = ['주민등록증', '운전면허증', '여권', 'passport', 'driver\'s license', 'driver’s license'].any((k) => lowerText.contains(k)) ||
                         lowerText.contains('<<<<') ||
                         lowerText.contains('<<<');
        if (isIDCard) {
          finalCategory = 3; // 신분증/여권은 무조건 메모(MEMO) 카테고리로 강제 지정
        }

        ref.read(selectedCategoryProvider.notifier).state = finalCategory;

        if (finalCategory == 0) {
          final isGifticon = ['기프티콘', '쿠폰', '바코드', '교환권', '모바일상품권', '모바일쿠폰', '선물하기', '교환처'].any((k) => lowerText.contains(k)) ||
                             lowerText.contains('사용기한') || lowerText.contains('유효기간');
          if (isGifticon) {
            ref.read(selectedSubCategoryProvider.notifier).state = 1; // 기프티콘
            
            // 기프티콘인 경우 로컬에서 유효기간 패턴을 찾아 날짜 텍스트필드에 미리 입력
            final datePat1 = RegExp(r'\b(\d{2}|\d{4})[.\-/]\d{1,2}[.\-/]\d{1,2}\b');
            final datePat2 = RegExp(r'(\d{2}|\d{4})년\s?\d{1,2}월\s?\d{1,2}일');
            final fullTextCleaned = recognizedText.text.replaceAll('\n', ' ');
            final m1 = datePat1.firstMatch(fullTextCleaned);
            if (m1 != null) {
              ref.read(scheduleDateProvider).text = m1.group(0)!;
            } else {
              final m2 = datePat2.firstMatch(fullTextCleaned);
              if (m2 != null) {
                ref.read(scheduleDateProvider).text = m2.group(0)!;
              }
            }
          } else {
            ref.read(selectedSubCategoryProvider.notifier).state = 0; // 일반 일정
          }
        }
      }
      
      ref.read(ocrStatusProvider.notifier).state = 'success';
      textRecognizer.close();
      
    } catch (e) {
      ref.read(extractedTextProvider.notifier).state = "❌ 분석 실패: $e";
      ref.read(ocrStatusProvider.notifier).state = 'success';
    }
  }

  // 사용자가 명시적으로 선택 시 호출되는 AI 기반 구조화 분석 모듈
  Future<void> _runAIAnalysis(BuildContext context, WidgetRef ref, XFile image) async {
    final rawText = ref.read(contentControllerProvider).text;
    if (rawText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ 분석할 텍스트가 비어 있습니다.')));
      return;
    }

    // 1. 개인정보 패턴 감지 여부 판정
    final hasSensitive = MaskingHelper.hasSensitivePatterns(rawText);
    bool proceed = true;

    if (hasSensitive) {
      // 다이얼로그 팝업 창으로 전송 및 익명화 허가 여부 질문
      proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('개인정보 포함 감지'),
            ],
          ),
          content: const Text(
            '분석할 텍스트 내에 개인정보(주민등록번호, 카드 번호, 바코드 등)로 의심되는 패턴이 감지되었습니다.\n\nAI 분석 서버로 전송하여 자동 구조화 과정을 진행할까요?\n(보안 전송을 위해 민감 데이터는 서버 전송 전 기기 내에서 자동 마스킹 치환됩니다.)'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('마스킹 후 전송'),
            ),
          ],
        ),
      ) ?? false;
    }

    if (!proceed) return;

    // 2. 서버 전송 전 익명화 마스킹 수행
    final maskedText = MaskingHelper.mask(rawText);
    ref.read(extractedTextProvider.notifier).state = maskedText;

    // 3. 기프티콘 여부 검사 후 로컬 선-정규화 기법 적용
    if (maskedText.startsWith('[기프티콘]')) {
      String brand = "";
      String productName = "";
      String expiryDate = "";
      
      for (var line in maskedText.split('\n')) {
        if (line.startsWith('교환처: ')) {
          brand = line.replaceFirst('교환처: ', '').trim();
        } else if (line.startsWith('상품명: ')) {
          productName = line.replaceFirst('상품명: ', '').trim();
        } else if (line.startsWith('유효기간: ')) {
          expiryDate = line.replaceFirst('유효기간: ', '').trim();
        }
      }
      
      ref.read(titleControllerProvider).text = 
          brand.isNotEmpty && brand != "기타/교환처" ? "[$brand] $productName" : productName;
      ref.read(contentControllerProvider).text = "교환처: $brand\n유효기간: $expiryDate";
      
      if (expiryDate.isNotEmpty && expiryDate != "정보 없음") {
        ref.read(scheduleDateProvider).text = expiryDate;
      } else {
        ref.read(scheduleDateProvider).clear();
      }
    }

    // 4. API 서버 연동 및 카테고리 기기 분류 주입
    ref.read(ocrStatusProvider.notifier).state = 'loading';
    try {
      final dio = Dio();
      const serverUrl = 'http://172.30.1.84:8000/api/analyze/v2';
      
      final localCategoryIndex = ref.read(selectedCategoryProvider);
      final indexToType = {
        0: 'SCHEDULE',
        1: 'PLACE',
        2: 'WISHLIST',
        3: 'MEMO',
      };
      final localType = indexToType[localCategoryIndex] ?? 'MEMO';

      final response = await dio.post(
        serverUrl,
        data: {
          'ocr_text': maskedText,
          'type': localType, // 로컬 AI 분류 결과를 필수 전송
          'masked_tokens': <String>[],
        },
        options: Options(contentType: 'application/json'),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final typeStr = data['type'] as String;
        final fields = data['fields'] as Map<String, dynamic>;

        // AI 응답 상태 보존 및 페이징 초기화
        ref.read(aiResponseFieldsProvider.notifier).state = fields;
        ref.read(currentItemIndexProvider.notifier).state = 0;
        
        final typeToIndex = {
          'SCHEDULE': 0,
          'PLACE': 1,
          'WISHLIST': 2,
          'MEMO': 3,
        };
        final categoryIndex = typeToIndex[typeStr] ?? 3;
        ref.read(selectedCategoryProvider.notifier).state = categoryIndex;
        
        // 상세 본문 수정 부분에 서버에서 가져온 json정보를 포맷팅하여 주입
        final prettyJson = const JsonEncoder.withIndent('  ').convert(fields);
        ref.read(contentControllerProvider).text = prettyJson;

        // 1. SCHEDULE 매핑
        if (categoryIndex == 0) {
          final subType = fields['sub_type'] as String?;
          final isGifticon = subType == 'GIFTICON' || 
                             (fields['exchange_place'] != null) ||
                             maskedText.contains('기프티콘') || 
                             maskedText.contains('쿠폰');
                             
          ref.read(selectedSubCategoryProvider.notifier).state = isGifticon ? 1 : 0;
          ref.read(titleControllerProvider).text = fields['title'] ?? '새로운 일정';
          
          final expiryDate = fields['expires_at'] as String?;
          final startDate = fields['start_at'] as String?;
          ref.read(scheduleDateProvider).text = expiryDate ?? startDate ?? '';
        }
        // 2. PLACE 매핑
        else if (categoryIndex == 1) {
          Map<String, dynamic> placeFields = fields;
          if (fields['items'] != null && (fields['items'] as List).isNotEmpty) {
            placeFields = (fields['items'] as List).first as Map<String, dynamic>;
          }
          ref.read(titleControllerProvider).text = placeFields['name'] ?? '새로운 장소';
          ref.read(placeLocationProvider).text = placeFields['address'] ?? placeFields['region'] ?? '';
        }
        // 3. WISHLIST 매핑
        else if (categoryIndex == 2) {
          Map<String, dynamic> itemFields = fields;
          if (fields['items'] != null && (fields['items'] as List).isNotEmpty) {
            itemFields = (fields['items'] as List).first as Map<String, dynamic>;
          }
          ref.read(titleControllerProvider).text = itemFields['product_name'] ?? '새로운 위시 상품';
        }
        // 4. MEMO 매핑
        else if (categoryIndex == 3) {
          ref.read(titleControllerProvider).text = fields['title'] ?? '새로운 메모';
        }

        print('🎯 AI 로컬 서버 분류 성공: $typeStr (Index: $categoryIndex)');
        
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🎯 AI 분류 완료: $typeStr'))
        );
      } else {
        throw Exception('서버 응답 비정상');
      }
    } catch (e) {
      print('⚠️ AI 로컬 서버 통신 실패 ($e). 스마트 로컬 룰베이스 분류기로 폴백합니다.');
      final String lowerText = maskedText.toLowerCase();
      
      int scheduleScore = 0;
      int placeScore = 0;
      int wishlistScore = 0;
      int memoScore = 0;

      // 1. SCHEDULE 키워드 점수화
      final scheduleKeywords = [
        '유효기간', '사용기한', '만료일', '까지', '예약', '구독', '결제일', '약속',
        '오전', '오후', '내일', '모레', '이번주', '다음주', '출발', '도착', '탑승', 
        '체크인', '마감', 'D-'
      ];
      for (var kw in scheduleKeywords) {
        if (lowerText.contains(kw.toLowerCase())) scheduleScore += 2;
      }
      if (lowerText.contains('년') || lowerText.contains('월') || lowerText.contains('일')) scheduleScore += 1;
      if (lowerText.contains('시') || lowerText.contains('분')) scheduleScore += 1;

      // 2. PLACE 키워드 점수화
      final placeKeywords = [
        '맛집', '카페', '식당', '평점', '리뷰', '영업시간', '주소', '지도', 
        '네이버지도', '카카오맵', '구글맵', '위치', '거리', '도보', '차량', '길찾기'
      ];
      for (var kw in placeKeywords) {
        if (lowerText.contains(kw.toLowerCase())) placeScore += 2;
      }
      final addressSuffixes = ['역', '동', '길', '로', '구'];
      for (var suffix in addressSuffixes) {
        if (RegExp('$suffix\\b').hasMatch(lowerText) || RegExp('$suffix\\s').hasMatch(lowerText)) {
          placeScore += 1;
        }
      }

      // 3. WISHLIST 키워드 점수화
      final wishlistKeywords = [
        '원', '₩', '할인', '쿠팡', '네이버쇼핑', '장바구니', '사이즈', '배송', 
        '무신사', '올리브영', '찜', '위시리스트', '품절', '재입고', '옵션', '할부', '적립', '포인트'
      ];
      for (var kw in wishlistKeywords) {
        if (lowerText.contains(kw.toLowerCase())) wishlistScore += 2;
      }

      // 4. MEMO 키워드 점수화
      final memoKeywords = [
        '재료', '만드는 법', '조리', 'QR', '리디북스', '카카오페이지', '네이버시리즈', 
        '웹소설', '체크리스트', '할 일', 'TODO', '메모', '참고', '기록', '출처', '제목', '챕터'
      ];
      for (var kw in memoKeywords) {
        if (lowerText.contains(kw.toLowerCase())) memoScore += 2;
      }

      int finalCategory = 3; // 기본값 MEMO
      int maxScore = 0;

      // 동점인 경우 우선순위: SCHEDULE > PLACE > WISHLIST > MEMO
      if (memoScore > maxScore) { maxScore = memoScore; finalCategory = 3; }
      if (wishlistScore > maxScore) { maxScore = wishlistScore; finalCategory = 2; }
      if (placeScore > maxScore) { maxScore = placeScore; finalCategory = 1; }
      if (scheduleScore > maxScore) { maxScore = scheduleScore; finalCategory = 0; }

      final isIDCard = ['주민등록증', '운전면허증', '여권', 'passport', 'driver\'s license', 'driver’s license'].any((k) => lowerText.contains(k)) ||
                       lowerText.contains('<<<<') ||
                       lowerText.contains('<<<');
      if (isIDCard) {
        finalCategory = 3; // 신분증/여권은 무조건 메모(MEMO) 카테고리로 강제 지정
      }

      ref.read(selectedCategoryProvider.notifier).state = finalCategory;

      if (finalCategory == 0) {
        final isGifticon = ['기프티콘', '쿠폰', '바코드', '교환권', '모바일상품권', '모바일쿠폰', '선물하기', '교환처'].any((k) => lowerText.contains(k)) ||
                           lowerText.contains('사용기한') || lowerText.contains('유효기간');
        if (isGifticon) {
          ref.read(selectedSubCategoryProvider.notifier).state = 1; // 기프티콘
        } else {
          ref.read(selectedSubCategoryProvider.notifier).state = 0; // 일반 일정
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ AI 서버 연결 실패: 로컬 규칙으로 안전 판정 완료!'))
      );
    } finally {
      ref.read(ocrStatusProvider.notifier).state = 'success';
    }
  }

  // 수정본 보관함 최종 저장 분기 로직
  void _saveCurrentCardAndRemoveFromQueue(BuildContext context, WidgetRef ref) {
    final title = ref.read(titleControllerProvider).text;
    final content = ref.read(contentControllerProvider).text;
    final categoryId = ref.read(selectedCategoryProvider);
    final subCategoryId = ref.read(selectedSubCategoryProvider); 
    final images = ref.read(pickedImagesProvider);
    final activeIndex = ref.read(activeImageIndexProvider);

    if (title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ 제목을 입력해 주세요.')));
      return;
    }

    String extraInfo = "";
    if (categoryId == 0) extraInfo = ref.read(scheduleDateProvider).text;
    if (categoryId == 1) extraInfo = ref.read(placeLocationProvider).text;

    // 기프티콘(0_1)과 위시리스트(2)만 갤러리 원본 스크린샷 사진 주소 저장
    String? finalImagePath;
    if ((categoryId == 0 && subCategoryId == 1) || categoryId == 2) {
      finalImagePath = images[activeIndex].path;
    }

    final newCard = {
      'id': DateTime.now().toString(),
      'categoryId': categoryId,
      'subCategoryId': categoryId == 0 ? subCategoryId : 0, 
      'title': title,
      'content': content,
      'extraInfo': extraInfo,
      'imagePath': finalImagePath, 
    };

    ref.read(savedCardsProvider.notifier).update((state) => [newCard, ...state]);

    final updatedImages = List<XFile>.from(images)..removeAt(activeIndex);
    ref.read(pickedImagesProvider.notifier).state = updatedImages;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('💾 지정된 보관함 방으로 안전하게 입고되었습니다!')));

    ref.read(ocrStatusProvider.notifier).state = 'idle';
    _clearAllFields(ref);

    if (updatedImages.isNotEmpty) {
      if (activeIndex >= updatedImages.length) {
        ref.read(activeImageIndexProvider.notifier).state = updatedImages.length - 1;
      }
    }
  }

  Map<String, dynamic> _getCategoryStyle(int category, {int subCategory = 0}) {
    if (category == 0 && subCategory == 1) {
      return {'name': '🎟️ 기프티콘 (GIFTICON)', 'color': Colors.cyan[700]!, 'icon': Icons.confirmation_number};
    }
    switch (category) {
      case 0: return {'name': '📅 일반 일정 (SCHEDULE)', 'color': Colors.blue, 'icon': Icons.calendar_today};
      case 1: return {'name': '📍 장소 (PLACE)', 'color': Colors.teal, 'icon': Icons.map};
      case 2: return {'name': '🎁 위시리스트 (WISHLIST)', 'color': Colors.pink, 'icon': Icons.shopping_bag};
      default: return {'name': '📝 메모 (MEMO)', 'color': Colors.amber[700]!, 'icon': Icons.note};
    }
  }

  // 손가락으로 확대/축소(Pinch to Zoom)가 가능한 풀스크린 이미지 뷰어
  void _showEnlargedImage(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Text(
                  '💡 손가락 두 개로 확대 및 이동이 가능합니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 보관함 항목 클릭 시 띄워줄 상세 디테일 모달 팝업창 시스템
  void _showCardDetail(BuildContext context, Map<String, dynamic> card, Map<String, dynamic> cardStyle) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (card['imagePath'] != null)
                  GestureDetector(
                    onTap: () => _showEnlargedImage(context, card['imagePath']),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          constraints: const BoxConstraints(maxHeight: 280),
                          width: double.infinity,
                          color: Colors.black12,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                            child: Image.file(
                              File(card['imagePath']),
                              width: double.infinity,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        // ✨ [수정 완료] Colors.black.withOpacity(0.65) 로 정상 변경!
                        Container(
                          margin: const EdgeInsets.all(10),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('터치하여 확대', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cardStyle['color'].withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cardStyle['icon'], color: cardStyle['color'], size: 14),
                            const SizedBox(width: 5),
                            Text(cardStyle['name'], style: TextStyle(color: cardStyle['color'], fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(card['title'], style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 10),
                      if (card['extraInfo'].toString().isNotEmpty) ...[
                        Text(
                          card['categoryId'] == 0 && card['subCategoryId'] == 1
                              ? '⏳ 기프티콘 유효기간'
                              : card['categoryId'] == 0 ? '⏰ 일정 일시 설정'
                              : '🗺️ 장소 주소 및 명칭',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(card['extraInfo'], style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cardStyle['color'])),
                        const SizedBox(height: 15),
                      ],
                      const Text('📝 추출 상세 본문', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 5),
                      Text(card['content'], style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87)),
                      const SizedBox(height: 25),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cardStyle['color'],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('확인 완료'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<XFile> pickedImages = ref.watch(pickedImagesProvider);
    final int activeIndex = ref.watch(activeImageIndexProvider);
    final String ocrStatus = ref.watch(ocrStatusProvider);
    final String extractedText = ref.watch(extractedTextProvider);
    final int selectedCategory = ref.watch(selectedCategoryProvider);
    final int selectedSubCategory = ref.watch(selectedSubCategoryProvider); 
    final List<Map<String, dynamic>> savedCards = ref.watch(savedCardsProvider);
    final String currentMenu = ref.watch(currentMenuProvider);

    final titleController = ref.watch(titleControllerProvider);
    final contentController = ref.watch(contentControllerProvider);
    final scheduleDateController = ref.watch(scheduleDateProvider);
    final placeLocationController = ref.watch(placeLocationProvider);

    final style = _getCategoryStyle(selectedCategory, subCategory: selectedCategory == 0 ? selectedSubCategory : 0);

    String appBarTitle = '🌱 소생 - 맞춤 검토 후 분류';
    if (currentMenu == 'cat_0_0') appBarTitle = '📅 일반 일정 보관함';
    if (currentMenu == 'cat_0_1') appBarTitle = '🎟️ 기프티콘 보관함';
    if (currentMenu == 'cat_1') appBarTitle = '📍 장소 보관함';
    if (currentMenu == 'cat_2') appBarTitle = '🎁 위시리스트 보관함';
    if (currentMenu == 'cat_3') appBarTitle = '📝 메모 보관함';

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple[50],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.deepPurple),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🌱 소생 앱', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text('스마트 이미지-텍스트 소생 서랍장', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.collections, color: Colors.deepPurple),
              title: const Text('🔍 스크린샷 소생대기실', style: TextStyle(fontWeight: FontWeight.bold)),
              selected: currentMenu == 'home',
              onTap: () {
                ref.read(currentMenuProvider.notifier).state = 'home';
                Navigator.pop(context);
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 10, bottom: 5),
              child: Text('🗄️ 내 보관 서랍장 목록', style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            
            ExpansionTile(
              leading: const Icon(Icons.calendar_today, color: Colors.blue),
              title: const Text('일정 (SCHEDULE)', style: TextStyle(fontSize: 14)),
              initiallyExpanded: currentMenu.startsWith('cat_0'),
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 45),
                  leading: const Icon(Icons.calendar_month, color: Colors.blueAccent, size: 18),
                  title: const Text('일반 일정', style: TextStyle(fontSize: 13)),
                  selected: currentMenu == 'cat_0_0',
                  onTap: () {
                    ref.read(currentMenuProvider.notifier).state = 'cat_0_0';
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 45),
                  leading: const Icon(Icons.confirmation_number, color: Colors.cyan, size: 18),
                  title: const Text('기프티콘', style: TextStyle(fontSize: 13)),
                  selected: currentMenu == 'cat_0_1',
                  onTap: () {
                    ref.read(currentMenuProvider.notifier).state = 'cat_0_1';
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            
            ListTile(
              leading: const Icon(Icons.map, color: Colors.teal),
              title: const Text('장소 (PLACE)'),
              selected: currentMenu == 'cat_1',
              onTap: () {
                ref.read(currentMenuProvider.notifier).state = 'cat_1';
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_bag, color: Colors.pink),
              title: const Text('위시리스트 (WISHLIST)'),
              selected: currentMenu == 'cat_2',
              onTap: () {
                ref.read(currentMenuProvider.notifier).state = 'cat_2';
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.note, color: Colors.amber),
              title: const Text('메모 (MEMO)'),
              selected: currentMenu == 'cat_3',
              onTap: () {
                ref.read(currentMenuProvider.notifier).state = 'cat_3';
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: currentMenu == 'home'
              ? Column(
                  children: [
                    if (pickedImages.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        height: 180,
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[300]!)),
                        child: const Center(child: Text('소생할 스크린샷들을 선택해 주세요.\n(이미지 고화질 줌인 장착)', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13))),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _pickMultiImages(ref),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('갤러리에서 사진 무더기로 가져오기'),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        ),
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('⏳ 소생 대기열 목록 (${pickedImages.length}장 남음)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple)),
                          TextButton.icon(
                            onPressed: () => _removeActiveImage(ref),
                            icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                            label: const Text('이 사진 삭제', style: TextStyle(color: Colors.red, fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: pickedImages.length,
                          itemBuilder: (context, index) {
                            bool isActive = index == activeIndex;
                            return GestureDetector(
                              onTap: () {
                                ref.read(activeImageIndexProvider.notifier).state = index;
                                ref.read(ocrStatusProvider.notifier).state = 'idle';
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: 60,
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: isActive ? Colors.deepPurple : Colors.grey[300]!, width: isActive ? 3 : 1)),
                                child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(File(pickedImages[index].path), fit: BoxFit.cover)),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 15),

                      Container(
                        width: double.infinity,
                        height: 220,
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(pickedImages[activeIndex].path), fit: BoxFit.contain)),
                      ),
                      const SizedBox(height: 15),

                      if (ocrStatus == 'idle')
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _runSingleOCR(ref, pickedImages[activeIndex]),
                            icon: const Icon(Icons.psychology),
                            label: const Text('⚡ 이 사진 텍스트 추출 및 편집'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100], foregroundColor: Colors.green[900]),
                          ),
                        ),

                      if (ocrStatus == 'loading')
                        const Padding(padding: EdgeInsets.all(15.0), child: CircularProgressIndicator(color: Colors.green)),

                      if (ocrStatus == 'success' && extractedText.isNotEmpty) ...[
                        const SizedBox(height: 15),
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: style['color'], width: 2.5)),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('📁 저장할 대분류 카테고리', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  children: List.generate(4, (index) {
                                    String chipLabel = "메모";
                                    if (index == 0) chipLabel = "일정";
                                    if (index == 1) chipLabel = "장소";
                                    if (index == 2) chipLabel = "위시";
                                    return ChoiceChip(
                                      label: Text(chipLabel, style: const TextStyle(fontSize: 11)),
                                      selected: selectedCategory == index,
                                      onSelected: (selected) {
                                        if (selected) ref.read(selectedCategoryProvider.notifier).state = index;
                                      },
                                    );
                                  }),
                                ),
                                const Divider(),
                                
                                if (selectedCategory == 0) ...[
                                  Text('🎟️ 일정 세부 분류 선택', style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<int>(
                                    value: selectedSubCategory,
                                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                    items: const [
                                      DropdownMenuItem(value: 0, child: Text('🗓️ 일반 스케줄 일정', style: TextStyle(fontSize: 14))),
                                      DropdownMenuItem(value: 1, child: Text('🎟️ 기프티콘 / 쿠폰 교환권', style: TextStyle(fontSize: 14))),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) ref.read(selectedSubCategoryProvider.notifier).state = val;
                                    },
                                  ),
                                  const SizedBox(height: 15),
                                ],

                                Row(
                                  children: [
                                    Icon(style['icon'], color: style['color']),
                                    const SizedBox(width: 8),
                                    Text(style['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: style['color'])),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                TextField(
                                  controller: titleController,
                                  decoration: const InputDecoration(labelText: '📌 제목 수정', border: OutlineInputBorder()),
                                ),
                                const SizedBox(height: 15),
                                
                                if (selectedCategory == 0) ...[
                                  TextField(
                                    controller: scheduleDateController,
                                    decoration: InputDecoration(
                                      labelText: selectedSubCategory == 1 ? '⏰ 기프티콘 유효기간 입력' : '⏰ 일정 일시 입력', 
                                      border: const OutlineInputBorder(), 
                                      prefixIcon: const Icon(Icons.access_time, color: Colors.blue)
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                ],
                                if (selectedCategory == 1) ...[
                                  TextField(
                                    controller: placeLocationController,
                                    decoration: const InputDecoration(labelText: '📍 장소 위치/주소 입력', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pin_drop, color: Colors.teal)),
                                  ),
                                  const SizedBox(height: 15),
                                ],
                                
                                TextField(
                                  controller: contentController,
                                  maxLines: 4,
                                  decoration: const InputDecoration(labelText: '📝 상세 본문 수정', border: OutlineInputBorder()),
                                ),
                                const SizedBox(height: 10),
                                const DynamicFeaturesCard(),
                                const SizedBox(height: 15),
                                Row(
                                   children: [
                                     Expanded(
                                       child: ElevatedButton.icon(
                                         onPressed: () => _runAIAnalysis(context, ref, pickedImages[activeIndex]),
                                         icon: const Icon(Icons.auto_awesome),
                                         label: const Text('AI 분석 (LLM)'),
                                         style: ElevatedButton.styleFrom(
                                           backgroundColor: Colors.deepPurple,
                                           foregroundColor: Colors.white,
                                           padding: const EdgeInsets.symmetric(vertical: 12),
                                         ),
                                       ),
                                     ),
                                     const SizedBox(width: 10),
                                     Expanded(
                                       child: ElevatedButton.icon(
                                         onPressed: () => _saveCurrentCardAndRemoveFromQueue(context, ref),
                                         icon: const Icon(Icons.save),
                                         label: const Text('바로 저장하기'),
                                         style: ElevatedButton.styleFrom(
                                           backgroundColor: style['color'],
                                           foregroundColor: Colors.white,
                                           padding: const EdgeInsets.symmetric(vertical: 12),
                                         ),
                                       ),
                                     ),
                                   ],
                                 )
                              ],
                            ),
                          ),
                        ),
                      ],
                    ]
                  ],
                )
              : Column(
                  children: [
                    NavigatorBuilder(
                      builder: (context) {
                        List<String> menuParts = currentMenu.split('_');
                        int targetCatId = int.parse(menuParts[1]);
                        int? targetSubCatId = menuParts.length > 2 ? int.parse(menuParts[2]) : null;

                        final filteredCards = savedCards.where((c) {
                          if (targetSubCatId != null) {
                            return c['categoryId'] == targetCatId && c['subCategoryId'] == targetSubCatId;
                          }
                          return c['categoryId'] == targetCatId;
                        }).toList();

                        final cardStyle = _getCategoryStyle(targetCatId, subCategory: targetSubCatId ?? 0);

                        if (filteredCards.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 100),
                              child: Column(
                                children: [
                                  Icon(cardStyle['icon'], size: 55, color: Colors.grey[300]),
                                  const SizedBox(height: 10),
                                  Text('이 방은 현재 텅 비어있습니다.\n대기열에서 관련 사진을 저장해 보세요!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredCards.length,
                          itemBuilder: (context, index) {
                            final card = filteredCards[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cardStyle['color'], width: 1.5)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (card['imagePath'] != null)
                                    ClipRRect(
                                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                                      child: Image.file(
                                        File(card['imagePath']),
                                        width: double.infinity,
                                        height: 150,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ListTile(
                                    onTap: () => _showCardDetail(context, card, cardStyle),
                                    leading: CircleAvatar(
                                      backgroundColor: cardStyle['color'].withOpacity(0.15),
                                      child: Icon(cardStyle['icon'], color: cardStyle['color'], size: 18),
                                    ),
                                    title: Text(card['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (card['extraInfo'].toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4, bottom: 4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: cardStyle['color'].withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                              child: Text(card['extraInfo'], style: TextStyle(color: cardStyle['color'], fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                        Text(card['content'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                    trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class NavigatorBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) builder;
  const NavigatorBuilder({super.key, required this.builder});
  @override
  Widget build(BuildContext context) => builder(context);
}

class DynamicFeaturesCard extends ConsumerWidget {
  const DynamicFeaturesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = ref.watch(aiResponseFieldsProvider);
    if (fields == null || fields.isEmpty) return const SizedBox();

    final Map<String, String> fieldLabels = {
      'title': '제목',
      'expires_at': '만료일',
      'start_at': '시작일',
      'name': '상호명',
      'address': '주소',
      'region': '지역',
      'product_name': '상품명',
      'price_amount': '가격',
      'memo': '메모',
      'original_price': '정가',
      'discount_rate': '할인율',
      'category': '카테고리',
      'rating': '평점',
      'hours': '영업시간',
      'seller': '판매처',
      'body': '본문',
      'description': '설명',
      'exchange_place': '교환처',
      'sub_type': '세부 분류',
    };

    // 복수 항목 처리
    final hasItems = fields.containsKey('items') && fields['items'] is List && (fields['items'] as List).isNotEmpty;
    final List<dynamic> items = hasItems ? (fields['items'] as List) : [];
    final currentItemIndex = ref.watch(currentItemIndexProvider);
    final activeIndex = currentItemIndex >= items.length ? 0 : currentItemIndex;

    final activeFields = hasItems ? (items[activeIndex] as Map<String, dynamic>) : fields;

    // 핵심 필드 및 시스템 내부 키 제외
    final excludeKeys = {
      'title', 'expires_at', 'start_at', 'name', 'address',
      'product_name', 'price_amount', 'items', 'body', 'sub_type'
    };

    final entryList = activeFields.entries
        .where((entry) => !excludeKeys.contains(entry.key) && entry.value != null && entry.value.toString().trim().isNotEmpty)
        .toList();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 16),
                    SizedBox(width: 6),
                    Text('✨ AI 추출 상세 정보', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple)),
                  ],
                ),
                if (hasItems)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Text('총 ${items.length}개 항목', style: const TextStyle(fontSize: 10, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const Divider(height: 16),

            // 복수 항목 페이징 조작계
            if (hasItems) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: activeIndex > 0
                        ? () {
                            ref.read(currentItemIndexProvider.notifier).state = activeIndex - 1;
                            _updateActiveItemControllers(ref, items[activeIndex - 1], ref.read(selectedCategoryProvider));
                          }
                        : null,
                    icon: const Icon(Icons.arrow_left, size: 16),
                    label: const Text('이전', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Text('${activeIndex + 1} / ${items.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 15),
                  ElevatedButton.icon(
                    onPressed: activeIndex < items.length - 1
                        ? () {
                            ref.read(currentItemIndexProvider.notifier).state = activeIndex + 1;
                            _updateActiveItemControllers(ref, items[activeIndex + 1], ref.read(selectedCategoryProvider));
                          }
                        : null,
                    icon: const Icon(Icons.arrow_right, size: 16),
                    label: const Text('다음', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            if (entryList.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('추가 추출된 세부 항목이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entryList.length,
                separatorBuilder: (context, index) => const Divider(height: 8, color: Colors.black12),
                itemBuilder: (context, index) {
                  final entry = entryList[index];
                  final label = fieldLabels[entry.key] ?? entry.key;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.value.toString(),
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _updateActiveItemControllers(WidgetRef ref, Map<String, dynamic> item, int categoryIndex) {
    if (categoryIndex == 1) { // PLACE
      ref.read(titleControllerProvider).text = item['name'] ?? '';
      ref.read(placeLocationProvider).text = item['address'] ?? item['region'] ?? '';
    } else if (categoryIndex == 2) { // WISHLIST
      ref.read(titleControllerProvider).text = item['product_name'] ?? '';
    }
  }
}