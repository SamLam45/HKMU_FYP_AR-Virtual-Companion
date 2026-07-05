import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'auth_service.dart';
import 'websocket_service.dart';

class ARPartnerService {
  final AudioRecorder _recorder = AudioRecorder();
  final Dio _dio = Dio();
  final AudioPlayer _audioPlayer = AudioPlayer(); // 實例化 AudioPlayer
  final WebSocketService _webSocketService =
      WebSocketService(); // 實例化 WebSocketService
  Future<void>? _prepareRealtimeFuture;
  DateTime? _lastRealtimePreparedAt;

  /// 避免同時多處呼叫 `prepareBackend` 造成重複 HTTP（例如日記頁預熱 + 儲存後 refresh）
  static Future<void>? _prepareBackendInFlight;

  /// 預熱專用 Dio，可重用連線
  static Dio? _preheatDio;

  // 請替換成您實際的 Hugging Face Spaces 網址
  final String _apiUrl =
      "https://samlam123-ai-companion.hf.space/v1/chat/voice";
  final String _baseUrl = "https://samlam123-ai-companion.hf.space";

  // 喚醒後端並預熱快取 (解決 Hugging Face Space 冷啟動問題與連線延遲)
  //
  // 優化：只打 `/v1/chat/prepare`（已含喚醒與快取刷新），不再額外打 `/health`，
  // 少一次 RTT 與後端負擔；專用短 Dio 設定 connect/receive，冷啟仍給足等待時間。
  Future<void> prepareBackend({bool forceRefresh = false}) async {
    // 一般預熱：與進行中請求合併，避免重複打 HF
    if (!forceRefresh) {
      final existing = _prepareBackendInFlight;
      if (existing != null) {
        await existing;
        return;
      }
    } else {
      // 儲存日記後需強制刷新：先等上一輪完成，再單獨打一次（不可與上一輪合併掉）
      if (_prepareBackendInFlight != null) {
        await _prepareBackendInFlight;
      }
    }

    final run = _prepareBackendOnce(forceRefresh);
    _prepareBackendInFlight = run;
    try {
      await run;
    } finally {
      if (identical(_prepareBackendInFlight, run)) {
        _prepareBackendInFlight = null;
      }
    }
  }

  Future<void> _prepareBackendOnce(bool forceRefresh) async {
    try {
      debugPrint("嘗試喚醒後端服務並預熱快取...");
      final userId = await AuthService.getUidOrGuest();
      final refreshFlag = forceRefresh ? "true" : "false";
      final url =
          "$_baseUrl/v1/chat/prepare?user_id=$userId&force_refresh=$refreshFlag";

      // 預熱專用：與語音長請求分開；HF 冷啟可能較久，receive 給足
      _preheatDio ??= Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );

      await _preheatDio!.get(url);
      debugPrint("後端服務已喚醒，且快取預熱請求已完成！");
    } catch (e) {
      debugPrint("喚醒後端服務失敗或超時（可能仍在啟動中）: $e");
    }
  }

  Future<void> prepareRealtimeSession() async {
    if (_prepareRealtimeFuture != null) {
      await _prepareRealtimeFuture;
      return;
    }
    _prepareRealtimeFuture = Future.wait([
      prepareBackend(),
      initializeWebSocket(),
      AuthService.getUidOrGuest(),
    ]).then((_) {});
    try {
      await _prepareRealtimeFuture;
      _lastRealtimePreparedAt = DateTime.now();
      _webSocketService.markWarmupReady();
    } finally {
      _prepareRealtimeFuture = null;
    }
  }

  Future<void> ensureRealtimePrepared({
    Duration timeout = const Duration(milliseconds: 1800),
    bool allowBackgroundRetry = true,
  }) async {
    final now = DateTime.now();
    if (_lastRealtimePreparedAt != null &&
        now.difference(_lastRealtimePreparedAt!) < const Duration(minutes: 4)) {
      return;
    }

    try {
      await prepareRealtimeSession().timeout(timeout);
    } catch (e) {
      debugPrint("Realtime prepare timeout/failure, continue with fallback: $e");
      if (allowBackgroundRetry) {
        Future<void>.delayed(const Duration(milliseconds: 200), () async {
          try {
            await prepareRealtimeSession();
          } catch (_) {}
        });
      }
    }
  }

  // 初始化 WebSocket 服務
  Future<void> initializeWebSocket() async {
    await _webSocketService.initialize();
  }

  // 設定回調
  void setWebSocketCallbacks({
    Function(String)? onTextReceived,
    Function(String)? onTranscriptReceived,
    Function(String)? onUserTranscriptReceived,
    Function(bool)? onConnectionChanged,
    Function(double)? onAudioLevel,
    Function()? onInterrupted,
    Function()? onTurnComplete, // New callback
    Function()? onAiSpeakingStarted, // 🆕 新增
    Function()? onAiSpeakingEnded, // 🆕 新增
  }) {
    _webSocketService.onTextReceived = onTextReceived;
    _webSocketService.onTranscriptReceived = onTranscriptReceived;
    _webSocketService.onUserTranscriptReceived = onUserTranscriptReceived;
    _webSocketService.onConnectionChanged = onConnectionChanged;
    _webSocketService.onAudioLevel = onAudioLevel;
    _webSocketService.onInterrupted = onInterrupted;
    _webSocketService.onTurnComplete =
        onTurnComplete; // Pass to WebSocketService
    _webSocketService.onAiSpeakingStarted = onAiSpeakingStarted; // 🆕
    _webSocketService.onAiSpeakingEnded = onAiSpeakingEnded; // 🆕
  }

  void setLivePlaybackGain(double gain) {
    _webSocketService.setPlaybackGain(gain);
  }

  void setUserMute(bool muted) {
    _webSocketService.setUserMute(muted);
  }

  // 連接 WebSocket 並開始串流
  Future<void> startLiveChat({bool enableMicrophone = true}) async {
    await ensureRealtimePrepared(
      timeout: const Duration(milliseconds: 1500),
      allowBackgroundRetry: true,
    );
    final userId = await AuthService.getUidOrGuest();
    await _webSocketService.connect(userId);
    // Only start microphone streaming if enabled
    if (enableMicrophone) {
      await _webSocketService.startAudioStreaming();
    }
  }

  // 停止串流並斷開連接
  Future<void> stopLiveChat() async {
    await _webSocketService.stopAudioStreaming();
  }

  void sendImage(Uint8List bytes) {
    _webSocketService.sendImage(bytes);
  }

  void sendText(String text) {
    _webSocketService.sendText(text);
  }

  void sendSystemUpdate(String text) {
    _webSocketService.sendSystemUpdate(text);
  }

  Future<void> startGeminiLiveOnceCapture() async {
    await _webSocketService.ensurePlayerStarted();
    await _webSocketService.startOneShotCapture();
  }

  Future<Map<String, dynamic>?> stopGeminiLiveOnceAndPlay() async {
    final Uint8List pcm = await _webSocketService.stopOneShotCapture();
    if (pcm.isEmpty) return null;

    try {
      final response = await _dio.post(
        "$_baseUrl/v1/chat/gemini_live_once",
        data: {"audio_base64": base64Encode(pcm), "sample_rate": 16000},
        options: Options(headers: {"Content-Type": "application/json"}),
      );

      if (response.statusCode != 200) return null;
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      if (data["status"] != "success") return null;
      final payload = data["data"];
      if (payload is! Map<String, dynamic>) return null;

      final text = payload["text"]?.toString();
      if (text != null && text.isNotEmpty) {
        _webSocketService.onTextReceived?.call(text);
      }

      final audioBase64 = payload["audio_base64"]?.toString();
      if (audioBase64 == null || audioBase64.isEmpty) return payload;

      final bytes = base64Decode(audioBase64);
      await _webSocketService.playPcmResponse(bytes);
      return payload;
    } catch (e) {
      debugPrint("Gemini Live Once failed: $e");
      return null;
    }
  }

  void disconnectLiveChat() {
    _webSocketService.disconnect();
  }

  Future<Map<String, dynamic>?> analyzePersona(
    String userId,
    List<Map<String, String>> qaList,
  ) async {
    try {
      final idToken = await AuthService.getIdToken();

      var response = await _dio.post(
        "$_baseUrl/v1/persona/analyze",
        data: {"user_id": userId, "qa_list": qaList},
        options: Options(
          headers: {
            "Content-Type": "application/json",
            if (idToken != null) "Authorization": "Bearer $idToken",
          },
        ),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        return response.data['data'];
      }
      return null;
    } catch (e) {
      debugPrint("Persona Analysis failed: $e");
      return null;
    }
  }

  Future<void> startTalking() async {
    if (await _recorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/user_voice.m4a';

      // 開始錄音
      await _recorder.start(const RecordConfig(), path: path);
    }
  }

  Future<Map<String, dynamic>?> stopAndSend() async {
    final path = await _recorder.stop();
    if (path == null) return null;

    final userId = await AuthService.getUidOrGuest();
    final idToken = await AuthService.getIdToken();

    FormData formData = FormData.fromMap({
      "user_id": userId,
      "file": await MultipartFile.fromFile(path, filename: "voice.m4a"),
    });

    try {
      var response = await _dio.post(
        _apiUrl,
        data: formData,
        options: Options(
          headers: idToken != null
              ? {"Authorization": "Bearer $idToken"}
              : null,
        ),
      );
      return response.data['data'];
    } catch (e) {
      debugPrint("上傳失敗: $e");
      return null;
    }
  }

  Future<void> playAudioFromUrl(String url) async {
    try {
      debugPrint('嘗試播放音訊 URL: $url');
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
      debugPrint('音訊播放成功。');
    } catch (e) {
      debugPrint('播放音訊失敗: $e'); // 將 print 改為 debugPrint
    }
  }

  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose();
    disconnectLiveChat();
    _webSocketService.dispose();
  }
}
