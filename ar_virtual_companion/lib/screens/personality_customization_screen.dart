import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/personality_model.dart';
import '../providers/personality_provider.dart';
import '../providers/onboarding_provider.dart';
import '../services/ai_partner_service.dart';
import '../services/cache_service.dart';
import '../services/supabase_service.dart';

class PersonalityCustomizationScreen extends ConsumerStatefulWidget {
  const PersonalityCustomizationScreen({super.key});

  @override
  ConsumerState<PersonalityCustomizationScreen> createState() => _PersonalityCustomizationScreenState();
}

class _PersonalityCustomizationScreenState extends ConsumerState<PersonalityCustomizationScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _greetingController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _birthdayController = TextEditingController();
  final Map<String, Future<String>> _previewSrcFutureCache = {};
  bool _isSaving = false;
  final ARPartnerService _arPartnerService = ARPartnerService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Load fresh data from Supabase to ensure sync with Onboarding
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(personalityProvider.notifier).loadFromSupabase().then((_) {
        if (mounted) {
          _initializeControllers();
        }
      });
    });
    
    _initializeControllers();
  }

  String _logTailUrl(String? url) {
    if (url == null || url.isEmpty) return '(empty)';
    try {
      final u = Uri.parse(url);
      if (u.pathSegments.isNotEmpty) {
        return '…/${u.pathSegments.last}';
      }
    } catch (_) {}
    return url.length > 80 ? '${url.substring(0, 77)}...' : url;
  }

  /// 性別改變時將 avatar 指到該性別第一個 idle.glb（同 Onboarding 邏輯），避免 gender=male 但 avatar_url 仍係 female1。
  Future<void> _syncAvatarToGenderPrefix(String genderLower) async {
    final prefix = '${genderLower}1';
    try {
      final home = await SupabaseService.fetchAvatarAssets('$prefix/Home');
      final outside = await SupabaseService.fetchAvatarAssets('$prefix/Outside');
      final urls = [...home, ...outside].where((u) => u.endsWith('idle.glb')).toList();
      debugPrint(
        '[PersonalityCustomization] 性別改動 → 同步模型列表 prefix=$prefix idle 數量=${urls.length}',
      );
      if (!mounted) return;
      if (urls.isNotEmpty) {
        ref.read(personalityProvider.notifier).updateAvatarPath(urls.first);
        debugPrint(
          '[PersonalityCustomization] avatarPath 已設為 ${_logTailUrl(urls.first)}',
        );
      } else {
        debugPrint(
          '[PersonalityCustomization] 警告：$prefix 冇 idle.glb，avatarPath 未自動改（請手動去 Appearance 揀）',
        );
      }
    } catch (e, st) {
      debugPrint('[PersonalityCustomization] _syncAvatarToGenderPrefix 失敗: $e\n$st');
    }
  }

  void _initializeControllers() {
    final personalityAsync = ref.read(personalityProvider);
    final personality = personalityAsync.valueOrNull;
    if (personality == null) return;

    _nameController.text = personality.characterName;
    _bioController.text = personality.bio;
    _greetingController.text = personality.greeting;
    _descriptionController.text = personality.personalityDescription;
    if (personality.birthday != null) {
      _birthdayController.text = "${personality.birthday!.year}-${personality.birthday!.month.toString().padLeft(2, '0')}-${personality.birthday!.day.toString().padLeft(2, '0')}";
    }
  }

  Future<String> _resolveModelPreviewSrc(String remoteUrl) {
    return _previewSrcFutureCache.putIfAbsent(
      remoteUrl,
      () async {
        if (remoteUrl.isEmpty || !remoteUrl.startsWith('http')) {
          return remoteUrl;
        }

        final relativePath = await CacheService().validateAndGetPath(remoteUrl);
        if (relativePath == null || relativePath.isEmpty) {
          return remoteUrl;
        }

        final docDir = await getApplicationDocumentsDirectory();
        final localPath = p.join(docDir.path, relativePath);
        if (!await File(localPath).exists()) {
          return remoteUrl;
        }

        return File(localPath).uri.toString();
      },
    );
  }

  @override
  void dispose() {
    _arPartnerService.dispose();
    _tabController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _greetingController.dispose();
    _descriptionController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final personalityAsync = ref.watch(personalityProvider);

    return personalityAsync.when(
      data: (personality) => Scaffold(
        appBar: AppBar(
          title: const Text('AI Personality Settings'),
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: personality.primaryColor,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: personality.primaryColor,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.person, size: 20), text: 'Basic'),
              Tab(icon: Icon(Icons.psychology, size: 20), text: 'AI Style'),
              Tab(icon: Icon(Icons.palette, size: 20), text: 'Appearance'),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              controller: _tabController,
              children: [
                KeepAliveWrapper(child: _buildBasicTab(personality)),
                KeepAliveWrapper(child: _buildTraitsTab(personality)),
                KeepAliveWrapper(child: _buildAppearanceTab(personality)),
              ],
            ),
            if (_isSaving)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black45,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isSaving ? null : _savePersonality,
          backgroundColor: personality.primaryColor,
          icon: const Icon(Icons.save, color: Colors.white),
          label: Text(
            _isSaving ? 'Saving...' : 'Save Changes',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 4,
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

  Widget _buildSectionHeader(String title, IconData icon) {
    final personalityAsync = ref.watch(personalityProvider);
    final primaryColor = personalityAsync.valueOrNull?.primaryColor ?? Colors.blue;
    
    return Row(
      children: [
        Icon(icon, size: 20, color: primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildBasicTab(PersonalityProfile personality) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('AI Character Info', Icons.info_outline),
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'AI Name',
                  hint: 'Name your AI companion',
                  icon: Icons.person,
                ),
                const SizedBox(height: 20),
                _buildDropdownField(label: 'AI Gender', value: ['female', 'male'].contains(personality.gender.toLowerCase()) ? personality.gender.toLowerCase() : 'female', items: const ['female', 'male'], onChanged: (value) {
                  if (value != null) {
                    debugPrint('[PersonalityCustomization] Gender dropdown → $value');
                    ref.read(personalityProvider.notifier).updateGender(value);
                    unawaited(_syncAvatarToGenderPrefix(value));
                  }
                }),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _descriptionController,
                  label: 'AI Personality ',
                  hint: 'Describe how your AI should behave and talk...',
                  icon: Icons.psychology,
                  minLines: 3,
                  maxLines: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildTraitsTab(PersonalityProfile personality) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('AI Personality & Speaking Style', Icons.psychology),
          const SizedBox(height: 16),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'These settings change how the AI responds (tone, vibe, and interests). They do not describe you.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTraitCategory('AI Core Traits', PersonalityTrait.values.take(10).toList(), personality),
                const SizedBox(height: 24),
                _buildTraitCategory('How your AI speaks', 
                  PersonalityTrait.values.where((t) => [
                    PersonalityTrait.formal,
                    PersonalityTrait.casual,
                    PersonalityTrait.flirty,
                    PersonalityTrait.supportive,
                    PersonalityTrait.teasing,
                    PersonalityTrait.encouraging,
                  ].contains(t)).toList(), personality),
                const SizedBox(height: 24),
                _buildTraitCategory('AI Interests', 
                  PersonalityTrait.values.where((t) => [
                    PersonalityTrait.music,
                    PersonalityTrait.art,
                    PersonalityTrait.technology,
                    PersonalityTrait.nature,
                    PersonalityTrait.sports,
                    PersonalityTrait.reading,
                    PersonalityTrait.gaming,
                    PersonalityTrait.cooking,
                    PersonalityTrait.travel,
                    PersonalityTrait.fashion,
                  ].contains(t)).toList(), personality),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildAppearanceTab(PersonalityProfile personality) {
    // Determine folder prefix based on gender
    // 使用新的模型路徑前綴 female1 及 male1，provider 會自動抓取 Home 和 Outside
    final genderPrefix = '${personality.gender.toLowerCase()}1';
    final assetsAsync = ref.watch(avatarAssetsProvider(genderPrefix));
    
    // 使用 LayoutBuilder 讓內容自適應高度
    return LayoutBuilder(
      builder: (context, constraints) {
        return assetsAsync.when(
          data: (rawUrls) {
            // Filter to only include 'idle.glb'
            final urls = rawUrls.where((u) => u.endsWith('idle.glb')).toList();

            if (urls.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sentiment_dissatisfied, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('No models found for $genderPrefix', style: const TextStyle(fontSize: 18)),
                  ],
                ),
              );
            }

            // Find index of current avatarPath
            int currentIndex = urls.indexOf(personality.avatarPath);
            if (currentIndex == -1) {
              currentIndex = 0;
              // If current path is invalid/empty, update it to the first available model
              if (personality.avatarPath.isEmpty && urls.isNotEmpty) {
                Future.microtask(() => 
                  ref.read(personalityProvider.notifier).updateAvatarPath(urls[0])
                );
              }
            }

            final currentUrl = urls[currentIndex];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: IntrinsicHeight( 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Avatar Model', Icons.accessibility_new),
                      const SizedBox(height: 16),
                      
                      SizedBox(
                        height: constraints.maxHeight * 0.45,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: FutureBuilder<String>(
                                  future: _resolveModelPreviewSrc(currentUrl),
                                  builder: (context, snapshot) {
                                    final previewSrc = snapshot.data ?? currentUrl;
                                    return ModelViewer(
                                      key: ValueKey(previewSrc),
                                      src: previewSrc,
                                      autoRotate: true,
                                      cameraControls: true,
                                      backgroundColor: Colors.transparent,
                                      ar: false,
                                      loading: Loading.lazy,
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (urls.length > 1) ...[
                              Positioned(
                                left: 10,
                                child: IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Icon(Icons.arrow_back_ios_new, color: personality.primaryColor, size: 20),
                                  ),
                                  onPressed: () {
                                    final newIndex = (currentIndex - 1 + urls.length) % urls.length;
                                    ref.read(personalityProvider.notifier).updateAvatarPath(urls[newIndex]);
                                  },
                                ),
                              ),
                              Positioned(
                                right: 10,
                                child: IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Icon(Icons.arrow_forward_ios, color: personality.primaryColor, size: 20),
                                  ),
                                  onPressed: () {
                                    final newIndex = (currentIndex + 1) % urls.length;
                                    ref.read(personalityProvider.notifier).updateAvatarPath(urls[newIndex]);
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Model ${currentIndex + 1} of ${urls.length}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.touch_app, color: Colors.grey[400], size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Drag to rotate • Pinch to zoom',
                                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      _buildSectionHeader('Theme Colors', Icons.palette_outlined),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: _buildColorSelection(personality),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error loading models: $err')),
        );
      }
    );
  }

  Widget _buildAdvancedTab(PersonalityProfile personality) {
    // This method is no longer used but kept for reference if needed, 
    // or you can delete it. For now, I'm effectively removing it by not calling it.
    // In a real refactor, this entire method would be deleted.
    return Container();
  }


  Widget _buildSectionTitle(String title) {
    return _buildSectionHeader(title, Icons.info_outline);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int? maxLines = 1,
    int? minLines,
  }) {
    final personalityAsync = ref.watch(personalityProvider);
    final primaryColor = personalityAsync.valueOrNull?.primaryColor ?? Colors.blue;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: primaryColor, size: 20),
            filled: true,
            fillColor: Theme.of(context).primaryColor.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTraitCategory(String title, List<PersonalityTrait> traits, PersonalityProfile personality) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: traits.map((trait) => _buildTraitChip(trait, personality)).toList(),
        ),
      ],
    );
  }

  Widget _buildTraitChip(PersonalityTrait trait, PersonalityProfile personality) {
    final isSelected = personality.traits.contains(trait);
    
    return FilterChip(
      label: Text(
        trait.displayName,
        style: TextStyle(
          fontSize: 13,
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          ref.read(personalityProvider.notifier).addTrait(trait);
        } else {
          ref.read(personalityProvider.notifier).removeTrait(trait);
        }
      },
      avatar: Icon(
        trait.icon, 
        size: 16, 
        color: isSelected ? Colors.white : personality.primaryColor,
      ),
      selectedColor: personality.primaryColor,
      checkmarkColor: Colors.white,
      backgroundColor: personality.primaryColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? personality.primaryColor : Colors.transparent,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildAppearanceCategory(String title, List<CharacterAppearance> appearances, PersonalityProfile personality) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: appearances.map((appearance) => _buildAppearanceChip(appearance, personality)).toList(),
        ),
      ],
    );
  }

  Widget _buildAppearanceChip(CharacterAppearance appearance, PersonalityProfile personality) {
    final isSelected = personality.appearance == appearance;
    
    return FilterChip(
      label: Text(
        appearance.displayName,
        style: TextStyle(
          fontSize: 13,
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          ref.read(personalityProvider.notifier).updateAppearance(appearance);
        }
      },
      avatar: CircleAvatar(
        radius: 8,
        backgroundColor: appearance.color,
      ),
      selectedColor: personality.primaryColor,
      checkmarkColor: Colors.white,
      backgroundColor: personality.primaryColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? personality.primaryColor : Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildColorSelection(PersonalityProfile personality) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildColorPicker(
                'Primary Color',
                personality.primaryColor,
                (color) {
                  ref.read(personalityProvider.notifier).updateColors(
                    color,
                    personality.secondaryColor,
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildColorPicker(
                'Secondary Color',
                personality.secondaryColor,
                (color) {
                  ref.read(personalityProvider.notifier).updateColors(
                    personality.primaryColor,
                    color,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorPicker(String label, Color currentColor, Function(Color) onColorChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showColorPicker(currentColor, onColorChanged),
          child: Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: currentColor.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '#${currentColor.value.toRadixString(16).substring(2).toUpperCase()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    final personalityAsync = ref.watch(personalityProvider);
    final primaryColor = personalityAsync.valueOrNull?.primaryColor ?? Colors.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(item.substring(0, 1).toUpperCase() + item.substring(1)),
          )).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.wc, color: primaryColor, size: 20),
            filled: true,
            fillColor: Theme.of(context).primaryColor.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildInterestsSection(PersonalityProfile personality) {
    // This method is no longer used but kept for reference if needed.
    return Container();
  }

  Widget _buildTraitIntensitiesSection(PersonalityProfile personality) {
    // This method is no longer used but kept for reference if needed.
    return Container();
  }

  void _showColorPicker(Color currentColor, Function(Color) onColorChanged) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            currentColor: currentColor,
            onColorChanged: onColorChanged,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _savePersonality() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });

    try {
      final notifier = ref.read(personalityProvider.notifier);
      final pre = ref.read(personalityProvider).valueOrNull;
      debugPrint(
        '[PersonalityCustomization] Save 前 state: gender=${pre?.gender} '
        'avatar=${_logTailUrl(pre?.avatarPath)}',
      );

      // Update state first
      notifier
        ..updateCharacterName(_nameController.text)
        ..updateBio(_bioController.text)
        ..updateGreeting(_greetingController.text)
        ..updatePersonalityDescription(_descriptionController.text);

      final mid = ref.read(personalityProvider).valueOrNull;
      debugPrint(
        '[PersonalityCustomization] Save 寫入欄位後: gender=${mid?.gender} '
        'avatar=${_logTailUrl(mid?.avatarPath)}',
      );
      if (mid != null && mid.avatarPath.startsWith('http')) {
        final g = mid.gender.toLowerCase();
        final expect = '${g}1/';
        if (!mid.avatarPath.contains(expect)) {
          debugPrint(
            '[PersonalityCustomization] 警告：gender=$g 但 avatar URL 未包含「$expect」'
            '— 可能仲未打完「性別→同步模型」或非 Storage path；仍會照現狀寫入 Supabase',
          );
        }
      }

      // Save to Supabase
      await notifier.saveToSupabase().timeout(const Duration(seconds: 25));
      debugPrint('[PersonalityCustomization] saveToSupabase 完成（無 throw）');
      await Future.wait([
        notifier.refreshUserProfileCache(),
        _arPartnerService.prepareBackend(forceRefresh: true),
      ]);
      debugPrint('[PersonalityCustomization] refreshUserProfileCache + prepareBackend 完成');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Personality saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[PersonalityCustomization] Save 失敗: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving personality: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class ColorPicker extends StatefulWidget {
  final Color currentColor;
  final Function(Color) onColorChanged;

  const ColorPicker({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late Color selectedColor;

  @override
  void initState() {
    super.initState();
    selectedColor = widget.currentColor;
  }

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
      Colors.black,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) => GestureDetector(
        onTap: () {
          setState(() {
            selectedColor = color;
          });
          widget.onColorChanged(color);
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selectedColor == color
                ? Border.all(color: Colors.white, width: 3)
                : Border.all(color: Colors.grey.shade300),
            boxShadow: selectedColor == color
                ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)]
                : null,
          ),
        ),
      )).toList(),
    );
  }
}

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
