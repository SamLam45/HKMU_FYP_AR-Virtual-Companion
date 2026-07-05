enum EmotionalState {
  happy,
  sad,
  excited,
  calm,
  surprised,
  angry,
  confused,
  loving;

  String get displayName {
    switch (this) {
      case EmotionalState.happy:
        return 'Happy';
      case EmotionalState.sad:
        return 'Sad';
      case EmotionalState.excited:
        return 'Excited';
      case EmotionalState.calm:
        return 'Calm';
      case EmotionalState.surprised:
        return 'Surprised';
      case EmotionalState.angry:
        return 'Angry';
      case EmotionalState.confused:
        return 'Confused';
      case EmotionalState.loving:
        return 'Loving';
    }
  }
}

class VoiceSettings {
  final double pitch;
  final double rate;
  final double volume;

  const VoiceSettings({
    this.pitch = 1.0,
    this.rate = 0.5,
    this.volume = 0.8,
  });

  VoiceSettings copyWith({
    double? pitch,
    double? rate,
    double? volume,
  }) {
    return VoiceSettings(
      pitch: pitch ?? this.pitch,
      rate: rate ?? this.rate,
      volume: volume ?? this.volume,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pitch': pitch,
      'rate': rate,
      'volume': volume,
    };
  }

  factory VoiceSettings.fromJson(Map<String, dynamic> json) {
    return VoiceSettings(
      pitch: json['pitch']?.toDouble() ?? 1.0,
      rate: json['rate']?.toDouble() ?? 0.5,
      volume: json['volume']?.toDouble() ?? 0.8,
    );
  }
}

class AICharacter {
  final String name;
  final String personality;
  final VoiceSettings voiceSettings;
  final EmotionalState emotionalState;
  final DateTime createdAt;
  final DateTime lastInteraction;
  final Map<String, dynamic> preferences;

  const AICharacter({
    required this.name,
    required this.personality,
    required this.voiceSettings,
    required this.emotionalState,
    required this.createdAt,
    required this.lastInteraction,
    this.preferences = const {},
  });

  AICharacter copyWith({
    String? name,
    String? personality,
    VoiceSettings? voiceSettings,
    EmotionalState? emotionalState,
    DateTime? createdAt,
    DateTime? lastInteraction,
    Map<String, dynamic>? preferences,
  }) {
    return AICharacter(
      name: name ?? this.name,
      personality: personality ?? this.personality,
      voiceSettings: voiceSettings ?? this.voiceSettings,
      emotionalState: emotionalState ?? this.emotionalState,
      createdAt: createdAt ?? this.createdAt,
      lastInteraction: lastInteraction ?? this.lastInteraction,
      preferences: preferences ?? this.preferences,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'personality': personality,
      'voiceSettings': voiceSettings.toJson(),
      'emotionalState': emotionalState.name,
      'createdAt': createdAt.toIso8601String(),
      'lastInteraction': lastInteraction.toIso8601String(),
      'preferences': preferences,
    };
  }

  factory AICharacter.fromJson(Map<String, dynamic> json) {
    return AICharacter(
      name: json['name'] ?? 'Luna',
      personality: json['personality'] ?? 'Friendly AI companion',
      voiceSettings: VoiceSettings.fromJson(
        json['voiceSettings'] ?? {},
      ),
      emotionalState: EmotionalState.values.firstWhere(
        (e) => e.name == json['emotionalState'],
        orElse: () => EmotionalState.happy,
      ),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastInteraction: DateTime.parse(json['lastInteraction'] ?? DateTime.now().toIso8601String()),
      preferences: Map<String, dynamic>.from(json['preferences'] ?? {}),
    );
  }
}

class ConversationMemory {
  final String id;
  final String userMessage;
  final String aiResponse;
  final EmotionalState emotionalState;
  final DateTime timestamp;
  final Map<String, dynamic> context;

  const ConversationMemory({
    required this.id,
    required this.userMessage,
    required this.aiResponse,
    required this.emotionalState,
    required this.timestamp,
    this.context = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userMessage': userMessage,
      'aiResponse': aiResponse,
      'emotionalState': emotionalState.name,
      'timestamp': timestamp.toIso8601String(),
      'context': context,
    };
  }

  factory ConversationMemory.fromJson(Map<String, dynamic> json) {
    return ConversationMemory(
      id: json['id'] ?? '',
      userMessage: json['userMessage'] ?? '',
      aiResponse: json['aiResponse'] ?? '',
      emotionalState: EmotionalState.values.firstWhere(
        (e) => e.name == json['emotionalState'],
        orElse: () => EmotionalState.happy,
      ),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      context: Map<String, dynamic>.from(json['context'] ?? {}),
    );
  }
}
