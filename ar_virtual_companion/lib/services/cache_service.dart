import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

String _cacheUrlTail(String url) {
  try {
    final u = Uri.parse(url);
    if (u.pathSegments.isNotEmpty) {
      return '…/${u.pathSegments.last}';
    }
  } catch (_) {}
  return url.length > 96 ? '${url.substring(0, 93)}...' : url;
}

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;

  // 自定義 CacheManager，設定快取有效期為 10 年
  static final CacheManager _customCacheManager = CacheManager(
    Config(
      'customModelCache', // 快取鍵
      stalePeriod: const Duration(days: 365 * 10), // 10 年有效期
      maxNrOfCacheObjects: 100, // 最多快取 100 個模型
    ),
  );

  CacheService._internal();

  /// 僅讀本地已有快取（不發網路）：與 [getLocalPath] 相同來源之 `customModelCache`，
  /// 以及 `Documents/models/*_${url.hashCode}.glb`。
  Future<Uint8List?> tryReadCachedUrlBytes(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return null;
    try {
      final fileInfo = await _customCacheManager.getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        debugPrint(
          '[CacheService] 快取命中（flutter_cache），略過網路讀取: ${_cacheUrlTail(url)}',
        );
        return fileInfo.file.readAsBytes();
      }
    } catch (e) {
      debugPrint('[CacheService] tryReadCachedUrlBytes cache: $e');
    }
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(docDir.path, 'models'));
      if (!await modelsDir.exists()) return null;
      final suffix = '_${url.hashCode}.glb';
      await for (final entity in modelsDir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (p.basename(entity.path).endsWith(suffix)) {
          debugPrint(
            '[CacheService] 快取命中（Documents/models），略過網路讀取: ${_cacheUrlTail(url)}',
          );
          return entity.readAsBytes();
        }
      }
    } catch (e) {
      debugPrint('[CacheService] tryReadCachedUrlBytes models: $e');
    }
    return null;
  }

  /// 獲取模型的本地快取路徑（相對於 Documents 目錄）。
  ///
  /// 這解決了 AR 插件在 Android 上無法加載絕對路徑的問題。
  Future<String?> getLocalPath(String url) async {
    if (url.isEmpty || !url.startsWith('http')) {
      debugPrint('[CacheService] 無效的 URL: $url');
      return null;
    }

    try {
      // 獲取應用程式的 Documents 目錄
      final docDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(docDir.path, 'models'));
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      // 檢查快取中是否已有該檔案
      final fileInfo = await _customCacheManager.getFileFromCache(url);
      final File sourceFile;
      if (fileInfo != null && await fileInfo.file.exists()) {
        debugPrint(
          '[CacheService] 快取命中，略過下載（getLocalPath）: ${_cacheUrlTail(url)}',
        );
        sourceFile = fileInfo.file;
      } else {
        debugPrint(
          '[CacheService] 快取未命中，開始下載（會佔用 Storage egress）: ${_cacheUrlTail(url)}',
        );
        sourceFile = await _customCacheManager.getSingleFile(url);
      }

      if (await sourceFile.exists()) {
        // 使用 URL 的 MD5 或檔案名作為固定名稱，確保擴展名為 .glb
        final fileName = '${sourceFile.uri.pathSegments.last.split('.').first}_${url.hashCode}.glb';
        final permanentFile = File(p.join(modelsDir.path, fileName));

        // 如果永久檔案不存在，或者大小不一致，則從快取複製過來
        if (!await permanentFile.exists() || 
            await permanentFile.length() != await sourceFile.length()) {
          await sourceFile.copy(permanentFile.path);
          debugPrint('[CacheService] 模型已儲存至永久目錄: ${permanentFile.path}');
        }

        // 返回相對於 Documents 目錄的相對路徑
        // 例如: 'models/idle_12345.glb'
        return p.join('models', fileName);
      }
      return null;
    } catch (e) {
      debugPrint('[CacheService] 處理 URL 時發生錯誤: $url, 錯誤: $e');
      return null;
    }
  }

  /// 預先快取一組模型 URL。
  ///
  /// 這個方法會並行下載所有指定的 URL，並將它們存入快取。
  /// 這對於預先加載 idle, sitting, walking 等相關模型非常有用。
  Future<void> precacheModels(List<String> urls) async {
    final validUrls = urls.where((url) => url.isNotEmpty && url.startsWith('http')).toList();
    if (validUrls.isEmpty) return;

    debugPrint('[CacheService] 開始預先快取 ${validUrls.length} 個模型...');
    final futures = validUrls.map((url) => getLocalPath(url).catchError((_) => null));
    await Future.wait(futures);
    debugPrint('[CacheService] 模型預快取完成。');
  }

  /// 檢查本地檔案是否存在。
  ///
  /// 如果檔案不存在，會嘗試從快取中移除並重新下載。
  Future<String?> validateAndGetPath(String url) async {
    final relativePath = await getLocalPath(url);
    if (relativePath == null) return null;

    final docDir = await getApplicationDocumentsDirectory();
    final fullPath = p.join(docDir.path, relativePath);

    if (await File(fullPath).exists()) {
      return relativePath;
    } else {
      debugPrint('[CacheService] 檔案驗證失敗，嘗試重新下載: $url');
      await _customCacheManager.removeFile(url);
      return await getLocalPath(url);
    }
  }
}
