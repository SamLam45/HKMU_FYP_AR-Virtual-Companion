import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';
import '../services/ai_partner_service.dart';
import '../services/auth_service.dart';

/// Must match `Step2Persona` question count.
const int kOnboardingPersonaQuestionCount = 4;

List<List<String>> _clonePersonaSelections(List<List<String>> src) {
  return [for (final row in src) List<String>.from(row)];
}

class OnboardingState {
  final int currentStep;
  final String username;
  final String aiNickname;
  final DateTime? birthday;
  final bool isLoading;
  final String? error;
  
  // Chat-based inputs
  final List<String> chatHistory; // Stores the Q&A flow
  final String currentInput;
  
  // AI Generated Profile
  final Map<String, dynamic>? generatedProfile;
  final bool isProfileGenerated;
  final int totalQuestions;
  final int answeredQuestionsCount;

  /// Step 2: current quiz card index (0 .. kOnboardingPersonaQuestionCount-1), or length when loading/generating.
  final int personaQuestionIndex;
  /// Step 2: saved chip selections per question (persist across leaving the step).
  final List<List<String>> personaSelectionsPerQuestion;

  // Avatar Selection
  final String gender;
  final String? avatarModelUrl;
  /// Step 3: carousel index within current gender's idle.glb list.
  final int avatarCarouselIndex;

  OnboardingState({
    this.currentStep = 0,
    this.username = '',
    this.aiNickname = '',
    this.birthday,
    this.isLoading = false,
    this.error,
    this.chatHistory = const [],
    this.currentInput = '',
    this.generatedProfile,
    this.isProfileGenerated = false,
    this.totalQuestions = 6, // Set based on Step2Persona questions count
    this.answeredQuestionsCount = 0,
    this.personaQuestionIndex = 0,
    List<List<String>>? personaSelectionsPerQuestion,
    this.gender = 'female',
    this.avatarModelUrl,
    this.avatarCarouselIndex = 0,
  }) : personaSelectionsPerQuestion = personaSelectionsPerQuestion ??
            List.generate(kOnboardingPersonaQuestionCount, (_) => []);

  OnboardingState copyWith({
    int? currentStep,
    String? username,
    String? aiNickname,
    DateTime? birthday,
    bool? isLoading,
    String? error,
    List<String>? chatHistory,
    String? currentInput,
    Map<String, dynamic>? generatedProfile,
    bool? isProfileGenerated,
    int? totalQuestions,
    int? answeredQuestionsCount,
    int? personaQuestionIndex,
    List<List<String>>? personaSelectionsPerQuestion,
    String? gender,
    String? avatarModelUrl,
    /// When true, [avatarModelUrl] is ignored and the field is cleared (cannot do this with `??` alone).
    bool clearAvatarModelUrl = false,
    int? avatarCarouselIndex,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      username: username ?? this.username,
      aiNickname: aiNickname ?? this.aiNickname,
      birthday: birthday ?? this.birthday,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      chatHistory: chatHistory ?? this.chatHistory,
      currentInput: currentInput ?? this.currentInput,
      generatedProfile: generatedProfile ?? this.generatedProfile,
      isProfileGenerated: isProfileGenerated ?? this.isProfileGenerated,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      answeredQuestionsCount: answeredQuestionsCount ?? this.answeredQuestionsCount,
      personaQuestionIndex: personaQuestionIndex ?? this.personaQuestionIndex,
      personaSelectionsPerQuestion: personaSelectionsPerQuestion != null
          ? _clonePersonaSelections(personaSelectionsPerQuestion)
          : _clonePersonaSelections(this.personaSelectionsPerQuestion),
      gender: gender ?? this.gender,
      avatarModelUrl:
          clearAvatarModelUrl ? null : (avatarModelUrl ?? this.avatarModelUrl),
      avatarCarouselIndex: avatarCarouselIndex ?? this.avatarCarouselIndex,
    );
  }
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(OnboardingState());

  void setPersonaQuestionIndex(int index) {
    state = state.copyWith(personaQuestionIndex: index);
  }

  /// Persists chip selections for one question (0-based).
  void setPersonaSelectionsForQuestion(int questionIndex, Set<String> selection) {
    final rows = _clonePersonaSelections(state.personaSelectionsPerQuestion);
    while (rows.length <= questionIndex) {
      rows.add([]);
    }
    rows[questionIndex] = selection.toList()..sort();
    state = state.copyWith(personaSelectionsPerQuestion: rows);
  }

  void setAvatarCarouselIndex(int index) {
    state = state.copyWith(avatarCarouselIndex: index);
  }

  void setUsername(String value) {
    state = state.copyWith(username: value);
  }

  void setAiNickname(String value) {
    state = state.copyWith(aiNickname: value);
  }

  void setBirthday(DateTime date) {
    state = state.copyWith(birthday: date);
  }

  void addToChatHistory(String message) {
    final history = List<String>.from(state.chatHistory)..add(message);
    state = state.copyWith(chatHistory: history);
  }

  /// Removes the last Step 2 persona answer line (if present).
  void removeLastPersonaChatAnswer() {
    final history = List<String>.from(state.chatHistory);
    if (history.isNotEmpty && history.last.startsWith('User Answer for')) {
      history.removeLast();
      state = state.copyWith(chatHistory: history);
    }
  }

  void clearPersonaGenerationResult() {
    state = state.copyWith(
      isProfileGenerated: false,
      generatedProfile: null,
      isLoading: false,
    );
  }
  
  void updateProgress(int answered, int total) {
    state = state.copyWith(
      answeredQuestionsCount: answered,
      totalQuestions: total
    );
  }

  static const String _speechStyleQuestionText = 'How should your AI companion speak?';

  /// One chip label → canonical lowercase (app / Supabase).
  static String? _normalizeSpeechStyleToken(String raw) {
    final k = raw.trim().toLowerCase();
    const allowed = {
      'formal',
      'casual',
      'flirty',
      'supportive',
      'teasing',
      'encouraging',
    };
    if (allowed.contains(k)) return k;
    return null;
  }

  static const Map<String, String> _speechCanonicalToDisplay = {
    'formal': 'Formal',
    'casual': 'Casual',
    'flirty': 'Flirty',
    'supportive': 'Supportive',
    'teasing': 'Teasing',
    'encouraging': 'Encouraging',
  };

  /// Parses comma-separated multi-select; merges into [traits] for Customize chips; sets [communication_style] to first (backend compat).
  static void _mergeUserSpeechStylesFromChat(
    Map<String, dynamic> profile,
    List<String> chatHistory,
  ) {
    final prefix = "User Answer for '$_speechStyleQuestionText': ";
    for (final msg in chatHistory) {
      final line = msg.trim();
      if (!line.startsWith(prefix)) continue;

      final rest = line.substring(prefix.length).trim();
      final selected = <String>[];
      for (final part in rest.split(',')) {
        final n = _normalizeSpeechStyleToken(part);
        if (n != null && !selected.contains(n)) selected.add(n);
      }
      if (selected.isEmpty) return;

      profile['communication_style'] = selected.first;

      final rawTraits = profile['traits'];
      final traitList = <String>[
        if (rawTraits is List) ...rawTraits.map((e) => e.toString()),
      ];
      for (final s in selected) {
        final d = _speechCanonicalToDisplay[s];
        if (d == null) continue;
        if (!traitList.any((t) => t.toLowerCase() == d.toLowerCase())) {
          traitList.add(d);
        }
      }
      profile['traits'] = traitList;
      return;
    }
  }

  // AI Summary Generation via Backend
  Future<void> generatePersonalityProfile() async {
    state = state.copyWith(isLoading: true);
    
    try {
      final userId = await AuthService.getUidOrGuest();
      
      // Parse chat history → qa_list for /v1/persona/analyze
      // Step2 uses: User Answer for '<question>': <answer>
      // (Legacy format AI:/User: kept for compatibility.)
      List<Map<String, String>> qaList = [];
      String? lastQuestion;
      final userAnswerRe = RegExp(r"^User Answer for '(.+)': (.+)$");

      for (var msg in state.chatHistory) {
        final line = msg.trim();
        final ua = userAnswerRe.firstMatch(line);
        if (ua != null) {
          qaList.add({
            'question': ua.group(1)!.trim(),
            'answer': ua.group(2)!.trim(),
          });
          continue;
        }
        if (line.startsWith("AI:")) {
          lastQuestion = line.substring(3).trim();
        } else if (line.startsWith("User:") && lastQuestion != null) {
          qaList.add({
            "question": lastQuestion,
            "answer": line.substring(5).trim(),
          });
        }
      }

      if (qaList.isEmpty) {
        debugPrint(
          '[Onboarding] generatePersonalityProfile: qaList is empty — '
          'persona API had no interview answers (check chatHistory format).',
        );
      }

      // Call Backend API
      final service = ARPartnerService();
      final profile = await service.analyzePersona(userId, qaList);
      
      if (profile != null) {
        // Add interview data to the profile so it gets stored in Supabase
        final fullProfile = Map<String, dynamic>.from(profile);
        fullProfile['interview_data'] = qaList;
        _mergeUserSpeechStylesFromChat(fullProfile, state.chatHistory);

        state = state.copyWith(
          isLoading: false,
          generatedProfile: fullProfile,
          isProfileGenerated: true,
        );
      } else {
        // Fallback to mock if API fails
        print("API Analysis failed, using fallback");
        final mockProfile = {
            'summary': 'Based on our conversation, you seem to value deep connections and intellectual growth.',
            'traits': ['Supportive', 'Adventurous', 'Calm'],
            'communication_style': 'supportive',
            'interview_data': qaList,
            'interests': <String>[],
        };
        _mergeUserSpeechStylesFromChat(mockProfile, state.chatHistory);
        state = state.copyWith(
          isLoading: false,
          generatedProfile: mockProfile,
          isProfileGenerated: true,
        );
      }
    } catch (e) {
      print("Error generating profile: $e");
      state = state.copyWith(isLoading: false, error: "Failed to generate profile");
    }
  }

  void setGender(String gender) {
    state = state.copyWith(
      gender: gender,
      avatarCarouselIndex: 0,
      clearAvatarModelUrl: true,
    );
  }

  void setAvatarModelUrl(String url) {
    state = state.copyWith(avatarModelUrl: url);
  }

  void nextStep() {
    state = state.copyWith(currentStep: state.currentStep + 1);
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  /// From Step 2 (persona quiz): skip straight to Step 3 (AR avatar selection).
  void skipToAvatarStep() {
    state = state.copyWith(currentStep: 2);
  }

  Future<bool> completeOnboarding() async {
    var avatarUrl = state.avatarModelUrl?.trim();
    if (avatarUrl == null || avatarUrl.isEmpty) {
      final prefix = '${state.gender.toLowerCase()}1';
      final urls = await SupabaseService.fetchIdleGlbAvatarUrlsForGenderPrefix(prefix);
      if (urls.isEmpty) {
        state = state.copyWith(
          error: 'No avatar models found. Upload idle.glb files to ar_assets.',
        );
        return false;
      }
      final idx = state.avatarCarouselIndex.clamp(0, urls.length - 1);
      avatarUrl = urls[idx];
      state = state.copyWith(avatarModelUrl: avatarUrl);
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      await SupabaseService.createUserProfile(
        username: state.username,
        aiNickname: state.aiNickname,
        selectedPersonaId: null, // 不預設任何 persona
        preferences: {}, // Default
        gender: state.gender,
        avatarModelUrl: avatarUrl,
        birthday: state.birthday,
        detailedPersonalityProfile: state.generatedProfile,
      );
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }
}

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
  return OnboardingNotifier();
});

// 使用 KeepAlive 避免每次切換 Tab 或重建畫面時都重新向 Supabase 發送請求
final avatarAssetsProvider = FutureProvider.family<List<String>, String>((ref, genderPrefix) async {
  // 保持快取存活
  ref.keepAlive();
  
  final homeAssets = await SupabaseService.fetchAvatarAssets('$genderPrefix/Home');
  final outsideAssets = await SupabaseService.fetchAvatarAssets('$genderPrefix/Outside');
  return [...homeAssets, ...outsideAssets];
});
