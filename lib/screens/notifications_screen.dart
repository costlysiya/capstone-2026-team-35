import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../main.dart'; // SoseangTheme 가져오기 위해

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    try {
      // 실제 API 호출 
      // final dio = Dio();
      // final response = await dio.get('http://10.0.2.2:8000/api/notifications');
      // _notifications = response.data;
      
      // 더미 데이터 생성
      await Future.delayed(const Duration(milliseconds: 600));
      _notifications = [
        {
          "id": 1,
          "title": "🎉 분석 완료",
          "body": "스타벅스 기프티콘 분석이 완료되었습니다. 결과를 확인하세요!",
          "result_id": 12,
          "is_read": false,
          "created_at": "방금 전"
        },
        {
          "id": 2,
          "title": "✅ 새로운 장소 등록",
          "body": "을지다락 식당이 장소 보관함에 등록되었습니다.",
          "result_id": 15,
          "is_read": true,
          "created_at": "1시간 전"
        },
        {
          "id": 3,
          "title": "🔔 일정 리마인더",
          "body": "내일 오후 2시 회의 일정이 있습니다.",
          "result_id": null,
          "is_read": true,
          "created_at": "하루 전"
        }
      ];
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _markAsRead(int index) {
    setState(() {
      _notifications[index]['is_read'] = true;
    });
  }

  void _onNotificationTap(Map<String, dynamic> notif, int index) {
    _markAsRead(index);
    if (notif['result_id'] != null) {
      Navigator.pop(context, notif['result_id'].toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoseangTheme.ivory,
      appBar: AppBar(
        title: const Text('알림함', style: TextStyle(color: SoseangTheme.textDark)),
        centerTitle: true,
        backgroundColor: SoseangTheme.ivory,
        elevation: 0,
        iconTheme: const IconThemeData(color: SoseangTheme.textDark),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('알림을 불러오는 중 오류가 발생했습니다.\n$_error'));
    }
    if (_notifications.isEmpty) {
      return const Center(child: Text('새로운 알림이 없습니다.', style: TextStyle(color: SoseangTheme.textMuted)));
    }

    return ListView.separated(
      itemCount: _notifications.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: SoseangTheme.border),
      itemBuilder: (context, index) {
        final notif = _notifications[index];
        final isRead = notif['is_read'] == true;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          tileColor: isRead ? Colors.transparent : SoseangTheme.cream.withAlpha(128),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isRead ? Colors.grey[200] : SoseangTheme.scheduleColor.withAlpha(51),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active,
              color: isRead ? Colors.grey : SoseangTheme.scheduleDark,
            ),
          ),
          title: Text(
            notif['title'] ?? '',
            style: TextStyle(
              fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
              color: SoseangTheme.textDark,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                notif['body'] ?? '',
                style: const TextStyle(color: SoseangTheme.textMuted),
              ),
              const SizedBox(height: 6),
              Text(
                notif['created_at'] ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          onTap: () => _onNotificationTap(notif, index),
        );
      },
    );
  }
}
