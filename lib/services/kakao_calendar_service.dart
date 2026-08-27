import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

class KakaoCalendarService {
  static Future<bool> loginAndGetCalendarPermission() async {
    try {
      final origin = await KakaoSdk.origin;
      debugPrint('\n=============================================');
      debugPrint('🔑 카카오 안드로이드 키 해시: $origin');
      debugPrint('이 값을 복사해서 카카오 디벨로퍼스에 넣으세요!');
      debugPrint('=============================================\n');

      final bool isInstalled = await isKakaoTalkInstalled();
      List<String> scopes = ['talk_calendar'];

      OAuthToken token;
      if (isInstalled) {
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
        } catch (e) {
          token = await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      final scopesList = token.scopes;
      bool hasCalendarScope = scopesList != null && scopesList.contains('talk_calendar');

      if (!hasCalendarScope) {
        try {
          token = await UserApi.instance.loginWithNewScopes(scopes);
          return true;
        } catch (e) {
          debugPrint('권한 요청 실패: $e');
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('카카오 로그인 에러: $e');
      return false;
    }
  }

  static Future<bool> createEvent({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    try {
      bool hasPermission = await loginAndGetCalendarPermission();
      if (!hasPermission) return false;

      final token = await TokenManagerProvider.instance.manager.getToken();
      if (token == null) return false;

      final dio = Dio();
      // 종일 일정(all_day: true)의 경우 Kakao API 요구사항에 따라 00:00:00Z로 포맷팅
      final startAtStr = "${startAt.toIso8601String().split('T')[0]}T00:00:00Z";
      // 종일 일정이어도 end_at이 start_at보다 커야 하므로 다음 날 00:00:00Z로 설정합니다.
      final nextDay = startAt.add(const Duration(days: 1));
      final endAtStr = "${nextDay.toIso8601String().split('T')[0]}T00:00:00Z";
      
      final eventData = {
        "title": title,
        "time": {
          "start_at": startAtStr,
          "end_at": endAtStr,
          "time_zone": "Asia/Seoul",
          "all_day": true
        },
        "reminders": [1440, 10080]
      };

      final response = await dio.post(
        'https://kapi.kakao.com/v2/api/calendar/create/event',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${token.accessToken}',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
        data: {
          'event': jsonEncode(eventData)
        },
      );

      if (response.statusCode == 200) {
        debugPrint('카카오 톡캘린더 등록 성공! Event ID: ${response.data['event_id']}');
        return true;
      }
      return false;
    } catch (e) {
      if (e is DioException) {
        debugPrint('카카오 톡캘린더 등록 실패(Dio): ${e.response?.statusCode} - ${e.response?.data}');
      } else {
        debugPrint('카카오 톡캘린더 등록 실패: $e');
      }
      return false;
    }
  }
}
