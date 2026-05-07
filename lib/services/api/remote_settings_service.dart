import 'dart:convert';

import 'package:school_manager/services/api/api_client.dart';

class RemoteSettingsService {
  RemoteSettingsService._();
  static final RemoteSettingsService instance = RemoteSettingsService._();

  /// Retourne tous les paramètres de l'établissement sous forme clé→valeur.
  Future<Map<String, String>> getSettings() async {
    final response = await ApiClient.instance.get('/api/settings');
    if (response.statusCode != 200) {
      throw Exception('Chargement des paramètres échoué (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    }
    return {};
  }

  /// Upsert en batch une map clé→valeur vers le backend.
  Future<void> upsertSettings(Map<String, String> settings) async {
    if (settings.isEmpty) return;
    final response = await ApiClient.instance.put(
      '/api/settings',
      body: settings,
    );
    if (response.statusCode != 200) {
      throw Exception('Sauvegarde des paramètres échouée (${response.statusCode})');
    }
  }
}
