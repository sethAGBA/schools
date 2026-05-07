import 'dart:convert';

import 'package:school_manager/models/category.dart';
import 'package:school_manager/services/api/api_client.dart';

class RemoteCategoriesService {
  RemoteCategoriesService._();
  static final RemoteCategoriesService instance = RemoteCategoriesService._();

  Future<List<Category>> listCategories() async {
    final response = await ApiClient.instance.get('/api/categories');
    if (response.statusCode != 200) {
      throw Exception('Chargement des catégories échoué (${response.statusCode})');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.cast<Map<String, dynamic>>().map(_fromApi).toList();
  }

  Future<Category> createCategory(Category c) async {
    final response = await ApiClient.instance.post(
      '/api/categories',
      body: _toPayload(c),
    );
    if (response.statusCode != 201) {
      throw Exception('Création de catégorie échouée (${response.statusCode})');
    }
    return _fromApi(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Category> updateCategory(Category c) async {
    final response = await ApiClient.instance.put(
      '/api/categories/${Uri.encodeComponent(c.id)}',
      body: _toPayload(c),
    );
    if (response.statusCode != 200) {
      throw Exception('Mise à jour de catégorie échouée (${response.statusCode})');
    }
    return _fromApi(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteCategory(String id) async {
    final response = await ApiClient.instance.delete(
      '/api/categories/${Uri.encodeComponent(id)}',
    );
    if (response.statusCode != 204) {
      throw Exception('Suppression de catégorie échouée (${response.statusCode})');
    }
  }

  Category _fromApi(Map<String, dynamic> json) {
    return Category(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      color: json['color']?.toString() ?? '#6366F1',
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> _toPayload(Category c) => {
    'name': c.name.trim(),
    'description': c.description?.trim(),
    'color': c.color,
    'order': c.order,
  };
}
