import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<void> initializePermissions() async {
    // Request camera permission for AR functionality
    await Permission.camera.request();
    
    // Request microphone permission for voice interaction
    await Permission.microphone.request();
    
    // Request storage permission for saving models and data
    await Permission.storage.request();
    
    // Request location permission for AR scene understanding
    await Permission.location.request();
    
    // Request notification permission for daily pushes and care messages
    await Permission.notification.request();
  }
  
  static Future<bool> checkCameraPermission() async {
    return await Permission.camera.isGranted;
  }
  
  static Future<bool> checkMicrophonePermission() async {
    return await Permission.microphone.isGranted;
  }
  
  static Future<bool> checkStoragePermission() async {
    return await Permission.storage.isGranted;
  }
  
  static Future<bool> checkLocationPermission() async {
    return await Permission.location.isGranted;
  }
  
  static Future<bool> checkNotificationPermission() async {
    return await Permission.notification.isGranted;
  }
  
  static Future<void> requestAllPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.location,
      Permission.notification,
    ].request();
  }
}
