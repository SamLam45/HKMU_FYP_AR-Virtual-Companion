import 'dart:async';
import 'package:flutter/material.dart';

enum CharacterAnimationState {
  idle, // 站著閒聊狀態（使用 Idle 模型）
  walking, // 行路（使用 Walking 模型）
  sitting, // 坐著狀態（使用 Sitting Idle 模型）
  talking, // 普通說話
  happy, // 開心（AI 回應時偵測到用戶開心）
  comforting, // 安慰（AI 回應時偵測到用戶唔開心）
  sad, // 難過
  thinking, // 思考
  waving, // 揮手
}

enum CharacterGender {
  male, // 男性
  female, // 女性
}

enum SceneLocation {
  home, // 在家
  outside, // 出街
}

class ModelPathMetadata {
  final String idleModel; // Idle 模型路徑
  final String sittingModel; // Sitting Idle 模型路徑
  final String? talkingModel; // 說話模型路徑（可選）

  ModelPathMetadata({
    required this.idleModel,
    required this.sittingModel,
    this.talkingModel,
  });
}

class AnimationMetadata {
  final String name; // 動畫名稱 (用於ModelViewer)
  final double duration; // 動畫時長 (秒)
  final bool isLooping; // 是否循環播放
  final bool canInterrupt; // 是否可被打斷
  final CharacterAnimationState state; // 對應狀態

  AnimationMetadata({
    required this.name,
    required this.duration,
    required this.isLooping,
    required this.canInterrupt,
    required this.state,
  });
}

class CharacterAnimationManager {
  // 狀態
  CharacterAnimationState _currentState = CharacterAnimationState.idle;
  CharacterGender _currentGender = CharacterGender.female;
  SceneLocation _currentScene = SceneLocation.home;

  final StreamController<CharacterAnimationState> _animationStateController =
      StreamController<CharacterAnimationState>.broadcast();
  final StreamController<String> _modelPathController =
      StreamController<String>.broadcast();

  Stream<CharacterAnimationState> get animationStateStream =>
      _animationStateController.stream;
  Stream<String> get modelPathStream => _modelPathController.stream;

  CharacterAnimationState get currentState => _currentState;
  CharacterGender get currentGender => _currentGender;
  SceneLocation get currentScene => _currentScene;

  // 模型路徑配置 - 根據性別和場景
  late final Map<
    CharacterGender,
    Map<SceneLocation, Map<CharacterAnimationState, ModelPathMetadata>>
  >
  _modelPathLibrary;

  CharacterAnimationManager() {
    _initializeModelPaths();
  }

  /// 初始化模型路徑配置
  void _initializeModelPaths() {
    // 🆕 移除所有本地 assets/models 硬編碼路徑，全部改為空字符串
    // 系統現在完全依賴於 ARCharacterStateManager 從 Supabase 動態設置模型路徑
    _modelPathLibrary = {
      CharacterGender.female: {
        SceneLocation.home: {},
        SceneLocation.outside: {},
      },
      CharacterGender.male: {SceneLocation.home: {}, SceneLocation.outside: {}},
    };
  }

  /// 初始化角色性別
  void setCharacterGender(CharacterGender gender) {
    _currentGender = gender;
  }

  /// 設置場景
  void setScene(SceneLocation scene) {
    _currentScene = scene;
    debugPrint('[Animation] 場景切換為: ${scene.toString().split('.').last}');
  }

  /// 切換動畫狀態（實際上是切換模型）
  Future<void> changeAnimationState(
    CharacterAnimationState newState, {
    bool forceChange = false,
  }) async {
    // 檢查是否可以切換
    if (!forceChange && !_canChangeState(newState)) {
      debugPrint('無法切換到 $newState - 當前狀態無法被打斷');
      return;
    }

    // 如果已經是該狀態，不切換
    if (_currentState == newState && !forceChange) {
      return;
    }

    _currentState = newState;
    _animationStateController.add(newState);
    // 不再這裡呼叫 _updateModelPath()，改由 ARCharacterStateManager 監聽 _animationStateController 來處理
    debugPrint('[Animation] 切換到: $newState');
  }

  /// 獲取當前模型路徑
  /// 注意：此方法現在已廢棄，模型路徑由 ARCharacterStateManager 管理
  String getCurrentModelPath() {
    return '';
  }

  /// 獲取特定狀態的模型元數據
  ModelPathMetadata? _getModelMetadata(CharacterAnimationState state) {
    return _modelPathLibrary[_currentGender]?[_currentScene]?[state];
  }

  /// 當檢測到坐著物體時
  Future<void> onSeatingObjectDetected() async {
    await changeAnimationState(CharacterAnimationState.sitting);
  }

  /// 當失去坐著物體檢測時
  Future<void> onSeatingObjectLost() async {
    await changeAnimationState(CharacterAnimationState.idle);
  }

  /// 開始說話動畫（可帶情感）
  Future<void> startTalking({CharacterAnimationState? emotion}) async {
    final target = emotion ?? CharacterAnimationState.talking;
    await changeAnimationState(target, forceChange: true);
  }

  /// 停止說話動畫（從 talking / happy / comforting 回 idle）
  Future<void> stopTalking() async {
    if (_currentState == CharacterAnimationState.talking ||
        _currentState == CharacterAnimationState.happy ||
        _currentState == CharacterAnimationState.comforting) {
      await changeAnimationState(CharacterAnimationState.idle);
    }
  }

  /// 播放表情動畫
  Future<void> playEmotionAnimation(CharacterAnimationState emotion) async {
    if (emotion == CharacterAnimationState.happy ||
        emotion == CharacterAnimationState.sad ||
        emotion == CharacterAnimationState.thinking) {
      await changeAnimationState(emotion, forceChange: true);

      // 延遲後回到 idle
      await Future.delayed(const Duration(seconds: 2));
      await changeAnimationState(CharacterAnimationState.idle);
    }
  }

  /// 播放揮手動作
  Future<void> playWave() async {
    await changeAnimationState(
      CharacterAnimationState.waving,
      forceChange: true,
    );

    await Future.delayed(const Duration(seconds: 1));
    await changeAnimationState(CharacterAnimationState.idle);
  }

  /// 清理資源
  void dispose() {
    _animationStateController.close();
    _modelPathController.close();
  }

  // === 私有方法 ===

  /// 檢查是否可以切換到新狀態
  bool _canChangeState(CharacterAnimationState newState) {
    if (_currentState == newState) return false;
    return true; // 簡化邏輯，所有狀態都可切換
  }
}
