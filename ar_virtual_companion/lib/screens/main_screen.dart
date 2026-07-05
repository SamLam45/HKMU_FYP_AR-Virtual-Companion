import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart';

import 'ar_screen_flutter.dart';
import 'settings_screen.dart';
import 'personality_customization_screen.dart';
import 'user_profile_screen.dart'; // Import User Profile Screen
import '../providers/ai_provider.dart';
import '../providers/voice_provider_simple.dart';
import '../providers/personality_provider.dart';
import '../models/personality_model.dart'; // Add this import
import '../services/ai_partner_service.dart';
import '../services/push_notification_service.dart'; // Add this import
import '../services/supabase_service.dart'; // Add this import

// New placeholder screens for navigation
import 'calendar_screen.dart';

import 'insights_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with TickerProviderStateMixin {
  int _selectedIndex = 2; // Default to AR Home (Center)
  Key _insightsKey = UniqueKey();
  Key _calendarKey = UniqueKey();

  /// 首頁（Home tab）顯示時預熱 HF 後端；不阻塞 UI。
  void _warmupBackendForHome() {
    unawaited(
      ARPartnerService()
          .prepareBackend(forceRefresh: false)
          .catchError((_) {}),
    );
  }

  Future<void> _scheduleBirthdayNotification() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        await PushNotificationService().checkAndScheduleBirthday(user.id);
      } catch (e) {
        debugPrint('Failed to schedule birthday notification: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmupBackendForHome();
      _scheduleBirthdayNotification();
    });
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      // Force reload of InsightsScreen when tapped
      _insightsKey = UniqueKey();
    }
    // Reload calendar data when switching to calendar tab
    if (index == 0) {
      // We can use a GlobalKey or a ValueNotifier to trigger reload in CalendarScreen,
      // but simpler is to just rebuild it if needed, or let CalendarScreen handle it.
      // Since CalendarScreen is stateful and kept in IndexedStack, it won't rebuild automatically.
      // We can use a key technique similar to InsightsScreen if we want a full reload.
      _calendarKey = UniqueKey();
    }
    if (index == 2) {
      _warmupBackendForHome();
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CalendarScreen(key: _calendarKey),
      InsightsScreen(key: _insightsKey),
      const HomeScreenContent(), // The original HomeScreen content
      const PersonalityCustomizationScreen(),
      const UserProfileScreen(), // Replaced SettingsScreen with UserProfileScreen
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: ConvexAppBar(
        style: TabStyle.fixedCircle,
        backgroundColor: Theme.of(context).cardTheme.color ?? Colors.white,
        activeColor: Theme.of(context).primaryColor,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        items: const [
          TabItem(icon: Icons.calendar_month_rounded, title: 'Calendar'),
          TabItem(icon: Icons.insights_rounded, title: 'Recap'),
          TabItem(icon: Icons.home_rounded, title: 'Home'),
          TabItem(icon: Icons.checkroom_rounded, title: 'Customize'),
          TabItem(icon: Icons.person_rounded, title: 'Profile'), // Changed icon and title
        ],
        initialActiveIndex: _selectedIndex,
        onTap: _onItemTapped,
        elevation: 8,
        height: 60,
        cornerRadius: 20, // Rounded top corners
      ),
    );
  }
}

// Extracted from original HomeScreen to be a child widget
class HomeScreenContent extends ConsumerStatefulWidget {
  const HomeScreenContent({super.key});

  @override
  ConsumerState<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends ConsumerState<HomeScreenContent>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiProvider);
    final voiceState = ref.watch(voiceProvider);
    final personalityAsync = ref.watch(personalityProvider);

    return personalityAsync.when(
      data: (personality) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 80), // Space for bottom bar
                child: Column(
                  children: [
                    _buildHeader(context),
                    _buildMainContent(context, aiState, voiceState, personality),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello there! 👋',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your AR companion awaits',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings_rounded),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, aiState, voiceState, PersonalityProfile personality) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: personality.primaryColor.withOpacity(0.1),
                    border: Border.all(
                      color: personality.primaryColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.face_retouching_natural,
                        size: 80,
                        color: personality.primaryColor,
                      ),
                      if (aiState.isOnline)
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  personality.characterName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: personality.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: personality.primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Summary',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: personality.primaryColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatSummary(personality.personalityDescription),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                
                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ARScreenFlutter(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.view_in_ar_rounded),
                    label: const Text('AR Mode'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatSummary(String description) {
    final cleaned = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) {
      return 'Your companion profile is being prepared.';
    }
    if (cleaned.length <= 180) {
      return cleaned;
    }
    return '${cleaned.substring(0, 177)}...';
  }
}
