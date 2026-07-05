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

final pickedImageProvider = StateProvider<XFile?>((ref) => null);
final ocrStatusProvider = StateProvider<String>((ref) => 'idle');
final extractedTextProvider = StateProvider<String>((ref) => '');

// ✨ 3주차 추가: 사용자가 편집할 카드 정보를 저장할 프로바이더들
final titleControllerProvider = Provider((ref) => TextEditingController());
final contentControllerProvider = Provider((ref) => TextEditingController());

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

  Future<void> _pickImage(WidgetRef ref) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      ref.read(pickedImageProvider.notifier).state = image;
      ref.read(ocrStatusProvider.notifier).state = 'idle';
      ref.read(extractedTextProvider.notifier).state = '';
      
      // 입력창 초기화
      ref.read(titleControllerProvider).clear();
      ref.read(contentControllerProvider).clear();
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
        ref.read(extractedTextProvider.notifier).state = recognizedText.text;
        
        // 💡 [간단 파싱 알고리즘] 첫 줄은 무조건 제목으로, 나머지는 본문으로 쪼개서 채워넣기
        List<String> lines = recognizedText.text.split('\n');
        if (lines.isNotEmpty) {
          ref.read(titleControllerProvider).text = lines.first; // 첫 줄을 제목 칸에 쏙!
          ref.read(contentControllerProvider).text = lines.skip(1).join('\n'); // 나머진 본문에 쏙!
        }
      }
      
      ref.read(ocrStatusProvider.notifier).state = 'success';
      textRecognizer.close();
      
    } catch (e) {
      ref.read(extractedTextProvider.notifier).state = "❌ OCR 분석 실패: $e";
      ref.read(ocrStatusProvider.notifier).state = 'success';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final XFile? pickedImage = ref.watch(pickedImageProvider);
    final String ocrStatus = ref.watch(ocrStatusProvider);
    final String extractedText = ref.watch(extractedTextProvider);
    
    // 컨트롤러 가져오기
    final titleController = ref.watch(titleControllerProvider);
    final contentController = ref.watch(contentControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🌱 소생 앱 - 정보 초안 카드'),
        backgroundColor: Colors.deepPurple[50],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. 이미지 박스
                Container(
                  width: 300,
                  height: 300,
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
                const SizedBox(height: 20),
                
                // 2. 버튼 영역
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
                      label: const Text('진짜 텍스트 추출'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100]),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                
                // 로딩 애니메이션
                if (ocrStatus == 'loading')
                  const Column(
                    children: [
                      CircularProgressIndicator(color: Colors.green),
                      SizedBox(height: 10),
                      Text('구글 AI가 글자를 분류하는 중...'),
                    ],
                  ),
                
                // 3. ✨ [3주차 업그레이드] 추출 성공 시 나타나는 편집 가능한 카드 형태 UI
                if (ocrStatus == 'success' && extractedText.isNotEmpty)
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.edit_note, color: Colors.deepPurple),
                              SizedBox(width: 5),
                              Text('📋 스크린샷 정보 초안', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          const Divider(),
                          const SizedBox(height: 10),
                          
                          // 제목 입력 필드
                          TextField(
                            controller: titleController,
                            decoration: const InputDecoration(
                              labelText: '📌 제목 (자동 추출됨)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 15),
                          
                          // 본문 내용 입력 필드
                          TextField(
                            controller: contentController,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: '📝 내용',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // 4주차에 쓸 임시 저장 버튼 뼈대 만들기
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // 다음 주차에 실제로 폰에 저장하는 기능을 넣을 거예요!
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('🎉 [${titleController.text}] 초안이 임시 확인되었습니다!')),
                                );
                              },
                              icon: const Icon(Icons.save),
                              label: const Text('이 정보 카드로 저장하기'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}