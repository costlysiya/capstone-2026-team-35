import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; 
import 'package:flutter_riverpod/legacy.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'core/storage/app_storage.dart';

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

// [사이드 메뉴 상태] 'home', 'cat_0_0'(일반일정), 'cat_0_1'(기프티콘), 'cat_1', 'cat_2', 'cat_3'
final currentMenuProvider = StateProvider<String>((ref) => 'home');

// ✍️ 입력 컨트롤러들
final titleControllerProvider = Provider((ref) => TextEditingController());
final contentControllerProvider = Provider((ref) => TextEditingController());
final scheduleDateProvider = Provider((ref) => TextEditingController());   
final placeLocationProvider = Provider((ref) => TextEditingController()); 
final wishlistPriceProvider = Provider((ref) => TextEditingController());   

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
    ref.read(wishlistPriceProvider).clear();
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

  // 단수 이미지 OCR 추출 및 추천 자동 매칭
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
        ref.read(extractedTextProvider.notifier).state = recognizedText.text;
        
        List<String> lines = recognizedText.text.split('\n');
        if (lines.isNotEmpty) {
          ref.read(titleControllerProvider).text = lines.first;
          ref.read(contentControllerProvider).text = lines.skip(1).join('\n');
        }

        String lowerText = recognizedText.text;
        
        if (lowerText.contains('기프티콘') || lowerText.contains('쿠폰') || lowerText.contains('바코드') || lowerText.contains('교환권') || lowerText.contains('유효기간')) {
          ref.read(selectedCategoryProvider.notifier).state = 0;    
          ref.read(selectedSubCategoryProvider.notifier).state = 1; 
        } else if (lowerText.contains('년') || lowerText.contains('월') || lowerText.contains('일') || lowerText.contains('시')) {
          ref.read(selectedCategoryProvider.notifier).state = 0; 
          ref.read(selectedSubCategoryProvider.notifier).state = 0; 
        } else if (lowerText.contains('길') || lowerText.contains('로') || lowerText.contains('동')) {
          ref.read(selectedCategoryProvider.notifier).state = 1; 
        } else if (lowerText.contains('원') || lowerText.contains('가격')) {
          ref.read(selectedCategoryProvider.notifier).state = 2; 
        } else {
          ref.read(selectedCategoryProvider.notifier).state = 3; 
        }
      }
      
      ref.read(ocrStatusProvider.notifier).state = 'success';
      textRecognizer.close();
      
    } catch (e) {
      ref.read(extractedTextProvider.notifier).state = "❌ 분석 실패: $e";
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
    if (categoryId == 2) extraInfo = ref.read(wishlistPriceProvider).text;

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

  // ✨ [핵심 신설] 보관함 항목 클릭 시 띄워줄 아름다운 디테일 모달 팝업창 시스템
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
                // 1. 이미지 보관 조건부 렌더링 (기프티콘, 위시리스트만 상단 노출)
                if (card['imagePath'] != null)
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
                
                // 2. 텍스트 정보 본문 영역
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 카테고리 태그 뱃지
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
                      
                      // 제목
                      Text(card['title'], style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 10),
                      
                      // 카테고리별 맞춤 정보 헤더 자동 판별 분기
                      if (card['extraInfo'].toString().isNotEmpty) ...[
                        Text(
                          card['categoryId'] == 0 && card['subCategoryId'] == 1
                              ? '⏳ 기프티콘 유효기간'
                              : card['categoryId'] == 0 ? '⏰ 일정 일시 설정'
                              : card['categoryId'] == 1 ? '🗺️ 장소 주소 및 명칭'
                              : '💵 아이템 소생 가격',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(card['extraInfo'], style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cardStyle['color'])),
                        const SizedBox(height: 15),
                      ],
                      
                      // 상세 파싱 본문 텍스트
                      const Text('📝 추출 상세 본문', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 5),
                      Text(card['content'], style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87)),
                      const SizedBox(height: 25),
                      
                      // 모달 닫기 확인 단추
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
    final wishlistPriceController = ref.watch(wishlistPriceProvider);

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
                        child: const Center(child: Text('소생할 스크린샷들을 선택해 주세요.\n(상세보기 마운트 완료)', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13))),
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
                          TextButton(onPressed: () => ref.read(pickedImagesProvider.notifier).state = [], child: const Text('전체 취소', style: TextStyle(color: Colors.red, fontSize: 11)))
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
                                
                                if (selectedCategory == 0) 
                                  TextField(
                                    controller: scheduleDateController,
                                    decoration: InputDecoration(
                                      labelText: selectedSubCategory == 1 ? '⏰ 기프티콘 유효기간 입력' : '⏰ 일정 일시 입력', 
                                      border: const OutlineInputBorder(), 
                                      prefixIcon: const Icon(Icons.access_time, color: Colors.blue)
                                    ),
                                  ),
                                if (selectedCategory == 1) 
                                  TextField(
                                    controller: placeLocationController,
                                    decoration: const InputDecoration(labelText: '📍 장소 위치/주소 입력', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pin_drop, color: Colors.teal)),
                                  ),
                                if (selectedCategory == 2) 
                                  TextField(
                                    controller: wishlistPriceController,
                                    decoration: const InputDecoration(labelText: '💵 아이템 가격 입력', border: OutlineInputBorder(), prefixIcon: Icon(Icons.monetization_on, color: Colors.pink)),
                                  ),
                                if (selectedCategory != 3) const SizedBox(height: 15),
                                
                                TextField(
                                  controller: contentController,
                                  maxLines: 4,
                                  decoration: const InputDecoration(labelText: '📝 상세 본문 수정', border: OutlineInputBorder()),
                                ),
                                const SizedBox(height: 15),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _saveCurrentCardAndRemoveFromQueue(context, ref),
                                    icon: const Icon(Icons.check_circle),
                                    label: const Text('수정 본 보관함에 저장하기'),
                                    style: ElevatedButton.styleFrom(backgroundColor: style['color'], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                                  ),
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
                                    // ✨ [핵심 연동] 이제 저장된 카드를 누르면 팝업창이 뜨도록 onTap을 추가했어!
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