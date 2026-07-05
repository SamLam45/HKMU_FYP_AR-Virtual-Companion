import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/onboarding_provider.dart';

class Step2Persona extends ConsumerStatefulWidget {
  const Step2Persona({super.key});

  @override
  Step2PersonaState createState() => Step2PersonaState();
}

class Step2PersonaState extends ConsumerState<Step2Persona>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Structure: Question text + optional predefined choices
  final List<Map<String, dynamic>> _questions = [
    {
      "text": "How would you describe your personality?",
      "options": ["Introverted", "Extroverted", "Ambivert", "Thoughtful", "Energetic"],
      "allowMultiple": true
    },
    {
      "text": "What are you looking for in an AI friend?",
      "options": ["A listener", "A mentor", "Mental support", "Just casual chat", "Entertainment"],
      "allowMultiple": true
    },
    {
      "text": "What are your hobbies?",
      "options": ["Reading", "Gaming", "Sports", "Travel", "Music", "Art", "Technology", "Nature", "Cooking", "Fashion"],
      "allowMultiple": true
    },
    {
      "text": "How should your AI companion speak?",
      "options": ["Formal", "Casual", "Flirty", "Supportive", "Teasing", "Encouraging"],
      "allowMultiple": true
    },
  ];

  @override
  void initState() {
    super.initState();
    assert(_questions.length == kOnboardingPersonaQuestionCount);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(onboardingProvider.notifier);
      final s = ref.read(onboardingProvider);
      final capped = s.personaQuestionIndex.clamp(0, _questions.length);
      if (s.personaQuestionIndex != capped) {
        notifier.setPersonaQuestionIndex(capped);
      }
      notifier.updateProgress(capped, _questions.length);
    });
  }

  Set<String> _selectionsForIndex(OnboardingState s, int questionIndex) {
    if (questionIndex < 0 || questionIndex >= s.personaSelectionsPerQuestion.length) {
      return {};
    }
    return Set<String>.from(s.personaSelectionsPerQuestion[questionIndex]);
  }

  void _handleOptionSelect(int questionIndex, String option, bool allowMultiple) {
    final notifier = ref.read(onboardingProvider.notifier);
    final s = ref.read(onboardingProvider);
    final current = _selectionsForIndex(s, questionIndex);
    if (allowMultiple) {
      if (current.contains(option)) {
        current.remove(option);
      } else {
        current.add(option);
      }
    } else {
      current
        ..clear()
        ..add(option);
    }
    notifier.setPersonaSelectionsForQuestion(questionIndex, current);
    setState(() {});
  }

  /// Handles bottom-bar / system back while on the persona step before leaving Step 2.
  /// Returns true if the event was consumed (stay on Step 2).
  bool handleParentBackIntent() {
    final providerState = ref.read(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final qi = providerState.personaQuestionIndex;

    if (providerState.isProfileGenerated) {
      notifier.clearPersonaGenerationResult();
      notifier.removeLastPersonaChatAnswer();
      notifier.setPersonaQuestionIndex(_questions.length - 1);
      notifier.updateProgress(_questions.length - 1, _questions.length);
      setState(() {});
      return true;
    }

    if (qi >= _questions.length) {
      notifier.removeLastPersonaChatAnswer();
      notifier.setPersonaQuestionIndex(_questions.length - 1);
      notifier.updateProgress(_questions.length - 1, _questions.length);
      setState(() {});
      return true;
    }

    if (qi > 0) {
      notifier.removeLastPersonaChatAnswer();
      notifier.setPersonaQuestionIndex(qi - 1);
      notifier.updateProgress(qi - 1, _questions.length);
      setState(() {});
      return true;
    }

    return false;
  }

  void _nextQuestion() {
    final notifier = ref.read(onboardingProvider.notifier);
    final s = ref.read(onboardingProvider);
    final qi = s.personaQuestionIndex;
    if (qi >= _questions.length) return;

    final selected = _selectionsForIndex(s, qi);
    if (selected.isEmpty) return;

    final currentQuestion = _questions[qi];
    final answerText = selected.join(", ");
    notifier.addToChatHistory("User Answer for '${currentQuestion['text']}': $answerText");

    final nextIndex = qi + 1;
    notifier.setPersonaQuestionIndex(nextIndex);
    notifier.updateProgress(nextIndex, _questions.length);

    if (nextIndex >= _questions.length) {
      notifier.generatePersonalityProfile();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(onboardingProvider);
    final isCompleted = state.isProfileGenerated;
    final qi = state.personaQuestionIndex;

    if (isCompleted && state.generatedProfile != null) {
      return _buildSummaryCard(context, state);
    }

    if (qi >= _questions.length) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentQuestion = _questions[qi];
    final options = currentQuestion['options'] as List<String>;
    final allowMultiple = currentQuestion['allowMultiple'] as bool;
    final selected = _selectionsForIndex(state, qi);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: (qi + 1) / _questions.length,
            backgroundColor: Colors.grey.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(height: 32),
          Text(
            currentQuestion['text'],
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          if (allowMultiple)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                "Select all that apply",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 32),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: options.map((option) {
                  final isSelected = selected.contains(option);
                  return InkWell(
                    onTap: () => _handleOptionSelect(qi, option, allowMultiple),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Theme.of(context).primaryColor : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
                          width: 1.5,
                        ),
                        boxShadow: [
                          if (!isSelected)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      child: Text(
                        option,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: selected.isNotEmpty ? _nextQuestion : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Theme.of(context).primaryColor,
              disabledBackgroundColor: Colors.grey.shade300,
            ),
            child: const Text(
              "Next",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, OnboardingState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.auto_awesome, color: Theme.of(context).primaryColor, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Persona Generated!",
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                "Based on your preferences",
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      state.generatedProfile!['summary'],
                      style: TextStyle(
                        color: Colors.grey[800],
                        height: 1.5,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (state.generatedProfile!['traits'] as List<dynamic>)
                          .map((t) => Chip(
                                label: Text(t.toString(),
                                    style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600)),
                                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.08),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.2)),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade50,
                          foregroundColor: Colors.green,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.green.withOpacity(0.5)),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline),
                            SizedBox(width: 8),
                            Text("Ready to Continue", style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
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
}
