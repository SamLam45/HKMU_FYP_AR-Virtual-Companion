import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/onboarding_provider.dart';
import 'step1_profile.dart';
import 'step2_persona.dart';
import 'step3_avatar.dart';
import '../main_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late PageController _pageController;
  final GlobalKey<Step2PersonaState> _step2Key = GlobalKey<Step2PersonaState>();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onNext() async {
    final state = ref.read(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    if (state.currentStep == 0) {
      // Step 1: Profile Validation
      if (state.username.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please validate your username first')),
        );
        return;
      }
      if (state.aiNickname.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Please enter AI nickname')),
        );
        return;
      }
      notifier.nextStep();
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (state.currentStep == 1) {
      // Step 2: Persona Validation
      // Ensure personality profile is generated
      if (!state.isProfileGenerated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please complete the personality quiz first')),
        );
        return;
      }
      
      notifier.nextStep();
      _pageController.animateToPage(
        2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (state.currentStep == 2) {
      // Step 3: Finish — [completeOnboarding] resolves a default idle.glb URL if still unset.
      final success = await notifier.completeOnboarding();
      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      } else if (mounted) {
        final currentState = ref.read(onboardingProvider);
        if (currentState.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${currentState.error}')),
          );
        }
      }
    }
  }

  void _handleBack() {
    final state = ref.read(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    if (state.currentStep == 1) {
      final consumed = _step2Key.currentState?.handleParentBackIntent() ?? false;
      if (consumed) return;
    }

    if (state.currentStep > 0) {
      final targetPage = state.currentStep - 1;
      notifier.previousStep();
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final totalSteps = 3;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Skip on Step 2 (persona quiz) → go straight to AR model selection (Step 3)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (state.currentStep == 1)
                    TextButton(
                      onPressed: () {
                        final notifier = ref.read(onboardingProvider.notifier);
                        notifier.skipToAvatarStep();
                        _pageController.animateToPage(
                          2,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Progress Indicator
            LinearProgressIndicator(
              value: (state.currentStep + 1) / totalSteps,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
            ),
            
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disable swipe
                children: [
                  const Step1Profile(),
                  Step2Persona(key: _step2Key),
                  const Step3Avatar(),
                ],
              ),
            ),

            // Bottom Navigation
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (state.currentStep > 0)
                    TextButton(
                      onPressed: state.isLoading ? null : _handleBack,
                      child: Text('Back', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  else
                    const SizedBox.shrink(), // Placeholder

                  ElevatedButton(
                    onPressed: state.isLoading || (state.currentStep == 1 && !state.isProfileGenerated) ? null : _onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (state.currentStep == 1 && !state.isProfileGenerated) 
                          ? Theme.of(context).disabledColor 
                          : Theme.of(context).primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: state.isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            state.currentStep == totalSteps - 1 ? 'Finish' : 
                            (state.currentStep == 1 && !state.isProfileGenerated) 
                              ? '${state.totalQuestions - state.answeredQuestionsCount} Left' 
                              : 'Next'
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
