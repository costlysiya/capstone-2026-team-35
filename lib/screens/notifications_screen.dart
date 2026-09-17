import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart'; // SoseangTheme 가져오기 위해

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
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
      await Future.delayed(const Duration(milliseconds: 300));
      final savedCards = ref.read(savedCardsProvider);
      final readNotifs = ref.read(readNotificationsProvider);

      List<dynamic> generatedNotifs = [];
      final now = DateTime.now();
      final todayStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final todayMonth = now.month;
      final todayDay = now.day;

      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowStr =
          "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";
      final tomorrowMonth = tomorrow.month;
      final tomorrowDay = tomorrow.day;

      for (var card in savedCards) {
        if (card['categoryId'] == 0) {
          // SCHEDULE
          final extraInfo = card['extraInfo']?.toString() ?? '';
          final normalizedExtraInfo = extraInfo.replaceAll('/', '-');

          if (normalizedExtraInfo.startsWith(todayStr)) {
            generatedNotifs.add({
              "id": card['id'],
              "title": "🔔 ${todayMonth}월 ${todayDay}일 일정 알림",
              "body":
                  "[${card['title']}] 일정이 오늘(${todayMonth}월 ${todayDay}일) 예정되어 있습니다.",
              "result_id": card['id'],
              "is_read": readNotifs.contains(card['id'].toString()),
              "created_at": "오늘",
            });
          } else if (normalizedExtraInfo.startsWith(tomorrowStr)) {
            generatedNotifs.add({
              "id": card['id'],
              "title": "🔔 ${tomorrowMonth}월 ${tomorrowDay}일 일정 알림",
              "body":
                  "[${card['title']}] 일정이 내일(${tomorrowMonth}월 ${tomorrowDay}일) 예정되어 있습니다.",
              "result_id": card['id'],
              "is_read": readNotifs.contains(card['id'].toString()),
              "created_at": "내일",
            });
          }
        }
      }

      _notifications = generatedNotifs;

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
    final notifId = _notifications[index]['id'].toString();
    ref.read(readNotificationsProvider.notifier).update((state) {
      return {...state, notifId};
    });
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
        title: const Text(
          '알림함',
          style: TextStyle(color: SoseangTheme.textDark),
        ),
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
      return const Center(
        child: Text(
          '새로운 알림이 없습니다.',
          style: TextStyle(color: SoseangTheme.textMuted),
        ),
      );
    }

    return ListView.separated(
      itemCount: _notifications.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: SoseangTheme.border),
      itemBuilder: (context, index) {
        final notif = _notifications[index];
        final isRead = notif['is_read'] == true;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          tileColor: isRead
              ? Colors.transparent
              : SoseangTheme.cream.withAlpha(128),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isRead
                  ? Colors.grey[200]
                  : SoseangTheme.scheduleColor.withAlpha(51),
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
