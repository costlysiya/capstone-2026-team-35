import 'dart:io';
import 'package:flutter/foundation.dart'; // ✨ kIsWeb을 쓰기 위해 꼭 필요해요!
import 'package:path_provider/path_provider.dart';

class AppStorage {
  static const List<String> categories = [
    'SCHEDULE',
    'PLACE',
    'WISHLIST',
    'MEMO',
  ];

  static Future<void> initDirectories() async {
    // ✨ 크롬(웹) 브라우저 환경일 때는 폴더 생성을 하지 않고 바로 빠져나갑니다!
    if (kIsWeb) {
      return;
    }

    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String basePath = '${appDocDir.path}/AppStorage';

      for (String category in categories) {
        final Directory dir = Directory('$basePath/$category');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        } else {
        }
      }
    } catch (e) {
    }
  }
}
