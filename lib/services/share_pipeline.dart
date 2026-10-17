import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../config.dart';
import 'ai_service.dart';
import 'embedding_service.dart';
import 'item_repository.dart';
import 'share_service.dart';

/// Paylaşılan bir içeriği uygulama verisine dönüştüren örnek akış.
///
/// 1. Hemen minimal veriyle kaydet (kullanıcı beklemez).
/// 2. AI etiketleme + embedding arka planda çalışır, sonra kayda eklenir.
///
/// Yeni uygulamada asıl iş mantığın buraya gelir.
class SharePipeline {
  SharePipeline({
    ItemRepository? repository,
    AiService? ai,
    EmbeddingService? embedding,
  })  : _repo = repository ?? ItemRepository(),
        _ai = ai ??
            AiService(
              groqApiKey: AppConfig.groqApiKey,
              openRouterApiKey: AppConfig.openRouterApiKey,
            ),
        _embedding = embedding ??
            EmbeddingService(
              apiKey: AppConfig.googleApiKey,
              openRouterApiKey: AppConfig.openRouterApiKey,
            );

  final ItemRepository _repo;
  final AiService _ai;
  final EmbeddingService _embedding;

  /// [ShareService.processQueue] için handler. true = işlendi, kuyruktan sil.
  Future<bool> handle(SharePayload payload, {String locale = 'en'}) async {
    try {
      if (payload.hasUrl && await _repo.existsUrl(payload.url)) return true;

      final item = await _repo.add(
        title: _initialTitle(payload),
        content: payload.text.isEmpty ? null : payload.text,
        url: payload.hasUrl ? payload.url : null,
        note: payload.note.isEmpty ? null : payload.note,
      );

      unawaited(_enrich(item.id, payload, locale));
      return true;
    } catch (e) {
      // İnternet yok vb. — false dönünce bir sonraki açılışta tekrar denenir.
      debugPrint('SharePipeline: $e');
      return false;
    }
  }

  Future<void> _enrich(String itemId, SharePayload payload, String locale) async {
    final source = [
      if (payload.note.isNotEmpty) payload.note,
      if (payload.text.isNotEmpty) payload.text,
      if (payload.hasUrl) payload.url,
    ].join('\n');
    if (source.isEmpty) return;

    final excerpt = source.length > 1500 ? source.substring(0, 1500) : source;

    final json = await _ai.completeJson(
      'Content:\n"""\n$excerpt\n"""\n\n'
      'Return a JSON object: {"title": "<max 8 words>", '
      '"tags": ["<2-5 short lowercase tags>"]}',
      system: 'You label saved content. ${AiService.languageInstruction(locale)} '
          'Output JSON only.',
    );

    final title = json?['title']?.toString().trim();
    final tags = (json?['tags'] as List<dynamic>?)
        ?.map((e) => e.toString().trim())
        .where((t) => t.isNotEmpty)
        .take(5)
        .toList();

    final embedText = [
      if (title != null && title.isNotEmpty) title,
      if (tags != null && tags.isNotEmpty) tags.join(' '),
      excerpt,
    ].join(' | ');
    final vector = await _embedding.embedWithMeta(embedText);

    try {
      await _repo.update(
        itemId,
        title: (title == null || title.isEmpty) ? null : title,
        tags: tags,
        embedding: vector?.vector,
        embeddingIsFallback: vector?.isFallback,
      );
    } catch (e) {
      debugPrint('SharePipeline._enrich: $e');
    }
  }

  String _initialTitle(SharePayload payload) {
    if (payload.note.isNotEmpty) return _truncate(payload.note, 80);
    if (payload.text.isNotEmpty) return _truncate(payload.text, 80);
    final host = Uri.tryParse(payload.url)?.host ?? '';
    return host.isEmpty ? payload.url : host.replaceFirst('www.', '');
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max).trimRight()}…';
}
