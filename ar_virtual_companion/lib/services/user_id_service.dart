import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 簡單的使用者 ID 管理：為每個裝置產生一個持久的 guest ID。
class UserIdService {
  static const _userIdKey = 'guest_user_id';
  static final Random _random = Random();

  /// 取得現有的 userId；若沒有，就產生一個新的 guest_xxx 並儲存到本機。
  static Future<String> getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_userIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final millis = DateTime.now().millisecondsSinceEpoch;
    final rand = _random.nextInt(0x7fffffff);
    final newId = 'guest_${millis}_$rand';

    await prefs.setString(_userIdKey, newId);
    return newId;
  }
}


