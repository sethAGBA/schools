import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Result returned by [DirectoryHelper.pickDirectory].
class DirectorySelectionResult {
  DirectorySelectionResult({
    required this.path,
    this.usedFallback = false,
    this.errorMessage,
  });

  /// Absolute path selected by the user or from the fallback strategy.
  final String? path;

  /// Indicates that the platform file picker failed and a fallback directory was used.
  final bool usedFallback;

  /// Optional human readable error that explains why the picker failed.
  final String? errorMessage;

  bool get hasPath => path != null && path!.isNotEmpty;
}

class DirectoryHelper {
  const DirectoryHelper._();

  /// Opens a directory picker. If the platform picker cannot be displayed, a fallback
  /// directory (e.g. Downloads or Documents) is returned instead.
  static Future<DirectorySelectionResult> pickDirectory({
    String? dialogTitle,
  }) async {
    try {
      final directoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
        // macOS requires the picker window to stay attached to avoid crashes.
        lockParentWindow: !kIsWeb && Platform.isMacOS,
      );
      return DirectorySelectionResult(path: directoryPath);
    } catch (_) {
      final fallback = await _resolveFallbackDirectory();
      final fallbackPath = fallback?.path;
      return DirectorySelectionResult(
        path: fallbackPath,
        usedFallback: true,
        errorMessage: fallbackPath != null
            ? "Fenêtre de sélection indisponible. Utilisation du dossier $fallbackPath."
            : "Impossible de déterminer un dossier de sauvegarde par défaut.",
      );
    }
  }

  static Future<Directory?> _resolveFallbackDirectory() async {
    try {
      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          return downloads;
        }
      }
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }
}
