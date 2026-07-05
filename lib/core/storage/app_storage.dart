import 'dart:io';
import 'package:flutter/foundation.dart'; // ✨ kIsWeb을 쓰기 위해 꼭 필요해요!
import 'package:path_provider/path_provider.dart';

class AppStorage {
  static const List<String> categories = ['SCHEDULE', 'PLACE', 'WISHLIST', 'MEMO'];

  static Future<void> initDirectories() async {
    // ✨ 크롬(웹) 브라우저 환경일 때는 폴더 생성을 하지 않고 바로 빠져나갑니다!
    if (kIsWeb) {
      print('🌐 [소생 앱] 현재 크롬(웹) 환경이므로 로컬 폴더 생성을 건너뜁니다.');
      return;
    }

    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String basePath = '${appDocDir.path}/AppStorage';

      for (String category in categories) {
        final Directory dir = Directory('$basePath/$category');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
          print('📂 [소생 앱] 로컬 폴더 생성 완료: ${dir.path}');
        } else {
          print('✅ [소생 앱] 이미 폴더가 존재합니다: ${dir.path}');
        }
      }
    } catch (e) {
      print('❌ [소생 앱] 폴더 생성 중 오류 발생: $e');
    }
  }
}