import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/personality_model.dart';
import '../services/supabase_service.dart';

/// Maps API / DB labels to [PersonalityTrait]. Returns null if unknown (avoid defaulting to friendly).
PersonalityTrait? _mapPersonalityTraitLabel(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return null;
  for (final e in PersonalityTrait.values) {
    if (e.name.toLowerCase() == t || e.displayName.toLowerCase() == t) {
      return e;
    }
  }
  const synonyms = <String, PersonalityTrait>{
    'traveling': PersonalityTrait.travel,
    'travel': PersonalityTrait.travel,
    'extroverted': PersonalityTrait.energetic,
    'introverted': PersonalityTrait.shy,
    'thoughtful': PersonalityTrait.serious,
    'ambivert': PersonalityTrait.playful,
    'listener': PersonalityTrait.supportive,
    'a listener': PersonalityTrait.supportive,
    'mental support': PersonalityTrait.supportive,
    'just casual chat': PersonalityTrait.casual,
    'entertainment': PersonalityTrait.playful,
  };
  return synonyms[t];
}

String _avatarLogTail(String path) {
  if (path.isEmpty) return '(empty)';
  try {
    final u = Uri.parse(path);
    if (u.pathSegments.isNotEmpty) {
      return '…/${u.pathSegments.last}';
    }
  } catch (_) {}
  return path.length > 60 ? '${path.substring(0, 57)}...' : path;
}

/// Merge base when Supabase has no `detailed_personality` (e.g. onboarding Step 2 skipped).
/// Avoids [PersonalityTemplates.templates[0]] (Luna → Calm + Mysterious) leaking into the UI.
PersonalityProfile _neutralPersonalityMergeBase() {
  return PersonalityProfile(
    characterName: 'Companion',
    traits: const [PersonalityTrait.friendly, PersonalityTrait.supportive],
    appearance: CharacterAppearance.casual,
    bio: '',
    greeting: 'Hello!',
    personalityDescription: 'You is AI companion',
    traitIntensities: const {},
    interests: const [],
    communicationStyle: 'supportive',
    primaryColor: const Color(0xFF6B73FF),
    secondaryColor: const Color(0xFF9B59B6),
    avatarPath: '',
    gender: 'female',
  );
}

// Provider to expose the raw Supabase user profile map, cached within the notifier.
final userProfileProvider = Provider<AsyncValue<Map<String, dynamic>?>>((ref) {
  final personalityState = ref.watch(personalityProvider);
  return personalityState.when(
    data: (profile) => AsyncData(ref.read(personalityProvider.notifier).getCachedUserProfile()),
    loading: () => const AsyncLoading(),
    error: (err, stack) => AsyncError(err, stack),
  );
});

class PersonalityNotifier extends StateNotifier<AsyncValue<PersonalityProfile>> {
  Map<String, dynamic>? _cachedUserProfile;

  PersonalityNotifier() : super(const AsyncLoading()) {
    _loadPersonality();
  }

  Map<String, dynamic>? getCachedUserProfile() => _cachedUserProfile;

  Future<void> _loadPersonality() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final personalityJson = prefs.getString('personality_profile');
      
      if (personalityJson != null) {
        final personalityData = jsonDecode(personalityJson);
        state = AsyncData(PersonalityProfile.fromJson(personalityData));
      } else {
        // If no local data, fetch from Supabase
        await loadFromSupabase();
      }
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      print('Error loading personality: $e');
    }
  }

  Future<void> loadFromSupabase() async {
    try {
      state = const AsyncLoading();
      final profile = await SupabaseService.fetchUserProfile();
      _cachedUserProfile = profile; // Cache the raw profile

      if (profile != null) {
        final detailed = profile['detailed_personality'] as Map<String, dynamic>?;
        final PersonalityProfile currentPersonality = state.valueOrNull ??
            (detailed == null
                ? _neutralPersonalityMergeBase()
                : PersonalityTemplates.createFromTemplate(PersonalityTemplates.templates[0]));

        List<PersonalityTrait> mappedTraits = [];
        if (detailed != null) {
          if (detailed['traits'] != null) {
            final traitsList = (detailed['traits'] as List<dynamic>).map((e) => e.toString()).toList();
            for (final t in traitsList) {
              final m = _mapPersonalityTraitLabel(t);
              if (m != null) mappedTraits.add(m);
            }
          }

          if (detailed['interests'] != null) {
            final interestsList = (detailed['interests'] as List<dynamic>).map((e) => e.toString()).toList();
            for (final t in interestsList) {
              final m = _mapPersonalityTraitLabel(t);
              if (m != null) mappedTraits.add(m);
            }
          }
          mappedTraits = mappedTraits.toSet().toList();
        }

        final finalTraits = mappedTraits.isNotEmpty
            ? mappedTraits
            : const <PersonalityTrait>[
                PersonalityTrait.friendly,
                PersonalityTrait.supportive,
              ];

        CharacterAppearance? appearance;
        if (detailed?['appearance'] != null) {
          final appearanceStr = detailed!['appearance'].toString();
          appearance = CharacterAppearance.values.firstWhere(
            (e) => e.toString().split('.').last == appearanceStr,
            orElse: () => CharacterAppearance.casual,
          );
        }

        Color? primaryColor;
        Color? secondaryColor;
        if (detailed?['colors'] != null) {
          final colors = detailed!['colors'];
          if (colors['primary'] != null) primaryColor = Color(colors['primary']);
          if (colors['secondary'] != null) secondaryColor = Color(colors['secondary']);
        }

        Map<String, double>? traitIntensities;
        if (detailed?['trait_intensities'] != null) {
          final rawIntensities = detailed!['trait_intensities'] as Map<String, dynamic>;
          traitIntensities = rawIntensities.map((k, v) => MapEntry(k, (v as num).toDouble()));
        }

        List<String>? interests;
        if (detailed?['interests'] != null) {
          interests = List<String>.from(detailed!['interests']);
        }

        final commRaw = detailed?['communication_style']?.toString();
        final communicationStyle = commRaw != null && commRaw.isNotEmpty
            ? commRaw.toLowerCase().trim()
            : currentPersonality.communicationStyle;

        final newProfile = currentPersonality.copyWith(
          characterName: profile['ai_nickname'] ?? currentPersonality.characterName,
          avatarPath: profile['avatar_url'] ?? currentPersonality.avatarPath,
          traits: finalTraits,
          personalityDescription: detailed?['summary'] ?? currentPersonality.personalityDescription,
          communicationStyle: communicationStyle,
          gender: profile['gender'] ?? currentPersonality.gender,
          birthday: profile['birthday'] != null ? DateTime.tryParse(profile['birthday']) : currentPersonality.birthday,
          bio: detailed?['bio'] ?? currentPersonality.bio,
          greeting: detailed?['greeting'] ?? currentPersonality.greeting,
          appearance: appearance ?? currentPersonality.appearance,
          primaryColor: primaryColor ?? currentPersonality.primaryColor,
          secondaryColor: secondaryColor ?? currentPersonality.secondaryColor,
          traitIntensities: traitIntensities ?? currentPersonality.traitIntensities,
          interests: interests ?? currentPersonality.interests,
        );
        
        state = AsyncData(newProfile);
        await _savePersonality(newProfile);
      } else {
        // If profile is null, load default
        final defaultProfile = PersonalityTemplates.createFromTemplate(PersonalityTemplates.templates[0]);
        state = AsyncData(defaultProfile);
        await _savePersonality(defaultProfile);
      }
    } catch (e, stack) {
      state = AsyncError(e, stack);
      print('Error loading from Supabase: $e');
    }
  }

  /// 只刷新 Supabase profile 快取（例如 preferences／selected_persona_id），唔經過 AsyncLoading，避免成個 UI 閃爍。
  Future<void> refreshUserProfileCache() async {
    try {
      final profile = await SupabaseService.fetchUserProfile();
      _cachedUserProfile = profile;
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData(current);
      }
    } catch (e) {
      debugPrint('refreshUserProfileCache failed: $e');
    }
  }

  Future<void> saveToSupabase() async {
    final currentState = state.valueOrNull;
    if (currentState == null) {
      debugPrint('[PersonalityNotifier] saveToSupabase 略過：state 為 null');
      return;
    }

    try {
      String communicationStyle = currentState.communicationStyle;
      final styleTraits = [PersonalityTrait.formal, PersonalityTrait.flirty, PersonalityTrait.casual, PersonalityTrait.supportive, PersonalityTrait.teasing, PersonalityTrait.encouraging];
      final foundStyles = currentState.traits.where((t) => styleTraits.contains(t)).toList();
      if (foundStyles.isNotEmpty) {
        communicationStyle = foundStyles.first.name;
      }

      final interestTraits = [PersonalityTrait.music, PersonalityTrait.art, PersonalityTrait.technology, PersonalityTrait.nature, PersonalityTrait.sports, PersonalityTrait.reading, PersonalityTrait.gaming, PersonalityTrait.cooking, PersonalityTrait.travel, PersonalityTrait.fashion];
      final interestStrings = currentState.traits.where((t) => interestTraits.contains(t)).map((t) => t.displayName).toList();

      final updatedProfile = currentState.copyWith(
        communicationStyle: communicationStyle,
        interests: interestStrings,
      );

      final detailedPersonality = {
        'traits': updatedProfile.traits.map((e) => e.displayName).toList(),
        'summary': updatedProfile.personalityDescription,
        'communication_style': communicationStyle,
        'bio': updatedProfile.bio,
        'greeting': updatedProfile.greeting,
        'appearance': updatedProfile.appearance.toString().split('.').last,
        'trait_intensities': updatedProfile.traitIntensities,
        'interests': interestStrings,
        'colors': {
          'primary': updatedProfile.primaryColor.value,
          'secondary': updatedProfile.secondaryColor.value,
        },
      };

      debugPrint(
        '[PersonalityNotifier] saveToSupabase → Supabase: gender=${updatedProfile.gender} '
        'avatar_url 尾段=${_avatarLogTail(updatedProfile.avatarPath)}',
      );
      await SupabaseService.updatePersonalityProfile(
        aiNickname: updatedProfile.characterName,
        gender: updatedProfile.gender,
        birthday: updatedProfile.birthday,
        avatarModelUrl: updatedProfile.avatarPath,
        detailedPersonality: detailedPersonality,
      );
      debugPrint('[PersonalityNotifier] saveToSupabase：updatePersonalityProfile 已回傳');

      state = AsyncData(updatedProfile);
      await _savePersonality(updatedProfile);
    } catch (e) {
      print('Error saving to Supabase: $e');
      throw e;
    }
  }

  Future<void> _savePersonality(PersonalityProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('personality_profile', jsonEncode(profile.toJson()));
    } catch (e) {
      print('Error saving personality: $e');
    }
  }

  void updateCharacterName(String name) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(characterName: name);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateBio(String bio) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(bio: bio);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateGreeting(String greeting) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(greeting: greeting);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updatePersonalityDescription(String description) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(personalityDescription: description);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void addTrait(PersonalityTrait trait) {
    if (state.valueOrNull == null || state.value!.traits.contains(trait)) return;
    final newTraits = List<PersonalityTrait>.from(state.value!.traits)..add(trait);
    final newProfile = state.value!.copyWith(traits: newTraits);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void removeTrait(PersonalityTrait trait) {
    if (state.valueOrNull == null) return;
    final newTraits = List<PersonalityTrait>.from(state.value!.traits)..remove(trait);
    final newProfile = state.value!.copyWith(traits: newTraits);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateTraitIntensity(PersonalityTrait trait, double intensity) {
    if (state.valueOrNull == null) return;
    final newIntensities = Map<String, double>.from(state.value!.traitIntensities);
    newIntensities[trait.name] = intensity;
    final newProfile = state.value!.copyWith(traitIntensities: newIntensities);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateAppearance(CharacterAppearance appearance) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(appearance: appearance);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateColors(Color primaryColor, Color secondaryColor) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    );
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateInterests(List<String> interests) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(interests: interests);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateCommunicationStyle(String style) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(communicationStyle: style);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateGender(String gender) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(gender: gender);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateBirthday(DateTime birthday) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(birthday: birthday);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void updateAvatarPath(String avatarPath) {
    if (state.valueOrNull == null) return;
    final newProfile = state.value!.copyWith(avatarPath: avatarPath);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void loadTemplate(PersonalityTemplate template) {
    print('Loading template: ${template.name}');
    final newProfile = PersonalityTemplates.createFromTemplate(template);
    state = AsyncData(newProfile);
    print('New state character name: ${newProfile.characterName}');
    _savePersonality(newProfile);
    print('Template loaded and saved');
  }

  void resetToDefault() {
    final newProfile = PersonalityTemplates.createFromTemplate(PersonalityTemplates.templates[0]);
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  void createCustomPersonality({
    required String characterName,
    required List<PersonalityTrait> traits,
    required CharacterAppearance appearance,
    required String bio,
    required String greeting,
    required String personalityDescription,
    required Color primaryColor,
    required Color secondaryColor,
    required String avatarPath,
    String gender = 'female',
    DateTime? birthday,
  }) {
    final newProfile = PersonalityProfile(
      characterName: characterName,
      traits: traits,
      appearance: appearance,
      bio: bio,
      greeting: greeting,
      personalityDescription: personalityDescription,
      traitIntensities: _generateTraitIntensities(traits),
      interests: _generateInterests(traits),
      communicationStyle: _determineCommunicationStyle(traits),
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      avatarPath: avatarPath,
      isCustom: true,
      gender: gender,
      birthday: birthday,
    );
    state = AsyncData(newProfile);
    _savePersonality(newProfile);
  }

  Map<String, double> _generateTraitIntensities(List<PersonalityTrait> traits) {
    final intensities = <String, double>{};
    for (final trait in traits) {
      intensities[trait.name] = 0.8; // Default intensity
    }
    return intensities;
  }

  List<String> _generateInterests(List<PersonalityTrait> traits) {
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

  String _determineCommunicationStyle(List<PersonalityTrait> traits) {
    if (traits.contains(PersonalityTrait.formal)) return 'formal';
    if (traits.contains(PersonalityTrait.flirty)) return 'flirty';
    if (traits.contains(PersonalityTrait.casual)) return 'casual';
    return 'casual';
  }
}

final personalityProvider = StateNotifierProvider<PersonalityNotifier, AsyncValue<PersonalityProfile>>((ref) {
  return PersonalityNotifier();
});

// Additional providers for specific aspects
final characterNameProvider = Provider<String>((ref) {
  return ref.watch(personalityProvider).when(
    data: (p) => p.characterName,
    loading: () => '...',
    error: (e, s) => 'Error',
  );
});

final personalityTraitsProvider = Provider<List<PersonalityTrait>>((ref) {
  return ref.watch(personalityProvider).when(
    data: (p) => p.traits,
    loading: () => [],
    error: (e, s) => [],
  );
});

final characterAppearanceProvider = Provider<CharacterAppearance>((ref) {
  return ref.watch(personalityProvider).when(
    data: (p) => p.appearance,
    loading: () => CharacterAppearance.casual,
    error: (e, s) => CharacterAppearance.casual,
  );
});

final personalityColorsProvider = Provider<Map<String, Color>>((ref) {
  final personality = ref.watch(personalityProvider).valueOrNull;
  return {
    'primary': personality?.primaryColor ?? Colors.grey,
    'secondary': personality?.secondaryColor ?? Colors.blueGrey,
  };
});

final personalityInterestsProvider = Provider<List<String>>((ref) {
  return ref.watch(personalityProvider).valueOrNull?.interests ?? [];
});

final communicationStyleProvider = Provider<String>((ref) {
  return ref.watch(personalityProvider).valueOrNull?.communicationStyle ?? 'casual';
});
