import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

enum DetectedObjectType {
  chair, // 椅子
  sofa, // 沙發
  bed, // 床
  couch, // 沙發
  stool, // 凳子
  bench, // 長凳
  table, // 桌子
  person, // 人
  unknown, // 未知
}

class DetectedObject {
  final DetectedObjectType type;
  final String label;
  final double confidence;
  final DateTime detectedAt;

  DetectedObject({
    required this.type,
    required this.label,
    required this.confidence,
    required this.detectedAt,
  });
}

class ObjectDetectionService {
  ObjectDetector? _objectDetector;
  final StreamController<DetectedObject?> _detectionController =
      StreamController<DetectedObject?>.broadcast();

  Stream<DetectedObject?> get detectionStream => _detectionController.stream;

  Timer? _detectionTimer;
  DetectedObject? _lastDetection;
  bool _isInitialized = false;

  ObjectDetectionService();

  /// 初始化物體檢測
  Future<bool> initialize() async {
    try {
      // 修正：使用較新的配置方式，避免缺少 modelPath 錯誤
      final options = ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: true,
        multipleObjects: true,
      );

      _objectDetector = ObjectDetector(options: options);
      _isInitialized = true;
      return true;
    } catch (e) {
      print('物體檢測初始化失敗: $e');
      return false;
    }
  }

  /// 從相機幀檢測物體
  Future<DetectedObject?> detectFromCameraImage(CameraImage cameraImage) async {
    if (!_isInitialized || _objectDetector == null) {
      debugPrint('[物體檢測] 未初始化');
      return null;
    }

    try {
      // 將 CameraImage 轉換為 InputImage
      final inputImage = _convertCameraImageToInputImage(cameraImage);
      if (inputImage == null) {
        debugPrint('[物體檢測] 圖像轉換失敗');
        return null;
      }

      // 運行物體檢測
      final objects = await _objectDetector!.processImage(inputImage);

      if (objects.isEmpty) {
        if (_lastDetection != null) {
          _lastDetection = null;
          _detectionController.add(null);
        }
        return null;
      }

      // 找到最高可信度的檢測（取第一個檢測對象）
      final highestConfidence = objects.first;

      // 檢查標籤是否存在
      if (highestConfidence.labels.isEmpty) {
        return null;
      }

      final label = highestConfidence.labels.first;
      final labelText = _getLabelText(label);
      final confidence = label.confidence; // 🆕 獲取真實置信度

      // 將檢測結果轉換為我們的對象類型
      final detectedType = _classifyObject(
        highestConfidence.labels,
        confidence,
      );

      _lastDetection = DetectedObject(
        type: detectedType,
        label: labelText,
        confidence: confidence,
        detectedAt: DateTime.now(),
      );

      debugPrint('[物體檢測] 成功: $labelText ($confidence) -> $detectedType');

      _detectionController.add(_lastDetection);
      return _lastDetection;
    } catch (e) {
      debugPrint('[物體檢測] 錯誤: $e');
      return null;
    }
  }

  Future<DetectedObject?> detectFromFilePath(String filePath) async {
    if (!_isInitialized || _objectDetector == null) {
      debugPrint('[物體檢測] 未初始化');
      return null;
    }

    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final objects = await _objectDetector!.processImage(inputImage);

      if (objects.isEmpty) {
        if (_lastDetection != null) {
          _lastDetection = null;
          _detectionController.add(null);
        }
        return null;
      }

      final highestConfidence = objects.first;
      if (highestConfidence.labels.isEmpty) {
        return null;
      }

      final label = highestConfidence.labels.first;
      final labelText = _getLabelText(label);
      final confidence = label.confidence;

      final detectedType = _classifyObject(
        highestConfidence.labels,
        confidence,
      );

      _lastDetection = DetectedObject(
        type: detectedType,
        label: labelText,
        confidence: confidence,
        detectedAt: DateTime.now(),
      );

      debugPrint('[物體檢測] 成功: $labelText ($confidence) -> $detectedType');
      _detectionController.add(_lastDetection);
      return _lastDetection;
    } catch (e) {
      debugPrint('[物體檢測] 錯誤: $e');
      return null;
    }
  }

  /// 開始連續檢測 (用於實時監測)
  void startContinuousDetection(
    Future<CameraImage?> Function() getCameraImage, {
    Duration interval = const Duration(milliseconds: 500),
  }) {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(interval, (_) async {
      try {
        final image = await getCameraImage();
        if (image != null) {
          await detectFromCameraImage(image);
        } else {
          // debugPrint('[物體檢測] 無法獲取相機圖像');
        }
      } catch (e) {
        debugPrint('[物體檢測] 連續檢測錯誤: $e');
      }
    });
  }

  void startContinuousFileDetection(
    Future<String?> Function() getImagePath, {
    Duration interval = const Duration(seconds: 2),
  }) {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(interval, (_) async {
      try {
        final path = await getImagePath();
        if (path == null || path.isEmpty) return;
        await detectFromFilePath(path);
      } catch (e) {
        debugPrint('[物體檢測] 連續檢測錯誤: $e');
      }
    });
  }

  /// 停止連續檢測
  void stopContinuousDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = null;
  }

  /// 獲取最後的檢測結果
  DetectedObject? get lastDetection => _lastDetection;

  /// 檢查是否檢測到坐著的物體
  bool isSeatingObjectDetected() {
    if (_lastDetection == null) return false;

    return [
      DetectedObjectType.chair,
      DetectedObjectType.sofa,
      DetectedObjectType.couch,
      DetectedObjectType.stool,
      DetectedObjectType.bench,
      DetectedObjectType.bed,
    ].contains(_lastDetection!.type);
  }

  /// 設置檢測信心閾值 (預設 0.5)
  double confidenceThreshold = 0.5;

  /// 清理資源
  void dispose() {
    _detectionTimer?.cancel();
    _objectDetector?.close();
    _detectionController.close();
    _isInitialized = false;
  }

  // === 私有方法 ===

  /// 將 CameraImage 轉換為 InputImage
  InputImage? _convertCameraImageToInputImage(CameraImage cameraImage) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageRotation = InputImageRotation.rotation0deg; // 這裡可以根據傳感器方向動態調整

      final inputImageFormat = Platform.isAndroid
          ? InputImageFormat.nv21
          : InputImageFormat.bgra8888;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: cameraImage.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('[物體檢測] 圖像轉換失敗: $e');
      return null;
    }
  }

  /// 連接攝像頭平面數據
  Uint8List _concatenatePlanes(List<Plane> planes) {
    final int totalSize = planes.fold(
      0,
      (prev, plane) => prev + plane.bytes.length,
    );
    final Uint8List concatenated = Uint8List(totalSize);
    int offset = 0;
    for (final Plane plane in planes) {
      concatenated.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }
    return concatenated;
  }

  /// 分類檢測到的物體
  DetectedObjectType _classifyObject(List<Label> labels, double confidence) {
    if (confidence < confidenceThreshold) {
      return DetectedObjectType.unknown;
    }

    if (labels.isEmpty) return DetectedObjectType.unknown;

    final label = _getLabelText(labels.first).toLowerCase();

    // 椅子相關詞彙
    if (label.contains('chair') ||
        label.contains('seat') ||
        label.contains('stool')) {
      return DetectedObjectType.chair;
    }

    // 沙發相關詞彙
    if (label.contains('sofa') ||
        label.contains('couch') ||
        label.contains('divan')) {
      return DetectedObjectType.sofa;
    }

    // 床相關詞彙
    if (label.contains('bed')) {
      return DetectedObjectType.bed;
    }

    // 長凳相關詞彙
    if (label.contains('bench') || label.contains('pew')) {
      return DetectedObjectType.bench;
    }

    // 人相關詞彙
    if (label.contains('person') || label.contains('human')) {
      return DetectedObjectType.person;
    }

    return DetectedObjectType.unknown;
  }

  /// 從檢測標籤獲取標籤文本
  String _getLabelFromDetection(List<Label> labels) {
    if (labels.isEmpty) return 'Unknown';
    return _getLabelText(labels.first);
  }

  /// 獲取標籤文本（處理不同的 API 版本）
  String _getLabelText(Label label) {
    // 嘗試不同的屬性名稱，以適應不同版本的 google_mlkit_object_detection
    try {
      // 首先嘗試 .text 屬性（較新版本）
      return (label as dynamic).text?.toString() ?? 'Unknown';
    } catch (e) {
      try {
        // 嘗試 .label 屬性
        return (label as dynamic).label?.toString() ?? 'Unknown';
      } catch (e2) {
        return label.toString();
      }
    }
  }
}
