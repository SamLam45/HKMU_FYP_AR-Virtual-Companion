import 'dart:async';
import 'package:ar_ai_girl_friend/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'object_detection_service.dart';
import 'character_animation_manager.dart';

/// AR角色狀態管理器 - 整合所有AR相關服務
///
/// 功能：
/// 1. 物體檢測 - 自動檢測椅子/沙發等坐著物體
/// 2. 模型管理 - 支持動態模型路徑（從 Supabase），並進行本地快取
/// 3. 狀態切換 - idle 和 sitting 狀態管理
/// 4. 相機控制 - 讀取相機幀進行物體檢測
///
/// 設計原則：
/// - 優先使用 Supabase 的動態 URL，並快取到本地
/// - 支持本地資源路徑（備用）
/// - 不依賴於性別/場景配置（由外部 Supabase 提供）
class ARCharacterStateManager {
  // 服務實例
  late ObjectDetectionService _objectDetectionService;
  late CharacterAnimationManager _animationManager;
  final CacheService _cacheService = CacheService();

  // 狀態
  bool _isInitialized = false;
  bool _isDetectionActive = false;
  bool _isDisposed = false;

  // 模型路徑（儲存本地快取路徑或本地 asset 路徑）
  String? _currentIdleModelPath;
  String? _currentSittingModelPath;
  String? _currentWalkingModelPath;
  String? _currentTalkingModelPath;
  String? _currentHappyModelPath;
  String? _currentComfortingModelPath;

  // 流控制器
  final StreamController<CharacterAnimationState> _animationStateController =
      StreamController<CharacterAnimationState>.broadcast();
  final StreamController<DetectedObject?> _detectedObjectController =
      StreamController<DetectedObject?>.broadcast();
  final StreamController<String> _modelPathController =
      StreamController<String>.broadcast();

  ARCharacterStateManager();

  // 取消計時器
  Timer? _detectionDebounceTimer;
  DetectedObject? _lastStableDetection;
  static const Duration _detectionStabilityDuration = Duration(
    milliseconds: 800,
  );

  // Getters
  Stream<CharacterAnimationState> get animationStateStream =>
      _animationStateController.stream;
  Stream<DetectedObject?> get detectedObjectStream =>
      _detectedObjectController.stream;
  Stream<String> get modelPathStream => _modelPathController.stream;

  bool get isInitialized => _isInitialized;
  bool get isDetectionActive => _isDetectionActive;
  CharacterAnimationState get currentAnimationState =>
      _isInitialized ? _animationManager.currentState : CharacterAnimationState.idle;
  DetectedObject? get lastDetectedObject => _lastStableDetection;

  /// 初始化所有AR服務
  Future<bool> initialize() async {
    if (_isInitialized) {
      return true;
    }
    try {
      // 初始化服務
      _objectDetectionService = ObjectDetectionService();
      _animationManager = CharacterAnimationManager();

      // 初始化物體檢測
      final detectionInitialized = await _objectDetectionService.initialize();
      if (!detectionInitialized) {
        debugPrint('[AR State] 物體檢測初始化失敗');
        return false;
      }

      // 監聽動畫狀態變化
      _animationManager.animationStateStream.listen((state) {
        _animationStateController.add(state);
        _updateModelPath(); // 當狀態改變時更新路徑
      });

      // 監聽物體檢測結果
      _objectDetectionService.detectionStream.listen((detection) {
        _handleDetectionResult(detection);
      });

      _isInitialized = true;
      debugPrint('[AR State] 初始化完成');
      return true;
    } catch (e) {
      debugPrint('[AR State] 初始化錯誤: $e');
      return false;
    }
  }

  /// 設置並快取動態模型路徑（來自 Supabase）
  ///
  /// 這個方法會接收 URL，通過 CacheService 轉換為本地路徑，然後儲存。
  Future<void> setAndCacheDynamicModelPaths({
    required String idleModelUrl,
    required String sittingModelUrl,
    String? walkingModelUrl,
    String? talkingModelUrl,
    String? happyModelUrl,
    String? comfortingModelUrl,
  }) async {
    debugPrint('[AR State] 開始快取動態模型...');

    Future<String?> _safeCachePath(String url, String label) async {
      try {
        final path = await _cacheService.validateAndGetPath(url);
        if (path == null) {
          debugPrint('[AR State] ⚠️ $label 快取失敗 (null)，URL 可能無效: $url');
        }
        return path;
      } catch (e) {
        debugPrint('[AR State] ⚠️ $label 下載異常: $e');
        return null;
      }
    }

    final futures = <Future<String?>>[];
    futures.add(_safeCachePath(idleModelUrl, 'Idle'));         // 0
    futures.add(_safeCachePath(sittingModelUrl, 'Sitting'));   // 1
    int idx = 2;
    final int? walkIdx = walkingModelUrl != null ? idx++ : null;
    final int? talkIdx = talkingModelUrl != null ? idx++ : null;
    final int? happyIdx = happyModelUrl != null ? idx++ : null;
    final int? comfortIdx = comfortingModelUrl != null ? idx++ : null;
    if (walkingModelUrl != null) futures.add(_safeCachePath(walkingModelUrl, 'Walking'));
    if (talkingModelUrl != null) futures.add(_safeCachePath(talkingModelUrl, 'Talking'));
    if (happyModelUrl != null) futures.add(_safeCachePath(happyModelUrl, 'Happy'));
    if (comfortingModelUrl != null) futures.add(_safeCachePath(comfortingModelUrl, 'Comforting'));

    final results = await Future.wait(futures);

    _currentIdleModelPath = results[0];
    _currentSittingModelPath = results[1];
    if (walkIdx != null) _currentWalkingModelPath = results[walkIdx];
    if (talkIdx != null) _currentTalkingModelPath = results[talkIdx];
    if (happyIdx != null) _currentHappyModelPath = results[happyIdx];
    if (comfortIdx != null) _currentComfortingModelPath = results[comfortIdx];

    _updateModelPath();

    debugPrint('[AR State] 動態模型本地路徑已設置');
    debugPrint('[AR State] Idle: $_currentIdleModelPath');
    debugPrint('[AR State] Sitting: $_currentSittingModelPath');
    if (_currentWalkingModelPath != null) debugPrint('[AR State] Walking: $_currentWalkingModelPath');
    if (_currentTalkingModelPath != null) debugPrint('[AR State] Talking: $_currentTalkingModelPath');
    if (_currentHappyModelPath != null) debugPrint('[AR State] Happy: $_currentHappyModelPath');
    if (_currentComfortingModelPath != null) debugPrint('[AR State] Comforting: $_currentComfortingModelPath');
  }

  /// 設置本地模型路徑（備用方案）
  void setLocalModelPath({
    required String idleModel,
    required String sittingModel,
    String? walkingModel,
    String? talkingModel,
  }) {
    _currentIdleModelPath = idleModel;
    _currentSittingModelPath = sittingModel;
    _currentWalkingModelPath = walkingModel ?? _currentWalkingModelPath;
    _currentTalkingModelPath = talkingModel ?? _currentTalkingModelPath;
    _updateModelPath();

    debugPrint('[AR State] 本地模型路徑已設置');
    debugPrint('[AR State] Idle: $idleModel');
    debugPrint('[AR State] Sitting: $sittingModel');
    if (walkingModel != null) {
      debugPrint('[AR State] Walking: $walkingModel');
    }
    if (talkingModel != null) {
      debugPrint('[AR State] Talking: $talkingModel');
    }
  }

  /// 從本地模型路徑構建坐姿模型路徑
  void setupFromLocalPath(String idlePath) {
    if (idlePath.isEmpty) return;

    String sittingPath;
    String walkingPath;
    String talkingPath;
    if (idlePath.endsWith('/Idle.glb')) {
      sittingPath = idlePath.replaceAll('/Idle.glb', '/Sitting.glb');
      walkingPath = idlePath.replaceAll('/Idle.glb', '/Walking.glb');
      talkingPath = idlePath.replaceAll('/Idle.glb', '/Talking.glb');
    } else if (idlePath.endsWith('/idle.glb')) {
      sittingPath = idlePath.replaceAll('/idle.glb', '/sitting.glb');
      walkingPath = idlePath.replaceAll('/idle.glb', '/Walking.glb');
      talkingPath = idlePath.replaceAll('/idle.glb', '/Talking.glb');
    } else {
      final lastDot = idlePath.lastIndexOf('.');
      if (lastDot != -1) {
        sittingPath = '${idlePath.substring(0, lastDot)}_sitting.glb';
        walkingPath = '${idlePath.substring(0, lastDot)}_walking.glb';
        talkingPath = '${idlePath.substring(0, lastDot)}_talking.glb';
      } else {
        sittingPath = '${idlePath}_sitting';
        walkingPath = '${idlePath}_walking';
        talkingPath = '${idlePath}_talking';
      }
    }

    setLocalModelPath(
      idleModel: idlePath,
      sittingModel: sittingPath,
      walkingModel: walkingPath,
      talkingModel: talkingPath,
    );
  }

  /// 從 Supabase avatarPath 構建模型 URL 並進行快取
  Future<void> setupFromSupabaseAvatarPath(String avatarPath) async {
    if (avatarPath.isEmpty) {
      debugPrint('[AR State] avatarPath 為空，未設置模型路徑');
      return;
    }

    // 如果是本地路徑，直接調用 setupFromLocalPath
    if (avatarPath.startsWith('assets/')) {
      setupFromLocalPath(avatarPath);
      return;
    }

    // 處理不同格式的 URL
    String idleUrl = avatarPath;
    String sittingUrl = avatarPath;
    String walkingUrl = avatarPath;
    String talkingUrl = avatarPath;
    String happyUrl = '';
    String comfortingUrl = '';

    try {
      final uri = Uri.parse(avatarPath);
      final pathSegments = uri.pathSegments.toList();

      if (pathSegments.isNotEmpty) {
        final filename = pathSegments.last.toLowerCase();

        if (filename.contains('idle.glb') ||
            filename.contains('model_home.glb')) {
          pathSegments[pathSegments.length - 1] = 'idle.glb';
          idleUrl = uri.replace(pathSegments: pathSegments).toString();

          pathSegments[pathSegments.length - 1] = 'sitting.glb';
          sittingUrl = uri.replace(pathSegments: pathSegments).toString();

          pathSegments[pathSegments.length - 1] = 'Walking.glb';
          walkingUrl = uri.replace(pathSegments: pathSegments).toString();

          pathSegments[pathSegments.length - 1] = 'Talking.glb';
          talkingUrl = uri.replace(pathSegments: pathSegments).toString();

          pathSegments[pathSegments.length - 1] = 'Happy.glb';
          happyUrl = uri.replace(pathSegments: pathSegments).toString();

          pathSegments[pathSegments.length - 1] = 'Comforting.glb';
          comfortingUrl = uri.replace(pathSegments: pathSegments).toString();
        } else {
          final lastSlash = avatarPath.lastIndexOf('/');
          if (lastSlash != -1) {
            final baseUrl = avatarPath.substring(0, lastSlash);
            sittingUrl = '$baseUrl/sitting.glb';
            walkingUrl = '$baseUrl/Walking.glb';
            talkingUrl = '$baseUrl/Talking.glb';
            happyUrl = '$baseUrl/Happy.glb';
            comfortingUrl = '$baseUrl/Comforting.glb';
          }
        }
      }
    } catch (e) {
      debugPrint('[AR State] URL 解析錯誤: $e');
    }

    // 使用新的方法來快取並設置路徑
    await setAndCacheDynamicModelPaths(
      idleModelUrl: idleUrl,
      sittingModelUrl: sittingUrl,
      walkingModelUrl: walkingUrl,
      talkingModelUrl: talkingUrl,
      happyModelUrl: happyUrl.isNotEmpty ? happyUrl : null,
      comfortingModelUrl: comfortingUrl.isNotEmpty ? comfortingUrl : null,
    );

    debugPrint('[AR State] 從 Supabase avatarPath 設置並快取模型完成');
  }

  /// 開始連續物體檢測
  void startObjectDetection(Future<CameraImage?> Function() getCameraImage) {
    if (_isDetectionActive || !_isInitialized) return;

    _isDetectionActive = true;
    debugPrint('[AR State] 開始物體檢測');

    _objectDetectionService.startContinuousDetection(() async {
      try {
        return await getCameraImage();
      } catch (e) {
        debugPrint('[AR State] 獲取相機幀失敗: $e');
        return null;
      }
    }, interval: const Duration(milliseconds: 500));
  }

  void startSnapshotDetection(Future<String?> Function() getImagePath) {
    if (_isDetectionActive || !_isInitialized) return;

    _isDetectionActive = true;
    debugPrint('[AR State] 開始物體檢測');

    _objectDetectionService.startContinuousFileDetection(() async {
      try {
        return await getImagePath();
      } catch (e) {
        debugPrint('[AR State] 獲取截圖失敗: $e');
        return null;
      }
    });
  }

  Future<void> detectOnceFromFilePath(String filePath) async {
    if (!_isInitialized) return;
    await _objectDetectionService.detectFromFilePath(filePath);
  }

  /// 停止物體檢測
  void stopObjectDetection() {
    if (!_isDetectionActive) return;

    _isDetectionActive = false;
    _objectDetectionService.stopContinuousDetection();
    debugPrint('[AR State] 停止物體檢測');
  }

  /// 開始說話動畫（可帶情感：happy / comforting，預設 talking）
  Future<void> startCharacterTalking({CharacterAnimationState? emotion}) async {
    debugPrint('🗣️ [AR State] 執行 startCharacterTalking(emotion: $emotion)');
    await _animationManager.startTalking(emotion: emotion);
  }

  /// 停止說話動畫
  Future<void> stopCharacterTalking() async {
    debugPrint('🤫 [AR State] 執行 stopCharacterTalking()');
    await _animationManager.stopTalking();
  }

  /// 播放情感動畫
  Future<void> playEmotionAnimation(String emotion) async {
    CharacterAnimationState? state;

    switch (emotion.toLowerCase()) {
      case 'happy':
      case '開心':
        state = CharacterAnimationState.happy;
        break;
      case 'sad':
      case '難過':
        state = CharacterAnimationState.sad;
        break;
      case 'thinking':
      case '思考':
        state = CharacterAnimationState.thinking;
        break;
      default:
        debugPrint('未知的表情: $emotion');
        return;
    }

    await _animationManager.playEmotionAnimation(state);
  }

  /// 播放揮手動作
  Future<void> playWaveAnimation() async {
    await _animationManager.playWave();
  }

  /// 立即切換動畫
  Future<void> forceChangeAnimation(CharacterAnimationState state) async {
    await _animationManager.changeAnimationState(state, forceChange: true);
  }

  Future<void> confirmSit() async {
    await _animationManager.onSeatingObjectDetected();
  }

  Future<void> standUp() async {
    await _animationManager.onSeatingObjectLost();
  }

  /// 手動觸發坐著物體檢測 (用於測試)
  Future<void> triggerSeatingDetected() async {
    await confirmSit();
    _lastStableDetection = DetectedObject(
      type: DetectedObjectType.chair,
      label: 'Manual Seating Trigger',
      confidence: 1.0,
      detectedAt: DateTime.now(),
    );
    _detectedObjectController.add(_lastStableDetection);
  }

  /// 手動觸發失去坐著物體檢測 (用於測試)
  Future<void> triggerSeatingLost() async {
    await standUp();
    _lastStableDetection = null;
    _detectedObjectController.add(null);
  }

  /// 獲取當前模型路徑
  ///
  /// 根據當前動畫狀態返回對應的模型路徑：
  /// - 如果在 sitting 狀態，返回 sitting model path
  /// - 如果在 talking 狀態，返回 talking model path
  /// - 否則返回 idle model path
  String? getModelPath() {
    if (!_isInitialized) {
      return _currentIdleModelPath;
    }
    final state = _animationManager.currentState;
    switch (state) {
      case CharacterAnimationState.talking:
        return _currentTalkingModelPath ?? _currentIdleModelPath;
      case CharacterAnimationState.sitting:
        return _currentSittingModelPath;
      case CharacterAnimationState.walking:
        return _currentWalkingModelPath ?? _currentIdleModelPath;
      case CharacterAnimationState.happy:
        return _currentHappyModelPath ?? _currentTalkingModelPath ?? _currentIdleModelPath;
      case CharacterAnimationState.comforting:
        return _currentComfortingModelPath ?? _currentTalkingModelPath ?? _currentIdleModelPath;
      default:
        return _currentIdleModelPath;
    }
  }

  /// 獲取當前 Idle 模型路徑
  String? getIdleModelPath() => _currentIdleModelPath;

  /// 獲取當前 Sitting 模型路徑
  String? getSittingModelPath() => _currentSittingModelPath;

  /// 獲取當前 Walking 模型路徑
  String? getWalkingModelPath() => _currentWalkingModelPath;

  /// 獲取當前 Talking 模型路徑
  String? getTalkingModelPath() => _currentTalkingModelPath;

  /// 清理資源
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    if (_isInitialized) {
      stopObjectDetection();
      _detectionDebounceTimer?.cancel();
      _objectDetectionService.dispose();
      _animationManager.dispose();
    }
    _animationStateController.close();
    _detectedObjectController.close();
    _modelPathController.close();

    debugPrint('[AR State] ARCharacterStateManager 已清理');
  }

  // === 私有方法 ===

  /// 處理物體檢測結果 (帶防抖)
  void _handleDetectionResult(DetectedObject? detection) {
    if (_isDisposed) return;
    _detectionDebounceTimer?.cancel();

    if (detection == null) {
      // 沒有檢測到物體
      _detectionDebounceTimer = Timer(_detectionStabilityDuration, () {
        if (_isDisposed) return;
        if (_lastStableDetection != null) {
          _lastStableDetection = null;
          if (!_detectedObjectController.isClosed) {
            _detectedObjectController.add(null);
          }
          debugPrint('[AR State] 失去物體檢測');
        }
      });
      return;
    }

    // 檢測到物體
    _detectionDebounceTimer = Timer(_detectionStabilityDuration, () {
      if (_isDisposed) return;
      _lastStableDetection = detection;
      if (!_detectedObjectController.isClosed) {
        _detectedObjectController.add(detection);
      }
    });
  }

  /// 更新模型路徑到流
  void _updateModelPath() {
    if (_isDisposed || _modelPathController.isClosed) return;
    final path = getModelPath();
    if (path != null) {
      _modelPathController.add(path);
      debugPrint('[AR State] 模型路徑已流式傳送: ${_maskSensitiveUrl(path)}');
    }
  }

  /// 遮罩敏感的 URL 信息（用於日誌）
  String _maskSensitiveUrl(String url) {
    if (url.startsWith('assets/')) {
      return url;
    }
    // 只顯示 URL 的最後部分（文件名）
    final parts = url.split('/');
    if (parts.length >= 3) {
      return '.../${parts[parts.length - 2]}/${parts[parts.length - 1]}';
    }
    return url;
  }
}
