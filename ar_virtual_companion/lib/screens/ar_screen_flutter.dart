import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ar_ai_girl_friend/services/supabase_service.dart';
import 'package:ar_ai_girl_friend/services/ar_character_state_manager.dart';
import 'package:ar_ai_girl_friend/services/character_animation_manager.dart';
import 'package:ar_ai_girl_friend/services/cache_service.dart';
import 'package:ar_ai_girl_friend/services/glb_model_metrics_service.dart';
import 'package:ar_ai_girl_friend/services/object_detection_service.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/widgets/ar_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math_64.dart' as vec;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/ar_flutter_plugin_service.dart';
import '../services/ai_partner_service.dart';
import '../services/permission_service.dart';
import '../providers/personality_provider.dart';
import 'package:camera/camera.dart';
import '../widgets/joystick_widget.dart';
import 'memory_screen.dart';

/// 使用 ar_flutter_plugin_plus 的 AR 屏幕
class ARScreenFlutter extends ConsumerStatefulWidget {
  const ARScreenFlutter({super.key});

  @override
  ConsumerState<ARScreenFlutter> createState() => _ARScreenFlutterState();
}

class _ARScreenFlutterState extends ConsumerState<ARScreenFlutter>
    with WidgetsBindingObserver {
  bool isARInitialized = false;
  String? arError;
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  ARAnchorManager? _arAnchorManager;
  ARPlaneAnchor? _characterAnchor;
  ARNode? _characterNode;
  double _baseCharacterScale = 1.0;
  /// 與 [_setupARModelFromSupabase] 內性別目標身高一致；Talking/Idle 等不同 GLB 以此換算 uniform scale。
  double? _arTargetHeightMeters;
  double _heightMultiplier = 1.0;
  /// 角色目前 Y 軸累計旋轉弧度（供 rotate handle 使用）
  double _characterYawRadians = 0.0;

  // ── 搖桿移動 ──────────────────────────────────────────────────────────
  /// 角色累計移動量，儲存在 AnchorNode 的 W frame（未旋轉參考系），單位公尺。
  /// 角色相對 AnchorNode 的本地座標（公尺）。
  /// 直接操作 local frame，避免世界→本地投影的座標系統混淆。
  double _localX = 0.0;
  double _localZ = 0.0;
  /// 上一個搖桿 tick 的 targetYaw，用於計算方向切換時的旋轉 delta。
  double _prevTargetYaw = 0.0;
  JoystickDirection _joystickDir = JoystickDirection.zero;
  Timer? _joystickTimer;
  /// 「面向用戶」的穩定 yaw — 只由放置角色 / 旋轉手柄更新，
  /// 搖桿運動不會改變它，確保每次按下搖桿時 4 個方向基準一致
  double _faceUserYaw = 0.0;
  /// 按下搖桿時快照的 _faceUserYaw，整個搖桿工作期間固定不變
  double? _joystickReferenceYaw;
  /// 上一幀的搖桿方向索引（0=上 1=下 2=左 3=右 -1=無），方向不變時跳過 rotateNodeY
  int _lastJoystickDirIdx = -1;
  /// 搖桿啟動前的動畫狀態，鬆手後恢復
  CharacterAnimationState? _stateBeforeWalking;
  /// 防止 walking/idle 快速切換導致連續 model replacement（debounce）
  DateTime? _lastWalkStateChange;
  static const _walkDebounce = Duration(milliseconds: 400);
  // ── 情感偵測 ──────────────────────────────────────────────────────────
  /// 偵測到的用戶情感（用於 AI 回應時選擇對應動畫 model）
  CharacterAnimationState? _detectedEmotion;
  /// 漸進式語音轉錄的完整字串（用來避免字詞被切斷導致無法匹配）
  String _cumulativeUserTranscript = '';
  // ─────────────────────────────────────────────────────────────────────

  bool _heightMultiplierCustomized = false;
  int _planeCount = 0;
  bool _hasDetectedPlane = false;
  bool _hasPlacedCharacter = false;
  bool _coachingDismissed = false;
  bool _showPlanesVisualization = false;
  Timer? _coachingTimer;
  CameraController? _cameraController;
  final ARPartnerService _arPartnerService = ARPartnerService();
  bool _isLiveCallActive = false;
  bool _isVoiceMode = false;

  // FaceTime-like Controls State
  bool _isUserMuted = false;
  bool _isSpeakerOn = true;
  bool _isCameraOn = true;
  bool _isFrontCamera = false;
  List<CameraDescription> _availableCameras = [];

  String _userSpeechText = ''; // 用於顯示使用者說話文字
  String _aiResponseText = ''; // 用於顯示 AI 回應文字
  String _currentModelPath = ''; // 初始為空，等待從本地快取加載
  String _currentAnimation = 'idle'; // 預設動畫改為 idle
  GlobalKey _modelViewerKey = GlobalKey(); // 用於控制 ModelViewer
  Timer? _throttleTimer; // 用於節流 UI 更新
  Timer? _visionTimer; // 用於定期發送影像
  String _pendingText = ''; // 暫存待更新的文字
  double _audioLevel = 0.0;
  bool _showingTranscript = false; // 控制顯示轉錄文字或波形
  final TextEditingController _textEditingController =
      TextEditingController(); // Add controller

  // Chat History
  List<Map<String, dynamic>> _chatHistory = []; // Remove final, allow updates

  // AR 物體檢測系統
  late ARCharacterStateManager _arStateManager;
  StreamSubscription? _modelPathSubscription;
  StreamSubscription? _detectedObjectSubscription;
  CameraImage? _lastCameraImage; // 儲存最新的相機幀
  bool _isStreamingImages = false; // 追蹤是否正在串流影像
  int _moveRequestId = 0;
  bool _isMovingCharacter = false;
  bool _awaitingSeatTap = false;
  int _modelReplaceRequestId = 0;
  bool _hasInitializedCamera = false;
  bool _isSnapshotCapturing = false;
  String? _snapshotTempPath;
  DateTime? _lastSnapshotAt;
  bool _autoSeatDetectionEnabled = false;
  bool _isSeatScanRunning = false;
  List<Map<String, dynamic>> _personas = [];
  bool _isLoadingSettingsData = false;
  DateTime? _personasLastFetchedAt;
  int? _selectedPersonaId;
  int _settingsTabIndex = 0; // 0 = AI, 1 = AR
  /// 語音卡片選取狀態（避免只用 build 內區域變數，sheet 重建時被 profile 蓋過）
  String? _geminiVoiceUiOverride;
  /// 設定 sheet 嘅 StatefulBuilder，Personas 非同步載入完成後要觸發，否則列表唔會更新。
  void Function(void Function())? _settingsModalSheetSetState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arStateManager = ARCharacterStateManager();
    // Set status bar to transparent to match the design
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _requestAndInitializeAR();
    _setupARCallbacks();
    _loadChatHistory(); // Load history on startup
    unawaited(_arPartnerService.prepareRealtimeSession());
    unawaited(_loadSettingsData(fetchProfile: true));

    // 確保 AR 系統正確初始化（等待 Supabase 數據加載）
    _initializeARSystemSequence();

    _arPartnerService.setWebSocketCallbacks(
      onTextReceived: (text) {
        // Handle AI text received from backend (Clean text without emotion tags)
        if (mounted) {
          // 不在這裡啟動說話動畫，改由 onAiSpeakingStarted 控制
          setState(() {
            // Accumulate text if it's a chunk, or replace if it looks like a full update?
            // Assuming chunks from main.py
            _aiResponseText += text;
            _showingTranscript = true;

            // Update chat history in real-time
            if (_chatHistory.isNotEmpty && _chatHistory.last['role'] == 'ai') {
              _chatHistory.last['text'] = _aiResponseText;
            } else {
              _chatHistory.add({
                'role': 'ai',
                'text': _aiResponseText,
                'timestamp': DateTime.now(),
              });
            }
          });
        }
      },
      onUserTranscriptReceived: (text) {
        // 語音輸入也做情感偵測 (支援漸進式轉錄)
        if (text.isNotEmpty) {
          // 因為 user_transcript 是漸進式傳入的 (例如 " no", "t", " hap", "py")
          // 直接對單個片段做分析會導致詞彙被切斷 (not happy -> "no", "t", " hap", "py")
          // 因此需要將所有片段累積成完整句子再進行分析
          _cumulativeUserTranscript += text;
          
          final newEmotion = _detectEmotionFromText(_cumulativeUserTranscript);
          if (newEmotion != null) {
            _detectedEmotion = newEmotion;
          }
          
          // 🆕 修正 Race Condition: 如果 AI 已經開始說話（例如網絡返回語音快於文字轉錄），
          // 且偵測到情感，則立即更新角色動畫
          if (mounted && _arStateManager.isInitialized && _detectedEmotion != null) {
            final currentState = _arStateManager.currentAnimationState;
            if (currentState == CharacterAnimationState.talking) {
              debugPrint('🎭 [情感偵測] AI 已在說話，動態切換情感動畫: $_detectedEmotion');
              _arStateManager.startCharacterTalking(emotion: _detectedEmotion);
            }
          }
        }
        if (mounted) {
          setState(() {
            // Update user speech text
            _userSpeechText = text;

            // Update chat history in real-time
            if (_chatHistory.isNotEmpty &&
                _chatHistory.last['role'] == 'user') {
              _chatHistory.last['text'] = text;
            } else {
              _chatHistory.add({
                'role': 'user',
                'text': text,
                'timestamp': DateTime.now(),
              });
            }
          });
        }
      },
      onTranscriptReceived: (text) {
        if (text.isEmpty) return;
        _pendingText = _sanitizeAiText(text);

        if (mounted) {
          // 不在這裡啟動說話動畫，改由 onAiSpeakingStarted 控制
          setState(() {
            if (_aiResponseText.isNotEmpty &&
                !text.startsWith(_aiResponseText) &&
                !_aiResponseText.startsWith(text)) {
              _aiResponseText += " $_pendingText";
            } else {
              // If _aiResponseText is empty, just set it
              // If text is a substring of _aiResponseText, ignore (duplicate)
              // If _aiResponseText is a substring of text, replace (update)
              if (_aiResponseText.isEmpty) {
                _aiResponseText = _pendingText;
              }
              // Complex overlapping logic omitted for simplicity, appending is safer for chunks
              // But Transcript usually sends full updates or chunks?
              // Gemini 'output_transcription' is usually chunks.
            }
            _showingTranscript = true;

            // Update Chat History
            if (_chatHistory.isNotEmpty && _chatHistory.last['role'] == 'ai') {
              _chatHistory.last['text'] = _aiResponseText;
            } else {
              _chatHistory.add({
                'role': 'ai',
                'text': _aiResponseText,
                'timestamp': DateTime.now(),
              });
            }
          });
        }
      },
      onTurnComplete: () {
        // Optional: Mark turn as complete or finalize text
        if (mounted) {
          setState(() {
            // Finalize AI response
            if (_aiResponseText.isNotEmpty) {
              if (_chatHistory.isNotEmpty &&
                  _chatHistory.last['role'] == 'ai') {
                _chatHistory.last['text'] = _aiResponseText;
              } else {
                _chatHistory.add({
                  'role': 'ai',
                  'text': _aiResponseText,
                  'timestamp': DateTime.now(),
                });
              }
            }
          });
        }
      },
      onAiSpeakingStarted: () {
        if (mounted) {
          final emotion = _detectedEmotion;
          debugPrint('🎭 [AR 動畫] AI 開始播放音訊，偵測情感: ${emotion ?? "none → 用 talking"}');
          debugPrint('🎭 [AR 動畫] 當前 model path: ${_arStateManager.getModelPath()}');
          _arStateManager.startCharacterTalking(emotion: emotion);
        }
      },
      onAiSpeakingEnded: () {
        if (mounted) {
          debugPrint('[AR 動畫] AI 音訊播放結束，切換回 Idle 模型');
          _arStateManager.stopCharacterTalking();
          _detectedEmotion = null; // 重設，下次輸入重新偵測
          _cumulativeUserTranscript = ''; // 重設累積的語音轉錄
        }
      },
      onConnectionChanged: (isConnected) {
        debugPrint("WebSocket 連線狀態: $isConnected");
        if (mounted) {
          setState(() {
            if (!isConnected && _isLiveCallActive) {
              _isLiveCallActive = false;
              _isVoiceMode = false;
              _visionTimer?.cancel();
              _userSpeechText = '通話已結束';
            }
          });
        }
      },
      onAudioLevel: (level) {
        if (mounted && _isLiveCallActive) {
          setState(() {
            _audioLevel = level;
            if (level > 0.07) {
              _showingTranscript = false;
              _aiResponseText = '';
            }
          });
        }
      },
      onInterrupted: () {
        if (mounted && _isLiveCallActive) {
          setState(() {
            _showingTranscript = false;
          });
        }
      },
    );
  }

  Future<void> _loadChatHistory() async {
    final history = await SupabaseService.fetchRecentChatHistory();
    if (mounted) {
      setState(() {
        _chatHistory = history;
      });
    }
  }

  // ===== 序列化初始化流程 =====

  /// 按正確順序初始化 AR 系統
  /// 1. 先初始化 AR State（建立 _animationManager／物體檢測；否則 setupFromSupabaseAvatarPath 會 LateInitializationError）
  /// 2. 再從 profile 快取模型（可與後續 personality 路徑重複，快取層會去重）
  /// 3. 訂閱串流、套用 personality 模型、啟動檢測
  void _initializeARSystemSequence() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('[AR 序列] 開始 AR 系統初始化序列...');

      final coreOk = await _arStateManager.initialize();
      if (!coreOk) {
        debugPrint('❌ [AR 序列] AR State 初始化失敗');
        return;
      }
      debugPrint('[AR 序列] 步驟 1 完成：AR State 已初始化');

      await _loadAndCacheARModel();
      debugPrint('[AR 序列] 步驟 2 完成：profile 模型快取已處理');

      await _initializeARObjectDetection();
      debugPrint('[AR 序列] 步驟 3 完成：物體檢測訂閱與 personality 模型');

      debugPrint('[AR 序列] 所有初始化完成！');
    });
  }

  // ===== AR 物體檢測系統集成 =====

  Future<void> _initializeARObjectDetection() async {
    debugPrint('[AR 物體檢測] 開始初始化 AR 物體檢測系統...');

    if (!_arStateManager.isInitialized) {
      final initialized = await _arStateManager.initialize();
      if (!initialized) {
        debugPrint('❌ [AR 物體檢測] AR 物體檢測初始化失敗');
        return;
      }
    }

    debugPrint('✅ [AR 物體檢測] 系統初始化成功');

    // 從 Supabase 設置模型（此步驟已包含快取邏輯）
    await _setupARModelFromSupabase();

    // 監聽模型路徑變化 - 自動更新 UI
    _modelPathSubscription = _arStateManager.modelPathStream.listen((modelPath) {
      if (mounted && modelPath.isNotEmpty) {
        setState(() {
          _currentModelPath = modelPath;
          debugPrint('✅ [AR 物體檢測] 模型已切換: $modelPath');
        });

        if (_characterAnchor != null && _characterNode != null && _hasPlacedCharacter) {
          _replacePlacedCharacterModel(modelPath);
        } else {
          debugPrint('ℹ️ [AR 物體檢測] 角色尚未放置，已更新待放置模型');
        }
      }
    });

    _detectedObjectSubscription = _arStateManager.detectedObjectStream.listen((detection) {
      if (!mounted) return;
      if (_arStateManager.currentAnimationState == CharacterAnimationState.sitting) {
        if (_awaitingSeatTap) {
          setState(() {
            _awaitingSeatTap = false;
          });
        }
        return;
      }

      final nextAwaiting = detection != null && _isSeatingType(detection.type);
      if (_awaitingSeatTap != nextAwaiting) {
        setState(() {
          _awaitingSeatTap = nextAwaiting;
        });
      }
    });

    _startARObjectDetection();
  }

  Future<void> _loadAndCacheARModel() async {
    try {
      debugPrint('[AR 模型] 開始從快取的 profile 加載並快取模型...');

      // 改為從 userProfileProvider 讀取快取的 profile
      final profileAsyncValue = ref.read(userProfileProvider);
      final profile = profileAsyncValue.valueOrNull;

      if (profile != null) {
        final modelUrl = profile['avatar_url'] as String?;
        debugPrint('[AR 模型] 獲取到快取的 profile，avatar_url: $modelUrl');

        if (modelUrl != null && modelUrl.isNotEmpty) {
          await _arStateManager.setupFromSupabaseAvatarPath(modelUrl);
          debugPrint('✅ [AR 模型] 模型已觸發快取: ${_maskUrl(modelUrl)}');
        } else {
          debugPrint('⚠️ [AR 模型] avatar_url 為空或不存在');
        }
      } else {
        debugPrint('⚠️ [AR 模型] 無法從 Provider 獲取用戶 profile');
      }
    } catch (e) {
      debugPrint("❌ [AR 模型] 加載並快取 AR 模型失敗: $e");
    }
  }

  Future<void> _initCamera() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) return;

      // Default to back camera initially
      final camera = _availableCameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );

      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;
      await _initializeCameraController(camera);
    } catch (e) {
      debugPrint("相機初始化失敗: $e");
    }
  }

  Future<void> _initializeCameraController(
    CameraDescription cameraDescription,
  ) async {
    final previousController = _cameraController;

    if (previousController != null) {
      await previousController.dispose();
    }

    final controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    if (mounted) {
      setState(() {
        _cameraController = controller;
      });
    }

    try {
      await controller.initialize();
      debugPrint('✅ [相機] 控制器初始化完成');

      // 🆕 確保相機初始化後啟動物體檢測
      if (isARInitialized) {
        _startARObjectDetection();
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("相機控制器初始化失敗: $e");
    }
  }

  Future<void> _requestAndInitializeAR() async {
    await PermissionService.requestAllPermissions();
    _initializeAR();
  }

  void _setupARCallbacks() {
    ARFlutterPluginService.onARInitialized = (message) {
      if (mounted) {
        setState(() {
          isARInitialized = true;
          arError = null;
        });
      }
    };

    ARFlutterPluginService.onARError = (error) {
      if (mounted) {
        setState(() {
          arError = error;
          isARInitialized = false;
        });
      }
    };
  }

  Future<void> _initializeAR() async {
    final hasCameraPermission = await PermissionService.checkCameraPermission();
    if (!hasCameraPermission) {
      if (mounted) {
        setState(() {
          arError = '需要相機權限才能使用 AR 功能。請在設定中授予權限。';
          isARInitialized = false;
        });
      }
      return;
    }

    setState(() {
      isARInitialized = true;
      arError = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _throttleTimer?.cancel();
    _visionTimer?.cancel();
    _coachingTimer?.cancel();
    _modelPathSubscription?.cancel();
    _detectedObjectSubscription?.cancel();
    _removePlacedCharacter();
    _arSessionManager?.dispose();
    try {
      _stopARObjectDetection();
      _arStateManager.dispose();
    } catch (_) {}
    _arPartnerService.dispose();
    
    // Stop image stream before disposing to release buffers
    if (_isStreamingImages && _cameraController != null) {
      _cameraController!.stopImageStream();
      _isStreamingImages = false;
    }
    
    _cameraController?.dispose();
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    // 停止相機串流以避免在 Hot Reload 時發生緩衝區耗盡錯誤
    _stopARObjectDetection();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopARObjectDetection();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_arPartnerService.prepareRealtimeSession());
      if (_hasPlacedCharacter) {
        _startARObjectDetection();
      }
    }
  }

  // --- Controls Logic ---

  void _toggleUserMute() {
    setState(() {
      _isUserMuted = !_isUserMuted;
    });
    _arPartnerService.setUserMute(_isUserMuted);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    _arPartnerService.setLivePlaybackGain(_isSpeakerOn ? 1.0 : 0.0);
  }

  void _toggleCameraVideo() {
    setState(() {
      _isCameraOn = !_isCameraOn;
    });
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.isEmpty) return;

    final targetDirection = _isFrontCamera
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    try {
      final newCamera = _availableCameras.firstWhere(
        (camera) => camera.lensDirection == targetDirection,
        orElse: () => _availableCameras.first,
      );

      await _initializeCameraController(newCamera);

      if (mounted) {
        setState(() {
          _isFrontCamera =
              (newCamera.lensDirection == CameraLensDirection.front);
        });
      }
    } catch (e) {
      debugPrint("Switch camera failed: $e");
    }
  }

  void _showSettingsModal() {
    setState(() {
      _geminiVoiceUiOverride = null;
    });
    unawaited(_autoRestoreOnSettingsOpen());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, sheetSetState) {
          _settingsModalSheetSetState = sheetSetState;
          final bottomPadding = MediaQuery.of(context).padding.bottom + 20;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: Text(
                    '語言設定',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white10),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSettingsTabButton(
                          label: 'AI',
                          selected: _settingsTabIndex == 0,
                          onTap: () => sheetSetState(() => _settingsTabIndex = 0),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildSettingsTabButton(
                          label: 'AR',
                          selected: _settingsTabIndex == 1,
                          onTap: () => sheetSetState(() => _settingsTabIndex = 1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: _settingsTabIndex == 0
                        ? _buildAISettingsTab(sheetSetState)
                        : _buildARSettingsTab(sheetSetState),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      _settingsModalSheetSetState = null;
    });
  }

  Future<void> _autoRestoreOnSettingsOpen() async {
    // 當打開設定時，僅載入 Personas 列表，不再從 Profile 覆蓋本地已選中的 _selectedPersonaId
    await _loadSettingsData(fetchProfile: false);
  }

  /// PostgREST／JSON 可能回傳 int、num 或 null；避免 `as int?` 與 `!` 在邊緣情況爆掉。
  static int? _parseSelectedPersonaId(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  /// await 之後 AR 頁可能已 dispose；避免 `setState` 內部對 `_element!` 爆 Null check。
  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    try {
      setState(fn);
    } catch (e, st) {
      debugPrint('[AR 設定] setState 略過（可能已離開頁面）: $e');
      debugPrint('$st');
    }
  }

  void _notifySettingsSheetIfOpen() {
    try {
      _settingsModalSheetSetState?.call(() {});
    } catch (e) {
      debugPrint('[AR 設定] sheetSetState 略過: $e');
    }
  }

  Future<void> _loadSettingsData({
    bool fetchProfile = true,
    bool forcePersonasRefresh = false,
  }) async {
    if (_isLoadingSettingsData) return;
    if (mounted) {
      _setStateIfMounted(() {
        _isLoadingSettingsData = true;
      });
    } else {
      _isLoadingSettingsData = true;
    }
    try {
      final now = DateTime.now();
      final lastFetched = _personasLastFetchedAt;
      final shouldFetchPersonas =
          forcePersonasRefresh ||
          _personas.isEmpty ||
          lastFetched == null ||
          now.difference(lastFetched) > const Duration(minutes: 10);

      final profileFuture = fetchProfile
          ? SupabaseService.fetchUserProfile()
          : Future<Map<String, dynamic>?>.value(null);
      final personasFuture = shouldFetchPersonas
          ? SupabaseService.fetchPersonas()
          : Future<List<Map<String, dynamic>>>.value(_personas);

      final results = await Future.wait<dynamic>([profileFuture, personasFuture]);
      final profile = results[0] as Map<String, dynamic>?;
      final personas = results[1] as List<Map<String, dynamic>>;

      if (!mounted) return;
      _setStateIfMounted(() {
        _personas = personas;
        if (shouldFetchPersonas) {
          _personasLastFetchedAt = now;
        }
        if (fetchProfile) {
          _selectedPersonaId = _parseSelectedPersonaId(profile?['selected_persona_id']);
        }
      });
      _notifySettingsSheetIfOpen();
    } catch (e, st) {
      debugPrint('載入設定資料失敗: $e');
      debugPrint('$st');
    } finally {
      _isLoadingSettingsData = false;
      _setStateIfMounted(() {});
    }
  }

  Future<void> _applyPersona(Map<String, dynamic> persona) async {
    final nextPersonaId = _parseSelectedPersonaId(persona['id']);
    if (nextPersonaId != null && _selectedPersonaId == nextPersonaId) {
      debugPrint(
        '[Persona] 略過：已係同一個 persona id=$nextPersonaId（唔重複寫入／預熱）',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已經係呢個角色（id=$nextPersonaId）')),
        );
      }
      return;
    }
    if (nextPersonaId == null) {
      debugPrint('[Persona] 錯誤：persona 缺少有效 id，raw=${persona['id']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法套用：Persona id 無效')),
        );
      }
      return;
    }

    final String name = (persona['name'] as String?) ?? 'AI';
    final String description = (persona['description'] as String?) ?? '';
    final String systemPrompt = (persona['system_prompt'] as String?) ?? '';
    final dynamic rawTraits = persona['traits'];
    final String traitsStr = rawTraits is List
        ? rawTraits.map((e) => e.toString()).join(', ')
        : (rawTraits?.toString() ?? '');

    debugPrint(
      '[Persona] 用戶揀個性角色 → id=$nextPersonaId name=$name | '
      'DB 將寫入 selected_persona_id，後端 prompt 會跟 personas.traits（唔注入自訂 detailed_personality）',
    );
    final descLog = description.length > 80
        ? '${description.substring(0, 77)}…'
        : description;
    debugPrint(
      '[Persona] personas 列 traits=[$traitsStr] | description=$descLog',
    );

    if (mounted) {
      setState(() {
        _selectedPersonaId = nextPersonaId;
      });
    }
    // Bottom sheet 用 StatefulBuilder：父級 setState 唔會自動重畫 sheet，要即刻通知先見到選取框。
    _notifySettingsSheetIfOpen();

    try {
      await SupabaseService.updateSelectedPersonaId(nextPersonaId);
      debugPrint('[Persona] Supabase profiles.selected_persona_id 已更新 → $nextPersonaId');
      if (!_isLiveCallActive) {
        debugPrint('[Persona] 並行：refreshUserProfileCache + prepareBackend(forceRefresh:true)');
        await Future.wait([
          ref.read(personalityProvider.notifier).refreshUserProfileCache(),
          _arPartnerService.prepareBackend(forceRefresh: true),
        ]);
        debugPrint('[Persona] userProfile 快取與後端預熱已完成');
      } else {
        await ref.read(personalityProvider.notifier).refreshUserProfileCache();
        debugPrint('[Persona] userProfile 快取已 refresh');
        debugPrint('[Persona] Live 通話中 → 將用 WebSocket sendSystemUpdate 通知模型跟新角色');
      }
    } catch (e) {
      debugPrint('[Persona] 套用失敗（寫入／預熱）: $e');
    }

    if (_isLiveCallActive) {
      final promptMsg = "System Update: The user has switched the persona. From now on, you MUST strictly act as '$name'.\n"
          "Description: $description\n"
          "Instructions: $systemPrompt\n"
          "Acknowledge this change implicitly in your next response by adopting the new persona naturally.";
      _arPartnerService.sendSystemUpdate(promptMsg);
      debugPrint('[Persona] Live：已送出 system update（name + description + system_prompt）');
    }

    _notifySettingsSheetIfOpen();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切換為：$name')),
      );
    }
  }

  Future<void> _restoreCustomAISettings({bool silent = false}) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      if (!mounted) return;
      setState(() {
        _selectedPersonaId = null;
      });
      _notifySettingsSheetIfOpen();

      try {
        debugPrint(
          '[Persona] 自訂/復原 → selected_persona_id=null，後端會用返 profiles.detailed_personality（自訂 traits）',
        );
        await SupabaseService.updateSelectedPersonaId(null);
        debugPrint('[Persona] Supabase profiles.selected_persona_id 已清空');
        if (!_isLiveCallActive) {
          debugPrint('[Persona] 並行：refreshUserProfileCache + prepareBackend（自訂模式）');
          await Future.wait([
            ref.read(personalityProvider.notifier).refreshUserProfileCache(),
            _arPartnerService.prepareBackend(forceRefresh: true),
          ]);
          debugPrint('[Persona] userProfile 與後端預熱已完成（自訂模式）');
        } else {
          await ref.read(personalityProvider.notifier).refreshUserProfileCache();
        }
      } catch (e) {
        debugPrint('[Persona] 復原寫入／預熱失敗: $e');
      }

      if (_isLiveCallActive) {
        final promptMsg = "System Update: The user has restored their custom AI settings. Please act as your default self according to the initial system prompt and ignore any previous temporary persona instructions. Acknowledge this naturally.";
        _arPartnerService.sendSystemUpdate(promptMsg);
        debugPrint('[Persona] Live：已送出復原自訂設定 system update');
      }

      _notifySettingsSheetIfOpen();

      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已復原你的自訂 AI 設定')),
        );
      }
    } catch (e) {
      debugPrint('復原自訂設定失敗: $e');
    }
  }

  Widget _buildSettingsTabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0x33FFC9A7) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFFC8A2) : Colors.white10,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFFFFD3B5) : Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAISettingsTab(void Function(void Function()) sheetSetState) {
    final profileAsyncValue = ref.read(userProfileProvider);
    final profile = profileAsyncValue.valueOrNull;

    String currentVoice = 'Kore';
    if (profile != null) {
      final prefs = profile['preferences'] as Map<String, dynamic>?;
      if (prefs != null && prefs['gemini_voice'] != null) {
        currentVoice = prefs['gemini_voice'] as String;
      } else {
        final gender = profile['gender'] as String? ?? 'female';
        currentVoice = gender.toLowerCase() == 'male' ? 'Puck' : 'Kore';
      }
    }
    if (_geminiVoiceUiOverride != null) {
      currentVoice = _geminiVoiceUiOverride!;
    }

    final voices = [
      {'id': 'Puck', 'name': 'Puck', 'desc': '英式男性聲音'},
      {'id': 'Charon', 'name': 'Charon', 'desc': '低沉男性聲音'},
      {'id': 'Fenrir', 'name': 'Fenrir', 'desc': '粗獷男性聲音'},
      {'id': 'Kore', 'name': 'Kore', 'desc': '溫柔女性聲音'},
      {'id': 'Aoede', 'name': 'Aoede', 'desc': '開朗女性聲音'},
    ];

    IconData getIconForPersona(String name) {
      final lower = name.toLowerCase();
      if (lower.contains('therapist') || lower.contains('治療')) return Icons.chair;
      if (lower.contains('story') || lower.contains('說書')) return Icons.menu_book;
      if (lower.contains('friend') || lower.contains('朋友')) return Icons.people;
      if (lower.contains('assistant') || lower.contains('助理')) return Icons.auto_awesome;
      return Icons.person;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '個性',
          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        if (_isLoadingSettingsData && _personas.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SizedBox(
              height: 28,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFFC8A2),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '載入 Personas 中...',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 4),
            itemCount: 1 + _personas.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              // Index 0 = 預設（返回用家自訂 AI 設定）
              if (index == 0) {
                final selected = _selectedPersonaId == null;
                return GestureDetector(
                  onTap: () {
                    sheetSetState(() {
                      _selectedPersonaId = null;
                    });
                    unawaited(_restoreCustomAISettings());
                  },
                  child: Container(
                    width: 100,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0x26FFC8A2)
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFFFC8A2)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(
                          Icons.restore,
                          size: 24,
                          color: selected ? const Color(0xFFFFC8A2) : Colors.white70,
                        ),
                        Text(
                          '自訂/復原',
                          style: TextStyle(
                            color: selected ? const Color(0xFFFFD3B5) : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final persona = _personas[index - 1];
              final id = _parseSelectedPersonaId(persona['id']);
              final selected = _selectedPersonaId == id;
              final title = (persona['name'] as String?) ?? 'Persona';
              final desc = (persona['description'] as String?)?.trim();
              final descShort = (desc != null && desc.isNotEmpty)
                  ? (desc.length > 42 ? '${desc.substring(0, 40)}…' : desc)
                  : null;

              return GestureDetector(
                onTap: () {
                  // 唔好喺度先改 _selectedPersonaId：否則 _applyPersona 開頭會誤以為「已經係同一個」而略過，
                  // Supabase／prepareBackend 永遠唔會跑，後端亦唔會出 [Persona][prompt]。
                  unawaited(_applyPersona(persona));
                },
                child: Container(
                  width: 108,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0x26FFC8A2)
                        : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFFC8A2)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        getIconForPersona(title),
                        size: 22,
                        color: selected ? const Color(0xFFFFC8A2) : Colors.white70,
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? const Color(0xFFFFD3B5) : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (descShort != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          descShort,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        if (_personas.isEmpty && !_isLoadingSettingsData)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              '暫時未有 Persona 資料',
              style: TextStyle(color: Colors.white60),
            ),
          ),
        
        const SizedBox(height: 30),

        const Text(
          '語音',
          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: voices.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final voice = voices[index];
              final selected = currentVoice == voice['id'];

              return GestureDetector(
                onTap: () async {
                  final vid = voice['id']!;
                  setState(() => _geminiVoiceUiOverride = vid);
                  sheetSetState(() {});
                  try {
                    await SupabaseService.updateUserPreferences({
                      'gemini_voice': vid,
                    });
                    ref.invalidate(userProfileProvider);
                    if (_isLiveCallActive) {
                      await ref.read(personalityProvider.notifier).refreshUserProfileCache();
                      _reconnectLiveChat();
                    } else {
                      await Future.wait([
                        ref.read(personalityProvider.notifier).refreshUserProfileCache(),
                        _arPartnerService.prepareBackend(forceRefresh: true),
                      ]);
                    }
                    if (mounted) {
                      setState(() => _geminiVoiceUiOverride = null);
                    }
                    _notifySettingsSheetIfOpen();
                  } catch (e) {
                    debugPrint('更新語音設定失敗: $e');
                    if (mounted) {
                      setState(() => _geminiVoiceUiOverride = null);
                    }
                    _notifySettingsSheetIfOpen();
                  }
                },
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0x26FFC8A2)
                        : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFFC8A2)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        voice['name']!,
                        style: TextStyle(
                          color: selected ? const Color(0xFFFFD3B5) : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        voice['desc']!,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 30),
        const Divider(color: Colors.white10),
        const SizedBox(height: 8),

        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history, color: Colors.white70),
          title: const Text('聊天紀錄', style: TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: _showChatHistory,
        ),
      ],
    );
  }

  Widget _buildARSettingsTab(void Function(void Function()) sheetSetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '角色高度微調',
          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x33FFC8A2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFC8A2), width: 1.5),
              ),
              child: Text(
                'x${_heightMultiplier.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFFFFD3B5),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                  activeTrackColor: const Color(0xFFFFC8A2),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: const Color(0xFFFFC8A2),
                ),
                child: Slider(
                  value: _heightMultiplier,
                  min: 0.8,
                  max: 2.2,
                  divisions: 14,
                  onChanged: (value) {
                    setState(() {
                      _heightMultiplier = value;
                      _heightMultiplierCustomized = true;
                    });
                    sheetSetState(() {});
                    _updatePlacedCharacterScale();
                  },
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('顯示平面點點', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
            Switch(
              value: _showPlanesVisualization,
              activeColor: const Color(0xFFFFC8A2),
              onChanged: (value) {
                setState(() {
                  _showPlanesVisualization = value;
                });
                sheetSetState(() {});
                _configureARSession();
              },
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        const Divider(color: Colors.white10),
        const SizedBox(height: 16),
        
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetAR,
            icon: const Icon(Icons.refresh, color: Color(0xFFFFC8A2)),
            label: const Text(
              '重置 AR',
              style: TextStyle(color: Color(0xFFFFD3B5)),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0x66FFC8A2)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cameraswitch, color: Colors.white70),
          title: const Text('切換鏡頭', style: TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: _switchCamera,
        ),
      ],
    );
  }

  Future<void> _showChatHistory() async {
    // No longer fetch from DB every time. Use the local state _chatHistory.
    if (!mounted) return;

    final arContext = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '聊天紀錄',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      if (arContext.mounted) {
                        Navigator.of(arContext).push(
                          MaterialPageRoute(
                            builder: (context) => const MemoryScreen(),
                          ),
                        );
                      }
                    },
                    child: const Text('View All'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _chatHistory.isEmpty
                  ? const Center(
                      child: Text(
                        '暫無紀錄',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: _chatHistory.length,
                      itemBuilder: (context, index) {
                        final msg =
                            _chatHistory[_chatHistory.length - 1 - index];
                        final isUser = msg['role'] == 'user';
                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? Colors.cyanAccent.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20).copyWith(
                                bottomRight: isUser
                                    ? const Radius.circular(0)
                                    : null,
                                bottomLeft: !isUser
                                    ? const Radius.circular(0)
                                    : null,
                              ),
                            ),
                            child: Text(
                              msg['text'] ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _reconnectLiveChat() async {
    if (!_isLiveCallActive) return;
    debugPrint("重新連線 Live Chat 以套用新性格...");
    final wasVoiceMode = _isVoiceMode;
    await _arPartnerService.stopLiveChat();
    _arPartnerService.disconnectLiveChat(); // 必須斷開 WebSocket 才能重新建立帶有新 Prompt 的連線
    setState(() {
      _isLiveCallActive = false;
      _userSpeechText = '更新設定中...';
    });
    // 強制清除後端快取並預熱
    await _arPartnerService.prepareBackend(forceRefresh: true);
    
    await _startLiveCall(enableMicrophone: wasVoiceMode);
  }

  @override
  Widget build(BuildContext context) {
    // 🆕 監聽 personalityProvider 變化，當用戶在設定中更換角色時自動更新
    ref.listen(personalityProvider, (previous, next) {
      debugPrint('🆕 [AR 系統] 偵測到 Personality 變更，重新載入模型...');
      _setupARModelFromSupabase();
      
      // 重新連線以套用新的性格
      if (_isLiveCallActive) {
        _reconnectLiveChat();
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false, // 避免鍵盤彈出時壓縮 ARView 導致卡死
      body: Stack(
        children: [
          if (isARInitialized && arError == null && _isCameraOn)
            SizedBox.expand(
              child: ARView(
                key: _modelViewerKey,
                onARViewCreated: _onARViewCreated,
                planeDetectionConfig: PlaneDetectionConfig.horizontal,
              ),
            )
          else if (arError != null)
            _buildErrorView()
          else if (!_isCameraOn)
            const SizedBox.shrink()
          else
            _buildLoadingView(),

          if (isARInitialized &&
              arError == null &&
              _isCameraOn &&
              !_coachingDismissed)
            _buildCoachingOverlay(),

          if (_awaitingSeatTap)
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.cyanAccent.withOpacity(0.7),
                    ),
                  ),
                  child: const Text(
                    '偵測到可坐嘅物件，點一下座位位置',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),


          // ── 搖桿觸控區域（角色放置後才顯示）──────────────────────────────
          // 佔據螢幕左半邊、底部控制列上方；按下時搖桿就地浮現
          if (isARInitialized && arError == null && _hasPlacedCharacter)
            Positioned(
              left: 0,
              top: 80,       // 避開頂部 AppBar
              bottom: 210,   // 避開底部控制列（~200px）
              width: MediaQuery.of(context).size.width * 0.5,
              child: FloatingJoystick(
                baseRadius: 62,
                knobRadius: 26,
                onDirectionChanged: _onJoystickChange,
                onReleased: _onJoystickReleased,
              ),
            ),
          // ───────────────────────────────────────────────────────────────

          // 4. Transcript / Waveform Overlay (Floating in center-bottom area)
          if (_isLiveCallActive && (_showingTranscript || _audioLevel > 0.05))
            Positioned(
              bottom: 270, // 往上移動以避開「按住橫撥旋轉角色」控制項
              left: 20,
              right: 20,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: (_showingTranscript && _aiResponseText.isNotEmpty)
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _aiResponseText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            // maxLines: 3, // Removed limit
                            // overflow: TextOverflow.ellipsis, // Removed overflow
                          ),
                        )
                      : WaveformVisualizer(audioLevel: _audioLevel),
                ),
              ),
            ),

          // 4. Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.menu,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Ar companion ",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(width: 20, height: 2, color: Colors.white),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.history,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: _showChatHistory,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 5. Bottom Controls
          Positioned(
            bottom: MediaQuery.of(context).viewInsets.bottom, // 改回根據鍵盤高度調整
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachingOverlay() {
    final text = _coachingMessage();
    return Positioned(
      top: 92,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () {
            if (mounted) {
              setState(() {
                _coachingDismissed = true;
              });
            }
          },
          child: AnimatedOpacity(
            opacity: _coachingDismissed ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 250),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasDetectedPlane ? Icons.touch_app : Icons.explore,
                    color: Colors.white.withOpacity(0.9),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _planeCount > 0 ? '$_planeCount' : '',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _coachingMessage() {
    if (!_hasDetectedPlane) {
      return '請對準地面慢慢移動手機掃描平面';
    }
    if (!_hasPlacedCharacter) {
      return '已偵測到平面，點一下地面放置角色';
    }
    return '已放置：點地面移動角色；雙指扭動可旋轉面向';
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.6),
            Colors.black.withOpacity(0.8),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Rotate Handle（放置角色後才顯示）───────────────────────
          if (_hasPlacedCharacter) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) {
                _rotateCharacterByDelta(details.delta.dx);
              },
              child: Container(
                width: double.infinity,
                height: 48,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chevron_left,
                      color: Colors.white.withOpacity(0.85),
                      size: 24,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '按住橫撥旋轉角色',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.white.withOpacity(0.85),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ],
          // ───────────────────────────────────────────────────────────
          // Row 1: Function Buttons (Glass Style)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSquircleButton(
                icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                isActive: _isSpeakerOn,
                onTap: _toggleSpeaker,
              ),
              _buildSquircleButton(
                icon: !_isUserMuted ? Icons.mic : Icons.mic_off,
                isActive: !_isUserMuted,
                onTap: _toggleUserMute,
              ),
              _buildSquircleButton(
                icon: Icons.settings,
                isActive: true,
                onTap: _showSettingsModal,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Row 2: Integrated Bottom Bar (Glass Style)
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15), // Glass color
              borderRadius: BorderRadius.circular(24), // Squircle-ish
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Text Input Area
                Expanded(
                  child: TextField(
                    controller: _textEditingController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      // Ensure text field background is transparent to show glass effect
                      fillColor: Colors.transparent,
                      filled: true,
                      // Remove focus border and enabled border to hide internal borders
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                    onSubmitted: _handleSubmitted,
                  ),
                ),

                // Send Button (Only show when typing?) OR Call Button
                // The user requested input field, but we also have the Call toggle.
                // We can keep the Call button on the right, or switch to Send button when typing.
                // Let's keep the Call button for now, but maybe add a small send icon if text is not empty?
                // For simplicity and matching the "Integrated" look, let's keep the Call button on the right
                // similar to how it was, but if user types, maybe they press Enter to send.
                // Or we can replace Call button with Send button if text is not empty.
                const SizedBox(width: 8),

                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textEditingController,
                  builder: (context, value, child) {
                    final hasText = value.text.trim().isNotEmpty;
                    if (hasText) {
                      return GestureDetector(
                        onTap: () =>
                            _handleSubmitted(_textEditingController.text),
                        child: Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      );
                    } else {
                      return GestureDetector(
                        onTap: _toggleLiveCall,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: _isVoiceMode
                                ? Colors.redAccent
                                : const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(
                              20,
                            ), // Squircle-ish
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isVoiceMode) ...[
                                const Icon(
                                  Icons.call_end,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Stop",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ] else ...[
                                const Icon(
                                  Icons.graphic_eq,
                                  color: Colors.black87,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Call",
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSquircleButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15), // Glass color
          borderRadius: BorderRadius.circular(
            24,
          ), // Squircle shape (approx 37% of width)
          border: Border.all(
            color: isActive
                ? Colors.white.withOpacity(0.3)
                : Colors.redAccent.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.white60,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              arError ?? 'Error',
              style: const TextStyle(color: Colors.white),
            ),
            TextButton(onPressed: _initializeAR, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  void _showChatInput() {
    final TextEditingController textController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: '輸入訊息...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (text) async {
                    if (text.trim().isNotEmpty) {
                      _detectedEmotion = _detectEmotionFromText(text.trim());
                      if (!_isLiveCallActive) {
                        await _startLiveCall(enableMicrophone: false);
                      }
                      _arPartnerService.sendText(text.trim());
                      setState(() {
                        _userSpeechText = text.trim();
                        _aiResponseText = '';
                        _showingTranscript = false;
                      });
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFFFFCCAA)),
                onPressed: () async {
                  final text = textController.text.trim();
                  if (text.isNotEmpty) {
                    _detectedEmotion = _detectEmotionFromText(text);
                    if (!_isLiveCallActive) {
                      await _startLiveCall(enableMicrophone: false);
                    }
                    _arPartnerService.sendText(text);
                    setState(() {
                      _userSpeechText = text;
                      _aiResponseText = '';
                      _showingTranscript = false;
                    });
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmitted(String text) async {
    text = text.trim();
    if (text.isEmpty) return;

    _textEditingController.clear();
    _detectedEmotion = _detectEmotionFromText(text);

    if (!_isLiveCallActive) {
      await _startLiveCall(enableMicrophone: false);
    }

    _arPartnerService.sendText(text);

    setState(() {
      // Clear AI bubble immediately to indicate new turn
      _aiResponseText = '';
      _showingTranscript = false;

      // Add user message to history
      _chatHistory.add({
        'role': 'user',
        'text': text,
        'timestamp': DateTime.now(),
      });
    });
  }

  Future<void> _toggleLiveCall() async {
    if (_isVoiceMode) {
      _visionTimer?.cancel();
      await _arPartnerService.stopLiveChat();
      setState(() {
        _isLiveCallActive = false;
        _isVoiceMode = false;
        _userSpeechText = '通話結束';
        _audioLevel = 0.0;
        _showingTranscript = false;
        _aiResponseText = '';
      });
    } else {
      await _startLiveCall(enableMicrophone: true);
    }
  }

  Future<void> _startLiveCall({bool enableMicrophone = true}) async {
    if (_isLiveCallActive) {
      // If already connected but upgrading to voice
      if (enableMicrophone && !_isVoiceMode) {
        // TODO: Implement upgrade in service if needed,
        // but currently startLiveCall handles re-entry gracefully or we reconnect
        // For now, assume we might need to reconnect or enable streaming
        // Ideally service should support enabling streaming on existing connection
        // Re-calling startLiveCall might work
        try {
          await _arPartnerService.startLiveChat(enableMicrophone: true);
          setState(() {
            _isVoiceMode = true;
            _userSpeechText = '通話中...';
          });
        } catch (e) {
          debugPrint("Upgrade to voice failed: $e");
        }
      }
      return;
    }

    // 優先快取預熱，失敗時仍允許降級進線，避免 UI 卡住。
    await _arPartnerService.ensureRealtimePrepared(
      timeout: const Duration(milliseconds: 1600),
      allowBackgroundRetry: true,
    );

    setState(() {
      _isLiveCallActive = true;
      _isVoiceMode = enableMicrophone;
      _userSpeechText = '連線中...';
      _aiResponseText = '';
      _audioLevel = 0.0;
    });

    try {
      await _arPartnerService.initializeWebSocket();
      await _arPartnerService.startLiveChat(enableMicrophone: enableMicrophone);

      _visionTimer?.cancel();
      _visionTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (_isCameraOn &&
            _cameraController != null &&
            _cameraController!.value.isInitialized &&
            _isLiveCallActive &&
            _lastCameraImage != null) {
          try {
            // 🆕 廢除 takePicture，改用串流影像發送給 AI
            // 這樣就不會中斷物體檢測
            debugPrint('[AI Vision] 發送串流影像幀...');
            // 注意：這裡可能需要將 CameraImage 轉換為後端需要的格式（如 JPEG）
            // 為了簡化，我們先發送原始字節，或者你可以保留之前的 takePicture 但確保它不與 Stream 衝突
            // 但最穩定的做法是從 _lastCameraImage 轉換
          } catch (e) {
            debugPrint("影像發送失敗: $e");
          }
        }
      });

      setState(() {
        _userSpeechText = '通話中...';
      });
    } catch (e) {
      debugPrint("通話啟動失敗: $e");
      setState(() {
        _isLiveCallActive = false;
        _userSpeechText = '連線失敗';
      });
    }
  }

  void _resetAR() {
    _removePlacedCharacter();
    if (mounted) {
      final personality = ref.read(personalityProvider).valueOrNull;
      final gender = personality?.gender.toLowerCase() ?? 'female';
      setState(() {
        _planeCount = 0;
        _hasDetectedPlane = false;
        _hasPlacedCharacter = false;
        _coachingDismissed = false;
        _heightMultiplierCustomized = false;
        _heightMultiplier = gender == 'male' ? 1.8 : 1.6;
        _characterYawRadians = 0.0;
        _faceUserYaw = 0.0;
        _localX = 0.0;
        _localZ = 0.0;
        _prevTargetYaw = 0.0;
      });
    }
    _joystickTimer?.cancel();
    _joystickTimer = null;
    _joystickReferenceYaw = null;
    _loadAndCacheARModel();
  }

  void _showInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('AR 使用說明', style: TextStyle(color: Colors.white)),
        content: const Text(
          '1. 等待 AR 初始化完成\n'
          '2. AR 模型會自動顯示在鏡頭前\n'
          '3. 使用設定選單切換鏡頭或重置',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  void _showHeightTuning() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '角色高度微調',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'x${_heightMultiplier.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: _heightMultiplier,
                        min: 0.8,
                        max: 2.2,
                        divisions: 14,
                        activeColor: Colors.cyanAccent,
                        inactiveColor: Colors.white.withOpacity(0.2),
                        onChanged: (v) {
                          setSheetState(() {});
                          if (!mounted) return;
                          setState(() {
                            _heightMultiplier = v;
                            _heightMultiplierCustomized = true;
                          });
                          _updatePlacedCharacterScale();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          if (!mounted) return;
                          final personality = ref.read(personalityProvider).valueOrNull;
                          final gender = personality?.gender.toLowerCase() ?? 'female';
                          setState(() {
                            _heightMultiplier = gender == 'male' ? 1.8 : 1.6;
                            _heightMultiplierCustomized = true;
                          });
                          setSheetState(() {});
                          _updatePlacedCharacterScale();
                        },
                        child: const Text(
                          '重置',
                          style: TextStyle(color: Colors.cyanAccent),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          '完成',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;
    _arAnchorManager = arAnchorManager;

    _arObjectManager!.onRotationEnd = (name, transform) {
      final node = _characterNode;
      if (node != null && node.name == name) {
        node.transform = transform;
      }
    };

    _configureARSession();

    // 勿呼叫 ARObjectManager.onInitialize()：plugin 0.0.3 會對 arobjects_* 發 init，
    // Android 端僅在 arsession_* 實作 init → MissingPluginException。
    _arSessionManager!.onPlaneOrPointTap = _onPlaneOrPointTapped;
    _arSessionManager!.onPlaneDetected = (planeCount) {
      if (!mounted) return;
      final nextCount = planeCount;
      final nextDetected = nextCount > 0;
      final shouldHaptic = !_hasDetectedPlane && nextDetected;
      if (_planeCount != nextCount || _hasDetectedPlane != nextDetected) {
        setState(() {
          _planeCount = nextCount;
          _hasDetectedPlane = nextDetected;
        });
      }
      if (shouldHaptic) {
        HapticFeedback.mediumImpact();
      }
    };

    _startARObjectDetection();
  }

  /// 平面可見性等與手勢：統一在此呼叫，避免設定頁重複時漏掉 [handleRotation]。
  void _configureARSession() {
    _arSessionManager?.onInitialize(
      showFeaturePoints: false,
      showPlanes: _showPlanesVisualization,
      showWorldOrigin: false,
      handleTaps: true,
      handlePans: false,
      handleRotation: true,
    );
  }

  Future<void> _onPlaneOrPointTapped(
    List<ARHitTestResult> hitTestResults,
  ) async {
    if (hitTestResults.isEmpty) return;
    if (_currentModelPath.isEmpty) return;

    final hit = hitTestResults.first;

    // 如果已經放置了角色，點擊其他地方就讓他走過去
    if (_hasPlacedCharacter &&
        _characterAnchor != null &&
        _characterNode != null) {
      final shouldSitAfterMove = _awaitingSeatTap;
      if (shouldSitAfterMove && mounted) {
        setState(() {
          _awaitingSeatTap = false;
        });
      }
      await _movePlacedCharacterToHit(hit, sitAfterMove: shouldSitAfterMove);
      return;
    }

    if (_arAnchorManager == null || _arObjectManager == null) return;
    final newAnchor = ARPlaneAnchor(transformation: hit.worldTransform);
    final didAddAnchor = await _arAnchorManager!.addAnchor(newAnchor);
    if (didAddAnchor != true) return;

    await _removePlacedCharacter();

    // 計算面向相機的旋轉
    final targetPosition = _extractTranslation(hit.worldTransform);
    final dx = 0.0 - targetPosition.x;
    final dz = 0.0 - targetPosition.z;
    final yaw = math.atan2(dx, dz) + math.pi;

    // 記住初始放置角度，旋轉手柄以此為基準累積旋轉；搖桿方向以 _faceUserYaw 為基準
    _characterYawRadians = yaw;
    _faceUserYaw = yaw;
    _localX = 0.0;
    _localZ = 0.0;
    _prevTargetYaw = yaw;

    final scale = await _uniformScaleForModelAtPath(_currentModelPath);

    final modelSource = await _resolveModelSource(_currentModelPath);
    if (modelSource == null) {
      debugPrint('❌ [AR 放置] 失敗：找不到可用模型來源 $_currentModelPath');
      return;
    }

    // 不在 ARNode 上設 rotation — 旋轉統一由 AnchorNode 承載（setNodeYawAndLocalOffset）。
    // 避免 ModelNode 自帶 rotation 與 AnchorNode rotation 疊加導致雙重旋轉。
    final newNode = ARNode(
      type: modelSource.nodeType,
      uri: modelSource.uri,
      scale: vec.Vector3(scale, scale, scale),
      position: vec.Vector3(0.0, 0.0, 0.0),
    );

    final didAddNode = await _arObjectManager!.addNode(
      newNode,
      planeAnchor: newAnchor,
    );

    if (didAddNode == true) {
      _characterAnchor = newAnchor;
      _characterNode = newNode;
      // 用 AnchorNode 承載初始 yaw 旋轉（ModelNode 保持 identity rotation）
      await _arObjectManager!.setNodeYawAndLocalOffset(
        newNode.name,
        yaw * (180.0 / math.pi),
        0.0,
        0.0,
      );
      if (mounted) {
        setState(() {
          _hasPlacedCharacter = true;
        });
      }
      if (_awaitingSeatTap) {
        await _arStateManager.confirmSit();
        if (mounted) {
          setState(() {
            _awaitingSeatTap = false;
          });
        }
      }
      _coachingTimer?.cancel();
      _coachingTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        if (_coachingDismissed) return;
        setState(() {
          _coachingDismissed = true;
        });
      });
    } else {
      await _arAnchorManager!.removeAnchor(newAnchor);
    }
  }

  Future<void> _removePlacedCharacter() async {
    if (_arObjectManager == null || _arAnchorManager == null) return;

    final node = _characterNode;
    if (node != null) {
      await _arObjectManager!.removeNode(node);
    }
    _characterNode = null;

    final anchor = _characterAnchor;
    if (anchor != null) {
      await _arAnchorManager!.removeAnchor(anchor);
    }
    _characterAnchor = null;
  }

  void _updatePlacedCharacterScale() {
    unawaited(_applyPlacedCharacterUniformScale());
  }

  /// 按水平拖移量 [dx]（邏輯像素）旋轉角色 Y 軸。
  /// 靈敏度 0.5°/px，橫掃 360px 約旋轉 180°。
  /// 直接呼叫 native rotateNodeY，繞過有 bug 的 matrix decompose 路徑。
  void _rotateCharacterByDelta(double dx) {
    final node = _characterNode;
    if (node == null || _arObjectManager == null) return;

    const degPerPx = 0.5;
    final rotDelta = dx * degPerPx * (math.pi / 180.0);
    _characterYawRadians += rotDelta;
    // 不更新 _faceUserYaw：搖桿方向基準永遠以初始放置角度為準，
    // 無論旋轉手柄怎麼轉，搖桿的上下左右都保持一致。

    // AnchorNode 旋轉了 rotDelta 弧度，為保持世界位置不變，
    // local 座標需反向旋轉：newLocal = R_y(-rotDelta) * oldLocal
    final cos_d = math.cos(rotDelta);
    final sin_d = math.sin(rotDelta);
    final newLocalX =  _localX * cos_d - _localZ * sin_d;
    final newLocalZ =  _localX * sin_d + _localZ * cos_d;
    _localX = newLocalX;
    _localZ = newLocalZ;
    _prevTargetYaw = _characterYawRadians; // 同步，確保下次搖桿 delta 正確

    final yawDeg = _characterYawRadians * (180.0 / math.pi);
    _arObjectManager!.setNodeYawAndLocalOffset(node.name, yawDeg, _localX, _localZ);
  }

  // ── 搖桿移動 ────────────────────────────────────────────────────────────

  /// 搖桿方向改變時呼叫（由 FloatingJoystick.onDirectionChanged 回調）
  /// 注意：手指穿過死區時也會回報 zero，但此函數**不**負責停止邏輯；
  /// 停止邏輯由 [_onJoystickReleased]（onReleased 回調）處理。
  void _onJoystickChange(JoystickDirection dir) {
    _joystickDir = dir;

    // 只在計時器尚未啟動時啟動（手指仍按著，首次推出死區）
    if (dir.magnitude > 0.05 && _joystickTimer == null) {
      // 快照「面向用戶」穩定 yaw 作為本次搖桿工作期間的方向基準
      _joystickReferenceYaw = _faceUserYaw;
      // 本次工作期間的 yaw 起點 = 當前角色面向，確保首個方向 delta = 0
      _prevTargetYaw = _characterYawRadians;
      _joystickTimer = Timer.periodic(
        const Duration(milliseconds: 33), // 30fps：減少 native coroutine 頻率，降低 crash 風險
        _onJoystickTick,
      );
      // debounce：首次推出才觸發 walking 動畫
      final now = DateTime.now();
      if (_stateBeforeWalking == null ||
          _lastWalkStateChange == null ||
          now.difference(_lastWalkStateChange!) > _walkDebounce) {
        _stateBeforeWalking ??= _arStateManager.currentAnimationState;
        if (_arStateManager.currentAnimationState != CharacterAnimationState.walking) {
          _lastWalkStateChange = now;
          _arStateManager.forceChangeAnimation(CharacterAnimationState.walking);
        }
      }
    }
    // 穿過死區（magnitude ≈ 0）時計時器繼續運行，tick 裡 magnitude<0.05 自動跳過移動
  }

  /// 手指真正離開螢幕時呼叫（由 FloatingJoystick.onReleased 回調）
  void _onJoystickReleased() {
    _joystickDir = JoystickDirection.zero;
    _joystickTimer?.cancel();
    _joystickTimer = null;
    _joystickReferenceYaw = null;
    _lastJoystickDirIdx = -1;
    _prevTargetYaw = _characterYawRadians;

    final now = DateTime.now();
    if (_lastWalkStateChange == null ||
        now.difference(_lastWalkStateChange!) > _walkDebounce) {
      final restore = _stateBeforeWalking ?? CharacterAnimationState.idle;
      _stateBeforeWalking = null;
      _lastWalkStateChange = now;
      if (restore == CharacterAnimationState.talking) {
        _arStateManager.startCharacterTalking();
      } else {
        _arStateManager.forceChangeAnimation(CharacterAnimationState.idle);
      }
    }
  }

  /// 每幀更新角色面向 + 位置（搖桿按住期間）
  /// 4方向：角色面向移動方向跑
  ///   ↑ = 遠離用戶（見背面）　↓ = 靠近用戶（見正面）
  ///   ← = 向左跑　　　　　　 → = 向右跑
  void _onJoystickTick(Timer _) {
    try {
      final node = _characterNode;
      if (!mounted || node == null || _arObjectManager == null) return;

      const speed = 0.3 / 30.0; // 0.3 m/s @ 30fps

      final jx = _joystickDir.dx;
      final jy = _joystickDir.dy;
      final magnitude = _joystickDir.magnitude;
      if (magnitude < 0.05) return; // 手指在死區內：跳過但不停止

      // 按下搖桿瞬間記錄的「面向用戶」yaw 作為 4 個絕對方向基準（整個工作期間固定）
      final refYaw = _joystickReferenceYaw ?? _faceUserYaw;

      // 判斷方向索引（0=上 1=下 2=左 3=右）
      int dirIdx;
      double targetYaw;

      if (jy.abs() >= jx.abs()) {
        if (jy < 0) {
          // ↑ 搖桿向上 → 靠近用戶（正面朝用戶）
          dirIdx = 0;
          targetYaw = refYaw;
        } else {
          // ↓ 搖桿向下 → 遠離用戶（背對用戶跑）
          dirIdx = 1;
          targetYaw = refYaw + math.pi;
        }
      } else {
        if (jx > 0) {
          dirIdx = 3; // → 向右跑（用戶視角右）
          targetYaw = refYaw - math.pi / 2;
        } else {
          dirIdx = 2; // ← 向左跑（用戶視角左）
          targetYaw = refYaw + math.pi / 2;
        }
      }

      if (dirIdx != _lastJoystickDirIdx) {
        // 方向改變：AnchorNode 將旋轉 delta = targetYaw - prevYaw。
        // 為保持角色世界位置不變，反向旋轉 local 座標：
        //   newLocal = R_y(-delta) * oldLocal
        final delta = targetYaw - _prevTargetYaw;
        final cos_d = math.cos(delta);
        final sin_d = math.sin(delta);
        final newLocalX =  _localX * cos_d - _localZ * sin_d;
        final newLocalZ =  _localX * sin_d + _localZ * cos_d;
        _localX = newLocalX;
        _localZ = newLocalZ;

        _lastJoystickDirIdx = dirIdx;
        _characterYawRadians = targetYaw;
        _prevTargetYaw = targetYaw;
      }

      // 角色始終朝視覺前方（local +Z）移動，限制範圍防止溢出
      _localZ = (_localZ + speed).clamp(-30.0, 30.0);

      // 原子呼叫：旋轉與位置在同一 native coroutine 內完成，消除兩步呼叫的一幀跳動
      _arObjectManager!.setNodeYawAndLocalOffset(
        node.name,
        targetYaw * 180.0 / math.pi,
        _localX,
        _localZ,
      );
    } catch (e) {
      debugPrint('⚠️ [Joystick] tick error: $e');
    }
  }
  // ────────────────────────────────────────────────────────────────────────

  Future<void> _applyPlacedCharacterUniformScale() async {
    final node = _characterNode;
    if (node == null) return;
    final scale = await _uniformScaleForModelAtPath(_currentModelPath);
    if (!mounted || _characterNode != node) return;
    node.scale = vec.Vector3(scale, scale, scale);
  }

  Future<void> _replacePlacedCharacterModel(String modelPath) async {
    if (modelPath.isEmpty) return;
    if (_arObjectManager == null || _arAnchorManager == null) return;

    final modelSource = await _resolveModelSource(modelPath);
    if (modelSource == null) {
      debugPrint('❌ [AR 模型替換] 失敗：找不到可用模型來源 $modelPath');
      return;
    }

    debugPrint('🔄 [AR 模型替換] 準備加載新模型: ${modelSource.uri}');

    final requestId = ++_modelReplaceRequestId;
    final anchor = _characterAnchor;
    if (anchor == null) {
      debugPrint('⚠️ [AR 模型替換] 找不到 Anchor，無法替換');
      return;
    }

    // 根據新 GLB 的實際高度計算 uniform scale，確保與目標身高一致
    final uniformScale = await _uniformScaleForModelAtPath(modelPath);

    // 新 node 位置相對 anchor 為 (0,0,0)；anchor 負責世界座標
    // 旋轉暫設 identity，稍後由 rotateNodeY 重新套用 _characterYawRadians
    final newNode = ARNode(
      type: modelSource.nodeType,
      uri: modelSource.uri,
      scale: vec.Vector3(uniformScale, uniformScale, uniformScale),
      position: vec.Vector3.zero(),
    );

    final didAddNode = await _arObjectManager!.addNode(
      newNode,
      planeAnchor: anchor,
    );

    if (didAddNode != true) {
      debugPrint('❌ [AR 模型替換] 新模型加載失敗: $modelPath');
      return;
    }

    if (requestId != _modelReplaceRequestId) {
      await _arObjectManager!.removeNode(newNode);
      debugPrint('⚠️ [AR 模型替換] 請求已過期，捨棄新模型: $modelPath');
      return;
    }

    // 移除舊 node（新 node 先加再刪，避免視覺閃爍）
    final oldNode = _characterNode;
    _characterNode = newNode;

    if (oldNode != null) {
      await _arObjectManager!.removeNode(oldNode);
    }

    if (requestId != _modelReplaceRequestId) {
      await _arObjectManager!.removeNode(newNode);
      _characterNode = null;
      return;
    }

    // 原子呼叫：同時套用 yaw 旋轉與 local 位置，消除兩步分開呼叫的一幀跳動。
    // _localX/_localZ 已在搖桿/旋轉手柄操作中持續同步，直接使用即可。
    await _arObjectManager!.setNodeYawAndLocalOffset(
      newNode.name,
      _characterYawRadians * (180.0 / math.pi),
      _localX,
      _localZ,
    );

    debugPrint('✅ [AR 模型替換] 新模型加載成功（scale=$uniformScale, yaw=${(_characterYawRadians * 180 / math.pi).toStringAsFixed(1)}°）: $modelPath');
  }

  /// 根據用戶輸入文字偵測情感，決定 AI 回應時用哪個動畫 model。
  /// 返回 null 表示普通 talking。
  CharacterAnimationState? _detectEmotionFromText(String text) {
    // 清除所有標點符號，並將多個空白壓縮為單一空白，確保漸進式片段合併後格式一致
    final cleanText = text
        .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fa5]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
        
    final t = cleanText.toLowerCase();
    debugPrint('🎭 [情感偵測] 分析用戶輸入 (清理後): "$t"');

    // 不開心 / 需要安慰（英文為主，配少量中文）
    const sadKeywords = [
      // 英文 — 情緒狀態
      'feeling down', 'feel down', 'feeling low', 'feel low',
      'not okay', "not ok", "i'm sad", 'so sad', 'feel sad',
      'unhappy', 'not happy', 'depressed', 'miserable',
      'stressed', 'so stressed', 'anxious', 'overwhelmed',
      'frustrated', 'disappointed', 'hopeless', 'helpless',
      'lonely', 'alone', 'empty inside',
      'exhausted', 'burned out', 'burnt out', 'so tired',
      // 英文 — 事件 / 口語
      'bad day', 'rough day', 'tough day', 'terrible day', 'worst day',
      'broke up', 'breakup', 'break up', 'heartbroken', 'heart broken',
      'want to cry', 'wanna cry', 'feel like crying', 'crying',
      'can\'t cope', 'can\'t take it', 'struggling', 'give up',
      'hate my', 'sucks', 'messed up', 'screwed up', 'failed',
      'hurt', 'painful', 'in pain',
      // 中文（繁+簡）
      '唔開心', '不開心', '不开心', '難過', '难过',
      '傷心', '伤心', '壓力', '压力', '煩', '烦',
      '焦慮', '焦虑', '害怕', '寂寞', '孤獨', '孤独',
      '心痛', '絕望', '绝望', '灰心', '委屈',
    ];

    // 開心（英文為主，配少量中文）
    const happyKeywords = [
      // 英文 — 情緒狀態
      "i'm happy", 'so happy', 'feel happy', 'feeling happy',
      'excited', 'so excited', 'thrilled',
      'grateful', 'thankful', 'blessed',
      'proud', 'relieved', 'cheerful', 'joyful', 'on top of the world',
      'feeling good', 'feel good', 'feeling great', 'feel great',
      // 英文 — 事件 / 口語
      'good news', 'great news', 'best news',
      'good day', 'great day', 'best day', 'wonderful day', 'amazing day',
      'got promoted', 'promotion', 'passed', 'graduated',
      'love it', 'love this', 'loved it',
      'can\'t wait', 'looking forward',
      'made my day', 'awesome', 'amazing', 'wonderful', 'fantastic',
      'incredible', 'yay', 'woohoo', 'let\'s go',
      // 中文（繁+簡）
      '開心', '开心', '高興', '高兴', '興奮', '兴奋',
      '快樂', '快乐', '幸運', '幸运', '滿足', '满足',
      '好消息', '成功', '太好了', '好棒', '好正',
    ];

    for (final kw in sadKeywords) {
      if (t.contains(kw)) {
        debugPrint('🎭 [情感偵測] 偵測到「不開心」關鍵字: $kw → comforting');
        return CharacterAnimationState.comforting;
      }
    }
    for (final kw in happyKeywords) {
      if (t.contains(kw)) {
        debugPrint('🎭 [情感偵測] 偵測到「開心」關鍵字: $kw → happy');
        return CharacterAnimationState.happy;
      }
    }
    return null;
  }

  String _maskUrl(String url) {
    if (url.startsWith('assets/')) return url;
    final parts = url.split('/');
    if (parts.length >= 2) {
      return '.../${parts[parts.length - 2]}/${parts[parts.length - 1]}';
    }
    return url;
  }

  Future<String?> _absolutePathForScaleMetrics(String modelPath) async {
    if (modelPath.isEmpty) return null;
    final docDir = await getApplicationDocumentsDirectory();
    if (modelPath.startsWith('http://') || modelPath.startsWith('https://')) {
      final rel = await CacheService().getLocalPath(modelPath);
      if (rel == null) return null;
      final full = p.join(docDir.path, rel);
      return await File(full).exists() ? full : null;
    }
    if (modelPath.startsWith('assets/')) return null;
    final candidatePath = p.isAbsolute(modelPath)
        ? modelPath
        : p.join(docDir.path, modelPath);
    return await File(candidatePath).exists() ? candidatePath : null;
  }

  /// 依 GLB 內建高度把不同動畫模型（Idle/Talking/…）統一拉到 [_arTargetHeightMeters] × [_heightMultiplier]。
  Future<double> _uniformScaleForModelAtPath(String modelPathForMetrics) async {
    final mult = _heightMultiplier;
    final target = _arTargetHeightMeters;
    if (target == null) {
      return (_baseCharacterScale * mult).toDouble();
    }
    final abs = await _absolutePathForScaleMetrics(modelPathForMetrics);
    if (abs == null) {
      return (_baseCharacterScale * mult).toDouble();
    }
    final h = await GlbModelMetricsService.estimateHeightUnitsFromLocalFile(abs);
    if (h == null || h <= 0) {
      return (_baseCharacterScale * mult).toDouble();
    }
    return ((target / h).clamp(0.0001, 100.0) * mult).toDouble();
  }

  Future<({NodeType nodeType, String uri})?> _resolveModelSource(
    String modelPath,
  ) async {
    if (modelPath.isEmpty) return null;

    final docDir = await getApplicationDocumentsDirectory();

    if (modelPath.startsWith('http://') || modelPath.startsWith('https://')) {
      final localRel = await CacheService().getLocalPath(modelPath);
      if (localRel != null && localRel.isNotEmpty) {
        final candidatePath = p.join(docDir.path, localRel);
        if (await File(candidatePath).exists()) {
          final isValidFile = await GlbModelMetricsService.isLikelyValidGlbFile(
            candidatePath,
          );
          if (isValidFile) {
            final normalizedUri = localRel.replaceAll('\\', '/');
            debugPrint(
              '[AR 模型來源] 使用本地快取（免重複下載）: ${_maskUrl(modelPath)} → $normalizedUri',
            );
            return (
              nodeType: NodeType.fileSystemAppFolderGLB,
              uri: normalizedUri,
            );
          }
        }
      }
      final isValidRemote = await GlbModelMetricsService.isLikelyValidGlbUrl(
        modelPath,
      );
      if (!isValidRemote) {
        debugPrint('❌ [AR 模型來源] 遠端 GLB 驗證失敗: ${_maskUrl(modelPath)}');
        return null;
      }
      return (nodeType: NodeType.webGLB, uri: modelPath);
    }

    if (modelPath.startsWith('assets/')) {
      return null;
    }

    // 模型來源：CacheService 已做「先快取、未命中才下載」；此處 [modelPath] 已是相對於
    // Documents 的本地路徑（如 models/…）。放置時一律交給 Android type 2 +
    // loadModelInstance(絕對路徑)，避免走 webGLB 或 buffer 載入在 createTextures 崩潰。

    final candidatePath = p.isAbsolute(modelPath)
        ? modelPath
        : p.join(docDir.path, modelPath);

    if (!await File(candidatePath).exists()) {
      return null;
    }

    final isValidFile = await GlbModelMetricsService.isLikelyValidGlbFile(
      candidatePath,
    );
    if (!isValidFile) {
      debugPrint('❌ [AR 模型來源] 本地 GLB 驗證失敗: $candidatePath');
      return null;
    }

    // fileSystemAppFolderGLB：uri 為相對於 getApplicationDocumentsDirectory() 之路徑
    // （Android 對應 PathUtils.getDataDirectory → …/app_flutter/）。Native 以絕對路徑呼叫
    // loadModelInstance（loadResourcesSuspended）。
    final relativeUri = p.isAbsolute(modelPath)
        ? p.relative(candidatePath, from: docDir.path)
        : modelPath;
    final normalizedUri = relativeUri.replaceAll('\\', '/');
    return (
      nodeType: NodeType.fileSystemAppFolderGLB,
      uri: normalizedUri,
    );
  }

  vec.Vector3 _extractTranslation(vec.Matrix4 transform) {
    return transform.getTranslation();
  }

  bool _isSeatingType(DetectedObjectType type) {
    switch (type) {
      case DetectedObjectType.chair:
      case DetectedObjectType.sofa:
      case DetectedObjectType.bed:
      case DetectedObjectType.couch:
      case DetectedObjectType.stool:
      case DetectedObjectType.bench:
        return true;
      case DetectedObjectType.table:
      case DetectedObjectType.person:
      case DetectedObjectType.unknown:
        return false;
    }
  }

  Future<void> _movePlacedCharacterToHit(
    ARHitTestResult? hit, {
    bool sitAfterMove = false,
    bool forceWalk = false, // 🆕 新增參數控制是否強制走動
    vec.Vector3? localTargetPosition, // 🆕 直接傳入本地座標目標點
  }) async {
    if (_arStateManager.isInitialized != true) return;
    if (_characterAnchor == null) return;
    if (_characterNode == null) return;

    final requestId = ++_moveRequestId;
    _isMovingCharacter = true;

    try {
      if (forceWalk ||
          _arStateManager.currentAnimationState !=
              CharacterAnimationState.walking) {
        await _arStateManager.forceChangeAnimation(
          CharacterAnimationState.walking,
        );
      }

      final startOffset = vec.Vector3.copy(
        _characterNode?.position ?? vec.Vector3.zero(),
      );

      vec.Vector3 targetOffset;
      if (localTargetPosition != null) {
        // 如果提供了本地目標點，直接使用
        targetOffset = localTargetPosition;
      } else if (hit != null) {
        // 否則從 hit 的世界座標轉換為 Anchor 的本地座標
        final anchorInv = vec.Matrix4.copy(_characterAnchor!.transformation)
          ..invert();
        final localTarget = anchorInv * hit.worldTransform;
        targetOffset = _extractTranslation(localTarget);
      } else {
        return; // 沒有目標點
      }

      final delta = targetOffset - startOffset;
      final distance = delta.length;

      // 如果距離太近，直接結束並切換回 idle
      if (distance < 0.01) {
        debugPrint('[AR 行走] 距離太近 ($distance)，取消移動');
        if (sitAfterMove) {
          await _arStateManager.confirmSit();
        } else {
          if (_arStateManager.currentAnimationState !=
              CharacterAnimationState.idle) {
            await _arStateManager.forceChangeAnimation(
              CharacterAnimationState.idle,
            );
          }
        }
        return;
      }

      debugPrint('[AR 行走] 開始移動，距離: $distance 米');

      final direction = vec.Vector3(delta.x, 0.0, delta.z);
      var yaw = 0.0;
      if (direction.length2 > 1e-6) {
        yaw = math.atan2(direction.x, direction.z);
        final node = _characterNode;
        if (node != null) {
          node.rotation = vec.Matrix3.rotationY(yaw);
        }
      }

      const speedMetersPerSecond = 0.6;
      final durationSeconds = (distance / speedMetersPerSecond).clamp(
        0.35,
        6.0,
      );
      final duration = Duration(milliseconds: (durationSeconds * 1000).round());

      final startTime = DateTime.now();
      while (true) {
        if (requestId != _moveRequestId) return;
        final elapsed = DateTime.now().difference(startTime);
        final t = (elapsed.inMilliseconds / duration.inMilliseconds).clamp(
          0.0,
          1.0,
        );
        final eased = t * t * (3 - 2 * t);

        final next = vec.Vector3(
          startOffset.x + (targetOffset.x - startOffset.x) * eased,
          startOffset.y + (targetOffset.y - startOffset.y) * eased,
          startOffset.z + (targetOffset.z - startOffset.z) * eased,
        );

        final node = _characterNode;
        if (node == null) return;
        final rotation = vec.Quaternion.axisAngle(
          vec.Vector3(0.0, 1.0, 0.0),
          yaw,
        );
        node.transform = vec.Matrix4.compose(next, rotation, node.scale);

        if (t >= 1.0) break;
        await Future.delayed(const Duration(milliseconds: 33));
      }

      final node = _characterNode;
      if (node != null) {
        final rotation = vec.Quaternion.axisAngle(
          vec.Vector3(0.0, 1.0, 0.0),
          yaw,
        );
        node.transform = vec.Matrix4.compose(
          targetOffset,
          rotation,
          node.scale,
        );
      }

      if (sitAfterMove) {
        await _arStateManager.confirmSit();
      } else {
        if (_arStateManager.currentAnimationState !=
            CharacterAnimationState.idle) {
          await _arStateManager.forceChangeAnimation(
            CharacterAnimationState.idle,
          );
        }
      }
    } finally {
      if (requestId == _moveRequestId) {
        _isMovingCharacter = false;
      }
    }
  }

  /// 讓模型行近鏡頭的方法
  Future<void> _walkTowardsCamera() async {
    if (!_hasPlacedCharacter ||
        _characterNode == null ||
        _characterAnchor == null)
      return;

    // 1. 取得當前位置（相對於 Anchor 的本地座標）
    final currentTransform = _characterNode!.transform;
    final currentPosition = currentTransform.getTranslation();

    // 2. 獲取相機的當前世界座標
    // ARLocationManager 可能會有相機位置，或者我們可以從 ARSessionManager 獲取
    // 但最簡單直接的方法是假設手機相機就在 AR 場景的初始原點附近 (0,0,0)
    // 為了讓行走更有感，我們讓模型向其「正前方」走
    // 模型目前已經被設定為面向相機，所以其本地坐標系的 Z 軸正方向（或負方向，取決於模型）就是向著相機

    // 取得當前旋轉矩陣
    final rotationMatrix = currentTransform.getRotation();

    // 假設模型面朝 Z 軸正方向 (0, 0, 1)
    // 將這個本地前方向量轉換為世界/Anchor 前方向量
    // 注意：如果模型是背向 Z 軸，這裡可能要用 (0, 0, -1)
    // 根據之前 placement 的邏輯，我們用了 math.pi，所以模型本身可能是面向 Z 軸正向
    final forwardTranslation = vec.Vector3(0, 0, 1.0); // 每次走 1.0 米
    final worldForward = rotationMatrix.transform(forwardTranslation);

    // 忽略 Y 軸的變化（保持在同一個水平面上走）
    worldForward.y = 0;

    // 計算目標位置
    final targetPosition = currentPosition + worldForward;

    debugPrint(
      '[AR 行走] 當前位置: $currentPosition, 目標位置: $targetPosition, 行走向量: $worldForward',
    );

    // 強制啟用行走的位移邏輯，直接傳遞本地目標位置
    await _movePlacedCharacterToHit(
      null,
      forceWalk: true,
      localTargetPosition: targetPosition,
    );
  }

  Future<void> _setupARModelFromSupabase() async {
    try {
      debugPrint('[AR 物體檢測] 設置 AR 模型...');

      // 獲取當前用戶的 personality
      final personalityAsync = ref.read(personalityProvider);
      final personality = personalityAsync.valueOrNull;
      
      if (personality == null) {
        debugPrint('⚠️ [AR 物體檢測] personality 尚未載入');
        return;
      }

      final gender = personality.gender.toLowerCase();
      final avatarPath = personality.avatarPath;

      debugPrint('[AR 物體檢測] personality.gender: $gender');
      debugPrint('[AR 物體檢測] personality.avatarPath: $avatarPath');

      if (avatarPath.isEmpty || !avatarPath.startsWith('http')) {
        debugPrint('⚠️ [AR 物體檢測] avatarPath 為空，無法加載 Supabase 模型');
        // 不再回退到本地資源，因為用戶表示本地沒有模型
        return;
      }

      // 先寫入與 AR 相同的快取管線，避免随后 analyze 再走一次 raw HTTP、双重 egress
      await CacheService().getLocalPath(avatarPath);

      final glbAnalysis =
          await GlbModelMetricsService.analyzeRemoteGlbUrl(avatarPath);
      if (!glbAnalysis.isValid) {
        debugPrint('❌ [AR 物體檢測] avatarPath 不是有效 GLB，已中止載入: ${_maskUrl(avatarPath)}');
        return;
      }

      if (!_heightMultiplierCustomized) {
        _heightMultiplier = gender == 'male' ? 1.8 : 1.6;
      }

      final targetHeightMeters = gender == 'male' ? 1.8 : 1.6;
      _arTargetHeightMeters = targetHeightMeters;
      final heightUnits = glbAnalysis.height;
      if (heightUnits != null && heightUnits > 0) {
        final nextScale = (targetHeightMeters / heightUnits).clamp(
          0.0001,
          100.0,
        );
        _baseCharacterScale = nextScale.toDouble();
        debugPrint(
          '[AR 模型] target=$targetHeightMeters m, sourceHeight=$heightUnits, baseScale=$_baseCharacterScale, multiplier=$_heightMultiplier',
        );
      } else {
        _baseCharacterScale = 1.0;
        debugPrint('[AR 模型] 無法估算模型高度，使用 baseScale=1.0');
      }
      _updatePlacedCharacterScale();

      // ✅ 從 Supabase avatarPath 自動設置模型（會自動處理 sitting.glb）
      _arStateManager.setupFromSupabaseAvatarPath(avatarPath);
      debugPrint('✅ [AR 物體檢測] 從 Supabase 加載 AR 模型: ${_maskUrl(avatarPath)}');
    } catch (e) {
      debugPrint('❌ [AR 物體檢測] 設置 AR 模型失敗: $e');
    }
  }

  void _startARObjectDetection() {
    if (!_autoSeatDetectionEnabled) return;
    if (_arStateManager.isDetectionActive) return;

    if (_arSessionManager != null) {
      _arStateManager.startSnapshotDetection(() async {
        if (!_hasPlacedCharacter) return null;
        if (_isMovingCharacter) return null;
        if (_isLiveCallActive) return null;
        return _captureARSnapshotToTempFile();
      });
      return;
    }

    if (_cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_isStreamingImages) {
      _cameraController!.startImageStream((image) {
        _lastCameraImage = image;
      });
      _isStreamingImages = true;
      debugPrint('[AR 物體檢測] 已啟動相機影像串流');
    }

    _arStateManager.startObjectDetection(() async {
      return _lastCameraImage;
    });
  }

  void _stopARObjectDetection() {
    if (_isStreamingImages && _cameraController != null) {
      _cameraController!.stopImageStream();
      _isStreamingImages = false;
      _lastCameraImage = null;
      debugPrint('[AR 物體檢測] 已停止相機影像串流');
    }
    _arStateManager.stopObjectDetection();
  }

  Future<void> _scanSeatOnce() async {
    if (_isSeatScanRunning) return;
    if (_arSessionManager == null) return;
    if (!_hasPlacedCharacter) return;
    if (!_arStateManager.isInitialized) return;

    setState(() {
      _isSeatScanRunning = true;
    });

    try {
      final path = await _captureARSnapshotToTempFile();
      if (path == null || path.isEmpty) return;
      await _arStateManager.detectOnceFromFilePath(path);
    } finally {
      if (mounted) {
        setState(() {
          _isSeatScanRunning = false;
        });
      }
    }
  }

  Future<String?> _captureARSnapshotToTempFile() async {
    if (_isSnapshotCapturing) return null;
    final session = _arSessionManager;
    if (session == null) return null;
    if (!mounted) return null;

    final now = DateTime.now();
    final last = _lastSnapshotAt;
    if (last != null &&
        now.difference(last) < const Duration(seconds: 2) &&
        _snapshotTempPath != null) {
      return _snapshotTempPath;
    }

    _isSnapshotCapturing = true;
    try {
      final provider = await session.snapshot();
      final image = await _resolveImageProvider(provider);

      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return null;

      final tmp = await getTemporaryDirectory();
      final path = _snapshotTempPath ?? '${tmp.path}/ar_snapshot.jpg';
      _snapshotTempPath = path;

      final file = File(path);
      final jpgBytes = await compute(_encodeJpegFromRgba, {
        'bytes': rgba.buffer.asUint8List(),
        'width': image.width,
        'height': image.height,
      });
      await file.writeAsBytes(jpgBytes, flush: true);
      _lastSnapshotAt = now;
      return file.path;
    } catch (e) {
      debugPrint('[AR 物體檢測] 截圖失敗: $e');
      return null;
    } finally {
      _isSnapshotCapturing = false;
    }
  }

  Future<ui.Image> _resolveImageProvider(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info.image);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  String _sanitizeAiText(String input) {
    var text = input.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'),
      '',
    );
    text = text.trim();
    const maxLen = 600;
    // Don't truncate too early, let UI handle overflow or showing full text
    // But keep a reasonable limit to prevent memory issues
    if (text.length > maxLen) {
      text = text.substring(0, maxLen);
    }
    return text;
  }
}

class WaveformVisualizer extends StatelessWidget {
  final double audioLevel;
  final Color color;

  const WaveformVisualizer({
    super.key,
    required this.audioLevel,
    this.color = Colors.cyanAccent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (index) {
          final multipliers = [0.3, 0.6, 1.0, 0.6, 0.3];
          final height = (10 + (audioLevel * 100 * multipliers[index])).clamp(
            5.0,
            40.0,
          );

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 4,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

Uint8List _encodeJpegFromRgba(Map<String, Object?> payload) {
  final bytes = payload['bytes'] as Uint8List;
  final width = payload['width'] as int;
  final height = payload['height'] as int;

  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bytes.buffer,
    order: img.ChannelOrder.rgba,
  );

  final resized = (width > 640) ? img.copyResize(image, width: 640) : image;

  final encoded = img.encodeJpg(resized, quality: 70);
  return Uint8List.fromList(encoded);
}
