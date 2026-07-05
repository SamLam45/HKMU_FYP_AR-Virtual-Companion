import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../providers/ai_provider.dart';
import '../providers/voice_provider_simple.dart';
import '../providers/personality_provider.dart';
import '../models/ai_character.dart';
import '../models/personality_model.dart';
import 'personality_customization_screen.dart';
import 'memory_screen.dart';
import 'login_screen.dart';
import '../services/supabase_service.dart';
import '../services/session_cleanup.dart';
import '../services/data_export_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiProvider);
    final voiceState = ref.watch(voiceProvider);
    final personalityAsync = ref.watch(personalityProvider);
    
    return personalityAsync.when(
      data: (personality) => Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text(
            'Settings',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87, size: 24),
        ),
        body: Semantics(
          label: 'Settings screen',
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _buildOverviewCard(personality),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: _buildSectionHeader('Account'),
              ),
              Semantics(
                label: 'Account settings section',
                child: _buildAccountCard(),
              ),

              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: _buildSectionHeader('About'),
              ),
              Semantics(
                label: 'About and information section',
                child: _buildAboutCard(personality),
              ),
            ],
          ),
        ),
      ),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        body: Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    IconData icon;
    switch (title) {
      case 'Account':
        icon = Icons.manage_accounts;
        break;
      case 'About':
        icon = Icons.info_outline;
        break;
      default:
        icon = Icons.settings;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(PersonalityProfile personality) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: personality.primaryColor.withOpacity(0.08),
        border: Border.all(color: personality.primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: personality.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune, color: personality.primaryColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Manage your account settings quickly by section.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await _scaleController.forward();
                await _scaleController.reverse();
                onTap();
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: iconColor.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: iconColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ] else
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        height: 1,
        color: Theme.of(context).dividerColor.withOpacity(0.3),
      ),
    );
  }

  Future<void> _handleDeleteAccount() async {
    // Step 1: Initial Confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This will permanently remove all your data, including your profile, journal entries, and settings. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Step 2: Second Confirmation (Type "DELETE")
    final typeController = TextEditingController();
    if (!mounted) return;
    
    final finalCheck = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Final Confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please type "DELETE" to confirm.'),
            const SizedBox(height: 16),
            TextField(
              controller: typeController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'DELETE',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (typeController.text == 'DELETE') {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Verification failed. Please type DELETE exactly.')),
                );
              }
            },
            child: const Text('Confirm Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (finalCheck == true && mounted) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        await SupabaseService.deleteAccount();

        if (mounted) {
          // Remove loading indicator
          Navigator.pop(context);

          await SessionCleanup.afterSessionEnded(ref);
          if (!mounted) return;

          // Navigate to Login
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account deleted successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Remove loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting account: $e')),
          );
        }
      }
    }
  }

  Widget _buildAccountCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildSettingItem(
              icon: Icons.logout,
              iconColor: Colors.orange,
              title: 'Sign Out',
              subtitle: 'Sign out of your account',
              onTap: _handleSignOut,
            ),
            _buildDivider(),
            _buildSettingItem(
              icon: Icons.delete_forever,
              iconColor: Colors.red,
              title: 'Delete Account',
              subtitle: 'Permanently remove your account',
              onTap: _handleDeleteAccount,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await SupabaseService.signOut();
        if (mounted) {
          await SessionCleanup.afterSessionEnded(ref);
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error signing out: $e')),
          );
        }
      }
    }
  }

  Widget _buildAboutCard(PersonalityProfile personality) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: personality.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      color: personality.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Companion v1.0.0',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your virtual experience companion',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildDivider(),
            _buildSettingItem(
              icon: Icons.help_outline,
              iconColor: personality.primaryColor,
              title: 'Help & Support',
              subtitle: 'Get help and report issues',
              onTap: () => _showHelpDialog(),
            ),
            _buildDivider(),
            _buildSettingItem(
              icon: Icons.privacy_tip_outlined,
              iconColor: personality.primaryColor,
              title: 'Privacy Policy',
              subtitle: 'How we protect your data',
              onTap: () => _showPrivacyDialog(),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🎭 Character Customization', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• Tap "Personality" to customize traits, appearance, and colors'),
              Text('• Use templates for quick character setup'),
              Text('• Adjust communication style and interests'),
              SizedBox(height: 16),
              Text('🎨 AR Features', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• Place 3D characters in your environment'),
              Text('• Take photos of AR scenes'),
              Text('• Adjust AR quality and settings'),
              SizedBox(height: 16),
              Text('💬 Voice & Memory', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• Enable voice recognition for hands-free interaction'),
              Text('• View conversation history in Memory section'),
              Text('• Export your data for backup'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Last updated: January 21, 2026',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text(
                '1. Information We Collect',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Personal Information: Character names, personality traits, appearance preferences, and custom settings you create.\n'
                '• Conversation Data: Messages and interactions with your AI character.\n'
                '• Usage Data: App usage patterns, feature usage, and performance metrics.\n'
                '• Media Files: Photos and AR screenshots you choose to save.\n'
                '• Voice Data: Voice recordings if voice features are enabled.',
              ),
              const SizedBox(height: 16),
              const Text(
                '2. How We Use Your Information',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '• To provide and personalize your AI character experience.\n'
                '• To process conversations and generate appropriate responses.\n'
                '• To improve app performance and fix technical issues.\n'
                '• To save your preferences and settings.\n'
                '• To enable voice recognition and speech synthesis features.',
              ),
              const SizedBox(height: 16),
              const Text(
                '3. Data Storage and Security',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '• All data is stored locally on your device by default.\n'
                '• Optional cloud backup features may store data securely on our servers.\n'
                '• We use industry-standard encryption to protect your data.\n'
                '• Voice data is processed locally when possible to minimize transmission.',
              ),
              const SizedBox(height: 16),
              const Text(
                '4. Data Sharing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '• We do not sell your personal information to third parties.\n'
                '• Data may be shared with AI service providers for processing conversations.\n'
                '• Anonymous usage statistics may be shared for app improvement.\n'
                '• We may share data if required by law or to protect user safety.',
              ),
              const SizedBox(height: 16),
              const Text(
                '5. Your Rights',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Access: You can export your data anytime from Settings > Memory & Data.\n'
                '• Delete: You can clear all data from Settings > Memory & Data.\n'
                '• Modify: You can change your preferences and settings anytime.\n'
                '• Opt-out: You can disable voice features and data collection in settings.',
              ),
              const SizedBox(height: 16),
              const Text(
                '6. Children\'s Privacy',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This app is intended for users 13 and older. We do not knowingly collect personal information from children under 13.',
              ),
              const SizedBox(height: 16),
              const Text(
                '7. Changes to This Policy',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'We may update this privacy policy from time to time. We will notify you of any changes by posting the new policy in the app.',
              ),
              const SizedBox(height: 16),
              const Text(
                '8. Contact Us',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'If you have questions about this privacy policy, please contact us at privacy@ai-girlfriend-app.com',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
