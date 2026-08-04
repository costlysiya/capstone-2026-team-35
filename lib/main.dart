import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; 
import 'package:flutter_riverpod/legacy.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'core/ml/on_device_text_classifier.dart';
import 'core/storage/app_storage.dart';
import 'core/storage/database_helper.dart';
import 'core/utils/masking_helper.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'screens/notifications_screen.dart';
import 'package:badges/badges.dart' as badges;
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 🎨 소생 앱 디자인 테마 (뮤트파스텔-아이보리-베이지)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class SoseangTheme {
  // 카테고리별 테마 컬러 (레퍼런스 이미지 추출)
  static const Color scheduleColor = Color(0xFFF4B88C);  // 일정 - 주황/피치
  static const Color placeColor    = Color(0xFFA8D8E8);  // 장소 - 하늘
  static const Color wishColor     = Color(0xFFF2C4C4);  // 위시 - 핑크
  static const Color memoColor     = Color(0xFFF2DCA0);  // 메모 - 노랑
  static const Color gifticonColor = Color(0xFFF4B88C);  // 기프티콘 - 일정과 동일하게 주황

  // 카테고리별 진한 텍스트/아이콘 컬러
  static const Color scheduleDark = Color(0xFFD4874E);
  static const Color placeDark    = Color(0xFF5A9BB5);
  static const Color wishDark     = Color(0xFFCC8080);
  static const Color memoDark     = Color(0xFFC4A84E);
  static const Color gifticonDark = Color(0xFFD4874E);

  // 공통 배경색
  static const Color ivory      = Color(0xFFFBF8F1);  // 콘텐츠 영역
  static const Color cream      = Color(0xFFF5ECD7);  // 베이지 배경
  static const Color skyBg      = Color(0xFFC4DFE8);  // 연하늘 배경
  static const Color warmWhite  = Color(0xFFFFF9F0);  // 따뜻한 흰색
  static const Color textDark   = Color(0xFF5A5040);  // 본문 진한 텍스트
  static const Color textMuted  = Color(0xFF9A8E7E);  // 부제목/뮤트 텍스트
  static const Color border     = Color(0xFFE8DFD0);  // 연한 테두리

  // 항목별 테마색 리스트 (index 0~4: 일정/장소/대기실/위시/메모)
  static Color themeOf(String menu) {
    if (menu == 'home') return cream;
    if (menu.startsWith('cat_0')) return scheduleColor;
    if (menu == 'cat_1') return placeColor;
    if (menu == 'cat_2') return wishColor;
    if (menu == 'cat_3') return memoColor;
    return cream;
  }

  static Color darkOf(String menu) {
    if (menu == 'home') return textDark;
    if (menu.startsWith('cat_0')) return scheduleDark;
    if (menu == 'cat_1') return placeDark;
    if (menu == 'cat_2') return wishDark;
    if (menu == 'cat_3') return memoDark;
    return textDark;
  }
}

final onDeviceClassifier = OnDeviceTextClassifier();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await AppStorage.initDirectories();
  await onDeviceClassifier.initialize();

  // 앱 시작 시 로컬 DB에서 'CONFIRMED' 카드 모두 불러오기
  final dbRows = await DatabaseHelper.instance.getScreenshotsByStatus('CONFIRMED');
  final initialCards = dbRows.map((row) {
    int categoryId = 3;
    switch(row['type']) {
      case 'SCHEDULE': categoryId = 0; break;
      case 'PLACE': categoryId = 1; break;
      case 'WISHLIST': categoryId = 2; break;
    }
    
    String title = '제목 없음';
    String content = row['fields'] ?? '';
    String extraInfo = '';
    int subCategoryId = 0;
    
    Map<String, dynamic>? rawFields;
    try {
      if (row['fields'] != null && row['fields'].toString().startsWith('{')) {
        final parsed = jsonDecode(row['fields']);
        title = parsed['title'] ?? title;
        content = parsed['content'] ?? content;
        extraInfo = parsed['extraInfo'] ?? extraInfo;
        subCategoryId = parsed['subCategoryId'] ?? 0;
        rawFields = parsed;
      }
    } catch(e) {}

    return {
      'id': row['id'].toString(),
      'categoryId': categoryId,
      'subCategoryId': subCategoryId,
      'title': title,
      'content': content,
      'extraInfo': extraInfo,
      'imagePath': row['image_path'],
      'rawFields': rawFields,
    };
  }).toList();

  runApp(ProviderScope(
    overrides: [
      savedCardsProvider.overrideWith((ref) => initialCards.reversed.toList()),
    ],
    child: const MyApp()
  ));
}

class OcrDraft {
  final String imagePath;
  final String status; // 'idle', 'loading', 'success', 'error'
  final String extractedText;
  final String title;
  final String content;
  final int category; // 0: 일정, 1: 장소, 2: 위시, 3: 메모
  final int subCategory; // 0: 일반일정, 1: 기프티콘
  final String scheduleDate;
  final String placeLocation;
  final Map<String, dynamic>? aiFields;
  final Map<String, dynamic>? originalSensitiveInfo;

  final String aiStatus; // 'idle', 'loading', 'success', 'error'

  OcrDraft({
    required this.imagePath,
    required this.status,
    this.extractedText = '',
    this.title = '',
    this.content = '',
    this.category = 3,
    this.subCategory = 0,
    this.scheduleDate = '',
    this.placeLocation = '',
    this.aiFields,
    this.originalSensitiveInfo,
    this.aiStatus = 'idle',
  });

  OcrDraft copyWith({
    String? status,
    String? extractedText,
    String? title,
    String? content,
    int? category,
    int? subCategory,
    String? scheduleDate,
    String? placeLocation,
    Map<String, dynamic>? aiFields,
    Map<String, dynamic>? originalSensitiveInfo,
    String? aiStatus,
  }) {
    return OcrDraft(
      imagePath: this.imagePath,
      status: status ?? this.status,
      extractedText: extractedText ?? this.extractedText,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      scheduleDate: scheduleDate ?? this.scheduleDate,
      placeLocation: placeLocation ?? this.placeLocation,
      aiFields: aiFields ?? this.aiFields,
      originalSensitiveInfo: originalSensitiveInfo ?? this.originalSensitiveInfo,
      aiStatus: aiStatus ?? this.aiStatus,
    );
  }
}

// 사용자의 민감정보 원본 로컬 DB 보관 여부 설정
final saveOriginalInfoProvider = StateProvider<bool>((ref) => false);

// 캐시 및 백그라운드 큐 관리 프로바이더
final draftCacheProvider = StateProvider<Map<String, OcrDraft>>((ref) => {});
final queueProgressProvider = StateProvider<String>((ref) => '');
final serverProgressProvider = StateProvider<String>((ref) => '');

// 대기열 및 선택 인덱스 관리
final pickedImagesProvider = StateProvider<List<XFile>>((ref) => []);
final selectionModeProvider = StateProvider<bool>((ref) => false);
final selectedImagesProvider = StateProvider<Set<String>>((ref) => {});
final activeImageIndexProvider = StateProvider<int>((ref) => 0);

final ocrStatusProvider = StateProvider<String>((ref) => 'idle'); 
final extractedTextProvider = StateProvider<String>((ref) => '');

// 카테고리 세팅 (0: 일정, 1: 장소, 2: 위시, 3: 메모)
final selectedCategoryProvider = StateProvider<int>((ref) => 3);
// 일정 카테고리 내부 세부 분류 (0: 일반 일정, 1: 기프티콘)
final selectedSubCategoryProvider = StateProvider<int>((ref) => 0);

// AI 다중 항목 페이징 상태
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

// 장소 탭 전용 상태
final placeRegionProvider = StateProvider<Set<String>>((ref) => {});
final placeSearchProvider = StateProvider<String>((ref) => '');

// 🗓️ 캘린더 관련 상태 (일정 보관함)
final focusedDayProvider = StateProvider<DateTime>((ref) => DateTime.now());
final selectedDayProvider = StateProvider<DateTime?>((ref) => null);
// 선택 삭제 모드
final isSelectModeProvider = StateProvider<bool>((ref) => false);
final selectedCardsIdsProvider = StateProvider<Set<int>>((ref) => {});

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '소생 앱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4874E),
          surface: SoseangTheme.ivory,
        ),
        scaffoldBackgroundColor: SoseangTheme.cream,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: SoseangTheme.textDark,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: SoseangTheme.textDark),
        ),
        cardTheme: CardThemeData(
          color: SoseangTheme.ivory,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: SoseangTheme.border, width: 1),
          ),
        ),
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
    // (Removed aiResponseFieldsProvider state reset)
    ref.read(currentItemIndexProvider.notifier).state = 0;
  }

  // 1. 단일 이미지 로컬 OCR + 온디바이스 AI 분류 및 캐싱 (1차 초안 생성, 100% 로컬)
  Future<OcrDraft> _processAndCacheImage(WidgetRef ref, XFile image) async {
    final currentCache = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
    if (currentCache[image.path]?.status == 'success') {
      return currentCache[image.path]!;
    }

    currentCache[image.path] = OcrDraft(imagePath: image.path, status: 'loading');
    ref.read(draftCacheProvider.notifier).state = currentCache;

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      // 1. Layout-Aware OCR (공간 좌표 기반 텍스트 정렬)
      final List<TextLine> allLines = [];
      for (final block in recognizedText.blocks) {
        allLines.addAll(block.lines);
      }

      // Y축 기준으로 대략적 정렬 (위에서 아래로)
      allLines.sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));

      // Y축이 비슷한(동일 행) 라인들을 그룹화 (오차범위 15픽셀)
      final List<List<TextLine>> rows = [];
      for (final line in allLines) {
        if (rows.isEmpty) {
          rows.add([line]);
        } else {
          final lastRow = rows.last;
          // 현재 라인과 마지막 행의 Y축 중앙값 차이 계산
          final yDiff = (line.boundingBox.center.dy - lastRow.first.boundingBox.center.dy).abs();
          if (yDiff < 15) {
            lastRow.add(line);
          } else {
            rows.add([line]);
          }
        }
      }

      // 각 행 내에서 X축 기준으로 정렬 (왼쪽에서 오른쪽으로)하고 텍스트 조립
      final buffer = StringBuffer();
      for (final row in rows) {
        row.sort((a, b) => a.boundingBox.center.dx.compareTo(b.boundingBox.center.dx));
        buffer.writeln(row.map((e) => e.text).join(' \t ')); // 마크다운 표처럼 구분을 위해 탭 추가
      }
      
      final rawText = buffer.toString().trim();

      if (rawText.isEmpty) {
        final draft = OcrDraft(
          imagePath: image.path,
          status: 'success',
          extractedText: '⚠️ 글자가 없는 이미지입니다.',
          title: '새로운 소생 카드',
          content: '',
          category: 3,
        );
        final cache = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
        cache[image.path] = draft;
        ref.read(draftCacheProvider.notifier).state = cache;
        return draft;
      }

      final lowerText = rawText.toLowerCase();
      
      // 2. 1차 오토필 (제목 추출 정확도 개선)
      String titleText = '새로운 소생 카드';
      for (final row in rows) {
        final text = row.map((e) => e.text).join(' ').trim();
        if (text.isEmpty) continue;
        
        // 상태바(시간, 배터리, 통신사 등) 무시 필터링
        final cleanedText = text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
        final hasTime = RegExp(r'\d{1,2}:\d{2}').hasMatch(cleanedText);
        final hasBattery = RegExp(r'\d{1,3}%').hasMatch(cleanedText);
        final hasCarrier = RegExp(r'(SKT|KT|LG|LGU\+|LTE|5G)').hasMatch(cleanedText);
        
        if (hasTime || hasBattery || hasCarrier) {
           final koreanOrMeaningful = cleanedText.replaceAll(RegExp(r'[A-Z0-9:%]'), '').replaceAll('오전', '').replaceAll('오후', '');
           if (koreanOrMeaningful.length < 2) continue; // 의미 있는 텍스트가 2자 미만이면 상태바로 간주
        }

        if (text.length < 2) continue; // 너무 짧은 단어 무시
        
        titleText = text;
        break; // 의미 있는 첫 번째 줄을 제목으로!
      }

      // 온디바이스 AI 분류기 구동!
      final aiResultType = onDeviceClassifier.classify(rawText);
      final typeToIndex = {
        'SCHEDULE': 0,
        'PLACE': 1,
        'WISHLIST': 2,
        'MEMO': 3,
      };
      int finalCategory = typeToIndex[aiResultType] ?? 3;

      final isIDCard = ['주민등록증', '운전면허증', '여권', 'passport', "driver's license", "driver’s license"].any((k) => lowerText.contains(k)) ||
                       lowerText.contains('<<<<') || lowerText.contains('<<<');
      if (isIDCard) {
        finalCategory = 3; // 신분증/여권은 메모 카테고리로 강제 지정
      }

      int subCat = 0;
      String schedDate = '';
      String pLocation = '';

      if (finalCategory == 0) {
        final isGifticon = ['기프티콘', '쿠폰', '바코드', '교환권', '모바일상품권', '모바일쿠폰', '선물하기', '교환처'].any((k) => lowerText.contains(k)) ||
                           lowerText.contains('사용기한') || lowerText.contains('유효기간');
        if (isGifticon) {
          subCat = 1;
        }
        
        // 날짜 추출 (기프티콘 여부와 무관하게 일정 카테고리 전체 적용)
        final fullTextCleaned = rawText.replaceAll('\n', ' ');
        final dateBase = r'(\d{2,4}[.\-/년]\s?\d{1,2}[.\-/월]\s?\d{1,2}일?)';
        
        // 1. 유효기간, 기한, 마감, 까지 등이 명시된 deadline 최우선 추출
        final deadlinePat = RegExp('(유효기간|유효 기간|기한|마감|기간|일시)[^0-9]*' + dateBase + '|' + dateBase + r'\s*까지');
        final deadlineMatch = deadlinePat.firstMatch(fullTextCleaned);
        
        if (deadlineMatch != null) {
          schedDate = deadlineMatch.group(2) ?? deadlineMatch.group(3) ?? deadlineMatch.group(0)!;
        } else {
          // 2. 명시된 기한이 없으면 일반 날짜 아무거나 추출
          final datePat1 = RegExp(r'\b(\d{2}|\d{4})[.\-/]\d{1,2}[.\-/]\d{1,2}\b');
          final datePat2 = RegExp(r'(\d{2}|\d{4})년\s?\d{1,2}월\s?\d{1,2}일');
          final m1 = datePat1.firstMatch(fullTextCleaned);
          if (m1 != null) {
            schedDate = m1.group(0)!;
          } else {
            final m2 = datePat2.firstMatch(fullTextCleaned);
            if (m2 != null) {
              schedDate = m2.group(0)!;
            }
          }
        }
      } else if (finalCategory == 1) { // PLACE
        // 주소 오토필 로직
        final addressPat = RegExp(r'([가-힣]+(시|도)\s+[가-힣]+(시|군|구)\s+[가-힣]+(동|읍|면|로|길)\s*\d*(-\d+)?)');
        final m1 = addressPat.firstMatch(rawText);
        if (m1 != null) {
          pLocation = m1.group(0)!;
        } else {
          final fallbackPat = RegExp(r'([가-힣]+(시|군|구)\s+[가-힣]+(동|읍|면|로|길)\s*\d+(-\d+)?)');
          final m2 = fallbackPat.firstMatch(rawText);
          if (m2 != null) pLocation = m2.group(0)!;
        }
      }

      // SQLite DB에 1차 초안(DRAFT) 레코드 등록
      try {
        await DatabaseHelper.instance.insertScreenshot({
          'type': aiResultType,
          'confidence': 0.95,
          'fields': jsonEncode({'title': titleText, 'body': rawText, 'expires_at': schedDate, 'address': pLocation}),
          'image_path': image.path,
          'status': 'DRAFT',
        });
      } catch (e) {
        print('DB draft insert error (non-fatal): $e');
      }

      final draft = OcrDraft(
        imagePath: image.path,
        status: 'success',
        extractedText: rawText,
        title: titleText,
        content: rawText,
        category: finalCategory,
        subCategory: subCat,
        scheduleDate: schedDate,
        placeLocation: pLocation,
      );

      final cache = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
      cache[image.path] = draft;
      ref.read(draftCacheProvider.notifier).state = cache;
      return draft;
    } catch (e) {
      final draft = OcrDraft(
        imagePath: image.path,
        status: 'error',
        extractedText: '❌ 분석 실패: $e',
        title: '새로운 소생 카드',
        content: '',
        category: 3,
      );
      final cache = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
      cache[image.path] = draft;
      ref.read(draftCacheProvider.notifier).state = cache;
      return draft;
    }
  }

  // 2. 캐시된 초안 데이터를 UI 폼으로 복사
  void _loadDraftToUI(WidgetRef ref, String imagePath) {
    final cache = ref.read(draftCacheProvider);
    final draft = cache[imagePath];
    if (draft == null) {
      ref.read(ocrStatusProvider.notifier).state = 'idle';
      _clearAllFields(ref);
      return;
    }

    ref.read(ocrStatusProvider.notifier).state = draft.status;
    if (draft.status == 'success' || draft.status == 'error') {
      ref.read(extractedTextProvider.notifier).state = draft.extractedText;
      ref.read(contentControllerProvider).text = draft.content;
      ref.read(titleControllerProvider).text = draft.title;
      ref.read(selectedCategoryProvider.notifier).state = draft.category;
      ref.read(selectedSubCategoryProvider.notifier).state = draft.subCategory;
      ref.read(scheduleDateProvider).text = draft.scheduleDate;
      ref.read(placeLocationProvider).text = draft.placeLocation;
      // (Removed aiResponseFieldsProvider assignment)
    }
  }

  // 3. 사용자가 갤러리에서 다수 사진 선택 시 실행되는 백그라운드 큐
  Future<void> _startBackgroundBatchProcessing(WidgetRef ref, List<XFile> images) async {
    if (images.isEmpty) return;

    ref.read(queueProgressProvider.notifier).state = '분석 준비 중...';
    final activeIndex = ref.read(activeImageIndexProvider);
    final activeImage = images.length > activeIndex ? images[activeIndex] : images.first;

    // activeImage 먼저 즉시 처리하여 UI 표출
    await _processAndCacheImage(ref, activeImage);
    _loadDraftToUI(ref, activeImage.path);

    // 나머지 이미지 순차 백그라운드 처리 (사용자 UI 멈춤 없음)
    for (int i = 0; i < images.length; i++) {
      final img = images[i];
      ref.read(queueProgressProvider.notifier).state = '⚡ 로컬 AI 분석 중 (${i + 1}/${images.length})';
      
      await _processAndCacheImage(ref, img);

      // 현재 사용자가 보고 있는 이미지라면 UI 즉시 동기화
      final currentActiveIndex = ref.read(activeImageIndexProvider);
      final currentPickedList = ref.read(pickedImagesProvider);
      if (currentPickedList.length > currentActiveIndex && currentPickedList[currentActiveIndex].path == img.path) {
        _loadDraftToUI(ref, img.path);
      }
    }

    ref.read(queueProgressProvider.notifier).state = '✅ 로컬 분석 완료';
    Future.delayed(const Duration(seconds: 3), () {
      if (ref.read(queueProgressProvider).startsWith('✅')) {
        ref.read(queueProgressProvider.notifier).state = '';
      }
    });
  }

  // 4. 선택 활성 이미지 변경 시
  void _selectActiveImage(WidgetRef ref, List<XFile> images, int newIndex) {
    ref.read(activeImageIndexProvider.notifier).state = newIndex;
    final selectedImg = images[newIndex];
    final cache = ref.read(draftCacheProvider);

    if (cache[selectedImg.path]?.status == 'success') {
      _loadDraftToUI(ref, selectedImg.path);
    } else {
      // 백그라운드 큐가 아직 안 도달한 이미지를 클릭한 경우 즉시 우선 처리
      ref.read(ocrStatusProvider.notifier).state = 'loading';
      _processAndCacheImage(ref, selectedImg).then((_) {
        _loadDraftToUI(ref, selectedImg.path);
      });
    }
  }

  // 5. 사용자가 카테고리 수동 변경 시 캐시 및 썸네일 동기화
  void _updateActiveDraftCategory(WidgetRef ref, {int? category, int? subCategory}) {
    final images = ref.read(pickedImagesProvider);
    final activeIndex = ref.read(activeImageIndexProvider);
    if (images.isEmpty || activeIndex >= images.length) return;

    final activePath = images[activeIndex].path;
    final cache = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
    final existingDraft = cache[activePath];

    if (existingDraft != null) {
      final updatedCategory = category ?? existingDraft.category;
      final updatedSubCat = subCategory ?? existingDraft.subCategory;

      cache[activePath] = existingDraft.copyWith(
        category: updatedCategory,
        subCategory: updatedSubCat,
      );
      ref.read(draftCacheProvider.notifier).state = cache;
    }
  }

  // 갤러리에서 대량 가져오기 (대기열 최대 20장)
  Future<void> _pickMultiImages(WidgetRef ref) async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> newImages = await picker.pickMultiImage();
    
    if (newImages.isNotEmpty) {
      final currentList = ref.read(pickedImagesProvider);
      final int availableSlots = 20 - currentList.length;
      
      if (availableSlots <= 0) {
        // 이미 20장이 꽉 찼으면 추가 안 함 (선택적: SnackBar 등으로 알림 가능)
        return;
      }

      final addedList = newImages.take(availableSlots).toList();
      final updatedList = [...currentList, ...addedList];
      
      ref.read(pickedImagesProvider.notifier).state = updatedList;
      
      // 만약 기존에 하나도 없었다면 첫번째로 활성화
      if (currentList.isEmpty) {
        ref.read(activeImageIndexProvider.notifier).state = 0;
        ref.read(ocrStatusProvider.notifier).state = 'idle';
        _clearAllFields(ref);
      }

      // 새로 추가된 사진들에 대해서만 백그라운드 처리 시작
      _startBackgroundBatchProcessing(ref, addedList);
    }
  }

  // 현재 선택된 사진 1장만 대기열에서 삭제하는 기능
  void _removeActiveImage(WidgetRef ref) {
    final images = ref.read(pickedImagesProvider);
    final activeIndex = ref.read(activeImageIndexProvider);

    if (images.isEmpty) return;

    final removedImage = images[activeIndex];
    final updatedImages = List<XFile>.from(images)..removeAt(activeIndex);
    ref.read(pickedImagesProvider.notifier).state = updatedImages;

    // 캐시에서도 삭제
    final cache = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
    cache.remove(removedImage.path);
    ref.read(draftCacheProvider.notifier).state = cache;

    if (updatedImages.isNotEmpty) {
      final newIndex = activeIndex >= updatedImages.length ? updatedImages.length - 1 : activeIndex;
      _selectActiveImage(ref, updatedImages, newIndex);
    } else {
      ref.read(activeImageIndexProvider.notifier).state = 0;
      ref.read(ocrStatusProvider.notifier).state = 'idle';
      _clearAllFields(ref);
    }
  }

  Future<XFile?> _cropImage(BuildContext context, String filePath) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: filePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '이미지 자르기',
          toolbarColor: Theme.of(context).colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: '이미지 자르기',
        ),
      ],
    );
    if (croppedFile != null) {
      return XFile(croppedFile.path);
    }
    return null;
  }

  Future<void> _editAndCropActiveImage(BuildContext context, WidgetRef ref) async {
    final images = ref.read(pickedImagesProvider);
    final activeIndex = ref.read(activeImageIndexProvider);
    if (images.isEmpty || activeIndex >= images.length) return;

    final originalFile = images[activeIndex];
    final croppedFile = await _cropImage(context, originalFile.path);
    if (croppedFile != null) {
      // 1. 교체
      final updatedImages = List<XFile>.from(images);
      updatedImages[activeIndex] = croppedFile;
      ref.read(pickedImagesProvider.notifier).state = updatedImages;

      // 2. 이전 캐시 삭제
      final cache = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
      cache.remove(originalFile.path);
      ref.read(draftCacheProvider.notifier).state = cache;

      // 3. 즉시 OCR 큐 다시 돌리기 위해 상태 초기화 및 processAndCache 호출
      ref.read(ocrStatusProvider.notifier).state = 'loading';
      _clearAllFields(ref);
      await _processAndCacheImage(ref, croppedFile);
      _loadDraftToUI(ref, croppedFile.path);
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
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              final isSaving = ref.watch(saveOriginalInfoProvider);
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('개인정보 포함 감지'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('분석할 텍스트 내에 개인정보(주민등록번호, 카드 번호, 바코드 등)로 의심되는 패턴이 감지되었습니다.\n\nAI 분석 서버로 전송하여 자동 구조화 과정을 진행할까요?\n(보안 전송을 위해 민감 데이터는 서버 전송 전 기기 내에서 자동 마스킹 치환됩니다.)'),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: isSaving,
                      onChanged: (val) {
                        setState(() {
                          ref.read(saveOriginalInfoProvider.notifier).state = val ?? false;
                        });
                      },
                      title: const Text('원본 정보 기기 내 안전 보관 허용 (로컬 전용)', style: TextStyle(fontSize: 14)),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.orange,
                    ),
                  ],
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
              );
            },
          );
        },
      ) ?? false;
    }

    if (!proceed) return;

    // 2. 서버 전송 전 익명화 마스킹 수행 및 원본 추출 (옵션)
    Map<String, dynamic>? originalInfo;
    if (ref.read(saveOriginalInfoProvider)) {
      originalInfo = MaskingHelper.extractOriginalSensitiveInfo(rawText);
    }
    
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
    final cacheMap = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
    if (cacheMap.containsKey(image.path)) {
      cacheMap[image.path] = cacheMap[image.path]!.copyWith(
        aiStatus: 'loading',
        originalSensitiveInfo: originalInfo,
      );
      ref.read(draftCacheProvider.notifier).state = cacheMap;
    }
    try {
      final dio = Dio();
      const serverUrl = 'http://44.195.33.82:8000/api/analyze/v2';
      
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

        final typeToIndex = {
          'SCHEDULE': 0,
          'PLACE': 1,
          'WISHLIST': 2,
          'MEMO': 3,
        };
        final categoryIndex = typeToIndex[typeStr] ?? 3;

        int subCategoryIndex = 0;
        String newTitle = '새로운 메모';
        String newSchedule = '';
        String newPlace = '';

        // 1. SCHEDULE 매핑
        String newContent = '';
        if (categoryIndex == 0) {
          final subType = fields['sub_type'] as String?;
          final isGifticon = subType == 'GIFTICON' || 
                             (fields['exchange_place'] != null) ||
                             maskedText.contains('기프티콘') || 
                             maskedText.contains('쿠폰');
          final isSubscription = subType == 'SUBSCRIPTION' ||
                                 maskedText.contains('구독') ||
                                 maskedText.contains('정기결제') ||
                                 maskedText.contains('결제일');
                             
          if (isGifticon) {
            subCategoryIndex = 1;
          } else {
            subCategoryIndex = 0;
          }
          
          newTitle = fields['title'] ?? '새로운 일정';
          newContent = fields['content'] ?? fields['memo'] ?? fields['description'] ?? '';
          
          final expiryDate = fields['expires_at'] as String?;
          final startDate = fields['start_at'] as String?;
          newSchedule = expiryDate ?? startDate ?? '';
        }
        // 2. PLACE 매핑
        else if (categoryIndex == 1) {
          Map<String, dynamic> placeFields = fields;
          if (fields['items'] != null && (fields['items'] as List).isNotEmpty) {
            placeFields = (fields['items'] as List).first as Map<String, dynamic>;
          }
          newTitle = placeFields['name'] ?? '새로운 장소';
          newPlace = placeFields['address'] ?? placeFields['region'] ?? '';
        }
        // 3. WISHLIST 매핑
        else if (categoryIndex == 2) {
          Map<String, dynamic> itemFields = fields;
          if (fields['items'] != null && (fields['items'] as List).isNotEmpty) {
            itemFields = (fields['items'] as List).first as Map<String, dynamic>;
          }
          newTitle = itemFields['product_name'] ?? '새로운 위시 상품';
        }
        // 4. MEMO 매핑
        else if (categoryIndex == 3) {
          newTitle = fields['title'] ?? '새로운 메모';
        }

        // 캐시 업데이트: 다른 탭으로 이동해도 결과가 유지되도록 draft 전체에 저장
        final cacheMap2 = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
        if (cacheMap2.containsKey(image.path)) {
          cacheMap2[image.path] = cacheMap2[image.path]!.copyWith(
            aiStatus: 'success',
            aiFields: fields,
            category: categoryIndex,
            subCategory: subCategoryIndex,
            title: newTitle,
            scheduleDate: newSchedule,
            placeLocation: newPlace,
          );
          ref.read(draftCacheProvider.notifier).state = cacheMap2;
        }
        ref.read(currentItemIndexProvider.notifier).state = 0;

        // 화면 갱신 (선택된 이미지가 현재 이미지와 같은 경우에만)
        final pickedImages = ref.read(pickedImagesProvider);
        final activeIndex = ref.read(activeImageIndexProvider);
        if (pickedImages.isNotEmpty && activeIndex < pickedImages.length && pickedImages[activeIndex].path == image.path) {
          ref.read(selectedCategoryProvider.notifier).state = categoryIndex;
          ref.read(selectedSubCategoryProvider.notifier).state = subCategoryIndex;
          ref.read(titleControllerProvider).text = newTitle;
          ref.read(scheduleDateProvider).text = newSchedule;
          ref.read(placeLocationProvider).text = newPlace;
          if (newContent.isNotEmpty) {
            ref.read(contentControllerProvider).text = newContent;
          }
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
      print('⚠️ AI 로컬 서버 통신 실패 ($e). 온디바이스 AI 분류기로 폴백합니다.');
      
      final aiResultType = onDeviceClassifier.classify(maskedText);
      final typeToIndex = {
        'SCHEDULE': 0,
        'PLACE': 1,
        'WISHLIST': 2,
        'MEMO': 3,
      };
      int finalCategory = typeToIndex[aiResultType] ?? 3;
      int finalSubCategory = 0;

      final lowerText = maskedText.toLowerCase();
      final isIDCard = ['주민등록증', '운전면허증', '여권', 'passport', 'driver\'s license', 'driver’s license'].any((k) => lowerText.contains(k)) ||
                       lowerText.contains('<<<<') ||
                       lowerText.contains('<<<');
      if (isIDCard) {
        finalCategory = 3; // 신분증/여권은 무조건 메모(MEMO) 카테고리로 강제 지정
      }

      if (finalCategory == 0) {
        final isGifticon = ['기프티콘', '쿠폰', '바코드', '교환권', '모바일상품권', '모바일쿠폰', '선물하기', '교환처'].any((k) => lowerText.contains(k)) ||
                           lowerText.contains('사용기한') || lowerText.contains('유효기간');
        if (isGifticon) {
          finalSubCategory = 1; // 기프티콘
        } else {
          finalSubCategory = 0; // 일반 일정
        }
      }

      // Fallback 캐시 업데이트
      final cacheMapFallback = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
      if (cacheMapFallback.containsKey(image.path)) {
        cacheMapFallback[image.path] = cacheMapFallback[image.path]!.copyWith(
          aiStatus: 'error',
          category: finalCategory,
          subCategory: finalSubCategory,
        );
        ref.read(draftCacheProvider.notifier).state = cacheMapFallback;
      }

      final pickedImages = ref.read(pickedImagesProvider);
      final activeIndex = ref.read(activeImageIndexProvider);
      if (pickedImages.isNotEmpty && activeIndex < pickedImages.length && pickedImages[activeIndex].path == image.path) {
        ref.read(selectedCategoryProvider.notifier).state = finalCategory;
        ref.read(selectedSubCategoryProvider.notifier).state = finalSubCategory;
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ AI 서버 연결 실패: 로컬 규칙으로 안전 판정 완료!'))
      );
    } finally {
      final cacheMap3 = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
      if (cacheMap3.containsKey(image.path)) {
        final currentStatus = cacheMap3[image.path]!.aiStatus;
        if (currentStatus == 'loading') {
          cacheMap3[image.path] = cacheMap3[image.path]!.copyWith(aiStatus: 'idle');
          ref.read(draftCacheProvider.notifier).state = cacheMap3;
        }
      }
    }
  }

  Future<void> _runBackgroundAIAnalysis(WidgetRef ref, String imagePath) async {
    final cacheMap = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
    final draft = cacheMap[imagePath];
    if (draft == null) return;
    
    // 로딩 상태 반영
    cacheMap[imagePath] = draft.copyWith(aiStatus: 'loading');
    ref.read(draftCacheProvider.notifier).state = cacheMap;

    final rawText = draft.content;
    if (rawText.trim().isEmpty) {
      _updateDraftError(ref, imagePath, '분석할 텍스트가 없습니다.');
      return;
    }

    final maskedText = MaskingHelper.mask(rawText);

    try {
      final dio = Dio();
      const serverUrl = 'http://44.195.33.82:8000/api/analyze/v2';
      
      final indexToType = {
        0: 'SCHEDULE', 1: 'PLACE', 2: 'WISHLIST', 3: 'MEMO',
      };
      final localType = indexToType[draft.category] ?? 'MEMO';

      final response = await dio.post(
        serverUrl,
        data: {
          'ocr_text': maskedText,
          'type': localType,
          'masked_tokens': <String>[],
        },
        options: Options(contentType: 'application/json'),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final typeStr = data['type'] as String;
        final fields = data['fields'] as Map<String, dynamic>;

        final typeToIndex = {'SCHEDULE': 0, 'PLACE': 1, 'WISHLIST': 2, 'MEMO': 3};
        final categoryIndex = typeToIndex[typeStr] ?? 3;

        int subCategoryIndex = 0;
        String newTitle = '새로운 메모';
        String newSchedule = '';
        String newPlace = '';

        if (categoryIndex == 0) {
          final subType = fields['sub_type'] as String?;
          final isGifticon = subType == 'GIFTICON' || (fields['exchange_place'] != null) ||
                             maskedText.contains('기프티콘') || maskedText.contains('쿠폰');
          subCategoryIndex = isGifticon ? 1 : 0;
          newTitle = fields['title'] ?? '새로운 일정';
          newSchedule = (fields['expires_at'] as String?) ?? (fields['start_at'] as String?) ?? '';
        }
        else if (categoryIndex == 1) {
          Map<String, dynamic> placeFields = fields;
          if (fields['items'] != null && (fields['items'] as List).isNotEmpty) placeFields = (fields['items'] as List).first;
          newTitle = placeFields['name'] ?? '새로운 장소';
          newPlace = placeFields['address'] ?? placeFields['region'] ?? '';
        }
        else if (categoryIndex == 2) {
          Map<String, dynamic> itemFields = fields;
          if (fields['items'] != null && (fields['items'] as List).isNotEmpty) itemFields = (fields['items'] as List).first;
          newTitle = itemFields['product_name'] ?? '새로운 위시 상품';
        }
        else if (categoryIndex == 3) {
          newTitle = fields['title'] ?? '새로운 메모';
        }

        final cacheMap2 = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
        if (cacheMap2.containsKey(imagePath)) {
          cacheMap2[imagePath] = cacheMap2[imagePath]!.copyWith(
            aiStatus: 'success',
            aiFields: fields,
            category: categoryIndex,
            subCategory: subCategoryIndex,
            title: newTitle,
            scheduleDate: newSchedule,
            placeLocation: newPlace,
          );
          ref.read(draftCacheProvider.notifier).state = cacheMap2;
        }

        // 화면 갱신 (선택된 이미지가 현재 활성화된 이미지인 경우)
        final pickedImages = ref.read(pickedImagesProvider);
        final activeIndex = ref.read(activeImageIndexProvider);
        if (pickedImages.isNotEmpty && activeIndex < pickedImages.length && pickedImages[activeIndex].path == imagePath) {
          ref.read(selectedCategoryProvider.notifier).state = categoryIndex;
          ref.read(selectedSubCategoryProvider.notifier).state = subCategoryIndex;
          ref.read(titleControllerProvider).text = newTitle;
          ref.read(scheduleDateProvider).text = newSchedule;
          ref.read(placeLocationProvider).text = newPlace;
        }
      } else {
        throw Exception('서버 응답 비정상');
      }
    } catch (e) {
      _updateDraftError(ref, imagePath, 'AI 분석 실패: 로컬 판정 유지');
    }
  }

  void _updateDraftError(WidgetRef ref, String imagePath, String errorMsg) {
    final cache = Map<String, OcrDraft>.from(ref.read(draftCacheProvider));
    if (cache.containsKey(imagePath)) {
      cache[imagePath] = cache[imagePath]!.copyWith(aiStatus: 'error');
      ref.read(draftCacheProvider.notifier).state = cache;
    }
  }

  void _startBatchAIAnalysis(WidgetRef ref) {
    final selected = ref.read(selectedImagesProvider).toList();
    if (selected.isEmpty) return;
    
    // UI 초기화
    ref.read(selectionModeProvider.notifier).state = false;
    ref.read(selectedImagesProvider.notifier).state = {};

    final total = selected.length;
    int completed = 0;
    ref.read(serverProgressProvider.notifier).state = '🌐 서버 분석 중 (0/$total)';

    for (final imgPath in selected) {
      _runBackgroundAIAnalysis(ref, imgPath).then((_) {
        completed++;
        if (completed >= total) {
          ref.read(serverProgressProvider.notifier).state = '✅ 서버 분석 완료 ($total장)';
          Future.delayed(const Duration(seconds: 3), () {
            // 3초 후 자동으로 숨기기
            if (ref.read(serverProgressProvider).startsWith('✅')) {
              ref.read(serverProgressProvider.notifier).state = '';
            }
          });
        } else {
          ref.read(serverProgressProvider.notifier).state = '🌐 서버 분석 중 ($completed/$total)';
        }
      });
    }
  }

  // 수정본 보관함 최종 저장 분기 로직
  Future<void> _saveCurrentCardAndRemoveFromQueue(BuildContext context, WidgetRef ref) async {
    String title = ref.read(titleControllerProvider).text;
    String content = ref.read(contentControllerProvider).text;
    final categoryId = ref.read(selectedCategoryProvider);
    final subCategoryId = ref.read(selectedSubCategoryProvider); 
    final images = ref.read(pickedImagesProvider);
    final activeIndex = ref.read(activeImageIndexProvider);

    if (title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ 제목을 입력해 주세요.')));
      return;
    }

    // 강조된 빈 필드 확인 (AI 분석 완료 후 필수 필드 검증)
    final ocrStatus = ref.read(ocrStatusProvider);
    if (ocrStatus == 'success') {
      final List<String> emptyFields = [];
      if (categoryId == 0 && ref.read(scheduleDateProvider).text.trim().isEmpty) {
        emptyFields.add('일정 날짜');
      }
      if (categoryId == 1 && ref.read(placeLocationProvider).text.trim().isEmpty) {
        emptyFields.add('장소 위치/주소');
      }
      if (emptyFields.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ 비워진 필드를 먼저 입력해 주세요: ${emptyFields.join(', ')}'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    String extraInfo = "";
    if (categoryId == 0) extraInfo = ref.read(scheduleDateProvider).text;
    if (categoryId == 1) extraInfo = ref.read(placeLocationProvider).text;

    // 기프티콘(0_1)과 위시리스트(2)만 갤러리 원본 스크린샷 사진 주소 저장
    String? finalImagePath;
    if ((categoryId == 0 && subCategoryId == 1) || categoryId == 2) {
      finalImagePath = images[activeIndex].path;
    }

    // 1. 🚀 [새로 추가된 로컬 DB 영구 저장 로직]
    try {
      final indexToType = {
        0: 'SCHEDULE',
        1: 'PLACE',
        2: 'WISHLIST',
        3: 'MEMO',
      };
      
      final activePath = images[activeIndex].path;
      final activeDraft = ref.read(draftCacheProvider)[activePath];
      final aiFields = activeDraft?.aiFields;
      final originalSensitiveInfo = activeDraft?.originalSensitiveInfo;
      
      final bool hasItems = aiFields != null && aiFields.containsKey('items') && aiFields['items'] is List && (aiFields['items'] as List).isNotEmpty;
      final List<dynamic> items = hasItems ? (aiFields['items'] as List) : [];
      
      if (hasItems) {
        final currentIdx = ref.read(currentItemIndexProvider);
        final safeCurrentIdx = currentIdx >= items.length ? 0 : currentIdx;

        for (int i = 0; i < items.length; i++) {
          final item = items[i] as Map<String, dynamic>;
          
          String itemTitle = "";
          String itemExtraInfo = "";
          String itemContent = content; // 본문(OCR원문 등)은 전체적으로 공유

          // 사용자가 현재 화면에서 수정한 항목은 text controller 값 사용
          if (i == safeCurrentIdx) {
            itemTitle = title;
            itemExtraInfo = extraInfo;
          } else {
            // 다른 항목들은 aiFields 내부 값으로 초기화
            if (categoryId == 1) { // PLACE
              itemTitle = item['name']?.toString() ?? '제목 없음';
              itemExtraInfo = item['address']?.toString() ?? item['region']?.toString() ?? '';
            } else if (categoryId == 2) { // WISHLIST
              itemTitle = item['product_name']?.toString() ?? '제목 없음';
              itemExtraInfo = item['price_amount']?.toString() ?? '';
            } else {
              itemTitle = item['title']?.toString() ?? item['name']?.toString() ?? '제목 없음';
              itemExtraInfo = extraInfo;
            }
          }

          if (originalSensitiveInfo != null) {
            itemTitle = MaskingHelper.unmask(itemTitle, originalSensitiveInfo);
            itemContent = MaskingHelper.unmask(itemContent, originalSensitiveInfo);
            itemExtraInfo = MaskingHelper.unmask(itemExtraInfo, originalSensitiveInfo);
          }

          final dbRow = {
            'type': indexToType[categoryId] ?? 'MEMO',
            'confidence': 1.0, 
            'fields': jsonEncode({
              ...item,
              if (originalSensitiveInfo != null) 'original_sensitive_info': originalSensitiveInfo,
              'title': itemTitle,
              'content': itemContent,
              'extraInfo': itemExtraInfo,
              'categoryId': categoryId,
              'subCategoryId': categoryId == 0 ? subCategoryId : 0,
            }),
            'image_path': finalImagePath,
            'status': 'CONFIRMED'
          };
          
          final dbId = await DatabaseHelper.instance.insertScreenshot(dbRow);
          
          final newCard = {
            'id': dbId?.toString() ?? DateTime.now().toString(),
            'categoryId': categoryId,
            'subCategoryId': categoryId == 0 ? subCategoryId : 0, 
            'title': itemTitle,
            'content': itemContent,
            'extraInfo': itemExtraInfo,
            'imagePath': finalImagePath, 
            'rawFields': {
              ...item,
              if (originalSensitiveInfo != null) 'original_sensitive_info': originalSensitiveInfo,
              'title': itemTitle,
              'content': itemContent,
              'extraInfo': itemExtraInfo,
              'categoryId': categoryId,
              'subCategoryId': categoryId == 0 ? subCategoryId : 0,
            },
          };
          ref.read(savedCardsProvider.notifier).update((state) => [newCard, ...state]);
        }
      } else {
        if (originalSensitiveInfo != null) {
          title = MaskingHelper.unmask(title, originalSensitiveInfo);
          content = MaskingHelper.unmask(content, originalSensitiveInfo);
          extraInfo = MaskingHelper.unmask(extraInfo, originalSensitiveInfo);
        }

        final dbRow = {
          'type': indexToType[categoryId] ?? 'MEMO',
          'confidence': 1.0, 
          'fields': jsonEncode({
            if (aiFields != null) ...aiFields,
            if (originalSensitiveInfo != null) 'original_sensitive_info': originalSensitiveInfo,
            'title': title,
            'content': content,
            'extraInfo': extraInfo,
            'categoryId': categoryId,
            'subCategoryId': categoryId == 0 ? subCategoryId : 0,
          }),
          'image_path': finalImagePath,
          'status': 'CONFIRMED' 
        };
        
        final dbId = await DatabaseHelper.instance.insertScreenshot(dbRow);
        
        final newCard = {
          'id': dbId?.toString() ?? DateTime.now().toString(),
          'categoryId': categoryId,
          'subCategoryId': categoryId == 0 ? subCategoryId : 0, 
          'title': title,
          'content': content,
          'extraInfo': extraInfo,
          'imagePath': finalImagePath, 
          'rawFields': {
            if (aiFields != null) ...aiFields,
            if (originalSensitiveInfo != null) 'original_sensitive_info': originalSensitiveInfo,
            'title': title,
            'content': content,
            'extraInfo': extraInfo,
            'categoryId': categoryId,
            'subCategoryId': categoryId == 0 ? subCategoryId : 0,
          },
        };
        ref.read(savedCardsProvider.notifier).update((state) => [newCard, ...state]);
      }
    } catch (e) {
      print('❌ [로컬 DB 저장 실패] $e');
    }

    final updatedImages = List<XFile>.from(images)..removeAt(activeIndex);
    ref.read(pickedImagesProvider.notifier).state = updatedImages;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('💾 지정된 보관함 방으로 입고 및 로컬 DB에 안전하게 영구 저장되었습니다!')));
    }

    if (updatedImages.isNotEmpty) {
      final nextIndex = activeIndex >= updatedImages.length ? updatedImages.length - 1 : activeIndex;
      _selectActiveImage(ref, updatedImages, nextIndex);
    } else {
      ref.read(activeImageIndexProvider.notifier).state = 0;
      ref.read(ocrStatusProvider.notifier).state = 'idle';
      _clearAllFields(ref);
    }
  }

  Map<String, dynamic> _getCategoryStyle(int category, {int subCategory = 0}) {
    if (category == 0 && subCategory == 1) {
      return {'name': '🎟️ 기프티콘 (GIFTICON)', 'color': SoseangTheme.gifticonDark, 'bgColor': SoseangTheme.gifticonColor, 'icon': Icons.confirmation_number};
    }
    switch (category) {
      case 0: return {'name': '📅 일반 일정 (SCHEDULE)', 'color': SoseangTheme.scheduleDark, 'bgColor': SoseangTheme.scheduleColor, 'icon': Icons.event_note};
      case 1: return {'name': '📍 장소 (PLACE)', 'color': SoseangTheme.placeDark, 'bgColor': SoseangTheme.placeColor, 'icon': Icons.place};
      case 2: return {'name': '🎁 위시리스트 (WISHLIST)', 'color': SoseangTheme.wishDark, 'bgColor': SoseangTheme.wishColor, 'icon': Icons.favorite};
      default: return {'name': '📝 메모 (MEMO)', 'color': SoseangTheme.memoDark, 'bgColor': SoseangTheme.memoColor, 'icon': Icons.sticky_note_2};
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

  bool _hasValidAiFields(Map<String, dynamic>? rawFields) {
    if (rawFields == null || rawFields.isEmpty) return false;
    final excludeKeys = { 'title', 'name', 'product_name', 'start_at', 'expires_at', 'address', 'price_amount', 'items', 'body', 'keep_photo', 'map_ready', 'calendar_type', 'reminder_days', 'recurrence', 'confidence', 'status', 'id', 'missing_fields', 'masked_info', 'categoryId', 'subCategoryId', 'content', 'extraInfo' };
    final Map<String, String> fieldLabels = { 'title': '제목', 'memo': '메모', 'sub_type': '세부 분류', 'start_at': '시작일', 'expires_at': '만료일', 'location': '장소', 'barcode_number': '바코드 번호', 'name': '상호명', 'category': '카테고리', 'address': '주소', 'region': '지역', 'product_name': '상품명', 'price_amount': '가격', 'brand_or_store': '브랜드/판매처', 'option': '옵션', 'url': '상품 링크', 'body': '본문', 'tags': '태그', 'original_price': '정가', 'discount_rate': '할인율', 'rating': '평점', 'hours': '영업시간', 'seller': '판매처', 'description': '설명', 'exchange_place': '교환처' };
    
    return rawFields.entries.any((entry) => !excludeKeys.contains(entry.key) && fieldLabels.containsKey(entry.key) && entry.value != null && entry.value.toString().trim().isNotEmpty);
  }

  Widget _buildSavedAiFields(Map<String, dynamic> rawFields) {
    final excludeKeys = {
      'title', 'name', 'product_name',
      'start_at', 'expires_at',
      'address', 'price_amount',
      'items', 'body',
      'keep_photo', 'map_ready',
      'calendar_type', 'reminder_days',
      'recurrence',
      'confidence', 'status', 'id',
      'missing_fields', 'masked_info',
      'categoryId', 'subCategoryId',
      'content', 'extraInfo',
    };

    final Map<String, String> fieldLabels = {
      'title': '제목', 'memo': '메모',
      'sub_type': '세부 분류', 'start_at': '시작일', 'expires_at': '만료일',
      'location': '장소', 'barcode_number': '바코드 번호',
      'name': '상호명', 'category': '카테고리', 'address': '주소', 'region': '지역',
      'product_name': '상품명', 'price_amount': '가격', 'brand_or_store': '브랜드/판매처', 'option': '옵션', 'url': '상품 링크',
      'body': '본문', 'tags': '태그',
      'original_price': '정가', 'discount_rate': '할인율', 'rating': '평점', 'hours': '영업시간', 'seller': '판매처', 'description': '설명', 'exchange_place': '교환처',
    };

    final entryList = rawFields.entries
        .where((entry) => !excludeKeys.contains(entry.key) && fieldLabels.containsKey(entry.key) && entry.value != null && entry.value.toString().trim().isNotEmpty)
        .toList();

    if (entryList.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entryList.map((entry) {
        final label = fieldLabels[entry.key] ?? entry.key;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text(entry.value.toString(), style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // 보관함 항목 클릭 시 띄워줄 상세 디테일 모달 팝업창 시스템
  void _showCardDetail(BuildContext context, WidgetRef ref, Map<String, dynamic> card, Map<String, dynamic> cardStyle) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Stack(
            children: [
              SingleChildScrollView(
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
                      const Divider(color: SoseangTheme.border),
                      const SizedBox(height: 10),
                      if (card['extraInfo'].toString().isNotEmpty) ...[
                        Text(
                          card['categoryId'] == 0 && card['subCategoryId'] == 1
                              ? '⏳ 기프티콘 유효기간'
                              : card['categoryId'] == 0 ? '⏰ 일정 일시 설정'
                              : '🗺️ 장소 주소 및 명칭',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: SoseangTheme.textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(card['extraInfo'], style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cardStyle['color'])),
                        const SizedBox(height: 15),
                      ],
                      if (_hasValidAiFields(card['rawFields'])) ...[
                        const Text('✨ AI 추출 상세 정보', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 12)),
                        const SizedBox(height: 5),
                        _buildSavedAiFields(card['rawFields']),
                      ] else ...[
                        const Text('📝 추출 상세 본문', style: TextStyle(fontWeight: FontWeight.bold, color: SoseangTheme.textMuted, fontSize: 12)),
                        const SizedBox(height: 5),
                        Text(card['content'], style: const TextStyle(fontSize: 14, height: 1.4, color: SoseangTheme.textDark)),
                      ],
                      const SizedBox(height: 25),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                                onPressed: () {
                                  final titleCtrl = TextEditingController(text: card['title']);
                                  final extraCtrl = TextEditingController(text: card['extraInfo']);
                                  final contentCtrl = TextEditingController(text: card['content']);
                                  int editCatId = card['categoryId'] ?? 3;
                                  
                                  final Map<String, TextEditingController> aiFieldCtrls = {};
                                  final Map<String, String> fieldLabels = {
                                    'title': '제목', 'memo': '메모',
                                    'sub_type': '세부 분류', 'start_at': '시작일', 'expires_at': '만료일',
                                    'location': '장소', 'barcode_number': '바코드 번호',
                                    'name': '상호명', 'category': '카테고리', 'address': '주소', 'region': '지역',
                                    'product_name': '상품명', 'price_amount': '가격', 'brand_or_store': '브랜드/판매처', 'option': '옵션', 'url': '상품 링크',
                                    'body': '본문', 'tags': '태그',
                                    'original_price': '정가', 'discount_rate': '할인율', 'rating': '평점', 'hours': '영업시간', 'seller': '판매처', 'description': '설명', 'exchange_place': '교환처',
                                  };
                                  final excludeKeys = { 'title', 'name', 'product_name', 'start_at', 'expires_at', 'address', 'price_amount', 'items', 'body', 'keep_photo', 'map_ready', 'calendar_type', 'reminder_days', 'recurrence', 'confidence', 'status', 'id', 'missing_fields', 'masked_info', 'categoryId', 'subCategoryId', 'content', 'extraInfo' };

                                  if (card['rawFields'] != null && (card['rawFields'] as Map).isNotEmpty) {
                                    for (var entry in (card['rawFields'] as Map).entries) {
                                      if (!excludeKeys.contains(entry.key) && fieldLabels.containsKey(entry.key) && entry.value != null && entry.value.toString().trim().isNotEmpty) {
                                        aiFieldCtrls[entry.key] = TextEditingController(text: entry.value.toString());
                                      }
                                    }
                                  }
                                  
                                  showDialog(
                                  context: context,
                                  builder: (ctx) => StatefulBuilder(
                                    builder: (context, setState) {
                                      return AlertDialog(
                                        title: const Text('카드 수정'),
                                        content: SizedBox(
                                          width: MediaQuery.of(ctx).size.width * 0.9,
                                          child: SingleChildScrollView(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                DropdownButtonFormField<int>(
                                                  value: editCatId,
                                                  decoration: const InputDecoration(labelText: '카테고리'),
                                                  items: const [
                                                    DropdownMenuItem(value: 0, child: Text('일정')),
                                                    DropdownMenuItem(value: 1, child: Text('장소')),
                                                    DropdownMenuItem(value: 2, child: Text('위시리스트')),
                                                    DropdownMenuItem(value: 3, child: Text('메모')),
                                                  ],
                                                  onChanged: (val) {
                                                    if (val != null) setState(() => editCatId = val);
                                                  },
                                                ),
                                                const SizedBox(height: 10),
                                                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '제목')),
                                                const SizedBox(height: 10),
                                                if (editCatId == 0)
                                                  TextField(
                                                    controller: extraCtrl,
                                                    readOnly: true,
                                                    onTap: () async {
                                                      DateTime? pickedDate = await showDatePicker(
                                                        context: context,
                                                        initialDate: DateTime.now(),
                                                        firstDate: DateTime(2000),
                                                        lastDate: DateTime(2101),
                                                      );
                                                      if (pickedDate != null) {
                                                        String formattedDate = "${pickedDate.year}/${pickedDate.month.toString().padLeft(2, '0')}/${pickedDate.day.toString().padLeft(2, '0')}";
                                                        extraCtrl.text = formattedDate;
                                                      }
                                                    },
                                                    decoration: InputDecoration(
                                                      labelText: card['subCategoryId'] == 1 ? '기프티콘 유효기간' : '일정 일시',
                                                      prefixIcon: const Icon(Icons.calendar_today),
                                                    ),
                                                  )
                                                else
                                                  TextField(controller: extraCtrl, decoration: const InputDecoration(labelText: '추가 정보')),
                                                const SizedBox(height: 10),
                                                if (aiFieldCtrls.isNotEmpty) ...[
                                                  const Align(
                                                    alignment: Alignment.centerLeft,
                                                    child: Text('✨ AI 추출 상세 정보', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 12)),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Container(
                                                    width: double.infinity,
                                                    padding: const EdgeInsets.all(10),
                                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.03), borderRadius: BorderRadius.circular(8)),
                                                    child: Column(
                                                      children: aiFieldCtrls.entries.map((e) {
                                                        final label = fieldLabels[e.key] ?? e.key;
                                                        return Padding(
                                                          padding: const EdgeInsets.only(bottom: 8.0),
                                                          child: TextField(
                                                            controller: e.value,
                                                            decoration: InputDecoration(
                                                              labelText: label,
                                                              isDense: true,
                                                            ),
                                                            style: const TextStyle(fontSize: 13),
                                                          ),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  ),
                                                ] else
                                                  TextField(controller: contentCtrl, maxLines: 5, decoration: const InputDecoration(labelText: '추출 본문')),
                                              ],
                                            ),
                                          ),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                                          TextButton(
                                            onPressed: () async {
                                              Map<String, dynamic> updatedRawFields = {};
                                              if (card['rawFields'] != null) {
                                                updatedRawFields = Map<String, dynamic>.from(card['rawFields']);
                                                for (var entry in aiFieldCtrls.entries) {
                                                  updatedRawFields[entry.key] = entry.value.text;
                                                }
                                              }

                                              final newFields = jsonEncode({
                                                if (updatedRawFields.isNotEmpty) ...updatedRawFields,
                                                'title': titleCtrl.text,
                                                'content': contentCtrl.text,
                                                'extraInfo': extraCtrl.text,
                                                'categoryId': editCatId,
                                                'subCategoryId': card['subCategoryId'],
                                              });
                                              final typeStr = const ['SCHEDULE', 'PLACE', 'WISHLIST', 'MEMO'][editCatId];
                                              
                                              await DatabaseHelper.instance.updateTypeAndFields(int.tryParse(card['id'].toString()) ?? -1, typeStr, newFields);
                                              
                                              ref.read(savedCardsProvider.notifier).update((state) {
                                                return state.map((c) {
                                                  if (c['id'] == card['id']) {
                                                    return {
                                                      ...c,
                                                      'title': titleCtrl.text,
                                                      'content': contentCtrl.text,
                                                      'extraInfo': extraCtrl.text,
                                                      'categoryId': editCatId,
                                                      'type': typeStr,
                                                      'rawFields': updatedRawFields.isNotEmpty ? updatedRawFields : c['rawFields'],
                                                    };
                                                  }
                                                  return c;
                                                }).toList();
                                              });
                                              Navigator.pop(ctx);
                                              Navigator.pop(context);
                                            },
                                            child: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      );
                                    }
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cardStyle['color'],
                                side: BorderSide(color: cardStyle['color']),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('수정'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('카드 삭제'),
                                    content: const Text('정말로 이 카드를 삭제하시겠습니까?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await DatabaseHelper.instance.deleteScreenshot(int.tryParse(card['id'].toString()) ?? -1);
                                  ref.read(savedCardsProvider.notifier).update((state) => state.where((c) => c['id'] != card['id']).toList());
                                  if (context.mounted) Navigator.pop(context);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('삭제'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    FCMService().initialize(context);
    final List<XFile> pickedImages = ref.watch(pickedImagesProvider);
    final int activeIndex = ref.watch(activeImageIndexProvider);
    final String ocrStatus = ref.watch(ocrStatusProvider);
    final String extractedText = ref.watch(extractedTextProvider);
    final int selectedCategory = ref.watch(selectedCategoryProvider);
    final int selectedSubCategory = ref.watch(selectedSubCategoryProvider); 
    final List<Map<String, dynamic>> savedCards = ref.watch(savedCardsProvider);
    final String currentMenu = ref.watch(currentMenuProvider);
    final drafts = ref.watch(draftCacheProvider);
    final progressText = ref.watch(queueProgressProvider);
    final selectionMode = ref.watch(selectionModeProvider);
    final selectedImages = ref.watch(selectedImagesProvider);
    final serverProgress = ref.watch(serverProgressProvider);

    List<String> missingFields = [];
    if (pickedImages.isNotEmpty && activeIndex < pickedImages.length) {
      final activePath = pickedImages[activeIndex].path;
      final draft = drafts[activePath];
      final fields = draft?.aiFields;
      if (fields != null) {
        final hasItems = fields.containsKey('items') && fields['items'] is List && (fields['items'] as List).isNotEmpty;
        final List<dynamic> items = hasItems ? (fields['items'] as List) : [];
        final currentItemIndex = ref.watch(currentItemIndexProvider);
        final currentIdx = currentItemIndex >= items.length ? 0 : currentItemIndex;
        final activeFields = hasItems ? (items[currentIdx] as Map<String, dynamic>) : fields;
        if (activeFields['missing_fields'] is List) {
           missingFields = List<String>.from(activeFields['missing_fields']);
        }
      }
    }

    final titleController = ref.watch(titleControllerProvider);
    final contentController = ref.watch(contentControllerProvider);
    final scheduleDateController = ref.watch(scheduleDateProvider);
    final placeLocationController = ref.watch(placeLocationProvider);

    final style = _getCategoryStyle(selectedCategory, subCategory: selectedCategory == 0 ? selectedSubCategory : 0);

    String appBarTitle = '🌱 소생 - 대기실';
    if (currentMenu.startsWith('cat_0')) appBarTitle = '📅 일정 보관함';
    if (currentMenu == 'cat_1') appBarTitle = '📍 장소 보관함';
    if (currentMenu == 'cat_2') appBarTitle = '💝 위시 보관함';
    if (currentMenu == 'cat_3') appBarTitle = '📝 메모 보관함';

    // 현재 탭의 테마 컬러
    final themeColor = SoseangTheme.themeOf(currentMenu);
    final themeDark = SoseangTheme.darkOf(currentMenu);

    // 하단 탭 인덱스 매핑
    int currentTabIndex = 2; // 대기실
    if (currentMenu.startsWith('cat_0')) currentTabIndex = 0;
    if (currentMenu == 'cat_1') currentTabIndex = 1;
    if (currentMenu == 'cat_2') currentTabIndex = 3;
    if (currentMenu == 'cat_3') currentTabIndex = 4;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,

      appBar: AppBar(
        title: Text(appBarTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: badges.Badge(
              showBadge: true, // 안 읽은 알림이 있을 때만 true
              badgeContent: const Text('2', style: TextStyle(color: Colors.white, fontSize: 10)),
              badgeStyle: const badges.BadgeStyle(
                badgeColor: Colors.redAccent,
                padding: EdgeInsets.all(4),
              ),
              child: const Icon(Icons.notifications_none),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SizedBox.expand(
        child: Stack(
          children: [
          // 🎨 투톤 마블링 배경 (항목 변경 시 컬러만 변경)
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              child: CustomPaint(
                painter: MarblePainter(
                  color1: SoseangTheme.cream,
                  color2: themeColor,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          // 📄 메인 콘텐츠 (아이보리 카드)
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: SoseangTheme.ivory,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SoseangTheme.border, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: currentMenu == 'home'
                        ? Column(
                            children: [
                              if (pickedImages.isEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    color: SoseangTheme.cream.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(color: SoseangTheme.border),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '소생할 스크린샷들을 선택해 주세요.\n(이미지 고화질 줌인 장착)',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: SoseangTheme.textMuted, fontSize: 13),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _pickMultiImages(ref),
                                    icon: const Icon(Icons.photo_library),
                                    label: const Text('갤러리에서 사진 무더기로 가져오기'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: SoseangTheme.scheduleDark,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(selectionMode ? '다중 선택 모드' : '⏳ 대기열 (${pickedImages.length}장 남음)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: SoseangTheme.textDark)),
                                    if (progressText.isNotEmpty && !selectionMode)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: SoseangTheme.gifticonColor.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10), border: Border.all(color: SoseangTheme.gifticonDark)),
                                        child: Text(progressText, style: const TextStyle(color: SoseangTheme.gifticonDark, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    if (serverProgress.isNotEmpty && !selectionMode)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: SoseangTheme.placeColor.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10), border: Border.all(color: SoseangTheme.placeDark)),
                                        child: Text(serverProgress, style: const TextStyle(color: SoseangTheme.placeDark, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    Row(
                                      children: [
                                        if (selectionMode) ...[
                                          TextButton(
                                            onPressed: () {
                                              ref.read(selectedImagesProvider.notifier).state = pickedImages.map((e) => e.path).toSet();
                                            },
                                            child: const Text('전체선택', style: TextStyle(color: SoseangTheme.textDark, fontSize: 11)),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              ref.read(selectionModeProvider.notifier).state = false;
                                              ref.read(selectedImagesProvider.notifier).state = {};
                                            },
                                            child: const Text('취소', style: TextStyle(color: SoseangTheme.textMuted, fontSize: 11)),
                                          ),
                                        ] else ...[
                                          TextButton.icon(
                                            onPressed: () => ref.read(selectionModeProvider.notifier).state = true,
                                            icon: const Icon(Icons.check_box_outlined, size: 14, color: SoseangTheme.scheduleDark),
                                            label: const Text('선택', style: TextStyle(color: SoseangTheme.scheduleDark, fontSize: 11)),
                                          ),
                                          TextButton.icon(
                                            onPressed: () => _removeActiveImage(ref),
                                            icon: const Icon(Icons.delete_outline, size: 14, color: SoseangTheme.wishDark),
                                            label: const Text('삭제', style: TextStyle(color: SoseangTheme.wishDark, fontSize: 11)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                SizedBox(
                                  height: 80,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: pickedImages.length + 1,
                                    itemBuilder: (context, index) {
                                      if (index == pickedImages.length) {
                                        return GestureDetector(
                                          onTap: () => _pickMultiImages(ref),
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            width: 65,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: SoseangTheme.border, width: 2),
                                              color: SoseangTheme.cream.withValues(alpha: 0.5),
                                            ),
                                            child: const Center(
                                              child: Icon(Icons.add, color: SoseangTheme.textMuted, size: 28),
                                            ),
                                          ),
                                        );
                                      }

                                      bool isActive = index == activeIndex;
                                      final imgPath = pickedImages[index].path;
                                      final draft = drafts[imgPath];
                                      final isDone = draft?.status == 'success';
                                      final isLoading = draft?.status == 'loading';

                                      Color categoryBorderColor = SoseangTheme.border;
                                      String catIcon = '⚡';

                                      if (isDone) {
                                        final catStyle = _getCategoryStyle(draft!.category, subCategory: draft.subCategory);
                                        categoryBorderColor = catStyle['bgColor'] ?? catStyle['color'];
                                        if (draft.category == 0) catIcon = draft.subCategory == 1 ? '🎟️' : '🗓️';
                                        if (draft.category == 1) catIcon = '📍';
                                        if (draft.category == 2) catIcon = '🛍️';
                                        if (draft.category == 3) catIcon = '📝';
                                      }

                                      if (isActive) {
                                        categoryBorderColor = style['bgColor'] ?? style['color'];
                                      }

                                      final isSelected = selectedImages.contains(imgPath);
                                      return GestureDetector(
                                        onTap: () {
                                          if (selectionMode) {
                                            final updated = Set<String>.from(selectedImages);
                                            if (isSelected) {
                                              updated.remove(imgPath);
                                            } else {
                                              updated.add(imgPath);
                                            }
                                            ref.read(selectedImagesProvider.notifier).state = updated;
                                          } else {
                                            _selectActiveImage(ref, pickedImages, index);
                                          }
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          margin: const EdgeInsets.symmetric(horizontal: 4),
                                          width: 65,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: categoryBorderColor,
                                              width: isActive ? 3.5 : 2.0,
                                            ),
                                            boxShadow: isActive
                                                ? [
                                                    BoxShadow(
                                                      color: categoryBorderColor.withValues(alpha: 0.4),
                                                      blurRadius: 6,
                                                      spreadRadius: 1,
                                                    )
                                                  ]
                                                : null,
                                          ),
                                          child: Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: Image.file(
                                                  File(imgPath),
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                  fit: BoxFit.cover,
                                                  color: isDone && !isActive ? Colors.black.withValues(alpha: 0.2) : null,
                                                  colorBlendMode: isDone && !isActive ? BlendMode.darken : null,
                                                ),
                                              ),
                                              if (isLoading)
                                                Container(
                                                  color: Colors.black38,
                                                  child: const Center(
                                                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                                  ),
                                                ),
                                              if (isDone && !selectionMode)
                                                Positioned(
                                                  right: 2,
                                                  top: 2,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withValues(alpha: 0.7),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(catIcon, style: const TextStyle(fontSize: 10)),
                                                  ),
                                                ),
                                              if (selectionMode)
                                                Positioned(
                                                  right: 2,
                                                  top: 2,
                                                  child: Icon(
                                                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                                                    color: isSelected ? SoseangTheme.scheduleDark : Colors.white70,
                                                    size: 20,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                
                                if (selectionMode && selectedImages.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _startBatchAIAnalysis(ref),
                                      icon: const Icon(Icons.auto_awesome),
                                      label: Text('선택 항목 AI 일괄 분석 (${selectedImages.length}장)'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: SoseangTheme.scheduleDark,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 15),


                                Stack(
                                  children: [
                                    GestureDetector(
                                      onTap: pickedImages.isNotEmpty ? () => _showEnlargedImage(context, pickedImages[activeIndex].path) : null,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        width: double.infinity,
                                        height: 220,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(15),
                                          border: Border.all(color: style['bgColor'] ?? style['color'], width: 2.5),
                                          color: SoseangTheme.cream.withValues(alpha: 0.3),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: Image.file(
                                            File(pickedImages[activeIndex].path),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (ocrStatus == 'loading')
                                      Container(
                                        width: double.infinity,
                                        height: 220,
                                        decoration: BoxDecoration(
                                          color: Colors.black38,
                                          borderRadius: BorderRadius.circular(15),
                                        ),
                                        child: const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(color: Colors.white),
                                              SizedBox(height: 10),
                                              Text('🔍 온디바이스 AI 분석 중...', style: TextStyle(color: Colors.white, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (ocrStatus != 'loading' && pickedImages.isNotEmpty)
                                      Positioned(
                                        bottom: 12,
                                        right: 12,
                                        child: FloatingActionButton.small(
                                          heroTag: 'edit_image_btn',
                                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                                          foregroundColor: Colors.deepPurple,
                                          onPressed: () => _editAndCropActiveImage(context, ref),
                                          child: const Icon(Icons.crop_rotate, size: 20),
                                        ),
                                      ),
                                  ],
                                ),

                                if (ocrStatus == 'success' && extractedText.isNotEmpty) ...[
                                  const SizedBox(height: 15),
                                  Card(
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                      side: BorderSide(color: style['bgColor'] ?? style['color'], width: 2),
                                    ),
                                    color: SoseangTheme.warmWhite,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('📁 저장할 대분류 카테고리', style: TextStyle(fontSize: 12, color: SoseangTheme.textMuted, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            children: List.generate(4, (index) {
                                              String chipLabel = "메모";
                                              if (index == 0) chipLabel = "일정";
                                              if (index == 1) chipLabel = "장소";
                                              if (index == 2) chipLabel = "위시";
                                              final chipStyle = _getCategoryStyle(index);
                                              return ChoiceChip(
                                                label: Text(chipLabel, style: TextStyle(fontSize: 11, color: selectedCategory == index ? Colors.white : chipStyle['color'])),
                                                selected: selectedCategory == index,
                                                selectedColor: chipStyle['color'],
                                                backgroundColor: (chipStyle['bgColor'] as Color).withValues(alpha: 0.3),
                                                onSelected: (selected) {
                                                  if (selected) {
                                                    ref.read(selectedCategoryProvider.notifier).state = index;
                                                    _updateActiveDraftCategory(ref, category: index);
                                                  }
                                                },
                                              );
                                            }),
                                          ),
                                          const Divider(color: SoseangTheme.border),
                                          
                                          if (selectedCategory == 0) ...[
                                            Text('🎟️ 일정 세부 분류 선택', style: TextStyle(fontSize: 12, color: SoseangTheme.scheduleDark, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 6),
                                            DropdownButtonFormField<int>(
                                              value: selectedSubCategory,
                                              decoration: InputDecoration(
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SoseangTheme.border)),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              ),
                                              items: const [
                                                DropdownMenuItem(value: 0, child: Text('🗓️ 일반 스케줄 일정', style: TextStyle(fontSize: 14))),
                                                DropdownMenuItem(value: 1, child: Text('🎟️ 기프티콘 / 쿠폰 교환권', style: TextStyle(fontSize: 14))),
                                              ],
                                              onChanged: (val) {
                                                if (val != null) {
                                                  ref.read(selectedSubCategoryProvider.notifier).state = val;
                                                  _updateActiveDraftCategory(ref, subCategory: val);
                                                }
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
                                          Builder(
                                            builder: (context) {
                                              final isHighlighted = (ocrStatus == 'success' && titleController.text.trim().isEmpty) || missingFields.contains('title') || missingFields.contains('name') || missingFields.contains('product_name');
                                              return TextField(
                                                controller: titleController,
                                                onChanged: (_) => (context as Element).markNeedsBuild(),
                                                decoration: InputDecoration(
                                                  labelText: '📌 제목 수정',
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                    borderSide: isHighlighted ? const BorderSide(color: Colors.redAccent, width: 2) : const BorderSide(),
                                                  ),
                                                  enabledBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                    borderSide: isHighlighted ? const BorderSide(color: Colors.redAccent, width: 2) : const BorderSide(color: Colors.black38),
                                                  ),
                                                  fillColor: isHighlighted ? Colors.red.shade50 : SoseangTheme.ivory,
                                                  filled: true,
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 15),
                                          
                                          if (selectedCategory == 0) ...[
                                            Builder(
                                              builder: (context) {
                                                final isHighlighted = (ocrStatus == 'success' && scheduleDateController.text.trim().isEmpty) || missingFields.contains('start_at') || missingFields.contains('expires_at');
                                                return TextField(
                                                  controller: scheduleDateController,
                                                  readOnly: true,
                                                  onTap: () async {
                                                    DateTime? pickedDate = await showDatePicker(
                                                      context: context,
                                                      initialDate: DateTime.now(),
                                                      firstDate: DateTime(2000),
                                                      lastDate: DateTime(2101),
                                                    );
                                                    if (pickedDate != null) {
                                                      String formattedDate = "${pickedDate.year}/${pickedDate.month.toString().padLeft(2, '0')}/${pickedDate.day.toString().padLeft(2, '0')}";
                                                      scheduleDateController.text = formattedDate;
                                                      (context as Element).markNeedsBuild();
                                                    }
                                                  },
                                                  decoration: InputDecoration(
                                                    labelText: selectedSubCategory == 1 ? '⏰ 기프티콘 유효기간 선택' : '⏰ 일정 날짜 선택', 
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(10),
                                                      borderSide: isHighlighted ? const BorderSide(color: Colors.redAccent, width: 2) : const BorderSide(),
                                                    ),
                                                    enabledBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(10),
                                                      borderSide: isHighlighted ? const BorderSide(color: Colors.redAccent, width: 2) : const BorderSide(color: Colors.black38),
                                                    ),
                                                    prefixIcon: Icon(Icons.calendar_today, color: isHighlighted ? Colors.redAccent : SoseangTheme.scheduleDark),
                                                    fillColor: isHighlighted ? Colors.red.shade50 : SoseangTheme.ivory,
                                                    filled: true,
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 15),
                                          ],
                                          if (selectedCategory == 1) ...[
                                            Builder(
                                              builder: (context) {
                                                final isHighlighted = (ocrStatus == 'success' && placeLocationController.text.trim().isEmpty) || missingFields.contains('address');
                                                return TextField(
                                                  controller: placeLocationController,
                                                  onChanged: (_) => (context as Element).markNeedsBuild(),
                                                  decoration: InputDecoration(
                                                    labelText: '📍 장소 위치/주소 입력',
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(10),
                                                      borderSide: isHighlighted ? const BorderSide(color: Colors.redAccent, width: 2) : const BorderSide(),
                                                    ),
                                                    enabledBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(10),
                                                      borderSide: isHighlighted ? const BorderSide(color: Colors.redAccent, width: 2) : const BorderSide(color: Colors.black38),
                                                    ),
                                                    prefixIcon: Icon(Icons.pin_drop, color: isHighlighted ? Colors.redAccent : SoseangTheme.placeDark),
                                                    fillColor: isHighlighted ? Colors.red.shade50 : SoseangTheme.ivory,
                                                    filled: true,
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 15),
                                          ],
                                          
                                          if ((ref.watch(draftCacheProvider)[pickedImages[activeIndex].path])?.aiFields == null)
                                            Builder(
                                              builder: (context) {
                                                final isHighlighted = ocrStatus == 'success' && contentController.text.trim().isEmpty;
                                                return TextField(
                                                  controller: contentController,
                                                  maxLines: 4,
                                                  onChanged: (_) => (context as Element).markNeedsBuild(),
                                                  decoration: InputDecoration(
                                                    labelText: '📝 원본 OCR 텍스트',
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(10),
                                                      borderSide: isHighlighted ? const BorderSide(color: Colors.redAccent, width: 2) : const BorderSide(),
                                                    ),
                                                    enabledBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(10),
                                                      borderSide: isHighlighted ? const BorderSide(color: Colors.redAccent, width: 2) : const BorderSide(color: Colors.black38),
                                                    ),
                                                    fillColor: isHighlighted ? Colors.red.shade50 : SoseangTheme.ivory,
                                                    filled: true,
                                                  ),
                                                );
                                              },
                                            ),
                                          const SizedBox(height: 10),
                                          const DynamicFeaturesCard(),
                                          const SizedBox(height: 15),
                                          Row(
                                             children: [
                                               Expanded(
                                                 child: ElevatedButton.icon(
                                                   onPressed: (ref.watch(draftCacheProvider)[pickedImages[activeIndex].path])?.aiStatus == 'loading' 
                                                       ? null 
                                                       : () => _runAIAnalysis(context, ref, pickedImages[activeIndex]),
                                                   icon: (ref.watch(draftCacheProvider)[pickedImages[activeIndex].path])?.aiStatus == 'loading'
                                                       ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                                       : const Icon(Icons.auto_awesome),
                                                   label: Text((ref.watch(draftCacheProvider)[pickedImages[activeIndex].path])?.aiStatus == 'loading' ? '분석 중...' : 'AI 분석 (LLM)'),
                                                   style: ElevatedButton.styleFrom(
                                                     backgroundColor: SoseangTheme.textDark,
                                                     foregroundColor: Colors.white,
                                                     padding: const EdgeInsets.symmetric(vertical: 12),
                                                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                                                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                              Builder(
                                builder: (context) {
                                  List<String> menuParts = currentMenu.split('_');
                                  int targetCatId = int.parse(menuParts[1]);
                                  int? targetSubCatId = menuParts.length > 2 ? int.parse(menuParts[2]) : null;

                                  final selectedDay = ref.watch(selectedDayProvider);
                                  final focusedDay = ref.watch(focusedDayProvider);

                                  final filteredCards = savedCards.where((c) {
                                    // 캘린더 날짜 필터링 (선택된 날짜가 있을 때: 일반일정/기프티콘 통합)
                                    if (currentMenu.startsWith('cat_0') && selectedDay != null) {
                                      if (c['categoryId'] != targetCatId) return false;
                                      
                                      String cardDateStr = c['extraInfo'] ?? '';
                                      if (cardDateStr.isNotEmpty) {
                                        bool match = false;
                                        RegExp dateRegExp = RegExp(r'(\d{4})[^\d]+(\d{1,2})[^\d]+(\d{1,2})');
                                        var rMatch = dateRegExp.firstMatch(cardDateStr);
                                        if (rMatch != null) {
                                          int cy = int.parse(rMatch.group(1)!);
                                          int cm = int.parse(rMatch.group(2)!);
                                          int cd = int.parse(rMatch.group(3)!);
                                          if (cy == selectedDay.year && cm == selectedDay.month && cd == selectedDay.day) match = true;
                                        } else {
                                          String selectedDateStr = DateFormat('yyyy/MM/dd').format(selectedDay);
                                          if (cardDateStr.contains(selectedDateStr)) match = true;
                                        }
                                        if (!match) return false;
                                      } else {
                                        return false; // 날짜 정보 없으면 숨김
                                      }
                                      return true; // 여기서 true로 바로 반환 (서브카테고리 무시)
                                    }

                                    // 장소 보관함(cat_1) 검색 및 지역 필터
                                    if (currentMenu == 'cat_1') {
                                      if (c['categoryId'] != targetCatId) return false;
                                      
                                      final searchStr = ref.watch(placeSearchProvider).toLowerCase();
                                      final region = ref.watch(placeRegionProvider);
                                      
                                      if (searchStr.isNotEmpty) {
                                        final title = (c['title'] ?? '').toString().toLowerCase();
                                        final extra = (c['extraInfo'] ?? '').toString().toLowerCase();
                                        if (!title.contains(searchStr) && !extra.contains(searchStr)) return false;
                                      }
                                      
                                      if (region.isNotEmpty) {
                                        final extra = (c['extraInfo'] ?? '').toString();
                                        bool regionMatched = false;
                                        for (String r in region) {
                                          if (extra.contains(r)) {
                                            regionMatched = true;
                                            break;
                                          }
                                        }
                                        if (!regionMatched) return false;
                                      }
                                      return true;
                                    }

                                    // 날짜 미선택 시 평소 필터링
                                    if (targetSubCatId != null) {
                                      if (c['categoryId'] != targetCatId || c['subCategoryId'] != targetSubCatId) return false;
                                    } else {
                                      if (c['categoryId'] != targetCatId) return false;
                                    }
                                    return true;
                                  }).toList();

                                  final isSelectMode = ref.watch(isSelectModeProvider);
                                  final selectedIds = ref.watch(selectedCardsIdsProvider);

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        if (currentMenu.startsWith('cat_0')) ...[
                                          // 🗓️ 캘린더 위젯
                                          Container(
                                            margin: const EdgeInsets.only(bottom: 16),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(color: SoseangTheme.border),
                                            ),
                                            child: TableCalendar(
                                              firstDay: DateTime.utc(2020, 1, 1),
                                              lastDay: DateTime.utc(2030, 12, 31),
                                              focusedDay: focusedDay,
                                              headerStyle: const HeaderStyle(
                                                formatButtonVisible: false,
                                                titleCentered: true,
                                              ),
                                              selectedDayPredicate: (day) => isSameDay(selectedDay, day),
                                              onDaySelected: (sDay, fDay) {
                                                // 동일 날짜 누르면 선택 해제 (전체 보기)
                                                if (isSameDay(selectedDay, sDay)) {
                                                  ref.read(selectedDayProvider.notifier).state = null;
                                                } else {
                                                  ref.read(selectedDayProvider.notifier).state = sDay;
                                                  ref.read(focusedDayProvider.notifier).state = fDay;
                                                }
                                              },
                                              calendarStyle: CalendarStyle(
                                                selectedDecoration: const BoxDecoration(
                                                  color: SoseangTheme.scheduleColor,
                                                  shape: BoxShape.circle,
                                                ),
                                                todayDecoration: BoxDecoration(
                                                  color: SoseangTheme.scheduleColor.withOpacity(0.3),
                                                  shape: BoxShape.circle,
                                                ),
                                                markerDecoration: const BoxDecoration(
                                                  color: SoseangTheme.scheduleDark,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              eventLoader: (day) {
                                                return savedCards.where((c) {
                                                  if (c['categoryId'] != 0) return false;
                                                  String extra = c['extraInfo'] ?? '';
                                                  if (extra.isEmpty) return false;
                                                  
                                                  RegExp dateRegExp = RegExp(r'(\d{4})[^\d]+(\d{1,2})[^\d]+(\d{1,2})');
                                                  var rMatch = dateRegExp.firstMatch(extra);
                                                  if (rMatch != null) {
                                                    int cy = int.parse(rMatch.group(1)!);
                                                    int cm = int.parse(rMatch.group(2)!);
                                                    int cd = int.parse(rMatch.group(3)!);
                                                    if (cy == day.year && cm == day.month && cd == day.day) return true;
                                                  }
                                                  
                                                  String dayStr = DateFormat('yyyy/MM/dd').format(day);
                                                  return extra.contains(dayStr);
                                                }).toList();
                                              },
                                            ),
                                          ),
                                        ],
                                        if (currentMenu == 'cat_1') ...[
                                          // 장소 검색 바
                                          TextField(
                                            onChanged: (val) => ref.read(placeSearchProvider.notifier).state = val,
                                            decoration: InputDecoration(
                                              hintText: '상호명 또는 주소로 검색',
                                              prefixIcon: const Icon(Icons.search, color: SoseangTheme.placeColor),
                                              filled: true,
                                              fillColor: Colors.white,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: SoseangTheme.placeColor.withOpacity(0.5))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: SoseangTheme.placeColor.withOpacity(0.5))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: SoseangTheme.placeColor, width: 2)),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          // 다중 선택 지역 필터 드롭다운 버튼
                                          Builder(
                                            builder: (ctx) {
                                              final selectedRegions = ref.watch(placeRegionProvider);
                                              final allRegions = ['서울', '부산', '대구', '인천', '광주', '대전', '울산', '경기', '강원', '충청', '전라', '경북', '경남', '제주', '해외'];
                                              String btnText = '전체';
                                              if (selectedRegions.isNotEmpty) {
                                                btnText = selectedRegions.first;
                                                if (selectedRegions.length > 1) {
                                                  btnText += ' 외 ${selectedRegions.length - 1}곳';
                                                }
                                              }
                                              return InkWell(
                                                onTap: () {
                                                  showDialog(
                                                    context: context,
                                                    builder: (dCtx) {
                                                      final currentSelected = Set<String>.from(ref.read(placeRegionProvider));
                                                      return StatefulBuilder(
                                                        builder: (context, setState) {
                                                          return AlertDialog(
                                                            title: const Text('지역 다중 선택', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                            contentPadding: const EdgeInsets.only(top: 12, bottom: 0),
                                                            content: SizedBox(
                                                              width: double.maxFinite,
                                                              child: ListView.builder(
                                                                shrinkWrap: true,
                                                                itemCount: allRegions.length,
                                                                itemBuilder: (context, index) {
                                                                  final region = allRegions[index];
                                                                  final count = savedCards.where((c) => c['categoryId'] == 1 && (c['extraInfo'] ?? '').toString().contains(region)).length;
                                                                  return CheckboxListTile(
                                                                    title: Text('$region ($count)', style: const TextStyle(fontSize: 14)),
                                                                    value: currentSelected.contains(region),
                                                                    activeColor: SoseangTheme.placeColor,
                                                                    dense: true,
                                                                    controlAffinity: ListTileControlAffinity.leading,
                                                                    onChanged: (val) {
                                                                      setState(() {
                                                                        if (val == true) {
                                                                          currentSelected.add(region);
                                                                        } else {
                                                                          currentSelected.remove(region);
                                                                        }
                                                                      });
                                                                    },
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () => setState(() => currentSelected.clear()),
                                                                child: const Text('초기화', style: TextStyle(color: SoseangTheme.textMuted)),
                                                              ),
                                                              ElevatedButton(
                                                                onPressed: () {
                                                                  ref.read(placeRegionProvider.notifier).state = currentSelected;
                                                                  Navigator.pop(dCtx);
                                                                },
                                                                style: ElevatedButton.styleFrom(backgroundColor: SoseangTheme.placeColor, foregroundColor: Colors.white),
                                                                child: const Text('적용'),
                                                              ),
                                                            ],
                                                          );
                                                        },
                                                      );
                                                    }
                                                  );
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(color: SoseangTheme.placeColor.withOpacity(0.5)),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(btnText, style: const TextStyle(fontSize: 14, color: SoseangTheme.placeDark)),
                                                      const Icon(Icons.arrow_drop_down, color: SoseangTheme.placeColor),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                        Row(
                                          children: [
                                        if (currentMenu.startsWith('cat_0')) ...[
                                          if (selectedDay == null) ...[
                                            ChoiceChip(
                                              label: const Text('🗓️ 일반 일정', style: TextStyle(fontSize: 12)),
                                              selected: currentMenu == 'cat_0_0' || currentMenu == 'cat_0',
                                              selectedColor: SoseangTheme.scheduleColor,
                                              onSelected: (_) => ref.read(currentMenuProvider.notifier).state = 'cat_0_0',
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            const SizedBox(width: 8),
                                            ChoiceChip(
                                              label: const Text('🎟️ 기프티콘', style: TextStyle(fontSize: 12)),
                                              selected: currentMenu == 'cat_0_1',
                                              selectedColor: SoseangTheme.gifticonColor,
                                              onSelected: (_) => ref.read(currentMenuProvider.notifier).state = 'cat_0_1',
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          ] else ...[
                                            const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                              child: Text('해당 날짜의 모든 일정 (기프티콘 포함)', style: TextStyle(fontWeight: FontWeight.bold, color: SoseangTheme.textMuted, fontSize: 13)),
                                            ),
                                          ],
                                        ],
                                        const Spacer(),
                                        if (filteredCards.isNotEmpty)
                                          if (isSelectMode) ...[
                                            TextButton(
                                              onPressed: () {
                                                if (selectedIds.length == filteredCards.length && filteredCards.isNotEmpty) {
                                                  ref.read(selectedCardsIdsProvider.notifier).state = {};
                                                } else {
                                                  final allIds = filteredCards.map((c) => int.tryParse(c['id'].toString()) ?? -1).where((id) => id != -1).toSet();
                                                  ref.read(selectedCardsIdsProvider.notifier).state = allIds;
                                                }
                                              },
                                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                              child: Text(selectedIds.length == filteredCards.length && filteredCards.isNotEmpty ? '전체 해제' : '전체 선택', style: const TextStyle(fontSize: 12)),
                                            ),
                                            const SizedBox(width: 4),
                                            TextButton.icon(
                                              icon: const Icon(Icons.delete, color: Colors.red, size: 14),
                                              label: Text('삭제 (${selectedIds.length})', style: const TextStyle(color: Colors.red, fontSize: 12)),
                                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                              onPressed: selectedIds.isEmpty ? null : () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: const Text('선택 삭제'),
                                                    content: Text('${selectedIds.length}개의 항목을 삭제하시겠습니까?'),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                                                    ],
                                                  ),
                                                );
                                                if (confirm == true) {
                                                  await DatabaseHelper.instance.deleteMultipleScreenshots(selectedIds.toList());
                                                  ref.read(savedCardsProvider.notifier).update((state) => state.where((c) => !selectedIds.contains(int.tryParse(c['id'].toString()) ?? -1)).toList());
                                                  ref.read(isSelectModeProvider.notifier).state = false;
                                                  ref.read(selectedCardsIdsProvider.notifier).state = {};
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 4),
                                            TextButton(
                                              onPressed: () {
                                                ref.read(isSelectModeProvider.notifier).state = false;
                                                ref.read(selectedCardsIdsProvider.notifier).state = {};
                                              },
                                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                              child: const Text('취소', style: TextStyle(color: SoseangTheme.textMuted, fontSize: 12)),
                                            ),
                                          ] else
                                            TextButton.icon(
                                              icon: const Icon(Icons.checklist, size: 14),
                                              label: const Text('선택', style: TextStyle(fontSize: 12)),
                                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                              onPressed: () {
                                                ref.read(isSelectModeProvider.notifier).state = true;
                                                ref.read(selectedCardsIdsProvider.notifier).state = {};
                                              },
                                            ),
                                      ],
                                    ), // Row
                                  ],
                                ), // Column
                              ); // Padding
                            },
                          ),
                              NavigatorBuilder(
                                builder: (context) {
                                  List<String> menuParts = currentMenu.split('_');
                                  int targetCatId = int.parse(menuParts[1]);
                                  int? targetSubCatId = menuParts.length > 2 ? int.parse(menuParts[2]) : null;

                                  final selectedDay = ref.watch(selectedDayProvider);

                                  final filteredCards = savedCards.where((c) {
                                    // 캘린더 날짜 필터링 (선택된 날짜가 있을 때: 일반일정/기프티콘 통합)
                                    if (currentMenu.startsWith('cat_0') && selectedDay != null) {
                                      if (c['categoryId'] != targetCatId) return false;
                                      
                                      String cardDateStr = c['extraInfo'] ?? '';
                                      if (cardDateStr.isNotEmpty) {
                                        bool match = false;
                                        RegExp dateRegExp = RegExp(r'(\d{4})[^\d]+(\d{1,2})[^\d]+(\d{1,2})');
                                        var rMatch = dateRegExp.firstMatch(cardDateStr);
                                        if (rMatch != null) {
                                          int cy = int.parse(rMatch.group(1)!);
                                          int cm = int.parse(rMatch.group(2)!);
                                          int cd = int.parse(rMatch.group(3)!);
                                          if (cy == selectedDay.year && cm == selectedDay.month && cd == selectedDay.day) match = true;
                                        } else {
                                          String selectedDateStr = DateFormat('yyyy/MM/dd').format(selectedDay);
                                          if (cardDateStr.contains(selectedDateStr)) match = true;
                                        }
                                        if (!match) return false;
                                      } else {
                                        return false; // 날짜 정보 없으면 숨김
                                      }
                                      return true; // 여기서 true로 바로 반환 (서브카테고리 무시)
                                    }

                                    // 장소 보관함(cat_1) 검색 및 지역 필터
                                    if (currentMenu == 'cat_1') {
                                      if (c['categoryId'] != targetCatId) return false;
                                      
                                      final searchStr = ref.watch(placeSearchProvider).toLowerCase();
                                      final region = ref.watch(placeRegionProvider);
                                      
                                      if (searchStr.isNotEmpty) {
                                        final title = (c['title'] ?? '').toString().toLowerCase();
                                        final extra = (c['extraInfo'] ?? '').toString().toLowerCase();
                                        if (!title.contains(searchStr) && !extra.contains(searchStr)) return false;
                                      }
                                      
                                      if (region.isNotEmpty) {
                                        final extra = (c['extraInfo'] ?? '').toString();
                                        bool regionMatched = false;
                                        for (String r in region) {
                                          if (extra.contains(r)) {
                                            regionMatched = true;
                                            break;
                                          }
                                        }
                                        if (!regionMatched) return false;
                                      }
                                      return true;
                                    }

                                    // 날짜 미선택 시 평소 필터링
                                    if (targetSubCatId != null) {
                                      return c['categoryId'] == targetCatId && c['subCategoryId'] == targetSubCatId;
                                    }
                                    return c['categoryId'] == targetCatId;
                                  }).toList();

                                  final cardStyle = _getCategoryStyle(targetCatId, subCategory: targetSubCatId ?? 0);
                                  final isSelectMode = ref.watch(isSelectModeProvider);
                                  final selectedIds = ref.watch(selectedCardsIdsProvider);

                                  return Column(
                                    children: [
                                      if (filteredCards.isEmpty)
                                        Center(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 80),
                                            child: Column(
                                              children: [
                                                Icon(cardStyle['icon'], size: 55, color: SoseangTheme.border),
                                                const SizedBox(height: 10),
                                                const Text('이 방은 현재 텅 비어있습니다.\n대기실에서 관련 사진을 저장해 보세요!', textAlign: TextAlign.center, style: TextStyle(color: SoseangTheme.textMuted, fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                        )
                                      else
                                        ListView.builder(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          itemCount: filteredCards.length,
                                          itemBuilder: (context, index) {
                                            final card = filteredCards[index];
                                            return Card(
                                              margin: const EdgeInsets.symmetric(vertical: 8),
                                              elevation: 2,
                                              color: SoseangTheme.warmWhite,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(14),
                                                side: BorderSide(color: cardStyle['bgColor'] ?? cardStyle['color'], width: 1.5),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  ListTile(
                                                    onTap: () {
                                                      if (isSelectMode) {
                                                        final id = int.tryParse(card['id'].toString()) ?? -1;
                                                        final ids = Set<int>.from(selectedIds);
                                                        if (ids.contains(id)) ids.remove(id); else ids.add(id);
                                                        ref.read(selectedCardsIdsProvider.notifier).state = ids;
                                                      } else {
                                                        _showCardDetail(context, ref, card, cardStyle);
                                                      }
                                                    },
                                                    leading: CircleAvatar(
                                                      backgroundColor: (cardStyle['bgColor'] as Color?)?.withValues(alpha: 0.3) ?? cardStyle['color'].withValues(alpha: 0.15),
                                                      child: Icon(cardStyle['icon'], color: cardStyle['color'], size: 18),
                                                    ),
                                                    title: Text(card['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: SoseangTheme.textDark)),
                                                    subtitle: card['extraInfo'].toString().isNotEmpty
                                                        ? Padding(
                                                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                                                            child: Row(
                                                              children: [
                                                                if (card['categoryId'] == 0) ...[
                                                                  Icon(Icons.calendar_today, size: 14, color: cardStyle['color']),
                                                                  const SizedBox(width: 4),
                                                                ] else if (card['categoryId'] == 1) ...[
                                                                  Icon(Icons.pin_drop, size: 14, color: cardStyle['color']),
                                                                  const SizedBox(width: 4),
                                                                ],
                                                                Expanded(
                                                                  child: Text(
                                                                    card['extraInfo'],
                                                                    style: TextStyle(color: cardStyle['color'], fontSize: 13, fontWeight: FontWeight.w600),
                                                                    maxLines: 1,
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        : const SizedBox.shrink(),
                                                    trailing: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        if (card['imagePath'] != null) ...[
                                                          ClipRRect(
                                                            borderRadius: BorderRadius.circular(8),
                                                            child: Image.file(
                                                              File(card['imagePath']),
                                                              width: 48,
                                                              height: 48,
                                                              fit: BoxFit.cover,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                        ],
                                                        if (isSelectMode)
                                                          Checkbox(
                                                            value: selectedIds.contains(int.tryParse(card['id'].toString()) ?? -1),
                                                            onChanged: (val) {
                                                              final id = int.tryParse(card['id'].toString()) ?? -1;
                                                              final ids = Set<int>.from(selectedIds);
                                                              if (val == true) ids.add(id); else ids.remove(id);
                                                              ref.read(selectedCardsIdsProvider.notifier).state = ids;
                                                            },
                                                          )
                                                        else
                                                          const Icon(Icons.arrow_forward_ios, size: 12, color: SoseangTheme.textMuted),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
      bottomNavigationBar: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
          color: SoseangTheme.ivory,
          border: const Border(top: BorderSide(color: SoseangTheme.border, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentTabIndex,
          onTap: (index) {
            switch (index) {
              case 0: ref.read(currentMenuProvider.notifier).state = 'cat_0_0'; break;
              case 1: ref.read(currentMenuProvider.notifier).state = 'cat_1'; break;
              case 2: ref.read(currentMenuProvider.notifier).state = 'home'; break;
              case 3: ref.read(currentMenuProvider.notifier).state = 'cat_2'; break;
              case 4: ref.read(currentMenuProvider.notifier).state = 'cat_3'; break;
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: themeDark,
          unselectedItemColor: SoseangTheme.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.event_note, color: currentTabIndex == 0 ? SoseangTheme.scheduleDark : SoseangTheme.textMuted),
              activeIcon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: SoseangTheme.scheduleColor.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.event_note, color: SoseangTheme.scheduleDark),
              ),
              label: '일정',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.place, color: currentTabIndex == 1 ? SoseangTheme.placeDark : SoseangTheme.textMuted),
              activeIcon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: SoseangTheme.placeColor.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.place, color: SoseangTheme.placeDark),
              ),
              label: '장소',
            ),
            const BottomNavigationBarItem(
              icon: SizedBox(height: 24),
              activeIcon: SizedBox(height: 40),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border, color: currentTabIndex == 3 ? SoseangTheme.wishDark : SoseangTheme.textMuted),
              activeIcon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: SoseangTheme.wishColor.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.favorite, color: SoseangTheme.wishDark),
              ),
              label: '위시',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sticky_note_2_outlined, color: currentTabIndex == 4 ? SoseangTheme.memoDark : SoseangTheme.textMuted),
              activeIcon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: SoseangTheme.memoColor.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.sticky_note_2, color: SoseangTheme.memoDark),
              ),
              label: '메모',
            ),
          ],
        ),
      ),
          Positioned(
            child: InkWell(
              onTap: () => ref.read(currentMenuProvider.notifier).state = 'home',
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: themeDark,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 32),
              ),
            ),
          ),
        ],
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
    final pickedImages = ref.watch(pickedImagesProvider);
    final activeIndex = ref.watch(activeImageIndexProvider);
    if (pickedImages.isEmpty || activeIndex >= pickedImages.length) return const SizedBox.shrink();
    
    final activePath = pickedImages[activeIndex].path;
    final draft = ref.watch(draftCacheProvider)[activePath];
    final fields = draft?.aiFields;
    if (fields == null || fields.isEmpty) return const SizedBox();

    final Map<String, String> fieldLabels = {
      // ── 공통 ──
      'title': '제목',
      'memo': '메모',
      // ── SCHEDULE ──
      'sub_type': '세부 분류',
      'start_at': '시작일',
      'expires_at': '만료일',
      'location': '장소',
      'barcode_number': '바코드 번호',
      // ── PLACE ──
      'name': '상호명',
      'category': '카테고리',
      'address': '주소',
      'region': '지역',
      // ── WISHLIST ──
      'product_name': '상품명',
      'price_amount': '가격',
      'brand_or_store': '브랜드/판매처',
      'option': '옵션',
      'url': '상품 링크',
      // ── MEMO ──
      'body': '본문',
      'tags': '태그',
      // ── 기존 호환 ──
      'original_price': '정가',
      'discount_rate': '할인율',
      'rating': '평점',
      'hours': '영업시간',
      'seller': '판매처',
      'description': '설명',
      'exchange_place': '교환처',
    };

    // 복수 항목 처리
    final hasItems = fields.containsKey('items') && fields['items'] is List && (fields['items'] as List).isNotEmpty;
    final List<dynamic> items = hasItems ? (fields['items'] as List) : [];
    final currentItemIndex = ref.watch(currentItemIndexProvider);
    final currentIdx = currentItemIndex >= items.length ? 0 : currentItemIndex;

    final activeFields = hasItems ? (items[currentIdx] as Map<String, dynamic>) : fields;

    // 상단 폼에서 이미 직접 편집 가능한 필드 + 시스템 내부 필드 제외
    final excludeKeys = {
      // 상단 폼에서 편집하는 핵심 필드
      'title', 'name', 'product_name',       // 제목 칸
      'start_at', 'expires_at',               // 일정 날짜 칸
      'address',                              // 장소 주소 칸
      'price_amount',                         // 가격 (위시 제목에 포함)
      // 시스템 내부 필드 (사용자에게 보여줄 필요 없음)
      'items', 'body',                        // 구조/원문
      'keep_photo', 'map_ready',              // 서버 지시 플래그
      'calendar_type', 'reminder_days',       // 캘린더 자동 설정
      'recurrence',                           // 구독 반복 주기
      'confidence', 'status', 'id',           // 최상위 메타
      'missing_fields', 'masked_info',        // 서버 메타
      'categoryId', 'subCategoryId',          // 로컬 내부 저장용
      'content', 'extraInfo',                 // 로컬 내부 저장용
    };

    final entryList = activeFields.entries
        .where((entry) => !excludeKeys.contains(entry.key) && fieldLabels.containsKey(entry.key) && entry.value != null && entry.value.toString().trim().isNotEmpty)
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
                    onPressed: currentIdx > 0
                        ? () {
                            _syncActiveItemControllers(ref, items[currentIdx], ref.read(selectedCategoryProvider));
                            ref.read(currentItemIndexProvider.notifier).state = currentIdx - 1;
                            _updateActiveItemControllers(ref, items[currentIdx - 1], ref.read(selectedCategoryProvider));
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
                  Text('${currentIdx + 1} / ${items.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 15),
                  ElevatedButton.icon(
                    onPressed: currentIdx < items.length - 1
                        ? () {
                            _syncActiveItemControllers(ref, items[currentIdx], ref.read(selectedCategoryProvider));
                            ref.read(currentItemIndexProvider.notifier).state = currentIdx + 1;
                            _updateActiveItemControllers(ref, items[currentIdx + 1], ref.read(selectedCategoryProvider));
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

                  // sub_type 코드를 한국어로 변환
                  const subTypeLabels = {
                    'GIFTICON': '기프티콘/쿠폰',
                    'SUBSCRIPTION': '구독 서비스',
                    'APPOINTMENT': '약속/미팅',
                    'TICKET': '티켓/예약',
                    'DEADLINE': '마감일/시험',
                    'DELIVERY': '택배/배송',
                  };

                  // 필드별 아이콘 매핑
                  const fieldIcons = {
                    'sub_type': Icons.label_outline,
                    'memo': Icons.sticky_note_2_outlined,
                    'location': Icons.location_on_outlined,
                    'barcode_number': Icons.qr_code,
                    'category': Icons.category_outlined,
                    'region': Icons.map_outlined,
                    'brand_or_store': Icons.storefront_outlined,
                    'option': Icons.tune,
                    'url': Icons.link,
                    'tags': Icons.tag,
                    'original_price': Icons.price_change_outlined,
                    'discount_rate': Icons.discount_outlined,
                    'rating': Icons.star_outline,
                    'hours': Icons.access_time,
                    'seller': Icons.store_outlined,
                    'description': Icons.description_outlined,
                    'exchange_place': Icons.swap_horiz,
                  };

                  // 표시 값 계산
                  String displayValue;
                  if (entry.key == 'sub_type') {
                    displayValue = subTypeLabels[entry.value.toString()] ?? entry.value.toString();
                  } else if (entry.value is List) {
                    displayValue = (entry.value as List).join(', ');
                  } else {
                    displayValue = entry.value.toString();
                  }

                  final icon = fieldIcons[entry.key];
                  final isReadOnly = entry.key == 'sub_type';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 14, color: Colors.deepPurple.shade300),
                          const SizedBox(width: 4),
                        ],
                        SizedBox(
                          width: icon != null ? 72 : 90,
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: isReadOnly
                            ? Text(
                                displayValue,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade400),
                              )
                            : TextFormField(
                                key: ValueKey('${currentIdx}_${entry.key}'),
                                initialValue: displayValue,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                                  border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black12)),
                                ),
                                onChanged: (val) {
                                  if (hasItems) {
                                    items[currentIdx][entry.key] = val;
                                  } else {
                                    fields![entry.key] = val;
                                  }
                                },
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

  void _syncActiveItemControllers(WidgetRef ref, Map<String, dynamic> item, int categoryIndex) {
    if (categoryIndex == 1) { // PLACE
      item['name'] = ref.read(titleControllerProvider).text;
      item['address'] = ref.read(placeLocationProvider).text;
    } else if (categoryIndex == 2) { // WISHLIST
      item['product_name'] = ref.read(titleControllerProvider).text;
    }
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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 🎨 투톤 마블링 배경 CustomPainter
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class MarblePainter extends CustomPainter {
  final Color color1; // 크림/베이지 (고정)
  final Color color2; // 카테고리 테마색 (변동)

  MarblePainter({required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 전체를 color1(크림)로 칠하기
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = color1);

    // 1. 상단 물결 띠 (좌측 상단 일부는 크림색으로 남김)
    final path1 = Path()
      ..moveTo(0, h * 0.25)
      ..cubicTo(w * 0.3, h * 0.35, w * 0.7, h * 0.05, w, h * 0.2)
      ..lineTo(w, 0)
      ..lineTo(w * 0.3, 0)
      ..cubicTo(w * 0.15, h * 0.05, w * 0.05, h * 0.1, 0, h * 0.1)
      ..close();
    canvas.drawPath(path1, Paint()..color = color2);

    // 2. 중앙을 가로지르는 크고 두꺼운 물결 띠
    final path2 = Path()
      ..moveTo(0, h * 0.55)
      ..cubicTo(w * 0.4, h * 0.75, w * 0.6, h * 0.35, w, h * 0.5)
      ..lineTo(w, h * 0.8)
      ..cubicTo(w * 0.6, h * 0.65, w * 0.4, h * 0.95, 0, h * 0.8)
      ..close();
    canvas.drawPath(path2, Paint()..color = color2);

    // 3. 하단 좌측 모서리 작은 물결
    final path3 = Path()
      ..moveTo(0, h * 0.95)
      ..cubicTo(w * 0.2, h * 0.85, w * 0.5, h * 0.9, w * 0.7, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path3, Paint()..color = color2);
  }

  @override
  bool shouldRepaint(MarblePainter oldDelegate) =>
      oldDelegate.color1 != color1 || oldDelegate.color2 != color2;
}