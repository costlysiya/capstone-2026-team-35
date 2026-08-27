import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

class KakaoCalendarService {
  static Future<bool> loginAndGetCalendarPermission() async {
    try {
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
      final eventData = {
        "title": title,
        "time": {
          "start_at": startAt.toIso8601String() + "Z",
          "end_at": endAt.toIso8601String() + "Z",
          "time_zone": "Asia/Seoul",
          "all_day": false
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
      debugPrint('카카오 톡캘린더 등록 실패: $e');
      return false;
    }
  }
}
