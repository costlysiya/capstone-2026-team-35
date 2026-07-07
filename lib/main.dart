import 'dart:io';
import 'package:flutter/foundation.dart';
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

final pickedImageProvider = StateProvider<XFile?>((ref) => null);
final ocrStatusProvider = StateProvider<String>((ref) => 'idle');
final extractedTextProvider = StateProvider<String>((ref) => '');
final selectedCategoryProvider = StateProvider<int>((ref) => 3);

// [사이드 메뉴 상태 관리] 'home' 또는 'cat_0', 'cat_1', 'cat_2', 'cat_3'
final currentMenuProvider = StateProvider<String>((ref) => 'home');

final titleControllerProvider = Provider((ref) => TextEditingController());
final contentControllerProvider = Provider((ref) => TextEditingController());
final scheduleDateProvider = Provider((ref) => TextEditingController());   
final placeLocationProvider = Provider((ref) => TextEditingController()); 
final wishlistPriceProvider = Provider((ref) => TextEditingController());   

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

  Future<void> _pickImage(WidgetRef ref) async {
    final ImagePicker picker = ImagePicker(); // ✨ 오타 수정 완료!
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      ref.read(pickedImageProvider.notifier).state = image;
      ref.read(ocrStatusProvider.notifier).state = 'idle';
      ref.read(extractedTextProvider.notifier).state = '';
      ref.read(selectedCategoryProvider.notifier).state = 3; 
      _clearAllFields(ref);
    }
  }

  Future<void> _runRealOCR(WidgetRef ref, XFile pickedImage) async {
    ref.read(ocrStatusProvider.notifier).state = 'loading';

    try {
      final inputImage = InputImage.fromFilePath(pickedImage.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      if (recognizedText.text.trim().isEmpty) {
        ref.read(extractedTextProvider.notifier).state = "⚠️ 인식된 글자가 없습니다.";
      } else {
        final maskedText = MaskingHelper.mask(recognizedText.text);
        ref.read(extractedTextProvider.notifier).state = maskedText;
        
        List<String> lines = maskedText.split('\n');
        if (lines.isNotEmpty) {
          ref.read(titleControllerProvider).text = lines.first;
          ref.read(contentControllerProvider).text = lines.skip(1).join('\n');
        }

        String lowerText = maskedText;
        if (lowerText.contains('년') || lowerText.contains('월') || lowerText.contains('일') || lowerText.contains('시')) {
          ref.read(selectedCategoryProvider.notifier).state = 0; 
        } else if (lowerText.contains('길') || lowerText.contains('로') || lowerText.contains('동') || lowerText.contains('층')) {
          ref.read(selectedCategoryProvider.notifier).state = 1; 
        } else if (lowerText.contains('원') || lowerText.contains('%') || lowerText.contains('가격')) {
          ref.read(selectedCategoryProvider.notifier).state = 2; 
        } else {
          ref.read(selectedCategoryProvider.notifier).state = 3; 
        }
      }
      
      ref.read(ocrStatusProvider.notifier).state = 'success';
      textRecognizer.close();
      
    } catch (e) {
      ref.read(extractedTextProvider.notifier).state = "❌ OCR 분석 실패: $e";
      ref.read(ocrStatusProvider.notifier).state = 'success';
    }
  }

  Map<String, dynamic> _getCategoryStyle(int category) {
    switch (category) {
      case 0: return {'name': '📅 일정 (SCHEDULE)', 'color': Colors.blue, 'icon': Icons.calendar_today};
      case 1: return {'name': '📍 장소 (PLACE)', 'color': Colors.teal, 'icon': Icons.map};
      case 2: return {'name': '🎁 위시리스트 (WISHLIST)', 'color': Colors.pink, 'icon': Icons.shopping_bag};
      default: return {'name': '📝 메모 (MEMO)', 'color': Colors.amber[700]!, 'icon': Icons.note};
    }
  }

  void _saveCardToStorage(BuildContext context, WidgetRef ref, int categoryId) {
    final title = ref.read(titleControllerProvider).text;
    final content = ref.read(contentControllerProvider).text;
    final image = ref.read(pickedImageProvider);

    if (title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 제목을 입력해야 저장할 수 있습니다.')),
      );
      return;
    }

    String extraInfo = "";
    if (categoryId == 0) extraInfo = ref.read(scheduleDateProvider).text;
    if (categoryId == 1) extraInfo = ref.read(placeLocationProvider).text;
    if (categoryId == 2) extraInfo = ref.read(wishlistPriceProvider).text;

    final newCard = {
      'id': DateTime.now().toString(),
      'categoryId': categoryId,
      'title': title,
      'content': content,
      'extraInfo': extraInfo,
      'imagePath': image?.path,
    };

    ref.read(savedCardsProvider.notifier).update((state) => [newCard, ...state]);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('💾 지정된 보관함 방으로 카드가 쏙 들어갔습니다!')),
    );
    
    ref.read(ocrStatusProvider.notifier).state = 'idle';
    ref.read(pickedImageProvider.notifier).state = null;
    _clearAllFields(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final XFile? pickedImage = ref.watch(pickedImageProvider);
    final String ocrStatus = ref.watch(ocrStatusProvider);
    final String extractedText = ref.watch(extractedTextProvider);
    final int selectedCategory = ref.watch(selectedCategoryProvider);
    final List<Map<String, dynamic>> savedCards = ref.watch(savedCardsProvider);
    final String currentMenu = ref.watch(currentMenuProvider);

    final titleController = ref.watch(titleControllerProvider);
    final contentController = ref.watch(contentControllerProvider);
    final scheduleDateController = ref.watch(scheduleDateProvider);
    final placeLocationController = ref.watch(placeLocationProvider);
    final wishlistPriceController = ref.watch(wishlistPriceProvider);

    final style = _getCategoryStyle(selectedCategory);

    String appBarTitle = '🌱 소생 - 스크린샷 텍스트 추출';
    if (currentMenu == 'cat_0') appBarTitle = '📅 일정 보관함';
    if (currentMenu == 'cat_1') appBarTitle = '📍 장소 보관함';
    if (currentMenu == 'cat_2') appBarTitle = '🎁 위시리스트 보관함';
    if (currentMenu == 'cat_3') appBarTitle = '📝 메모 보관함';

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                  Text('스크린샷 정보 관리 서랍장', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.psychology, color: Colors.deepPurple),
              title: const Text('🔍 새 스크린샷 추출하기', style: TextStyle(fontWeight: FontWeight.bold)),
              selected: currentMenu == 'home',
              onTap: () {
                ref.read(currentMenuProvider.notifier).state = 'home';
                Navigator.pop(context);
              },
            ),
            const Divider(),
            // ✨ Padding 내부의 style 위치 에러 수정 완료!
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 10, bottom: 5),
              child: Text(
                '🗄️ 카테고리별 보관함', 
                style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.blue),
              title: const Text('일정 (SCHEDULE)'),
              selected: currentMenu == 'cat_0',
              onTap: () {
                ref.read(currentMenuProvider.notifier).state = 'cat_0';
                Navigator.pop(context);
              },
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
                    Container(
                      width: 300,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey[400]!),
                      ),
                      child: pickedImage == null
                          ? const Center(child: Text('스크린샷을 업로드해 주세요.'))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: kIsWeb
                                  ? Image.network(pickedImage.path, fit: BoxFit.contain)
                                  : Image.file(File(pickedImage.path), fit: BoxFit.contain),
                            ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ref),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('사진 고르기'),
                        ),
                        const SizedBox(width: 15),
                        ElevatedButton.icon(
                          onPressed: pickedImage != null && ocrStatus != 'loading'
                              ? () => _runRealOCR(ref, pickedImage)
                              : null,
                          icon: const Icon(Icons.psychology),
                          label: const Text('텍스트 추출'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    if (ocrStatus == 'loading')
                      const CircularProgressIndicator(color: Colors.green),
                    
                    if (ocrStatus == 'success' && extractedText.isNotEmpty)
                      Card(
                        elevation: 5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(color: style['color'], width: 2.5),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('⚙️ 예린이 AI 분류 결과 수정 (테스트용)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 6,
                                children: List.generate(4, (index) {
                                  final chipStyle = _getCategoryStyle(index);
                                  return ChoiceChip(
                                    label: Text(chipStyle['name'].toString().split(' ')[0], style: const TextStyle(fontSize: 11)),
                                    selected: selectedCategory == index,
                                    selectedColor: chipStyle['color'].withOpacity(0.3),
                                    onSelected: (selected) {
                                      if (selected) ref.read(selectedCategoryProvider.notifier).state = index;
                                    },
                                  );
                                }),
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  Icon(style['icon'], color: style['color']),
                                  const SizedBox(width: 8),
                                  Text(style['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: style['color'])),
                                ],
                              ),
                              const SizedBox(height: 15),
                              TextField(
                                controller: titleController,
                                decoration: const InputDecoration(labelText: '📌 제목', border: OutlineInputBorder()),
                              ),
                              const SizedBox(height: 15),
                              if (selectedCategory == 0) 
                                TextField(
                                  controller: scheduleDateController,
                                  decoration: const InputDecoration(labelText: '⏰ 일정 일시', hintText: '예: 2026-07-14 14:00', border: OutlineInputBorder(), prefixIcon: Icon(Icons.access_time, color: Colors.blue)),
                                ),
                              if (selectedCategory == 1) 
                                TextField(
                                  controller: placeLocationController,
                                  decoration: const InputDecoration(labelText: '📍 장소 위치/주소', hintText: '예: 서울시 강남구 테헤란로 12', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pin_drop, color: Colors.teal)),
                                ),
                              if (selectedCategory == 2) 
                                TextField(
                                  controller: wishlistPriceController,
                                  decoration: const InputDecoration(labelText: '💵 아이템 가격', hintText: '예: 45,000원', border: OutlineInputBorder(), prefixIcon: Icon(Icons.monetization_on, color: Colors.pink)),
                                ),
                              if (selectedCategory != 3) const SizedBox(height: 15),
                              TextField(
                                controller: contentController,
                                maxLines: 3,
                                decoration: const InputDecoration(labelText: '📝 상세 내용', border: OutlineInputBorder()),
                              ),
                              const SizedBox(height: 15),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _saveCardToStorage(context, ref, selectedCategory),
                                  icon: const Icon(Icons.save_alt),
                                  label: const Text('보관함에 저장'),
                                  style: ElevatedButton.styleFrom(backgroundColor: style['color'], foregroundColor: Colors.white),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                  ],
                )
              : Column(
                  children: [
                    // ✨ ListView.builder 내부의 괄호 매칭 및 레이아웃 구조 완벽 수정!
                    Builder(
                      builder: (context) {
                        int targetCatId = int.parse(currentMenu.split('_')[1]);
                        final filteredCards = savedCards.where((c) => c['categoryId'] == targetCatId).toList();
                        final cardStyle = _getCategoryStyle(targetCatId);

                        if (filteredCards.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 80),
                              child: Column(
                                children: [
                                  Icon(cardStyle['icon'], size: 60, color: Colors.grey[300]),
                                  const SizedBox(height: 10),
                                  Text('이 보관함 방은 텅 비어있습니다.\n새로운 스크린샷 카드를 저장해 보세요!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])),
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
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: cardStyle['color'], width: 1.5),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: cardStyle['color'].withOpacity(0.2),
                                  child: Icon(cardStyle['icon'], color: cardStyle['color']),
                                ),
                                title: Text(card['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (card['extraInfo'].toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: cardStyle['color'].withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                          child: Text(card['extraInfo'], style: TextStyle(color: cardStyle['color'], fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    Text(card['content'], maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 12),
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