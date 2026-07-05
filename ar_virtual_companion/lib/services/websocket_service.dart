import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';
import 'package:audio_session/audio_session.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription? _recorderSubscription;
  
  // SoLoud related
  AudioSource? _currentAudioSource;
  SoundHandle? _currentSoundHandle;
  
  bool _isAudioStreaming = false;
  double _playbackGain = 1.0;
  bool _isInitialized = false;
  Future<void>? _initializeFuture;
  
  // 保持一些狀態標記以符合原有介面
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  bool _warmupReady = false;

  Function(String)? onTextReceived;
  Function(String)? onTranscriptReceived;
  Function(String)? onUserTranscriptReceived;
  Function(bool)? onConnectionChanged;
  Function(double)? onAudioLevel;
  Function()? onInterrupted;
  Function()? onTurnComplete; // New callback
  Function()? onAiSpeakingStarted; // 🆕 新增：AI開始說話
  Function()? onAiSpeakingEnded; // 🆕 新增：AI結束說話

  void markWarmupReady() {
    _warmupReady = true;
  }

  // 緩衝設定
  // 為了適應 VoIP 模式，統一使用 24kHz
  static const int _sampleRate = 24000;
  
  // 緩衝區管理
  BytesBuilder? _captureBuilder;
  // 用於處理接收到的奇數 byte，防止 PCM 16-bit 錯位造成靜電噪音
  int? _pendingByte;

  // 處理隊列
  final List<Uint8List> _audioQueue = [];
  bool _isProcessingQueue = false;
  
  // Barge-in debouncing
  int _loudFrameCount = 0;
  static const int _bargeInThreshold = 3; // Number of consecutive loud frames required
  static const double _rmsThreshold = 2000.0; // Higher threshold for barge-in

  Future<void> _processAudioQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_audioQueue.isNotEmpty) {
      if (_currentAudioSource == null) {
        _audioQueue.clear();
        break;
      }

      final data = _audioQueue.removeAt(0);
      try {
        await _playBufferedStream(); 
        final adjusted = _playbackGain == 1.0 ? data : _applyPcm16Gain(data, _playbackGain);
        
        // 關鍵：使用 await 確保數據順序寫入底層 buffer
        // 雖然 addAudioDataStream 可能不是異步的，但在大量數據湧入時，
        // 給予事件循環喘息機會可以避免阻塞或順序問題
        SoLoud.instance.addAudioDataStream(_currentAudioSource!, adjusted);
      } catch (e) {
        debugPrint("Error adding stream data: $e");
      }
      
      // 給予極短暫的讓渡，避免阻塞 UI isolate
      await Future.delayed(Duration.zero);
    }
    _isProcessingQueue = false;
  }


  // 用於控制即時通話的狀態
  bool _isLiveCallActive = false;
  // 控制麥克風靜音狀態 (當 AI 說話時為 true)
  bool _isMicMuted = false;
  // 使用者手動靜音
  bool _isUserMuted = false;

  // AI 說話狀態追蹤
  bool _isAiSpeaking = false;
  DateTime? _expectedAudioEndTime;
  Timer? _speakingTimer;
  bool _pendingTurnComplete = false;

  void setUserMute(bool muted) {
    _isUserMuted = muted;
  }

  void setPlaybackGain(double gain) {
    _playbackGain = gain.clamp(0.0, 2.0);
    if (_currentSoundHandle != null) {
      SoLoud.instance.setVolume(_currentSoundHandle!, _playbackGain);
    }
  }

  void _unmuteMicrophoneForNextTurn() {
    if (_isMicMuted) {
      _isMicMuted = false;
      debugPrint("AI playback finished: Unmuting microphone");
    }
    _pendingTurnComplete = false;
  }

  void _markAiPlaybackStarted() {
    if (_isLiveCallActive && !_isMicMuted) {
      _isMicMuted = true;
      debugPrint("AI speaking: Muting microphone");
    }
    if (!_isAiSpeaking) {
      _pendingTurnComplete = false;
      _isAiSpeaking = true;
      debugPrint("==== [WebSocket] 偵測到 AI 語音，觸發 onAiSpeakingStarted ====");
      onAiSpeakingStarted?.call();
    }
  }

  void _markAiPlaybackEnded() {
    if (_isAiSpeaking) {
      _isAiSpeaking = false;
      _expectedAudioEndTime = null;
      debugPrint("==== [WebSocket] AI 語音播放完畢，觸發 onAiSpeakingEnded ====");
      onAiSpeakingEnded?.call();
    }
  }

  Future<void> _finalizeAiPlaybackTurn() async {
    _markAiPlaybackEnded();
    if (_pendingTurnComplete) {
      await clearAudioBuffer();
      await Future.delayed(const Duration(milliseconds: 350));
      _unmuteMicrophoneForNextTurn();
    }
  }

  Future<void> _handleInterruptedPlayback() async {
    _pendingTurnComplete = false;
    _speakingTimer?.cancel();
    await clearAudioBuffer();
    _markAiPlaybackEnded();
    _unmuteMicrophoneForNextTurn();
  }

  // 清空當前播放緩衝區 (用於插話/打斷)
  Future<void> clearAudioBuffer() async {
    _audioQueue.clear();
    _pendingByte = null;
    _expectedAudioEndTime = null;
    if (_currentAudioSource != null) {
      // SoLoud 目前沒有直接清空 BufferStream 的 API，通常需要 dispose 再重新建立
      // 或者我們可以嘗試停止當前播放
       if (_currentSoundHandle != null) {
         await SoLoud.instance.stop(_currentSoundHandle!);
         _currentSoundHandle = null;
       }
       // 重新建立 Source 以清空積累的緩衝
       await SoLoud.instance.disposeSource(_currentAudioSource!);
       _currentAudioSource = null;
       await _setupAudioSource();
       await _playBufferedStream();
    }
  }

  Uint8List _applyPcm16Gain(Uint8List input, double gain) {
    if (gain == 1.0) return input;
    final out = Uint8List.fromList(input);
    for (var i = 0; i + 1 < out.length; i += 2) {
      var sample = out[i] | (out[i + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      var scaled = (sample * gain).round();
      scaled = scaled.clamp(-32768, 32767);
      final u = scaled & 0xFFFF;
      out[i] = u & 0xFF;
      out[i + 1] = (u >> 8) & 0xFF;
    }
    return out;
  }

  Future<void> ensurePlayerStarted() async {
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
    }
  }

  Future<void> _setupAudioSource() async {
    if (_currentAudioSource != null) return;
    
    try {
      _currentAudioSource = SoLoud.instance.setBufferStream(
        maxBufferSizeBytes: 1024 * 1024 * 2, // 2MB buffer
        sampleRate: _sampleRate,
        channels: Channels.mono,
        format: BufferType.s16le,
        bufferingTimeNeeds: 0.05, // Reduced from 0.2 to 0.05 (50ms) for lower latency
        bufferingType: BufferingType.released,
      );
    } catch (e) {
      debugPrint("Error setting up audio source: $e");
    }
  }

  Future<void> _playBufferedStream() async {
    if (_currentAudioSource == null) return;
    
    try {
      if (_currentSoundHandle == null || !SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
        _currentSoundHandle = await SoLoud.instance.play(_currentAudioSource!);
        SoLoud.instance.setVolume(_currentSoundHandle!, _playbackGain);
      }
    } catch (e) {
      debugPrint("Error playing buffered stream: $e");
    }
  }

  Future<void> startOneShotCapture() async {
    if (_isAudioStreaming) return;
    
    if (!await _recorder.hasPermission()) {
      debugPrint("No microphone permission");
      return;
    }

    _captureBuilder = BytesBuilder(copy: false);
    _isAudioStreaming = true;
    
    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));

      _recorderSubscription = stream.listen((data) {
        _captureBuilder?.add(data);
      });
    } catch (e) {
      _isAudioStreaming = false;
      _captureBuilder = null;
      rethrow;
    }
  }

  Future<Uint8List> stopOneShotCapture() async {
    if (!_isAudioStreaming) return Uint8List(0);
    _isAudioStreaming = false;
    
    await _recorder.stop();
    await _recorderSubscription?.cancel();
    _recorderSubscription = null;
    
    final bytes = _captureBuilder?.takeBytes() ?? Uint8List(0);
    _captureBuilder = null;
    return bytes;
  }

  Future<void> playPcmResponse(Uint8List pcm) async {
    if (pcm.isEmpty) return;
    debugPrint("playPcmResponse input length: ${pcm.length}");

    if (pcm.length % 2 != 0) {
      debugPrint("PCM 長度奇數，已截斷最後 1 byte");
      pcm = pcm.sublist(0, pcm.length - 1);
    }

    await ensurePlayerStarted();
    
    // Create a temporary source for this response
    try {
      // 增加緩衝區大小，避免 pcmBufferFull 錯誤
      // 給予 2 倍長度 + 4KB 的緩衝空間，確保足夠容納 PCM 數據
      final bufferSize = pcm.length * 2 + 4096;

      final source = SoLoud.instance.setBufferStream(
        maxBufferSizeBytes: bufferSize,
        sampleRate: _sampleRate,
        channels: Channels.mono,
        format: BufferType.s16le,
        bufferingTimeNeeds: 0.05, // Reduced to 50ms for lower latency
        bufferingType: BufferingType.released,
      );
      
      final adjusted = _playbackGain == 1.0 ? pcm : _applyPcm16Gain(pcm, _playbackGain);
      try {
        SoLoud.instance.addAudioDataStream(source, adjusted);
      } catch (e) {
        debugPrint("SoLoud addAudioDataStream error: $e");
        await SoLoud.instance.disposeSource(source);
        return;
      }

      SoLoud.instance.setDataIsEnded(source);
      
      await SoLoud.instance.play(source);
      
      // Calculate duration and dispose after playback
      final duration = Duration(milliseconds: (pcm.length * 1000) ~/ (24000 * 2));
      Future.delayed(duration + const Duration(milliseconds: 500), () async {
        try {
          await SoLoud.instance.disposeSource(source);
        } catch (e) {
          debugPrint("Error disposing one-shot source: $e");
        }
      });
    } catch (e) {
      debugPrint("Error playing PCM response: $e");
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initializeFuture != null) {
      await _initializeFuture;
      return;
    }
    _initializeFuture = _initializeInternal();
    try {
      await _initializeFuture;
      _isInitialized = true;
    } finally {
      _initializeFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      // 為了配合 Gemini 24kHz 輸出，我們需要避免 videoChat 模式的強制 16kHz/48kHz 重採樣
      // 使用 voiceChat 模式，可能會有更好的 AEC 效果
      avAudioSessionMode: AVAudioSessionMode.voiceChat, 
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech, 
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication, 
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    await session.setActive(true);

    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init(
        sampleRate: 24000, // 強制 SoLoud 使用 24kHz
        bufferSize: 2048,
        channels: Channels.mono,
      );
    }
    
    debugPrint("音訊初始化完成：SoLoud Initialized / Recorder Ready");
  }

  Future<void> connect(String userId) async {
    if (_isConnected) return;

    try {
      if (!_warmupReady) {
        debugPrint("WebSocket connect before warmup finished; continuing with fallback.");
      }
      final wsUrl = "wss://samlam123-ai-companion.hf.space/v1/chat/live?user_id=$userId";
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      onConnectionChanged?.call(true);

      // 清空隊列
      _audioQueue.clear();
      // 準備音訊播放來源
      await ensurePlayerStarted();
      await _setupAudioSource();

      _channel!.stream.listen(
        (message) {
          if (message is List<int>) {
            Uint8List data = message is Uint8List ? message : Uint8List.fromList(message);
            
            // Debug: Print first 10 bytes in Hex to verify if it's audio or JSON
            if (data.isNotEmpty) {
               final preview = data.take(10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
               debugPrint("Received Binary (${data.length} bytes): $preview");
            }

            // 1. JSON 檢測與過濾
            // 僅在沒有積壓字節時嘗試檢測，避免破壞音訊流
            // 且僅當數據以 '{' (123) 開頭時才嘗試，減少誤判
            if (_pendingByte == null && data.isNotEmpty && data[0] == 123) {
              try {
                final jsonStr = utf8.decode(data);
                debugPrint("Received JSON in Binary Frame: $jsonStr");
                final jsonData = jsonDecode(jsonStr);
                if (jsonData['type'] == 'transcript' && jsonData['text'] != null) {
                  onTranscriptReceived?.call(jsonData['text']);
                  return;
                }
                if (jsonData['type'] == 'user_transcript' && jsonData['text'] != null) {
                  // 移除 _shouldSuppressUserTranscript() 檢查，因為當 AI 說話時麥克風已經靜音，
                  // 此時收到的 user_transcript 其實是 AI 說話前用戶的合法語音轉錄，不應被丟棄。
                  onUserTranscriptReceived?.call(jsonData['text']);
                  return;
                }
                if (jsonData['text'] != null) {
                  onTextReceived?.call(jsonData['text']);
                  return; // 成功解析為 JSON，不作為音訊處理
                }
              } catch (_) {
                // 解析失敗，視為音訊數據繼續處理
                debugPrint("Failed to decode JSON from binary starting with 123. Treating as audio.");
              }
            }

            // 2. 決定是否播放音訊
            // 如果是即時通話 (_isLiveCallActive) -> 播放
            // 如果是閒置狀態 (!_isAudioStreaming) -> 播放
            // 如果是 One-Shot 錄音中 (即 _isAudioStreaming 但非 _isLiveCallActive) -> 不播放 (避免干擾錄音)
            bool shouldPlay = _isLiveCallActive || !_isAudioStreaming;
            
            if (shouldPlay) {
               _markAiPlaybackStarted();

               // 更新預計播放結束時間
               final durationMs = (data.length * 1000) ~/ (24000 * 2);
               final now = DateTime.now();
               if (_expectedAudioEndTime == null || _expectedAudioEndTime!.isBefore(now)) {
                 _expectedAudioEndTime = now.add(Duration(milliseconds: durationMs));
               } else {
                 _expectedAudioEndTime = _expectedAudioEndTime!.add(Duration(milliseconds: durationMs));
               }

               // 設置定時器，在播放結束時觸發 ended 事件
               _speakingTimer?.cancel();
               final timeUntilEnd = _expectedAudioEndTime!.difference(now);
               _speakingTimer = Timer(timeUntilEnd + const Duration(milliseconds: 300), () {
                 unawaited(_finalizeAiPlaybackTurn());
               });

               // 3. 處理 Byte Alignment (關鍵修復：解決靜電噪音)
               if (_pendingByte != null) {
                 final newData = Uint8List(data.length + 1);
                 newData[0] = _pendingByte!;
                 newData.setRange(1, newData.length, data);
                 data = newData;
                 _pendingByte = null;
               }
               
               if (data.length % 2 != 0) {
                 _pendingByte = data[data.length - 1];
                 data = data.sublist(0, data.length - 1);
               }
               
               if (data.isEmpty) return;
               
               // Debug: 打印接收到的數據大小
               // final durationMs = (data.length * 1000) ~/ (24000 * 2);
               // debugPrint("Received ${data.length} bytes audio (approx $durationMs ms)");

               // 4. 加入播放緩衝區 (改用隊列)
               if (_currentAudioSource != null) {
                 _audioQueue.add(data);
                 if (!_isProcessingQueue) {
                   _processAudioQueue();
                 }
               }
            }
          } else if (message is String) {
            try {
              final data = jsonDecode(message);
              if (data['type'] == 'transcript' && data['text'] != null) {
                onTranscriptReceived?.call(data['text']);
              } else if (data['type'] == 'user_transcript' && data['text'] != null) {
                // 移除 _shouldSuppressUserTranscript() 檢查，因為當 AI 說話時麥克風已經靜音，
                // 此時收到的 user_transcript 其實是 AI 說話前用戶的合法語音轉錄，不應被丟棄。
                onUserTranscriptReceived?.call(data['text']);
              } else if (data['text'] != null) {
                onTextReceived?.call(data['text']);
              } else if (data['type'] == 'control' && data['event'] == 'turn_complete') {
                if (_isAiSpeaking) {
                  _pendingTurnComplete = true;
                  debugPrint("AI turn complete: waiting for playback to finish before unmuting microphone");
                } else {
                  _unmuteMicrophoneForNextTurn();
                }
                onTurnComplete?.call(); // Call callback
              } else if (data['type'] == 'control' && data['event'] == 'interrupted') {
                 unawaited(_handleInterruptedPlayback());
                 onInterrupted?.call();
              }
            } catch (e) {
              onTextReceived?.call(message);
            }
          }
        },
        onDone: () {
          debugPrint("WebSocket 正常關閉");
          _disconnectCleanup();
        },
        onError: (error) {
          debugPrint("WebSocket 錯誤: $error");
          _disconnectCleanup();
        },
      );
    } catch (e) {
      debugPrint("WebSocket 連接失敗: $e");
      _disconnectCleanup();
    }
  }

  Future<void> startAudioStreaming() async {
    if (!_isConnected || _channel == null) return;
    
    if (!await _recorder.hasPermission()) {
       debugPrint("Permission denied");
       return;
    }

    // 標記為即時通話模式
    _isLiveCallActive = true;
    _isAudioStreaming = true; // 保持兼容

    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ));

      _recorderSubscription = stream.listen((data) {
        if (_isConnected && _channel != null) {
          // 只有當麥克風未被靜音 (AI 說話) 且 使用者未手動靜音 時才發送音訊
          if (!_isMicMuted && !_isUserMuted) {
            _channel!.sink.add(data);
          }

          double rms = _calculateRMS(data);
          // Only report audio level if mic is not logically muted (i.e. user turn)
          // Normalize RMS (approx max 32768) to 0.0-1.0
          if (!_isMicMuted && !_isUserMuted) {
             onAudioLevel?.call(rms / 32768.0);
          } else {
             onAudioLevel?.call(0.0);
          }
        }
      });
    } catch (e) {
      _isLiveCallActive = false;
      _isAudioStreaming = false;
      rethrow;
    }
  }

  double _calculateRMS(Uint8List data) {
    if (data.isEmpty) return 0.0;
    
    double sumSquare = 0.0;
    // PCM 16-bit, so 2 bytes per sample
    for (int i = 0; i < data.length; i += 2) {
      if (i + 1 >= data.length) break;
      
      // Combine bytes to get 16-bit sample (Little Endian)
      int sample = data[i] | (data[i + 1] << 8);
      
      // Handle signed 16-bit integer conversion
      if (sample >= 0x8000) sample -= 0x10000;
      
      sumSquare += sample * sample;
    }
    
    int sampleCount = data.length ~/ 2;
    if (sampleCount == 0) return 0.0;
    
    return math.sqrt(sumSquare / sampleCount);
  }

  Future<void> stopAudioStreaming() async {
    _isLiveCallActive = false;
    _isAudioStreaming = false;
    _pendingTurnComplete = false;
    await _recorder.stop();
    await _recorderSubscription?.cancel();
    _recorderSubscription = null;
  }

  void sendImage(Uint8List jpegBytes) {
    if (!_isConnected || _channel == null) return;

    final base64Str = base64Encode(jpegBytes);
    final msg = {
      "type": "image",
      "data": base64Str,
      "mime_type": "image/jpeg"
    };

    _channel!.sink.add(jsonEncode(msg));
  }

  void sendText(String text) {
    if (!_isConnected || _channel == null) return;
    final msg = {"type": "text_input", "text": text};
    _channel!.sink.add(jsonEncode(msg));
  }

  void sendSystemUpdate(String text) {
    if (!_isConnected || _channel == null) return;
    final msg = {"type": "system_update", "text": text};
    _channel!.sink.add(jsonEncode(msg));
  }

  void disconnect() {
    _channel?.sink.close();
    _disconnectCleanup();
  }

  Future<void> dispose() async {
    disconnect();
    _recorder.dispose();
    if (_currentAudioSource != null) {
       await SoLoud.instance.disposeSource(_currentAudioSource!);
       _currentAudioSource = null;
    }
    // 注意：SoLoud 實例通常是全域的，如果在其他地方也用到，這裡 deinit 可能會影響其他功能。
    // 但此 Service 似乎是主要的音訊使用者。
    if (SoLoud.instance.isInitialized) {
      SoLoud.instance.deinit();
    }
    _isInitialized = false;
    debugPrint("WebSocketService 資源已釋放");
  }

  void _disconnectCleanup() {
    _isConnected = false;
    _warmupReady = false;
    _isMicMuted = false; // Reset mute state
    _pendingTurnComplete = false;
    _pendingByte = null;
    _audioQueue.clear();
    
    _speakingTimer?.cancel();
    _markAiPlaybackEnded();
    
    // 停止播放但不一定要釋放 Source，視需求而定
    if (_currentSoundHandle != null) {
      SoLoud.instance.stop(_currentSoundHandle!);
      _currentSoundHandle = null;
    }
    
    // 清空緩衝區 (SoLoud 沒有直接清空的方法，可能需要重新建立 Source)
    if (_currentAudioSource != null) {
      SoLoud.instance.disposeSource(_currentAudioSource!);
      _currentAudioSource = null;
    }

    stopAudioStreaming();
    onConnectionChanged?.call(false);
  }
}
