import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/item.dart';

/// `public.items` tablosu için CRUD + hybrid search.
/// RLS sayesinde her kullanıcı sadece kendi satırlarını görür.
class ItemRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<Item>> list({int limit = 50, int offset = 0}) async {
    if (_userId == null) return [];
    final rows = await _client
        .from('items')
        .select()
        .eq('user_id', _userId!)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(Item.fromJson).toList();
  }

  Future<Item> add({
    required String title,
    String? content,
    String? url,
    String? note,
    List<String> tags = const [],
    List<double>? embedding,
    bool embeddingIsFallback = false,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Oturum açılmamış');
    final row = await _client
        .from('items')
        .insert({
          'user_id': userId,
          'title': title,
          'content': content,
          'url': url,
          'note': note,
          'tags': tags,
          if (embedding != null) 'embedding': embedding,
          if (embedding != null) 'embedding_is_fallback': embeddingIsFallback,
        })
        .select()
        .single();
    return Item.fromJson(row);
  }

  Future<void> update(
    String id, {
    String? title,
    List<String>? tags,
    List<double>? embedding,
    bool? embeddingIsFallback,
  }) async {
    final data = <String, dynamic>{
      if (title != null) 'title': title,
      if (tags != null) 'tags': tags,
      if (embedding != null) 'embedding': embedding,
      if (embeddingIsFallback != null)
        'embedding_is_fallback': embeddingIsFallback,
    };
    if (data.isEmpty) return;
    await _client.from('items').update(data).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('items').delete().eq('id', id);
  }

  /// Aynı URL daha önce kaydedildi mi?
  Future<bool> existsUrl(String url) async {
    if (_userId == null || url.isEmpty) return false;
    final row = await _client
        .from('items')
        .select('id')
        .eq('user_id', _userId!)
        .eq('url', url)
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  /// Full-text + semantik arama, Reciprocal Rank Fusion ile birleştirilir.
  /// [queryEmbedding] yoksa sadece full-text sonuçları döner.
  Future<List<Item>> hybridSearch(
    String query, {
    List<double>? queryEmbedding,
    int matchCount = 20,
  }) async {
    final userId = _userId;
    if (userId == null || query.trim().isEmpty) return [];
    final rows = await _client.rpc('hybrid_search_items', params: {
      'query_text': query.trim(),
      'query_embedding': queryEmbedding,
      'match_user_id': userId,
      'match_count': matchCount,
    });
    return (rows as List<dynamic>)
        .map((e) => Item.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
