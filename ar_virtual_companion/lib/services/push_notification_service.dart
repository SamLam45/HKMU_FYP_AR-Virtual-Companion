import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();

  factory PushNotificationService() => _instance;

  PushNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // 1. 初始化時區資料
    tz.initializeTimeZones();

    try {
      final TimezoneInfo timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = timeZoneInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      // ignore: avoid_print
      print('無法獲取本地時區: $e');
    }

    // 2. 初始化本地通知設定
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // 通知被點擊時的處理邏輯
        // ignore: avoid_print
        print('通知被點擊: ${response.payload}');
      },
    );

    // 2.5 Request Exact Alarm Permission (Required for Android 12+ / API 31+ for scheduled notifications to work in background)
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestExactAlarmsPermission();
      }
    } catch (e) {
      print('無法請求 Exact Alarm 權限: $e');
    }

    // 3. 設定每日提醒
    await scheduleDailyReminder();

    // 4. 設定生日提醒（如果用戶已登入）
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      await checkAndScheduleBirthday(currentUser.id);
    }
  }

  Future<void> scheduleDailyReminder() async {
    final schedules = [
      {'id': 0, 'hour': 10, 'minute': 30, 'title': 'Good Morning!', 'body': 'It\'s a new day, let\'s write down your mood today!'},
      {'id': 1, 'hour': 12, 'minute': 0, 'title': 'Good Afternoon!', 'body': 'Lunch break! Take a moment to relax and write your journal.'},
      {'id': 2, 'hour': 15, 'minute': 0, 'title': 'Afternoon Check-in!', 'body': 'Drink some water, take a break, and log what happened today!'},
      {'id': 3, 'hour': 21, 'minute': 0, 'title': 'Good Night!', 'body': 'Good job today! Time to write your evening journal before bed.'},
    ];

    for (var schedule in schedules) {
      await _localNotificationsPlugin.zonedSchedule(
        id: schedule['id'] as int,
        title: schedule['title'] as String,
        body: schedule['body'] as String,
        scheduledDate: _nextInstanceOfTime(schedule['hour'] as int, schedule['minute'] as int),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminders',
            'Daily Reminders',
            channelDescription: 'Daily journal reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  tz.TZDateTime _nextInstanceOfBirthday(int month, int day) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    // 預設在生日當天早上 10:00 發送通知
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local, now.year, month, day, 10, 0);
    
    // 如果今年的生日已經過了，排程到明年
    if (scheduledDate.isBefore(now)) {
      scheduledDate = tz.TZDateTime(
          tz.local, now.year + 1, month, day, 10, 0);
    }
    return scheduledDate;
  }

  Future<void> scheduleBirthdayNotification(int month, int day, {String name = ''}) async {
    final String title = 'Happy Birthday! 🎂';
    final String body = name.isEmpty
        ? 'Wishing you a very Happy Birthday! Have a wonderful day!'
        : 'Happy Birthday, $name! Wishing you a wonderful day!';

    await _localNotificationsPlugin.zonedSchedule(
      id: 100, // 固定的 ID 避免重複排程
      title: title,
      body: body,
      scheduledDate: _nextInstanceOfBirthday(month, day),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'birthday_reminders',
          'Birthday Reminders',
          channelDescription: 'Yearly birthday wishes',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime, // 每年同一日期與時間觸發
    );
  }

  Future<void> checkAndScheduleBirthday(String userId) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('profiles')
          .select('birthday, username')
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        final birthdayStr = response['birthday'] as String?;
        final username = response['username'] as String? ?? '';

        if (birthdayStr != null && birthdayStr.isNotEmpty) {
          // birthdayStr 格式預期為 "YYYY-MM-DD"
          final parts = birthdayStr.split('-');
          if (parts.length == 3) {
            final month = int.tryParse(parts[1]);
            final day = int.tryParse(parts[2]);
            if (month != null && day != null) {
              await scheduleBirthdayNotification(month, day, name: username);
            }
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('檢查與排程生日通知時發生錯誤: $e');
    }
  }

  Future<void> checkEmotionAndNotify(String userId) async {
    final supabase = Supabase.instance.client;

    try {
      final today = DateTime.now();
      final startDate = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 2));
      final endDate = DateTime(today.year, today.month, today.day + 1);

      // 查詢最近 3 日內的日記
      final response = await supabase
          .from('daily_logs')
          .select('date, emotion')
          .eq('user_id', userId)
          .gte('date', startDate.toIso8601String())
          .lt('date', endDate.toIso8601String())
          .order('date', ascending: false)
          .limit(3);

      final List<dynamic> recentLogs = response;
      final negativeEmotions = ['anxious', 'sad', 'angry'];
      final requiredDates = List.generate(3, (index) {
        final date = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: index));
        return '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      }).toSet();

      final negativeLogDates = recentLogs
          .where((log) {
            final emotion = log['emotion']?.toString().toLowerCase() ?? '';
            return negativeEmotions.contains(emotion);
          })
          .map((log) => (log['date']?.toString() ?? '').split('T').first)
          .where((date) => date.isNotEmpty)
          .toSet();

      final hasNegativeLogsForRecentThreeDays =
          requiredDates.every(negativeLogDates.contains);

      if (hasNegativeLogsForRecentThreeDays) {
        await _showCareNotification();
      }
    } catch (e) {
      // ignore: avoid_print
      print('檢查情緒時發生錯誤: $e');
    }
  }

  Future<void> _showCareNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'care_channel',
      '關懷通知',
      channelDescription: '用於關懷訊息的通知頻道',
      importance: Importance.max,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    await _localNotificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 1000000, // 確保 ID 唯一性
      title: 'Are you okay?',
      body: 'I\'ve noticed you\'ve been a bit down lately. Feel free to talk to me anytime if you need to.',
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
    );
  }
}
