import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'lip_sync_provider.dart';

// Voice State
class VoiceState {
  final bool isListening;
  final bool isSpeaking;
  final String? recognizedText;
  final String? lastSpokenText;
  final bool isAvailable;
  final String? error;

  const VoiceState({
    this.isListening = false,
    this.isSpeaking = false,
    this.recognizedText,
    this.lastSpokenText,
    this.isAvailable = true, // Always available in demo mode
    this.error,
  });

  VoiceState copyWith({
    bool? isListening,
    bool? isSpeaking,
    String? recognizedText,
    String? lastSpokenText,
    bool? isAvailable,
    String? error,
  }) {
    return VoiceState(
      isListening: isListening ?? this.isListening,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      recognizedText: recognizedText ?? this.recognizedText,
      lastSpokenText: lastSpokenText ?? this.lastSpokenText,
      isAvailable: isAvailable ?? this.isAvailable,
      error: error ?? this.error,
    );
  }
}

// Voice Provider (Simplified Demo Version)
class VoiceProvider extends StateNotifier<VoiceState> {
  final LipSyncNotifier _lipSyncNotifier;
  
  VoiceProvider(this._lipSyncNotifier) : super(const VoiceState());

  Future<void> startListening() async {
    try {
      state = state.copyWith(isListening: true, error: null);
      
      // Simulate listening for 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      
      // Simulate recognized text
      final simulatedText = _getSimulatedUserInput();
      state = state.copyWith(
        recognizedText: simulatedText,
        isListening: false,
      );
      
      // Generate AI response
      await _processRecognizedText(simulatedText);
      
    } catch (e) {
      state = state.copyWith(
        isListening: false,
        error: 'Demo mode: Voice recognition not available',
      );
    }
  }

  Future<void> stopListening() async {
    state = state.copyWith(isListening: false);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    try {
      state = state.copyWith(
        isSpeaking: true,
        lastSpokenText: text,
        error: null,
      );

      // Start lip sync
      await _lipSyncNotifier.startLipSync(text);

      // Simulate speaking for 2 seconds
      await Future.delayed(const Duration(seconds: 2));
      
      // Stop lip sync
      _lipSyncNotifier.stopLipSync();
      
      state = state.copyWith(isSpeaking: false);
      
    } catch (e) {
      state = state.copyWith(
        isSpeaking: false,
        error: 'Demo mode: Text-to-speech not available',
      );
    }
  }

  Future<void> stopSpeaking() async {
    _lipSyncNotifier.stopLipSync();
    state = state.copyWith(isSpeaking: false);
  }

  Future<void> _processRecognizedText(String text) async {
    if (text.isEmpty) return;

    // Generate AI response
    final response = await _generateAIResponse(text);
    
    // Speak the response
    await speak(response);
  }

  Future<String> _generateAIResponse(String userInput) async {
    // Simulate AI response generation
    await Future.delayed(const Duration(milliseconds: 500));
    
    final responses = [
      "That's interesting! Tell me more about that.",
      "I understand how you feel about that.",
      "That sounds wonderful! I'm happy for you.",
      "I'm here to listen and help you with anything you need.",
      "You're such a thoughtful person. I appreciate you sharing that with me.",
      "I love spending time with you! What else would you like to talk about?",
      "That's amazing! You always surprise me with your stories.",
      "I'm so glad you're here with me right now.",
    ];
    
    return responses[DateTime.now().millisecond % responses.length];
  }

  String _getSimulatedUserInput() {
    final inputs = [
      "Hello, how are you today?",
      "I had a great day at work!",
      "Can you tell me a story?",
      "I'm feeling a bit sad today.",
      "What's your favorite color?",
      "I love spending time with you.",
      "Tell me something interesting.",
      "I'm excited about tomorrow!",
    ];
    
    return inputs[DateTime.now().millisecond % inputs.length];
  }

  Future<void> setVoiceSettings({
    double? pitch,
    double? rate,
    double? volume,
  }) async {
    // Demo mode - settings are not actually applied
    state = state.copyWith(error: 'Demo mode: Voice settings not available');
  }
}

// Provider instance
final voiceProvider = StateNotifierProvider<VoiceProvider, VoiceState>((ref) {
  final lipSyncNotifier = ref.read(lipSyncProvider.notifier);
  return VoiceProvider(lipSyncNotifier);
});
