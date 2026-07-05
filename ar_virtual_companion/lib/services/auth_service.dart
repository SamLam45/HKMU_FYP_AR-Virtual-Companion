import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'user_id_service.dart';

class AuthService {
  /// 獲取當前用戶 ID，如果未登入則返回訪客 ID
  static Future<String> getUidOrGuest() async {
    final user = SupabaseService.currentUser;
    if (user != null) return user.id;
    return await UserIdService.getOrCreateUserId();
  }

  /// 獲取當前用戶的 access token
  static Future<String?> getIdToken() async {
    final session = SupabaseService.client.auth.currentSession;
    return session?.accessToken;
  }

  /// 檢查用戶是否已登入
  static bool get isAuthenticated => SupabaseService.isAuthenticated;

  /// 獲取當前用戶
  static User? get currentUser => SupabaseService.currentUser;

  /// 登出
  static Future<void> signOut() async {
    await SupabaseService.signOut();
  }
}
