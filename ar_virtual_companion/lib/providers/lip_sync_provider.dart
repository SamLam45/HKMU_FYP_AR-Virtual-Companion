import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/lip_sync_service.dart';

class LipSyncState {
  final bool isActive;
  final VisemeType currentViseme;
  final double currentIntensity;
  final bool isTalking;
  final String currentText;

  LipSyncState({
    this.isActive = false,
    this.currentViseme = VisemeType.silence,
    this.currentIntensity = 0.0,
    this.isTalking = false,
    this.currentText = '',
  });

  LipSyncState copyWith({
    bool? isActive,
    VisemeType? currentViseme,
    double? currentIntensity,
    bool? isTalking,
    String? currentText,
  }) {
    return LipSyncState(
      isActive: isActive ?? this.isActive,
      currentViseme: currentViseme ?? this.currentViseme,
      currentIntensity: currentIntensity ?? this.currentIntensity,
      isTalking: isTalking ?? this.isTalking,
      currentText: currentText ?? this.currentText,
    );
  }
}

class LipSyncNotifier extends StateNotifier<LipSyncState> {
  final LipSyncService _lipSyncService = LipSyncService();

  LipSyncNotifier() : super(LipSyncState()) {
    _initializeLipSync();
  }

  void _initializeLipSync() {
    _lipSyncService.visemeStream.listen((visemes) {
      if (visemes.isNotEmpty) {
        final viseme = visemes.first;
        state = state.copyWith(
          currentViseme: viseme.type,
          currentIntensity: viseme.intensity,
          isTalking: viseme.type != VisemeType.silence,
        );
      }
    });
  }

  /// 開始口型同步
  Future<void> startLipSync(String text) async {
    if (text.isEmpty) return;
    
    state = state.copyWith(
      isActive: true,
      isTalking: true,
      currentText: text,
    );
    
    await _lipSyncService.generateLipSyncFromText(text);
  }

  /// 從音頻文件開始口型同步
  Future<void> startLipSyncFromAudio(String audioPath) async {
    state = state.copyWith(
      isActive: true,
      isTalking: true,
    );
    
    await _lipSyncService.generateLipSyncFromAudio(audioPath);
  }

  /// 停止口型同步
  void stopLipSync() {
    _lipSyncService.stopLipSync();
    state = state.copyWith(
      isActive: false,
      isTalking: false,
      currentViseme: VisemeType.silence,
      currentIntensity: 0.0,
      currentText: '',
    );
  }

  /// 更新當前口型
  void updateViseme(VisemeType viseme, double intensity) {
    state = state.copyWith(
      currentViseme: viseme,
      currentIntensity: intensity,
      isTalking: viseme != VisemeType.silence,
    );
  }

  /// 獲取口型動畫參數
  Map<String, double> getVisemeAnimationParams() {
    switch (state.currentViseme) {
      case VisemeType.silence:
        return {
          'mouthOpen': 0.0,
          'mouthWidth': 0.0,
          'jawOpen': 0.0,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.a:
        return {
          'mouthOpen': 0.8 * state.currentIntensity,
          'mouthWidth': 0.3 * state.currentIntensity,
          'jawOpen': 0.7 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.e:
        return {
          'mouthOpen': 0.4 * state.currentIntensity,
          'mouthWidth': 0.6 * state.currentIntensity,
          'jawOpen': 0.3 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.i:
        return {
          'mouthOpen': 0.2 * state.currentIntensity,
          'mouthWidth': 0.8 * state.currentIntensity,
          'jawOpen': 0.1 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.o:
        return {
          'mouthOpen': 0.6 * state.currentIntensity,
          'mouthWidth': 0.2 * state.currentIntensity,
          'jawOpen': 0.5 * state.currentIntensity,
          'lipPucker': 0.7 * state.currentIntensity,
          'lipFunnel': 0.0,
        };
      case VisemeType.u:
        return {
          'mouthOpen': 0.3 * state.currentIntensity,
          'mouthWidth': 0.1 * state.currentIntensity,
          'jawOpen': 0.2 * state.currentIntensity,
          'lipPucker': 0.9 * state.currentIntensity,
          'lipFunnel': 0.0,
        };
      case VisemeType.f:
      case VisemeType.v:
        return {
          'mouthOpen': 0.1 * state.currentIntensity,
          'mouthWidth': 0.0,
          'jawOpen': 0.0,
          'lipPucker': 0.0,
          'lipFunnel': 0.8 * state.currentIntensity,
        };
      case VisemeType.th:
        return {
          'mouthOpen': 0.2 * state.currentIntensity,
          'mouthWidth': 0.0,
          'jawOpen': 0.1 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.6 * state.currentIntensity,
        };
      case VisemeType.m:
      case VisemeType.p:
      case VisemeType.b:
        return {
          'mouthOpen': 0.0,
          'mouthWidth': 0.0,
          'jawOpen': 0.0,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.t:
      case VisemeType.d:
      case VisemeType.k:
      case VisemeType.g:
        return {
          'mouthOpen': 0.3 * state.currentIntensity,
          'mouthWidth': 0.2 * state.currentIntensity,
          'jawOpen': 0.2 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.s:
      case VisemeType.z:
      case VisemeType.sh:
      case VisemeType.zh:
        return {
          'mouthOpen': 0.2 * state.currentIntensity,
          'mouthWidth': 0.4 * state.currentIntensity,
          'jawOpen': 0.1 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.3 * state.currentIntensity,
        };
      case VisemeType.l:
        return {
          'mouthOpen': 0.3 * state.currentIntensity,
          'mouthWidth': 0.5 * state.currentIntensity,
          'jawOpen': 0.2 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.r:
        return {
          'mouthOpen': 0.4 * state.currentIntensity,
          'mouthWidth': 0.3 * state.currentIntensity,
          'jawOpen': 0.3 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.w:
        return {
          'mouthOpen': 0.2 * state.currentIntensity,
          'mouthWidth': 0.1 * state.currentIntensity,
          'jawOpen': 0.1 * state.currentIntensity,
          'lipPucker': 0.8 * state.currentIntensity,
          'lipFunnel': 0.0,
        };
      case VisemeType.y:
        return {
          'mouthOpen': 0.3 * state.currentIntensity,
          'mouthWidth': 0.6 * state.currentIntensity,
          'jawOpen': 0.2 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.h:
        return {
          'mouthOpen': 0.5 * state.currentIntensity,
          'mouthWidth': 0.3 * state.currentIntensity,
          'jawOpen': 0.4 * state.currentIntensity,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.ng:
        return {
          'mouthOpen': 0.1 * state.currentIntensity,
          'mouthWidth': 0.0,
          'jawOpen': 0.0,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.ee:
        return {
          'mouthOpen': 0.1 * state.currentIntensity,
          'mouthWidth': 1.0 * state.currentIntensity,
          'jawOpen': 0.0,
          'lipPucker': 0.0,
          'lipFunnel': 0.0,
        };
      case VisemeType.oo:
        return {
          'mouthOpen': 0.4 * state.currentIntensity,
          'mouthWidth': 0.0,
          'jawOpen': 0.3 * state.currentIntensity,
          'lipPucker': 1.0 * state.currentIntensity,
          'lipFunnel': 0.0,
        };
    }
  }

  @override
  void dispose() {
    _lipSyncService.dispose();
    super.dispose();
  }
}

final lipSyncProvider = StateNotifierProvider<LipSyncNotifier, LipSyncState>((ref) {
  return LipSyncNotifier();
});
