import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../providers/onboarding_provider.dart';
import '../../services/cache_service.dart';

class Step3Avatar extends ConsumerStatefulWidget {
  const Step3Avatar({super.key});

  @override
  ConsumerState<Step3Avatar> createState() => _Step3AvatarState();
}

class _Step3AvatarState extends ConsumerState<Step3Avatar> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // 快取解析結果，避免重複計算
  final Map<String, Future<String>> _previewSrcFutureCache = {};

  /// Carousel index persisted in [OnboardingState.avatarCarouselIndex]; prefer matching [avatarModelUrl] when possible.
  int _resolvedModelIndex(OnboardingState state, List<String> urls) {
    if (urls.isEmpty) return 0;
    final u = state.avatarModelUrl;
    if (u != null && u.isNotEmpty) {
      final at = urls.indexOf(u);
      if (at >= 0) return at;
    }
    return state.avatarCarouselIndex.clamp(0, urls.length - 1);
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
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    
    // Determine folder prefix based on gender
    // 使用新的模型路徑前綴 female1 及 male1，provider 會自動抓取 Home 和 Outside
    final genderPrefix = '${state.gender.toLowerCase()}1';
    final assetsAsync = ref.watch(avatarAssetsProvider(genderPrefix));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildHeader(context),
            const SizedBox(height: 24),
            _buildGenderToggle(context, state, notifier),
            const SizedBox(height: 24),
            Expanded(
              child: assetsAsync.when(
                data: (rawUrls) {
                  // Filter to only include 'idle.glb'
                  final urls = rawUrls.where((u) => u.endsWith('idle.glb')).toList();

                  if (urls.isEmpty) {
                    return _buildNoModelsFound(context);
                  }

                  final modelIndex = _resolvedModelIndex(state, urls);
                  if (modelIndex != state.avatarCarouselIndex) {
                    Future.microtask(() => notifier.setAvatarCarouselIndex(modelIndex));
                  }

                  if (state.avatarModelUrl == null || state.avatarModelUrl!.isEmpty) {
                    Future.microtask(() {
                      notifier.setAvatarCarouselIndex(0);
                      notifier.setAvatarModelUrl(urls[0]);
                    });
                  }

                  final currentUrl = urls[modelIndex];

                  return Column(
                    children: [
                      Expanded(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: FutureBuilder<String>(
                                  future: _resolveModelPreviewSrc(currentUrl),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const Center(child: CircularProgressIndicator());
                                    }
                                    return ModelViewer(
                                      key: ValueKey(snapshot.data!), // Force rebuild on URL change
                                      src: snapshot.data!,
                                      autoRotate: true,
                                      cameraControls: true,
                                      backgroundColor: Colors.transparent,
                                      ar: true,
                                      loading: Loading.eager,
                                    );
                                  },
                                ),
                              ),
                            ),
                            // Navigation Arrows
                            if (urls.length > 1) ...[
                              Positioned(
                                left: 0,
                                child: IconButton(
                                  icon: Icon(Icons.arrow_back_ios, color: Theme.of(context).primaryColor),
                                  onPressed: () {
                                    final i = _resolvedModelIndex(state, urls);
                                    final ni = (i - 1 + urls.length) % urls.length;
                                    notifier.setAvatarCarouselIndex(ni);
                                    notifier.setAvatarModelUrl(urls[ni]);
                                  },
                                ),
                              ),
                              Positioned(
                                right: 0,
                                child: IconButton(
                                  icon: Icon(Icons.arrow_forward_ios, color: Theme.of(context).primaryColor),
                                  onPressed: () {
                                    final i = _resolvedModelIndex(state, urls);
                                    final ni = (i + 1) % urls.length;
                                    notifier.setAvatarCarouselIndex(ni);
                                    notifier.setAvatarModelUrl(urls[ni]);
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Outfit ${modelIndex + 1} of ${urls.length}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Drag to rotate • Pinch to zoom',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Text(
                    'Error loading models: $err\nMake sure "ar_assets" bucket exists and has files.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Text(
          'Choose Avatar',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold, 
            color: Theme.of(context).colorScheme.onSurface
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select your companion\'s appearance.',
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildGenderToggle(BuildContext context, OnboardingState state, OnboardingNotifier notifier) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          _buildGenderOption(context, 'Female', state.gender == 'female', () {
            notifier.setGender('female');
          }),
          _buildGenderOption(context, 'Male', state.gender == 'male', () {
            notifier.setGender('male');
          }),
        ],
      ),
    );
  }

  Widget _buildGenderOption(BuildContext context, String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoModelsFound(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sentiment_dissatisfied, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'No models found.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Please upload .glb files to Supabase Storage\nin "ar_assets" bucket under "Home" and "Outside" folders.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
