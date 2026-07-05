import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cache_service.dart';

String _glbLogTail(String url) {
  try {
    final u = Uri.parse(url);
    if (u.pathSegments.isNotEmpty) {
      return '…/${u.pathSegments.last}';
    }
  } catch (_) {}
  return url.length > 96 ? '${url.substring(0, 93)}...' : url;
}

class GlbModelMetricsService {
  static final Map<String, double> _heightUnitsCache = {};
  static final Map<String, bool> _validityCache = {};
  static final Map<String, ({bool isValid, double? height})> _urlAnalysisCache = {};
  static final Map<String, Future<({bool isValid, double? height})>> _urlAnalysisInFlight = {};

  /// 遠端 GLB：優先從 [CacheService] 磁碟快取讀取（省 Storage egress），否則單次 HTTP。
  static Future<({bool isValid, double? height})> analyzeRemoteGlbUrl(String url) {
    final cached = _urlAnalysisCache[url];
    if (cached != null) {
      debugPrint(
        '[GLB] 度量：記憶體快取命中，略過磁碟／HTTP（${_glbLogTail(url)}）',
      );
      return Future.value(cached);
    }

    return _urlAnalysisInFlight.putIfAbsent(url, () async {
      try {
        Uint8List? bytes = await CacheService().tryReadCachedUrlBytes(url);

        if (bytes != null && !_hasValidGlbHeader(bytes)) {
          debugPrint(
            '[GLB] 度量：本地有快取但 GLB 標頭無效，將 HTTP GET（${_glbLogTail(url)}）',
          );
        }

        if (bytes == null || !_hasValidGlbHeader(bytes)) {
          debugPrint(
            '[GLB] 度量：HTTP GET（會計入 Supabase Storage egress）: ${_glbLogTail(url)}',
          );
          final uri = Uri.parse(url);
          final res = await http.get(uri);
          final ok = res.statusCode >= 200 && res.statusCode < 300;
          if (!ok) {
            final bad = (isValid: false, height: null);
            _urlAnalysisCache[url] = bad;
            _validityCache[url] = false;
            return bad;
          }
          bytes = res.bodyBytes;
        }

        final isValid = _hasValidGlbHeader(bytes);
        double? height;
        if (isValid) {
          height = _estimateHeightUnitsFromGlb(bytes);
        }
        final result = (isValid: isValid, height: height);
        _urlAnalysisCache[url] = result;
        _validityCache[url] = isValid;
        if (height != null) {
          _heightUnitsCache[url] = height;
        }
        return result;
      } catch (e) {
        debugPrint('[GLB] analyze URL failed: $e');
        final result = (isValid: false, height: null);
        _urlAnalysisCache[url] = result;
        _validityCache[url] = false;
        return result;
      } finally {
        _urlAnalysisInFlight.remove(url);
      }
    });
  }

  static Future<double?> estimateHeightUnitsFromUrl(String url) async {
    final r = await analyzeRemoteGlbUrl(url);
    return r.height;
  }

  static Future<bool> isLikelyValidGlbUrl(String url) async {
    final r = await analyzeRemoteGlbUrl(url);
    return r.isValid;
  }

  static Future<bool> isLikelyValidGlbFile(String filePath) async {
    final cached = _validityCache[filePath];
    if (cached != null) return cached;

    try {
      final bytes = await File(filePath).readAsBytes();
      final isValid = _hasValidGlbHeader(bytes);
      _validityCache[filePath] = isValid;
      return isValid;
    } catch (e) {
      debugPrint('[GLB] File validation failed: $e');
      _validityCache[filePath] = false;
      return false;
    }
  }

  /// 從已下載到本機的 GLB 估算模型高度（與 [analyzeRemoteGlbUrl] 相同算法，不發網路）。
  static Future<double?> estimateHeightUnitsFromLocalFile(String filePath) async {
    if (filePath.isEmpty) return null;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final h = _estimateHeightUnitsFromGlb(bytes);
      if (h != null && h > 0) {
        _heightUnitsCache[filePath] = h;
      }
      return h;
    } catch (e) {
      debugPrint('[GLB] local height estimate failed: $e');
      return null;
    }
  }

  static double? _estimateHeightUnitsFromGlb(Uint8List bytes) {
    if (bytes.lengthInBytes < 20) return null;
    final bd = ByteData.sublistView(bytes);

    const magicGlTF = 0x46546C67;
    final magic = bd.getUint32(0, Endian.little);
    if (magic != magicGlTF) return null;

    final length = bd.getUint32(8, Endian.little);
    if (length > bytes.lengthInBytes) return null;

    int offset = 12;
    Map<String, dynamic>? gltf;

    while (offset + 8 <= length) {
      final chunkLength = bd.getUint32(offset, Endian.little);
      final chunkType = bd.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (offset + chunkLength > length) break;

      const chunkTypeJson = 0x4E4F534A;
      if (chunkType == chunkTypeJson) {
        final jsonBytes = bytes.sublist(offset, offset + chunkLength);
        final jsonStr = utf8.decode(jsonBytes);
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          gltf = decoded;
        }
        break;
      }

      offset += chunkLength;
    }

    if (gltf == null) return null;

    final accessorsRaw = gltf['accessors'];
    final meshesRaw = gltf['meshes'];
    final nodesRaw = gltf['nodes'];
    if (accessorsRaw is! List) return null;
    if (meshesRaw is! List) return null;
    if (nodesRaw is! List) return _estimateHeightUnitsFromMeshes(meshesRaw, accessorsRaw);

    final meshBounds = _meshMinMaxY(meshesRaw, accessorsRaw);
    if (meshBounds.isEmpty) {
      return _estimateHeightUnitsFromMeshes(meshesRaw, accessorsRaw);
    }

    final parentByNode = <int, int>{};
    for (var i = 0; i < nodesRaw.length; i++) {
      final n = nodesRaw[i];
      if (n is! Map) continue;
      final children = n['children'];
      if (children is! List) continue;
      for (final c in children) {
        if (c is int) {
          parentByNode[c] = i;
        }
      }
    }

    double? globalMinY;
    double? globalMaxY;

    for (var nodeIndex = 0; nodeIndex < nodesRaw.length; nodeIndex++) {
      final node = nodesRaw[nodeIndex];
      if (node is! Map) continue;

      final meshIndex = node['mesh'];
      if (meshIndex is! int) continue;
      final bounds = meshBounds[meshIndex];
      if (bounds == null) continue;

      if (node.containsKey('matrix') || node.containsKey('rotation')) {
        continue;
      }

      var scaleY = 1.0;
      var translateY = 0.0;

      var current = nodeIndex;
      var hop = 0;
      while (hop < 64) {
        final n = nodesRaw[current];
        if (n is! Map) break;
        if (n.containsKey('matrix') || n.containsKey('rotation')) {
          scaleY = 1.0;
          translateY = 0.0;
          break;
        }
        final t = n['translation'];
        if (t is List && t.length >= 2 && t[1] is num) {
          translateY += (t[1] as num).toDouble();
        }
        final s = n['scale'];
        if (s is List && s.length >= 2 && s[1] is num) {
          scaleY *= (s[1] as num).toDouble();
        }
        final parent = parentByNode[current];
        if (parent == null) break;
        current = parent;
        hop++;
      }

      var minY = translateY + scaleY * bounds.$1;
      var maxY = translateY + scaleY * bounds.$2;
      if (minY > maxY) {
        final tmp = minY;
        minY = maxY;
        maxY = tmp;
      }

      globalMinY = globalMinY == null ? minY : (minY < globalMinY ? minY : globalMinY);
      globalMaxY = globalMaxY == null ? maxY : (maxY > globalMaxY ? maxY : globalMaxY);
    }

    if (globalMinY == null || globalMaxY == null) return null;
    final h = globalMaxY - globalMinY;
    if (h <= 0) return null;
    return h;
  }

  static bool _hasValidGlbHeader(Uint8List bytes) {
    if (bytes.lengthInBytes < 20) return false;
    final bd = ByteData.sublistView(bytes);
    const magicGlTF = 0x46546C67;
    final magic = bd.getUint32(0, Endian.little);
    if (magic != magicGlTF) return false;
    final declaredLength = bd.getUint32(8, Endian.little);
    if (declaredLength <= 0 || declaredLength > bytes.lengthInBytes) {
      return false;
    }
    return true;
  }

  static double? _estimateHeightUnitsFromMeshes(List meshesRaw, List accessorsRaw) {
    double? globalMinY;
    double? globalMaxY;

    for (final mesh in meshesRaw) {
      if (mesh is! Map) continue;
      final primitives = mesh['primitives'];
      if (primitives is! List) continue;

      for (final prim in primitives) {
        if (prim is! Map) continue;
        final attrs = prim['attributes'];
        if (attrs is! Map) continue;
        final posAccessorIndex = attrs['POSITION'];
        if (posAccessorIndex is! int) continue;
        if (posAccessorIndex < 0 || posAccessorIndex >= accessorsRaw.length) continue;

        final accessor = accessorsRaw[posAccessorIndex];
        if (accessor is! Map) continue;
        final minV = accessor['min'];
        final maxV = accessor['max'];
        if (minV is! List || maxV is! List) continue;
        if (minV.length < 2 || maxV.length < 2) continue;

        final minY = (minV[1] as num).toDouble();
        final maxY = (maxV[1] as num).toDouble();

        globalMinY = globalMinY == null ? minY : (minY < globalMinY ? minY : globalMinY);
        globalMaxY = globalMaxY == null ? maxY : (maxY > globalMaxY ? maxY : globalMaxY);
      }
    }

    if (globalMinY == null || globalMaxY == null) return null;
    final h = globalMaxY - globalMinY;
    if (h <= 0) return null;
    return h;
  }

  static Map<int, (double, double)> _meshMinMaxY(List meshesRaw, List accessorsRaw) {
    final out = <int, (double, double)>{};
    for (var meshIndex = 0; meshIndex < meshesRaw.length; meshIndex++) {
      final mesh = meshesRaw[meshIndex];
      if (mesh is! Map) continue;
      final primitives = mesh['primitives'];
      if (primitives is! List) continue;

      double? minY;
      double? maxY;
      for (final prim in primitives) {
        if (prim is! Map) continue;
        final attrs = prim['attributes'];
        if (attrs is! Map) continue;
        final posAccessorIndex = attrs['POSITION'];
        if (posAccessorIndex is! int) continue;
        if (posAccessorIndex < 0 || posAccessorIndex >= accessorsRaw.length) continue;

        final accessor = accessorsRaw[posAccessorIndex];
        if (accessor is! Map) continue;
        final minV = accessor['min'];
        final maxV = accessor['max'];
        if (minV is! List || maxV is! List) continue;
        if (minV.length < 2 || maxV.length < 2) continue;

        final y0 = (minV[1] as num).toDouble();
        final y1 = (maxV[1] as num).toDouble();
        minY = minY == null ? y0 : (y0 < minY ? y0 : minY);
        maxY = maxY == null ? y1 : (y1 > maxY ? y1 : maxY);
      }

      if (minY != null && maxY != null) {
        out[meshIndex] = (minY, maxY);
      }
    }
    return out;
  }
}
