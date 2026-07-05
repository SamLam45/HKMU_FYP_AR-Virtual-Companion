import 'dart:async';
import 'dart:math';

enum VisemeType {
  silence,    // 靜音
  a,          // "ah" 音 - 張大嘴巴
  e,          // "eh" 音 - 中等張開
  i,          // "ih" 音 - 扁平嘴巴
  o,          // "oh" 音 - 圓形嘴巴
  u,          // "uh" 音 - 小圓形嘴巴
  f,          // "f" 音 - 牙齒觸唇
  v,          // "v" 音 - 牙齒觸唇震動
  th,         // "th" 音 - 舌頭伸出
  m,          // "m" 音 - 嘴唇閉合
  p,          // "p" 音 - 嘴唇閉合準備爆破
  b,          // "b" 音 - 嘴唇閉合準備爆破
  t,          // "t" 音 - 舌頭頂住牙齦
  d,          // "d" 音 - 舌頭頂住牙齦
  k,          // "k" 音 - 舌頭後縮
  g,          // "g" 音 - 舌頭後縮
  s,          // "s" 音 - 牙齒接近，氣流通過
  z,          // "z" 音 - 牙齒接近，聲帶震動
  sh,         // "sh" 音 - 嘴唇突出，牙齒接近
  zh,         // "zh" 音 - 嘴唇突出，牙齒接近，聲帶震動
  l,          // "l" 音 - 舌頭頂住牙齦，側邊漏氣
  r,          // "r" 音 - 舌頭捲起
  w,          // "w" 音 - 圓唇，輕微閉合
  y,          // "y" 音 - 嘴唇微笑，牙齒接近
  h,          // "h" 音 - 嘴巴微張，氣流通過
  ng,         // "ng" 音 - 舌頭後縮，鼻腔共鳴
  ee,         // "ee" 音 - 極扁平嘴巴（長e音）
  oo,         // "oo" 音 - 極圓形嘴巴（長o音）
}

class VisemeData {
  final VisemeType type;
  final double intensity;
  final Duration duration;
  final double transitionFactor; // 過渡因子，用於平滑動畫
  final VisemeType? nextViseme; // 下一個口型，用於預測性協同發音

  VisemeData({
    required this.type,
    required this.intensity,
    required this.duration,
    this.transitionFactor = 1.0,
    this.nextViseme,
  });
}

class LipSyncService {
  static final LipSyncService _instance = LipSyncService._internal();
  factory LipSyncService() => _instance;
  LipSyncService._internal();

  final StreamController<List<VisemeData>> _visemeController = 
      StreamController<List<VisemeData>>.broadcast();
  
  Stream<List<VisemeData>> get visemeStream => _visemeController.stream;
  
  Timer? _currentTimer;
  List<VisemeData> _currentVisemes = [];
  int _currentVisemeIndex = 0;

  /// 從文本生成口型數據
  Future<void> generateLipSyncFromText(String text) async {
    _stopCurrentLipSync();
    
    // 將文本轉換為音素
    final phonemes = _textToPhonemes(text);
    
    // 生成口型數據
    _currentVisemes = _phonemesToVisemes(phonemes);
    
    // 開始播放口型動畫
    _playLipSync();
  }

  /// 從音頻文件生成口型數據（模擬）
  Future<void> generateLipSyncFromAudio(String audioPath) async {
    _stopCurrentLipSync();
    
    // 模擬從音頻分析口型
    // 在實際實現中，這裡會使用音頻分析庫
    final simulatedVisemes = _generateSimulatedVisemes();
    _currentVisemes = simulatedVisemes;
    
    _playLipSync();
  }

  /// 停止當前的口型同步
  void stopLipSync() {
    _stopCurrentLipSync();
  }

  void _stopCurrentLipSync() {
    _currentTimer?.cancel();
    _currentTimer = null;
    _currentVisemeIndex = 0;
  }

  void _playLipSync() {
    if (_currentVisemes.isEmpty) return;
    
    _currentVisemeIndex = 0;
    _playNextViseme();
  }

  void _playNextViseme() {
    if (_currentVisemeIndex >= _currentVisemes.length) {
      // 口型動畫結束，發送靜音
      _visemeController.add([VisemeData(
        type: VisemeType.silence,
        intensity: 0.0,
        duration: const Duration(milliseconds: 100),
      )]);
      return;
    }

    final viseme = _currentVisemes[_currentVisemeIndex];
    _visemeController.add([viseme]);
    
    _currentVisemeIndex++;
    
    _currentTimer = Timer(viseme.duration, () {
      _playNextViseme();
    });
  }

  /// 將文本轉換為音素（增強版）
  List<String> _textToPhonemes(String text) {
    final words = text.toLowerCase().trim().split(RegExp(r'\s+'));
    final phonemes = <String>[];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isNotEmpty) {
        phonemes.addAll(_wordToPhonemes(word));

        // 添加單詞間停頓（根據上下文調整長度）
        if (i < words.length - 1) {
          final nextWord = words[i + 1];
          if (_isPunctuation(nextWord)) {
            phonemes.add('long_pause'); // 標點符號前長停頓
          } else {
            phonemes.add(' '); // 普通單詞間停頓
          }
        }
      }
    }

    return phonemes;
  }

  /// 將單詞轉換為音素（增強版）
  List<String> _wordToPhonemes(String word) {
    final phonemes = <String>[];
    final chars = word.split('');

    for (int i = 0; i < chars.length; i++) {
      final char = chars[i];
      final nextChar = i + 1 < chars.length ? chars[i + 1] : '';
      final nextNextChar = i + 2 < chars.length ? chars[i + 2] : '';

      // 處理雙字母組合
      if (_isDigraph(char, nextChar)) {
        phonemes.add(char + nextChar);
        i++; // 跳過下一個字符
        continue;
      }

      // 處理特殊元音組合
      if (_isDiphthong(char, nextChar, nextNextChar)) {
        phonemes.add(char + nextChar + nextNextChar);
        i += 2; // 跳過下兩個字符
        continue;
      }

      // 處理單個字符
      switch (char) {
        case 'a':
          if (nextChar == 'i') {
            phonemes.add('ai');
            i++; // 跳過'i'
          } else {
            phonemes.add('a');
          }
          break;
        case 'e':
          if (nextChar == 'a') {
            phonemes.add('ea');
            i++; // 跳過'a'
          } else {
            phonemes.add('e');
          }
          break;
        case 'i':
          phonemes.add('i');
          break;
        case 'o':
          if (nextChar == 'u') {
            phonemes.add('ou');
            i++; // 跳過'u'
          } else {
            phonemes.add('o');
          }
          break;
        case 'u':
          phonemes.add('u');
          break;
        case 'f':
        case 'v':
        case 'θ': // th
        case 'ð': // th
        case 's':
        case 'z':
        case 'ʃ': // sh
        case 'ʒ': // zh
        case 'h':
          phonemes.add(char);
          break;
        case 'm':
        case 'n':
        case 'ŋ': // ng
          phonemes.add(char);
          break;
        case 'p':
        case 'b':
        case 't':
        case 'd':
        case 'k':
        case 'g':
          phonemes.add(char);
          break;
        case 'l':
        case 'r':
        case 'w':
        case 'j': // y
          phonemes.add(char);
          break;
        default:
          // 跳過未知字符
          break;
      }
    }

    return phonemes;
  }

  /// 檢查是否為雙字母組合
  bool _isDigraph(String char, String nextChar) {
    const digraphs = ['th', 'sh', 'ch', 'ph', 'wh', 'ng', 'gh'];
    return digraphs.contains(char + nextChar);
  }

  /// 檢查是否為雙元音
  bool _isDiphthong(String char, String nextChar, String nextNextChar) {
    // 常見的雙元音組合
    return ['ou', 'oi', 'ea', 'ai', 'au', 'oo'].contains(char + nextChar) ||
           ['igh', 'eigh'].contains(char + nextChar + nextNextChar);
  }

  /// 檢查是否為標點符號
  bool _isPunctuation(String word) {
    return word.contains(RegExp(r'[.!?;:,]'));
  }

  /// 將音素轉換為口型數據（增強版）
  List<VisemeData> _phonemesToVisemes(List<String> phonemes) {
    final visemes = <VisemeData>[];

    for (int i = 0; i < phonemes.length; i++) {
      final phoneme = phonemes[i];

      // 處理停頓
      if (phoneme == ' ' || phoneme == 'long_pause') {
        final duration = _getPhonemeDuration(phoneme);
        visemes.add(VisemeData(
          type: VisemeType.silence,
          intensity: 0.0,
          duration: duration,
          transitionFactor: 0.3, // 緩慢過渡到靜音
        ));
        continue;
      }

      final visemeType = _phonemeToViseme(phoneme);
      final duration = _getPhonemeDuration(phoneme);
      final intensity = _getPhonemeIntensity(phoneme);

      // 計算過渡因子（基於上下文）
      final transitionFactor = _calculateTransitionFactor(i, phonemes);

      // 添加下一個口型的預測信息（用於協同發音）
      final nextViseme = i + 1 < phonemes.length
          ? _phonemeToViseme(phonemes[i + 1])
          : null;

      visemes.add(VisemeData(
        type: visemeType,
        intensity: intensity,
        duration: duration,
        transitionFactor: transitionFactor,
        nextViseme: nextViseme,
      ));
    }

    return visemes;
  }

  /// 計算過渡因子（用於平滑動畫過渡）
  double _calculateTransitionFactor(int currentIndex, List<String> phonemes) {
    if (currentIndex == 0) return 0.8; // 開始較慢

    final prevPhoneme = phonemes[currentIndex - 1];
    final currentPhoneme = phonemes[currentIndex];

    // 如果是相似的音素，增加過渡因子
    if (_areSimilarPhonemes(prevPhoneme, currentPhoneme)) {
      return 0.9; // 平滑過渡
    }

    // 如果是不同的音素，減少過渡因子
    return 0.6; // 快速過渡
  }

  /// 檢查兩個音素是否相似（用於協同發音）
  bool _areSimilarPhonemes(String phoneme1, String phoneme2) {
    // 同類型音素相似
    final vowels = ['a', 'e', 'i', 'o', 'u', 'ɑ', 'ɛ', 'ɪ', 'ɔ', 'ʊ'];
    final fricatives = ['f', 'v', 'θ', 'ð', 's', 'z', 'ʃ', 'ʒ', 'h'];
    final nasals = ['m', 'n', 'ŋ'];
    final plosives = ['p', 'b', 't', 'd', 'k', 'g'];
    final liquids = ['l', 'r'];

    final p1Vowel = vowels.contains(phoneme1);
    final p2Vowel = vowels.contains(phoneme2);
    final p1Fricative = fricatives.contains(phoneme1);
    final p2Fricative = fricatives.contains(phoneme2);
    final p1Nasal = nasals.contains(phoneme1);
    final p2Nasal = nasals.contains(phoneme2);
    final p1Plosive = plosives.contains(phoneme1);
    final p2Plosive = plosives.contains(phoneme2);
    final p1Liquid = liquids.contains(phoneme1);
    final p2Liquid = liquids.contains(phoneme2);

    return (p1Vowel && p2Vowel) ||
           (p1Fricative && p2Fricative) ||
           (p1Nasal && p2Nasal) ||
           (p1Plosive && p2Plosive) ||
           (p1Liquid && p2Liquid);
  }

  /// 音素到口型的映射（增強版）
  VisemeType _phonemeToViseme(String phoneme) {
    switch (phoneme) {
      // 元音
      case 'a':
      case 'ɑ': // ah
      case 'ar':
        return VisemeType.a;
      case 'e':
      case 'ɛ': // eh
      case 'er':
      case 'ea':
        return VisemeType.e;
      case 'i':
      case 'ɪ': // ih
      case 'ir':
        return VisemeType.i;
      case 'o':
      case 'ɔ': // oh
      case 'or':
      case 'ou':
      case 'oi':
        return VisemeType.o;
      case 'u':
      case 'ʊ': // uh
      case 'ur':
      case 'oo':
        return VisemeType.u;

      // 雙元音
      case 'ai':
      case 'au':
        return VisemeType.a; // 使用'a'作為基礎

      // 唇音
      case 'p':
        return VisemeType.p;
      case 'b':
        return VisemeType.b;

      // 舌尖音
      case 't':
        return VisemeType.t;
      case 'd':
        return VisemeType.d;

      // 舌根音
      case 'k':
        return VisemeType.k;
      case 'g':
        return VisemeType.g;

      // 摩擦音
      case 'f':
        return VisemeType.f;
      case 'v':
        return VisemeType.v;
      case 'θ': // th
      case 'ð': // th
        return VisemeType.th;
      case 's':
        return VisemeType.s;
      case 'z':
        return VisemeType.z;
      case 'ʃ': // sh
        return VisemeType.sh;
      case 'ʒ': // zh
        return VisemeType.zh;
      case 'h':
        return VisemeType.h;

      // 鼻音
      case 'm':
        return VisemeType.m;
      case 'n':
        return VisemeType.m; // 將n映射到m，因為外觀相似
      case 'ŋ': // ng
        return VisemeType.ng;

      // 流音
      case 'l':
        return VisemeType.l;
      case 'r':
        return VisemeType.r;

      // 半元音
      case 'w':
        return VisemeType.w;
      case 'j': // y
        return VisemeType.y;

      default:
        return VisemeType.silence;
    }
  }

  /// 獲取音素持續時間（增強版）
  Duration _getPhonemeDuration(String phoneme) {
    switch (phoneme) {
      // 長停頓（標點符號）
      case 'long_pause':
        return const Duration(milliseconds: 400);

      // 短停頓（單詞間）
      case ' ':
        return const Duration(milliseconds: 80);

      // 元音 - 根據自然語音時長調整
      case 'a':
      case 'ɑ': // ah
        return const Duration(milliseconds: 140);
      case 'e':
      case 'ɛ': // eh
        return const Duration(milliseconds: 130);
      case 'i':
      case 'ɪ': // ih
        return const Duration(milliseconds: 120);
      case 'o':
      case 'ɔ': // oh
        return const Duration(milliseconds: 150);
      case 'u':
      case 'ʊ': // uh
        return const Duration(milliseconds: 135);

      // 雙元音 - 稍長
      case 'ai':
      case 'au':
      case 'ou':
      case 'oi':
      case 'ea':
        return const Duration(milliseconds: 180);

      // 摩擦音
      case 'f':
      case 'v':
      case 'θ': // th
      case 'ð': // th
        return const Duration(milliseconds: 110);
      case 's':
      case 'z':
      case 'ʃ': // sh
      case 'ʒ': // zh
        return const Duration(milliseconds: 125);
      case 'h':
        return const Duration(milliseconds: 80);

      // 鼻音
      case 'm':
      case 'n':
      case 'ŋ': // ng
        return const Duration(milliseconds: 95);

      // 塞音（爆破音）
      case 'p':
      case 'b':
      case 't':
      case 'd':
      case 'k':
      case 'g':
        return const Duration(milliseconds: 85);

      // 流音
      case 'l':
        return const Duration(milliseconds: 105);
      case 'r':
        return const Duration(milliseconds: 100);

      // 半元音
      case 'w':
      case 'j': // y
        return const Duration(milliseconds: 85);

      default:
        return const Duration(milliseconds: 100);
    }
  }

  /// 獲取音素強度（增強版）
  double _getPhonemeIntensity(String phoneme) {
    switch (phoneme) {
      // 停頓
      case 'long_pause':
      case ' ':
        return 0.0;

      // 強元音 - 高強度
      case 'a':
      case 'ɑ': // ah
      case 'ɔ': // oh
        return 0.95;

      // 中等元音
      case 'e':
      case 'ɛ': // eh
      case 'i':
      case 'ɪ': // ih
      case 'u':
      case 'ʊ': // uh
        return 0.85;

      // 雙元音 - 變化強度
      case 'ai':
      case 'au':
      case 'ou':
      case 'oi':
      case 'ea':
        return 0.9;

      // 摩擦音 - 根據發音位置調整
      case 'f':
      case 'v':
        return 0.75;
      case 'θ': // th
      case 'ð': // th
        return 0.8;
      case 's':
      case 'z':
        return 0.7;
      case 'ʃ': // sh
      case 'ʒ': // zh
        return 0.75;
      case 'h':
        return 0.6;

      // 鼻音 - 中等強度
      case 'm':
      case 'n':
      case 'ŋ': // ng
        return 0.65;

      // 塞音 - 根據發音位置調整
      case 'p':
      case 'b':
        return 0.7;
      case 't':
      case 'd':
        return 0.75;
      case 'k':
      case 'g':
        return 0.8;

      // 流音 - 較低強度
      case 'l':
        return 0.6;
      case 'r':
        return 0.55;

      // 半元音 - 最低強度
      case 'w':
      case 'j': // y
        return 0.5;

      default:
        return 0.6;
    }
  }

  /// 生成模擬的口型數據（用於測試）
  List<VisemeData> _generateSimulatedVisemes() {
    final visemes = <VisemeData>[];
    final random = Random();
    
    // 生成隨機的口型序列
    final visemeTypes = VisemeType.values;
    for (int i = 0; i < 20; i++) {
      final type = visemeTypes[random.nextInt(visemeTypes.length)];
      final intensity = 0.3 + random.nextDouble() * 0.7;
      final duration = Duration(milliseconds: 80 + random.nextInt(120));
      
      visemes.add(VisemeData(
        type: type,
        intensity: intensity,
        duration: duration,
      ));
    }
    
    return visemes;
  }

  void dispose() {
    _stopCurrentLipSync();
    _visemeController.close();
  }
}
