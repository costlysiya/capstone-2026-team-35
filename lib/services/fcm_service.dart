import 'dart:developer';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

// 백그라운드 메시지 핸들러 (반드시 최상위 함수여야 함)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
  // 백그라운드에서는 시스템 트레이에 알림이 표시됨
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  void initialize(BuildContext context) async {
    if (_isInitialized) return;
    _isInitialized = true;

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 알림 권한 요청
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('User granted permission: ${settings.authorizationStatus}');

    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true, // 팝업 띄우기
      badge: true,
      sound: true,
    );

    try {
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
      await _flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel', // id
        'High Importance Notifications', // title
        importance: Importance.max,
      );

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      debugPrint('flutter_local_notifications initialized successfully');
    } catch (e) {
      debugPrint('Error initializing flutter_local_notifications: $e');
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // FCM 기기 토큰 발급
      String? token = await _firebaseMessaging.getToken();
      debugPrint('FCM Token: $token');
      
      if (token != null) {
        _sendTokenToServer(token);
      }
    }

    // 포그라운드 메시지 리스너
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      
      debugPrint('Notification object: $notification, Android: $android');

      if (notification != null) {
        try {
          _flutterLocalNotificationsPlugin.show(
            id: notification.hashCode,
            title: notification.title,
            body: notification.body,
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'high_importance_channel',
                'High Importance Notifications',
                importance: Importance.max,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
            ),
          );
          debugPrint('Local notification shown successfully');
        } catch (e) {
          debugPrint('Error showing local notification: $e');
        }
      }
      
      if (notification != null) {
        debugPrint('Message also contained a notification: $notification');
        _showInAppNotification(context, notification);
      }
    });

    // 알림 클릭 리스너 (앱이 백그라운드 상태에서 클릭 시)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      _handleNotificationClick(context, message.data);
    });
  }

  void _sendTokenToServer(String token) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        'http://44.195.33.82:8000/api/notifications/token',
        data: {'device_token': token},
        options: Options(contentType: 'application/json'),
      );
      if (response.statusCode == 200) {
        debugPrint('Token sent to server successfully: $token');
      } else {
        debugPrint('Failed to send token to server. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error sending token to server: $e');
    }
  }

  void _showInAppNotification(BuildContext context, RemoteNotification notification) {
    // ScaffoldMessenger를 통한 커스텀 스낵바(In-app 팝업)
    // SnackBar는 기본적으로 하단에 나오지만 margin을 조정해 상단처럼 보이게 구성하거나 
    // Overlay/MaterialBanner 등을 사용할 수 있습니다. 여기서는 SnackBar 상단 마진 활용.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.title ?? '알림', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text(notification.body ?? '', style: const TextStyle(color: Colors.white)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150, left: 20, right: 20),
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF5A5040), // SoseangTheme.textDark
      ),
    );
  }

  void _handleNotificationClick(BuildContext context, Map<String, dynamic> data) {
    // data에 담긴 id나 type을 확인 후 라우팅
    final resultId = data['result_id'];
    if (resultId != null) {
      // 딥링크 라우팅
      debugPrint('Navigating to result detail: $resultId');
      // Navigator.push 처리
    }
  }
}
