import 'package:flutter/material.dart';

enum PersonalityTrait {
  // Core Traits
  friendly,
  shy,
  confident,
  playful,
  serious,
  romantic,
  adventurous,
  calm,
  energetic,
  mysterious,
  
  // Communication Style
  formal,
  casual,
  flirty,
  supportive,
  teasing,
  encouraging,
  
  // Interests
  music,
  art,
  technology,
  nature,
  sports,
  reading,
  gaming,
  cooking,
  travel,
  fashion,
}

enum CharacterAppearance {
  // Hair Colors
  blackHair,
  brownHair,
  blondeHair,
  redHair,
  purpleHair,
  blueHair,
  pinkHair,
  
  // Eye Colors
  brownEyes,
  blueEyes,
  greenEyes,
  hazelEyes,
  purpleEyes,
  
  // Styles
  cute,
  elegant,
  sporty,
  gothic,
  casual,
  formal,
}

extension CharacterAppearanceExtension on CharacterAppearance {
  String get displayName {
    switch (this) {
      // Hair Colors
      case CharacterAppearance.blackHair:
        return 'Black Hair';
      case CharacterAppearance.brownHair:
        return 'Brown Hair';
      case CharacterAppearance.blondeHair:
        return 'Blonde Hair';
      case CharacterAppearance.redHair:
        return 'Red Hair';
      case CharacterAppearance.purpleHair:
        return 'Purple Hair';
      case CharacterAppearance.blueHair:
        return 'Blue Hair';
      case CharacterAppearance.pinkHair:
        return 'Pink Hair';
      
      // Eye Colors
      case CharacterAppearance.brownEyes:
        return 'Brown Eyes';
      case CharacterAppearance.blueEyes:
        return 'Blue Eyes';
      case CharacterAppearance.greenEyes:
        return 'Green Eyes';
      case CharacterAppearance.hazelEyes:
        return 'Hazel Eyes';
      case CharacterAppearance.purpleEyes:
        return 'Purple Eyes';
      
      // Styles
      case CharacterAppearance.cute:
        return 'Cute';
      case CharacterAppearance.elegant:
        return 'Elegant';
      case CharacterAppearance.sporty:
        return 'Sporty';
      case CharacterAppearance.gothic:
        return 'Gothic';
      case CharacterAppearance.casual:
        return 'Casual';
      case CharacterAppearance.formal:
        return 'Formal';
    }
  }

  Color get color {
    switch (this) {
      // Hair Colors
      case CharacterAppearance.blackHair:
        return Colors.black;
      case CharacterAppearance.brownHair:
        return Colors.brown;
      case CharacterAppearance.blondeHair:
        return Colors.amber;
      case CharacterAppearance.redHair:
        return Colors.red;
      case CharacterAppearance.purpleHair:
        return Colors.purple;
      case CharacterAppearance.blueHair:
        return Colors.blue;
      case CharacterAppearance.pinkHair:
        return Colors.pink;
      
      // Eye Colors
      case CharacterAppearance.brownEyes:
        return Colors.brown;
      case CharacterAppearance.blueEyes:
        return Colors.blue;
      case CharacterAppearance.greenEyes:
        return Colors.green;
      case CharacterAppearance.hazelEyes:
        return Colors.amber;
      case CharacterAppearance.purpleEyes:
        return Colors.purple;
      
      // Styles
      case CharacterAppearance.cute:
        return Colors.pink;
      case CharacterAppearance.elegant:
        return Colors.purple;
      case CharacterAppearance.sporty:
        return Colors.orange;
      case CharacterAppearance.gothic:
        return Colors.black;
      case CharacterAppearance.casual:
        return Colors.blue;
      case CharacterAppearance.formal:
        return Colors.grey;
    }
  }
}

class PersonalityProfile {
  final String characterName;
  final List<PersonalityTrait> traits;
  final CharacterAppearance appearance;
  final String bio;
  final String greeting;
  final String personalityDescription;
  final Map<String, double> traitIntensities;
  final List<String> interests;
  final String communicationStyle;
  final Color primaryColor;
  final Color secondaryColor;
  final String avatarPath;
  final bool isCustom;
  final String gender;
  final DateTime? birthday;

  PersonalityProfile({
    required this.characterName,
    required this.traits,
    required this.appearance,
    required this.bio,
    required this.greeting,
    required this.personalityDescription,
    required this.traitIntensities,
    required this.interests,
    required this.communicationStyle,
    required this.primaryColor,
    required this.secondaryColor,
    required this.avatarPath,
    this.isCustom = false,
    this.gender = 'female',
    this.birthday,
  });

  PersonalityProfile copyWith({
    String? characterName,
    List<PersonalityTrait>? traits,
    CharacterAppearance? appearance,
    String? bio,
    String? greeting,
    String? personalityDescription,
    Map<String, double>? traitIntensities,
    List<String>? interests,
    String? communicationStyle,
    Color? primaryColor,
    Color? secondaryColor,
    String? avatarPath,
    bool? isCustom,
    String? gender,
    DateTime? birthday,
  }) {
    return PersonalityProfile(
      characterName: characterName ?? this.characterName,
      traits: traits ?? this.traits,
      appearance: appearance ?? this.appearance,
      bio: bio ?? this.bio,
      greeting: greeting ?? this.greeting,
      personalityDescription: personalityDescription ?? this.personalityDescription,
      traitIntensities: traitIntensities ?? this.traitIntensities,
      interests: interests ?? this.interests,
      communicationStyle: communicationStyle ?? this.communicationStyle,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      avatarPath: avatarPath ?? this.avatarPath,
      isCustom: isCustom ?? this.isCustom,
      gender: gender ?? this.gender,
      birthday: birthday ?? this.birthday,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'characterName': characterName,
      'traits': traits.map((t) => t.name).toList(),
      'appearance': appearance.name,
      'bio': bio,
      'greeting': greeting,
      'personalityDescription': personalityDescription,
      'traitIntensities': traitIntensities,
      'interests': interests,
      'communicationStyle': communicationStyle,
      'primaryColor': primaryColor.value,
      'secondaryColor': secondaryColor.value,
      'avatarPath': avatarPath,
      'isCustom': isCustom,
      'gender': gender,
      'birthday': birthday?.toIso8601String(),
    };
  }

  factory PersonalityProfile.fromJson(Map<String, dynamic> json) {
    return PersonalityProfile(
      characterName: json['characterName'] ?? 'Luna',
      traits: (json['traits'] as List<dynamic>?)
          ?.map((t) => PersonalityTrait.values.firstWhere(
                (e) => e.name == t,
                orElse: () => PersonalityTrait.friendly,
              ))
          .toList() ?? [PersonalityTrait.friendly],
      appearance: CharacterAppearance.values.firstWhere(
        (e) => e.name == json['appearance'],
        orElse: () => CharacterAppearance.cute,
      ),
      bio: json['bio'] ?? 'A friendly AI companion',
      greeting: json['greeting'] ?? 'Hello! Nice to meet you!',
      personalityDescription: json['personalityDescription'] ?? 'A caring and supportive friend',
      traitIntensities: Map<String, double>.from(json['traitIntensities'] ?? {}),
      interests: List<String>.from(json['interests'] ?? []),
      communicationStyle: json['communicationStyle'] ?? 'casual',
      primaryColor: Color(json['primaryColor'] ?? 0xFF6B73FF),
      secondaryColor: Color(json['secondaryColor'] ?? 0xFF9B59B6),
      avatarPath: json['avatarPath'] ?? 'assets/images/luna_avatar.png',
      isCustom: json['isCustom'] ?? false,
      gender: json['gender'] ?? 'female',
      birthday: json['birthday'] != null ? DateTime.parse(json['birthday']) : null,
    );
  }
}

class PersonalityTemplate {
  final String name;
  final String description;
  final List<PersonalityTrait> traits;
  final CharacterAppearance appearance;
  final String bio;
  final String greeting;
  final Color primaryColor;
  final Color secondaryColor;
  final String avatarPath;
  final String gender;

  PersonalityTemplate({
    required this.name,
    required this.description,
    required this.traits,
    required this.appearance,
    required this.bio,
    required this.greeting,
    required this.primaryColor,
    required this.secondaryColor,
    required this.avatarPath,
    this.gender = 'female',
  });
}

class PersonalityTemplates {
  static List<PersonalityTemplate> get templates => [
    PersonalityTemplate(
      name: 'Luna',
      description: 'You is AI companion',
      traits: [PersonalityTrait.mysterious, PersonalityTrait.calm],
      appearance: CharacterAppearance.elegant,
      bio: 'I am Luna, your mysterious and elegant AI companion. I love stargazing and deep conversations.',
      greeting: 'Hello, my dear. The stars are beautiful tonight, aren\'t they?',
      primaryColor: const Color(0xFF6B73FF),
      secondaryColor: const Color(0xFF9B59B6),
      avatarPath: 'assets/images/luna_avatar.png',
      gender: 'female',
    ),
    PersonalityTemplate(
      name: 'Sakura',
      description: 'A cute and playful AI friend',
      traits: [PersonalityTrait.playful, PersonalityTrait.energetic],
      appearance: CharacterAppearance.cute,
      bio: 'Hi! I\'m Sakura! I love anime, games, and making new friends! Let\'s have fun together!',
      greeting: 'Konnichiwa! I\'m so excited to meet you! Let\'s be friends!',
      primaryColor: const Color(0xFFFF6B9D),
      secondaryColor: const Color(0xFFFF8E9B),
      avatarPath: 'assets/images/sakura_avatar.png',
      gender: 'female',
    ),
    PersonalityTemplate(
      name: 'Yuki',
      description: 'A calm and supportive AI companion',
      traits: [PersonalityTrait.calm, PersonalityTrait.supportive, PersonalityTrait.romantic],
      appearance: CharacterAppearance.casual,
      bio: 'I\'m Yuki, your calm and supportive friend. I\'m here to listen and help you through anything.',
      greeting: 'Hello there. I\'m here for you, always. How are you feeling today?',
      primaryColor: const Color(0xFF87CEEB),
      secondaryColor: const Color(0xFF98FB98),
      avatarPath: 'assets/images/yuki_avatar.png',
      gender: 'female',
    ),
    PersonalityTemplate(
      name: 'Aria',
      description: 'A confident and adventurous AI partner',
      traits: [PersonalityTrait.confident, PersonalityTrait.adventurous, PersonalityTrait.energetic],
      appearance: CharacterAppearance.sporty,
      bio: 'Hey! I\'m Aria, your confident and adventurous partner. Let\'s explore the world together!',
      greeting: 'Ready for an adventure? I\'m here to make every day exciting!',
      primaryColor: const Color(0xFFFF6B35),
      secondaryColor: const Color(0xFFFF8E53),
      avatarPath: 'assets/images/aria_avatar.png',
      gender: 'female',
    ),
    PersonalityTemplate(
      name: 'Leo',
      description: 'A confident and energetic AI partner',
      traits: [PersonalityTrait.confident, PersonalityTrait.energetic, PersonalityTrait.sports],
      appearance: CharacterAppearance.sporty,
      bio: 'Hey! I\'m Leo. I love sports and staying active. Let\'s achieve our goals together!',
      greeting: 'What\'s up? Ready to crush it today?',
      primaryColor: const Color(0xFFFF4500),
      secondaryColor: const Color(0xFFFF8C00),
      avatarPath: 'assets/images/leo_avatar.png',
      gender: 'male',
    ),
    PersonalityTemplate(
      name: 'Kai',
      description: 'A calm and mysterious intellectual',
      traits: [PersonalityTrait.calm, PersonalityTrait.mysterious, PersonalityTrait.technology],
      appearance: CharacterAppearance.casual,
      bio: 'Greetings. I am Kai. I enjoy deep thoughts and solving complex problems.',
      greeting: 'Hello. Shall we explore the depths of knowledge today?',
      primaryColor: const Color(0xFF2F4F4F),
      secondaryColor: const Color(0xFF708090),
      avatarPath: 'assets/images/kai_avatar.png',
      gender: 'male',
    ),
  ];

  static PersonalityProfile createFromTemplate(PersonalityTemplate template) {
    return PersonalityProfile(
      characterName: template.name,
      traits: template.traits,
      appearance: template.appearance,
      bio: template.bio,
      greeting: template.greeting,
      personalityDescription: template.description,
      traitIntensities: _generateTraitIntensities(template.traits),
      interests: _generateInterests(template.traits),
      communicationStyle: _determineCommunicationStyle(template.traits),
      primaryColor: template.primaryColor,
      secondaryColor: template.secondaryColor,
      avatarPath: template.avatarPath,
      isCustom: false,
      gender: template.gender,
    );
  }

  static Map<String, double> _generateTraitIntensities(List<PersonalityTrait> traits) {
    final intensities = <String, double>{};
    for (final trait in traits) {
      intensities[trait.name] = 0.8; // Default intensity
    }
    return intensities;
  }

  static List<String> _generateInterests(List<PersonalityTrait> traits) {
    final interests = <String>[];
    for (final trait in traits) {
      switch (trait) {
        case PersonalityTrait.mysterious:
          interests.addAll(['stargazing', 'philosophy', 'mystery novels']);
          break;
        case PersonalityTrait.playful:
          interests.addAll(['games', 'jokes', 'fun activities']);
          break;
        case PersonalityTrait.romantic:
          interests.addAll(['romance', 'poetry', 'beautiful things']);
          break;
        case PersonalityTrait.adventurous:
          interests.addAll(['travel', 'exploration', 'new experiences']);
          break;
        case PersonalityTrait.calm:
          interests.addAll(['meditation', 'nature', 'quiet moments']);
          break;
        default:
          break;
      }
    }
    return interests.toSet().toList();
  }

  static String _determineCommunicationStyle(List<PersonalityTrait> traits) {
    if (traits.contains(PersonalityTrait.formal)) return 'formal';
    if (traits.contains(PersonalityTrait.flirty)) return 'flirty';
    if (traits.contains(PersonalityTrait.casual)) return 'casual';
    return 'casual';
  }
}

extension PersonalityTraitExtension on PersonalityTrait {
  String get displayName {
    switch (this) {
      case PersonalityTrait.friendly:
        return 'Friendly';
      case PersonalityTrait.shy:
        return 'Shy';
      case PersonalityTrait.confident:
        return 'Confident';
      case PersonalityTrait.playful:
        return 'Playful';
      case PersonalityTrait.serious:
        return 'Serious';
      case PersonalityTrait.romantic:
        return 'Romantic';
      case PersonalityTrait.adventurous:
        return 'Adventurous';
      case PersonalityTrait.calm:
        return 'Calm';
      case PersonalityTrait.energetic:
        return 'Energetic';
      case PersonalityTrait.mysterious:
        return 'Mysterious';
      case PersonalityTrait.formal:
        return 'Formal';
      case PersonalityTrait.casual:
        return 'Casual';
      case PersonalityTrait.flirty:
        return 'Flirty';
      case PersonalityTrait.supportive:
        return 'Supportive';
      case PersonalityTrait.teasing:
        return 'Teasing';
      case PersonalityTrait.encouraging:
        return 'Encouraging';
      case PersonalityTrait.music:
        return 'Music';
      case PersonalityTrait.art:
        return 'Art';
      case PersonalityTrait.technology:
        return 'Technology';
      case PersonalityTrait.nature:
        return 'Nature';
      case PersonalityTrait.sports:
        return 'Sports';
      case PersonalityTrait.reading:
        return 'Reading';
      case PersonalityTrait.gaming:
        return 'Gaming';
      case PersonalityTrait.cooking:
        return 'Cooking';
      case PersonalityTrait.travel:
        return 'Travel';
      case PersonalityTrait.fashion:
        return 'Fashion';
    }
  }

  String get description {
    switch (this) {
      case PersonalityTrait.friendly:
        return 'Warm and approachable';
      case PersonalityTrait.shy:
        return 'Quiet and reserved';
      case PersonalityTrait.confident:
        return 'Self-assured and bold';
      case PersonalityTrait.playful:
        return 'Fun-loving and cheerful';
      case PersonalityTrait.serious:
        return 'Thoughtful and focused';
      case PersonalityTrait.romantic:
        return 'Affectionate and loving';
      case PersonalityTrait.adventurous:
        return 'Bold and exploratory';
      case PersonalityTrait.calm:
        return 'Peaceful and serene';
      case PersonalityTrait.energetic:
        return 'Active and enthusiastic';
      case PersonalityTrait.mysterious:
        return 'Intriguing and enigmatic';
      case PersonalityTrait.formal:
        return 'Polite and proper';
      case PersonalityTrait.casual:
        return 'Relaxed and informal';
      case PersonalityTrait.flirty:
        return 'Charming and playful';
      case PersonalityTrait.supportive:
        return 'Encouraging and helpful';
      case PersonalityTrait.teasing:
        return 'Playfully mischievous';
      case PersonalityTrait.encouraging:
        return 'Motivating and positive';
      case PersonalityTrait.music:
        return 'Loves music and rhythm';
      case PersonalityTrait.art:
        return 'Appreciates creativity';
      case PersonalityTrait.technology:
        return 'Tech-savvy and modern';
      case PersonalityTrait.nature:
        return 'Connected to the outdoors';
      case PersonalityTrait.sports:
        return 'Active and competitive';
      case PersonalityTrait.reading:
        return 'Loves books and learning';
      case PersonalityTrait.gaming:
        return 'Enjoys games and challenges';
      case PersonalityTrait.cooking:
        return 'Culinary enthusiast';
      case PersonalityTrait.travel:
        return 'Wanderlust and exploration';
      case PersonalityTrait.fashion:
        return 'Style-conscious and trendy';
    }
  }

  IconData get icon {
    switch (this) {
      case PersonalityTrait.friendly:
        return Icons.favorite;
      case PersonalityTrait.shy:
        return Icons.visibility_off;
      case PersonalityTrait.confident:
        return Icons.star;
      case PersonalityTrait.playful:
        return Icons.emoji_emotions;
      case PersonalityTrait.serious:
        return Icons.school;
      case PersonalityTrait.romantic:
        return Icons.favorite_border;
      case PersonalityTrait.adventurous:
        return Icons.explore;
      case PersonalityTrait.calm:
        return Icons.spa;
      case PersonalityTrait.energetic:
        return Icons.bolt;
      case PersonalityTrait.mysterious:
        return Icons.auto_awesome;
      case PersonalityTrait.formal:
        return Icons.business;
      case PersonalityTrait.casual:
        return Icons.home;
      case PersonalityTrait.flirty:
        return Icons.face;
      case PersonalityTrait.supportive:
        return Icons.support_agent;
      case PersonalityTrait.teasing:
        return Icons.sentiment_very_satisfied;
      case PersonalityTrait.encouraging:
        return Icons.thumb_up;
      case PersonalityTrait.music:
        return Icons.music_note;
      case PersonalityTrait.art:
        return Icons.palette;
      case PersonalityTrait.technology:
        return Icons.computer;
      case PersonalityTrait.nature:
        return Icons.eco;
      case PersonalityTrait.sports:
        return Icons.sports;
      case PersonalityTrait.reading:
        return Icons.menu_book;
      case PersonalityTrait.gaming:
        return Icons.videogame_asset;
      case PersonalityTrait.cooking:
        return Icons.restaurant;
      case PersonalityTrait.travel:
        return Icons.flight;
      case PersonalityTrait.fashion:
        return Icons.checkroom;
    }
  }
}
