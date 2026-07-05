import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'push_notification_service.dart';
import 'ai_partner_service.dart';

class SupabaseService {
  // TODO: Replace with your actual Supabase URL and Anon Key if these are not correct
  static const String supabaseUrl = 'https://rhlainnjitprlicmhqfs.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_gVpIhKzo2RRLBcoRCspBUg_LeazUwlI';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  // Auth Helpers
  static User? get currentUser => client.auth.currentUser;
  static Session? get currentSession => client.auth.currentSession;
  static bool get isAuthenticated => currentUser != null;

  static Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;

    try {
      // Refresh the session to ensure we have a valid JWT
      try {
        await client.auth.refreshSession();
      } catch (e) {
        print('Session refresh failed: $e');
        // Continue anyway, maybe the existing token is still valid enough for the function
      }

      // Call the Edge Function to delete the user account
      // This will delete the user from auth.users and cascade delete profiles, memories, etc.
      await client.functions.invoke('delete-user-account');
      
      // Sign out as the final step
      await signOut();
    } catch (e) {
      print('Error deleting account: $e');
      throw e;
    }
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static Future<AuthResponse> signUp(String email, String password) async {
    return await client.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(email: email, password: password);
  }

  // Calendar/Journal Helpers

  /// `daily_logs.date` 在 DB 為 `date` 型別；用純日曆日字串避免與時區轉換混淆。
  static String _dateOnlyLocal(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Future<List<Map<String, dynamic>>> fetchDailyLogs(DateTime start, DateTime end) async {
    final user = currentUser;
    if (user == null) return [];

    try {
      final response = await client
          .from('daily_logs')
          .select()
          .eq('user_id', user.id)
          .gte('date', _dateOnlyLocal(start))
          .lte('date', _dateOnlyLocal(end))
          .order('date', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching logs: $e');
      return [];
    }
  }

  /// [exclusiveEnd] 為 true 時使用 `created_at < end`（半開區間），適合「當月」查詢（end = 下月 1 日 00:00）。
  static Future<List<Map<String, dynamic>>> fetchMemories(
    DateTime start,
    DateTime end, {
    bool exclusiveEnd = false,
  }) async {
    final user = currentUser;
    if (user == null) return [];

    try {
      final startIso = start.toIso8601String();
      final endIso = end.toIso8601String();
      final response = exclusiveEnd
          ? await client
              .from('memories')
              .select()
              .eq('user_id', user.id)
              .gte('created_at', startIso)
              .lt('created_at', endIso)
              .order('created_at', ascending: true)
          : await client
              .from('memories')
              .select()
              .eq('user_id', user.id)
              .gte('created_at', startIso)
              .lte('created_at', endIso)
              .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching memories: $e');
      return [];
    }
  }

  /// Fetch recent chat history for display
  /// Returns a list of messages in chronological order (oldest to newest)
  static Future<List<Map<String, dynamic>>> fetchRecentChatHistory({int limit = 50}) async {
    final user = currentUser;
    if (user == null) return [];

    try {
      // Fetch latest N memories
      final response = await client
          .from('memories')
          .select('content, metadata, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false) // Get newest first
          .limit(limit);
          
      // Reverse to chronological order for display
      final reversedData = List<Map<String, dynamic>>.from(response).reversed;
      
      final List<Map<String, dynamic>> history = [];
      for (var item in reversedData) {
        final metadata = item['metadata'] as Map<String, dynamic>?;
        if (metadata != null) {
          // Add User Message
          if (metadata['user_text'] != null && metadata['user_text'].toString().isNotEmpty) {
             history.add({
               'role': 'user',
               'text': metadata['user_text'],
               'timestamp': DateTime.parse(item['created_at']).toLocal(),
             });
          }
          // Add AI Message
          if (metadata['reply_text'] != null && metadata['reply_text'].toString().isNotEmpty) {
             history.add({
               'role': 'ai',
               'text': metadata['reply_text'],
               'timestamp': DateTime.parse(item['created_at']).toLocal(), // Approximate same time
             });
          }
        }
      }
      return history;
    } catch (e) {
      print('Error fetching chat history: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> fetchUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  static Future<void> saveDailyLog({
    required DateTime date,
    required String content,
    required String emotion,
    String? aiSummary,
    String? imageUrl,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('User not logged in');

    // DB 欄位為 `date`：存 YYYY-MM-DD（裝置日曆上的「那一天」）
    final dateIso = _dateOnlyLocal(date);

    final logData = {
      'user_id': user.id,
      'date': dateIso,
      'content': content,
      'emotion': emotion,
      'ai_summary': aiSummary,
      'image_url': imageUrl,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      // We use 'date' as part of the composite key or unique constraint in DB
      // Assuming 'user_id' + 'date' is unique
      await client.from('daily_logs').upsert(
        logData, 
        onConflict: 'user_id, date' 
      );
      
      // 檢查情緒並觸發推播 (Local + Supabase Query)
      await PushNotificationService().checkEmotionAndNotify(user.id);
      
      // 背景預熱刷新快取，不阻塞返回（Save 可立即關閉畫面）
      unawaited(
        ARPartnerService()
            .prepareBackend(forceRefresh: true)
            .then((_) => debugPrint('[Supabase] AI cache refresh completed after saving log'))
            .catchError((e) => debugPrint('[Supabase] Failed to refresh AI cache: $e')),
      );
      
    } catch (e) {
      print('Error saving daily log: $e');
      throw e;
    }
  }

  static Future<void> deleteDailyLog(DateTime date) async {
    final user = currentUser;
    if (user == null) throw Exception('User not logged in');
    
    final dateIso = _dateOnlyLocal(date);
    
    try {
      // 1. Fetch the log first to check for image_url
      final log = await client
          .from('daily_logs')
          .select('image_url')
          .eq('user_id', user.id)
          .eq('date', dateIso)
          .maybeSingle();

      // 2. Delete the log entry
      await client
          .from('daily_logs')
          .delete()
          .eq('user_id', user.id)
          .eq('date', dateIso);

      // 3. If log had an image, delete it from storage
      if (log != null && log['image_url'] != null) {
        final imageUrl = log['image_url'] as String;
        // Extract path from URL (assuming standard Supabase Storage URL format)
        // URL format: .../storage/v1/object/public/bucket_name/path/to/file
        final uri = Uri.parse(imageUrl);
        final pathSegments = uri.pathSegments;
        // Find 'public' or bucket name index to extract relative path
        // Typically for public buckets: .../public/ar_assets/journal/uid/file.jpg
        // We need 'journal/uid/file.jpg' if bucket is 'ar_assets'
        
        // Simple heuristic: remove everything before the bucket name 'ar_assets'
        // But the bucket name is part of the URL path in standard format.
        // Let's rely on the fact we know we uploaded to 'ar_assets' and the path starts with 'journal/'
        
        // Better approach: We know we stored it as 'journal/${user.id}/$fileName'
        // Let's try to extract that part.
        if (imageUrl.contains('/ar_assets/')) {
          final path = imageUrl.split('/ar_assets/').last;
          await client.storage.from('ar_assets').remove([path]);
        }
      }
      
      unawaited(
        ARPartnerService()
            .prepareBackend(forceRefresh: true)
            .then((_) => debugPrint('[Supabase] AI cache refresh completed after deleting log'))
            .catchError((e) => debugPrint('[Supabase] Failed to refresh AI cache: $e')),
      );
      
    } catch (e) {
      print('Error deleting daily log: $e');
      throw e;
    }
  }

  static Future<String?> uploadJournalImage(String filePath, String fileName) async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final fileBytes = await File(filePath).readAsBytes();
      final path = 'journal/${user.id}/$fileName';
      
      await client.storage
          .from('ar_assets') // Using ar_assets for now, ideally create a 'journal_images' bucket
          .uploadBinary(
            path,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );
          
      return client.storage.from('ar_assets').getPublicUrl(path);
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }
  
  // Onboarding Helpers

  /// Check if a username is already taken
  static Future<bool> checkUsernameExists(String username) async {
    try {
      final response = await client
          .from('profiles')
          .select('username')
          .eq('username', username)
          .maybeSingle();
      return response != null;
    } catch (e) {
      // If error (e.g. table doesn't exist or RLS issue), assume safe for now or handle accordingly
      print('Error checking username: $e');
      return false;
    }
  }

  /// 更新 profiles.selected_persona_id（null = 使用自訂／復原，唔用預設 Persona）
  static Future<void> updateSelectedPersonaId(int? personaId) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await client.from('profiles').update({
        'selected_persona_id': personaId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
      debugPrint('[Supabase] updateSelectedPersonaId id=$personaId');
    } catch (e) {
      debugPrint('Error updating selected_persona_id: $e');
      rethrow;
    }
  }

  /// Fetch all available AI personas (templates)
  static Future<List<Map<String, dynamic>>> fetchPersonas() async {
    try {
      final response = await client
          .from('personas')
          .select()
          .order('id', ascending: true);
      if (response is! List) {
        debugPrint('fetchPersonas: 非預期型別 ${response.runtimeType}');
        return [];
      }
      return List<Map<String, dynamic>>.from(
        response.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } catch (e) {
      print('Error fetching personas: $e');
      return [];
    }
  }

  /// Fetch avatar assets from Supabase Storage
  /// Returns a list of public URLs for the files in the specified folder
  static Future<List<String>> fetchAvatarAssets(String folder) async {
    try {
      final List<FileObject> objects = await client
          .storage
          .from('ar_assets')
          .list(path: folder);
      
      return objects
          .where((obj) => obj.name.endsWith('.glb') || obj.name.endsWith('.gltf'))
          .map((obj) => client.storage.from('ar_assets').getPublicUrl('$folder/${obj.name}'))
          .toList();
    } catch (e) {
      print('Error fetching avatar assets: $e');
      return [];
    }
  }

  /// Public idle.glb URLs for onboarding / default avatar (Home + Outside), same filter as Step 3 carousel.
  static Future<List<String>> fetchIdleGlbAvatarUrlsForGenderPrefix(String genderPrefix) async {
    final homeAssets = await fetchAvatarAssets('$genderPrefix/Home');
    final outsideAssets = await fetchAvatarAssets('$genderPrefix/Outside');
    return [...homeAssets, ...outsideAssets].where((u) => u.endsWith('idle.glb')).toList();
  }

  /// Create or update user profile with onboarding data
  static Future<void> createUserProfile({
    required String username,
    required String aiNickname,
    int? selectedPersonaId,
    required Map<String, dynamic> preferences,
    required String gender,
    required String avatarModelUrl,
    Map<String, dynamic>? personalitySettings,
    DateTime? birthday,
    Map<String, dynamic>? detailedPersonalityProfile,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('User not logged in');

    final updates = {
      'id': user.id,
      'username': username,
      'ai_nickname': aiNickname,
      'selected_persona_id': selectedPersonaId,
      'preferences': preferences,
      'gender': gender,
      'avatar_url': avatarModelUrl,
      'personality_settings': personalitySettings,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (birthday != null) {
      updates['birthday'] = birthday.toIso8601String();
    }
    
    if (detailedPersonalityProfile != null) {
      updates['detailed_personality'] = detailedPersonalityProfile;
    }

    try {
      // Use maybeSingle to check if profile exists, or handle error
      // Upsert requires primary key to be present in data or query
      // Here 'id' is the primary key
      await client.from('profiles').upsert(updates);
    } catch (e) {
      print('Error saving profile: $e');
      
      // Handle schema mismatches by removing problematic fields and retrying
      bool retryNeeded = false;
      
      // Handle unique constraint violation on username (23505)
      // If username exists but belongs to another user, we should prompt user to change it.
      // But here we are in 'upsert', and if ID matches, it updates.
      // If username matches ANOTHER user, it fails.
      if (e.toString().contains('23505') || e.toString().contains('profiles_username_key')) {
         throw Exception('Username already taken. Please choose another one.');
      }

      if (e.toString().contains('detailed_personality')) {
         updates.remove('detailed_personality');
         retryNeeded = true;
      }
      
      if (e.toString().contains('birthday')) {
         updates.remove('birthday');
         retryNeeded = true;
      }
      
      if (retryNeeded) {
         try {
            await client.from('profiles').upsert(updates);
         } catch (retryError) {
            print('Retry failed: $retryError');
            if (retryError.toString().contains('23505')) {
               throw Exception('Username already taken. Please choose another one.');
            }
            throw retryError;
         }
      } else {
         throw e;
      }
    }
  }
  
  /// Update specific fields of the user profile
  static Future<void> updatePersonalityProfile({
    String? aiNickname,
    String? gender,
    DateTime? birthday,
    Map<String, dynamic>? detailedPersonality,
    String? avatarModelUrl,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('User not logged in');

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (aiNickname != null) updates['ai_nickname'] = aiNickname;
    if (gender != null) updates['gender'] = gender;
    if (birthday != null) updates['birthday'] = birthday.toIso8601String();
    if (detailedPersonality != null) updates['detailed_personality'] = detailedPersonality;
    if (avatarModelUrl != null) updates['avatar_url'] = avatarModelUrl;

    debugPrint(
      '[Supabase] updatePersonalityProfile user=${user.id} keys=${updates.keys.toList()} '
      'gender=${updates['gender']} avatar_url=${updates['avatar_url'] != null ? "(有值)" : "(null)"}',
    );

    try {
      await client.from('profiles').update(updates).eq('id', user.id);
      debugPrint('[Supabase] updatePersonalityProfile profiles.update 成功');
    } catch (e) {
      print('Error updating personality profile: $e');
      throw e;
    }
  }

  /// Check if user has completed onboarding
  static Future<bool> hasCompletedOnboarding() async {
    final user = currentUser;
    if (user == null) return false;
    
    try {
      final response = await client
          .from('profiles')
          .select('username, ai_nickname')
          .eq('id', user.id)
          .maybeSingle();
          
      if (response == null) return false;
      return response['username'] != null && response['ai_nickname'] != null;
    } catch (e) {
      return false;
    }
  }

  /// Update user preferences (e.g. voice settings)
  static Future<void> updateUserPreferences(Map<String, dynamic> newPreferences) async {
    final user = currentUser;
    if (user == null) return;

    try {
      // 1. Fetch current preferences
      final response = await client
          .from('profiles')
          .select('preferences')
          .eq('id', user.id)
          .maybeSingle();
      
      final currentPreferences = response?['preferences'] as Map<String, dynamic>? ?? {};
      
      // 2. Merge new preferences
      final updatedPreferences = {...currentPreferences, ...newPreferences};

      // 3. Update profile
      await client.from('profiles').update({
        'preferences': updatedPreferences,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
    } catch (e) {
      print('Error updating preferences: $e');
      throw e;
    }
  }
}
