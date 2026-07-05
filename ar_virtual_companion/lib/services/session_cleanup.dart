import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/onboarding_provider.dart';
import '../providers/personality_provider.dart';

/// Clears user-scoped local data and resets Riverpod state after sign-out / account deletion
/// so the next login or new account does not inherit the previous user's onboarding or profile cache.
class SessionCleanup {
  SessionCleanup._();

  static Future<void> clearLocalPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('personality_profile');
  }

  static void invalidateOnboardingAndPersonality(WidgetRef ref) {
    ref.invalidate(onboardingProvider);
    ref.invalidate(personalityProvider);
  }

  /// Call after [SupabaseService.signOut] or [SupabaseService.deleteAccount] (which signs out).
  static Future<void> afterSessionEnded(WidgetRef ref) async {
    await clearLocalPreferences();
    invalidateOnboardingAndPersonality(ref);
  }
}
