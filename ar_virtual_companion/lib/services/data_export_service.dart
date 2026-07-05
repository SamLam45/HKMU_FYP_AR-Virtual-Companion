import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/personality_model.dart';
import '../models/ai_character.dart';

class DataExportResult {
  final String filePath;
  final int bytesWritten;

  const DataExportResult({
    required this.filePath,
    required this.bytesWritten,
  });
}

class DataExportService {
  /// Exports user data to a JSON file and returns the saved path.
  ///
  /// Notes:
  /// - Conversation history is not persisted in this project yet (Memory screen uses demo data),
  ///   so `conversations` will be empty until persistence is implemented.
  Future<DataExportResult> exportAll({
    required PersonalityProfile personality,
    AICharacter? character,
  }) async {
    final now = DateTime.now().toUtc();

    final exportPayload = <String, dynamic>{
      'schemaVersion': 1,
      'exportedAt': now.toIso8601String(),
      'platform': _platformString(),
      'personalityProfile': personality.toJson(),
      'aiCharacter': character == null ? null : _characterToJson(character),
      'conversations': <dynamic>[],
    };

    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(exportPayload));
    final targetDir = await _getBestExportDirectory();
    await targetDir.create(recursive: true);

    final safeName = _safeFilename(personality.characterName.isEmpty ? 'character' : personality.characterName);
    final filename = 'ar_ai_girl_friend_export_${safeName}_${now.toIso8601String().replaceAll(':', '-')}.json';
    final filePath = p.join(targetDir.path, filename);

    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    return DataExportResult(
      filePath: filePath,
      bytesWritten: bytes.length,
    );
  }

  Map<String, dynamic> _characterToJson(AICharacter character) {
    return {
      'name': character.name,
      'personality': character.personality,
      'emotionalState': character.emotionalState.name,
      'voiceSettings': {
        'pitch': character.voiceSettings.pitch,
        'rate': character.voiceSettings.rate,
        'volume': character.voiceSettings.volume,
      },
      'createdAt': character.createdAt.toIso8601String(),
      'lastInteraction': character.lastInteraction.toIso8601String(),
    };
  }

  String _platformString() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  String _safeFilename(String input) {
    // Keep letters/numbers/underscore/dash; replace everything else.
    final cleaned = input.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_').trim();
    return cleaned.isEmpty ? 'export' : cleaned;
  }

  Future<Directory> _getBestExportDirectory() async {
    if (kIsWeb) {
      // Web file saving requires browser APIs; fall back to app documents to avoid crashes.
      return getApplicationDocumentsDirectory();
    }

    // Prefer Downloads on desktop platforms when available.
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {}

    // On Android, external storage directory is typically more user-accessible.
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) return ext;
      } catch (_) {}
    }

    return getApplicationDocumentsDirectory();
  }
}

