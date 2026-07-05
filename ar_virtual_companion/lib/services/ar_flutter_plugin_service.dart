import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class ARFlutterPluginService {
  // 保留狀態追蹤，確保與你現有的 Screen 邏輯相容
  static bool _isARInitialized = false;
  static String _currentAnimationName = '';

  static Function(String)? onARInitialized;
  static Function(String)? onARError;
  static Function(String)? onAnimationChanged; // 新增：動畫切換回調

  /// 初始化
  static Future<bool> initializeAR() async {
    // model_viewer 本身不需要繁瑣的初始化，這裡模擬成功狀態
    _isARInitialized = true;
    onARInitialized?.call('AR 環境準備就緒');
    return true;
  }

  /// 創建 3D 模型視圖 (取代原本的 ARView)
  /// 只要設定 autoPlay: true 並指定 animationName，模型進場就不會是 T-Pose
  static Widget createARView({
    required Function() onARViewCreated,
    required Function(String) onError,
    String modelPath = 'assets/models/idle.glb',
    String? animationName, // 傳入你在 gltf-viewer 看到的名稱，例如 "mixamo.com"
    Stream<String>? animationChangeStream, // 新增：監聽動畫變化流
  }) {
    // 透過 PostFrameCallback 通知視圖已創建
    WidgetsBinding.instance.addPostFrameCallback((_) => onARViewCreated());

    return StreamBuilder<String>(
      stream: animationChangeStream,
      initialData: animationName ?? '',
      builder: (context, snapshot) {
        final currentAnimation = snapshot.data ?? animationName ?? '';
        _currentAnimationName = currentAnimation;

        return ModelViewer(
          backgroundColor: Colors.transparent, // 設為透明以顯示相機背景
          src: modelPath,
          alt: "AR Partner",
          autoPlay: true, // 關鍵：讓動作自動跑起來
          animationName: currentAnimation.isEmpty
              ? animationName
              : currentAnimation, // 動態動畫名稱
          ar: false, // 如果你只是要疊加在畫面上，設為 false 較穩定
          autoRotate: false, // 避免角色自己轉圈
          cameraControls: true, // 允許使用者手動調整角度
          interactionPrompt: InteractionPrompt.none, // 隱藏手指引導動畫
          cameraOrbit: "0deg 75deg 105%", // 調整攝影機視角，確保角色在畫面中心
          exposure: 1.0, // 調整亮度
          shadowIntensity: 1.0, // 開啟陰影增強真實感
        );
      },
    );
  }

  /// 更新動畫名稱 (用於從其他服務調用)
  static void updateAnimationName(String animationName) {
    if (_currentAnimationName != animationName) {
      _currentAnimationName = animationName;
      onAnimationChanged?.call(animationName);
    }
  }

  /// 獲取當前動畫名稱
  static String getCurrentAnimationName() => _currentAnimationName;

  /// 拍照功能 (model_viewer 無法直接使用 snapshot，建議透過 RepaintBoundary)
  static Future<void> capturePhoto() async {
    debugPrint("ModelViewer 拍照需透過 RepaintBoundary 實現");
  }

  static void reset() {
    // 清理邏輯
    _currentAnimationName = '';
  }

  static void dispose() {
    _isARInitialized = false;
    _currentAnimationName = '';
  }
}
