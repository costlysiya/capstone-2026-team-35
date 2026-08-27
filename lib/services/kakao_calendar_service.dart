import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

class KakaoCalendarService {
  /// 카카오 로그인을 수행하고 톡캘린더 권한(talk_calendar)을 확보합니다.
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

      // 사용자 동의 내역 중 톡캘린더 권한이 있는지 확인
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

  /// 톡캘린더에 일정을 등록합니다.
  static Future<bool> createEvent({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    try {
      bool hasPermission = await loginAndGetCalendarPermission();
      if (!hasPermission) return false;

      final event = Event(
        title: title,
        time: EventTime(
          startAt: startAt,
          endAt: endAt,
          timeZone: 'Asia/Seoul',
          allDay: false,
        ),
        reminders: [1440, 10080], // 1440분(1일 전), 10080분(7일 전)
      );

      String eventId = await TalkApi.instance.addEvent(event);
      debugPrint('카카오 톡캘린더 등록 성공! Event ID: $eventId');
      return true;
    } catch (e) {
      debugPrint('카카오 톡캘린더 등록 실패: $e');
      return false;
    }
  }
}
