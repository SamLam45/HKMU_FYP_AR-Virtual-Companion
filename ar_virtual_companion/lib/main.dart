import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/welcome_screen.dart';
import 'services/permission_service.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';

import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize(); // Initialize Supabase
  
  // Initialize permissions
  await PermissionService.initializePermissions();
  
  // Initialize push notification service
  await PushNotificationService().initialize();
  
  runApp(
    const ProviderScope(
      child: AIGirlfriendApp(),
    ),
  );
}

class AIGirlfriendApp extends StatelessWidget {
  const AIGirlfriendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Companion',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme, // Optional: You can remove this or keep it if you want to support dark mode later
      themeMode: ThemeMode.light, // Force light mode for "SumOne" cream style
      home: const WelcomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
