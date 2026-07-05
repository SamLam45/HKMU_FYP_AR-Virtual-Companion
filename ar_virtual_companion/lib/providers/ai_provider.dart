import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai_character.dart';

// AI Character State
class AIState {
  final AICharacter? character;
  final bool isOnline;
  final bool isProcessing;
  final String? lastMessage;
  final String? error;

  const AIState({
    this.character,
    this.isOnline = false,
    this.isProcessing = false,
    this.lastMessage,
    this.error,
  });

  AIState copyWith({
    AICharacter? character,
    bool? isOnline,
    bool? isProcessing,
    String? lastMessage,
    String? error,
  }) {
    return AIState(
      character: character ?? this.character,
      isOnline: isOnline ?? this.isOnline,
      isProcessing: isProcessing ?? this.isProcessing,
      lastMessage: lastMessage ?? this.lastMessage,
      error: error ?? this.error,
    );
  }

  String? get characterName => character?.name;
}

// AI Provider
class AIProvider extends StateNotifier<AIState> {
  AIProvider() : super(const AIState()) {
    _initializeCharacter();
  }

  Future<void> _initializeCharacter() async {
    try {
      state = state.copyWith(isProcessing: true);
      
      // Create default character
      final character = AICharacter(
        name: 'Luna',
        personality: 'Friendly and caring AI companion',
        voiceSettings: VoiceSettings(
          pitch: 1.0,
          rate: 0.5,
          volume: 0.8,
        ),
        emotionalState: EmotionalState.happy,
        createdAt: DateTime.now(),
        lastInteraction: DateTime.now(),
      );
      
      state = state.copyWith(
        character: character,
        isOnline: true,
        isProcessing: false,
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Failed to initialize AI character: $e',
      );
    }
  }

  Future<void> updateEmotionalState(EmotionalState emotion) async {
    if (state.character == null) return;
    
    final updatedCharacter = state.character!.copyWith(
      emotionalState: emotion,
    );
    
    state = state.copyWith(character: updatedCharacter);
  }

  Future<void> updatePersonality(String personality) async {
    if (state.character == null) return;
    
    final updatedCharacter = state.character!.copyWith(
      personality: personality,
    );
    
    state = state.copyWith(character: updatedCharacter);
  }

  Future<void> updateVoiceSettings(VoiceSettings voiceSettings) async {
    if (state.character == null) return;
    
    final updatedCharacter = state.character!.copyWith(
      voiceSettings: voiceSettings,
    );
    
    state = state.copyWith(character: updatedCharacter);
  }
}

// Provider instance
final aiProvider = StateNotifierProvider<AIProvider, AIState>((ref) {
  return AIProvider();
});
