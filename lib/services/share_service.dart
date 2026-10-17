import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Share Extension'dan (iOS) / ShareActivity'den (Android) gelen tek bir
/// paylaşım.
class SharePayload {
  final String id;
  final String url;
  final String text;
  final String note;
  final DateTime createdAt;

  const SharePayload({
    required this.id,
    required this.url,
    required this.text,
    required this.note,
    required this.createdAt,
  });

  bool get hasUrl => url.isNotEmpty;

  static SharePayload? fromMap(Map<dynamic, dynamic> raw) {
    final url = raw['url']?.toString().trim() ?? '';
    final text = raw['text']?.toString().trim() ?? '';
    if (url.isEmpty && text.isEmpty) return null;

    final rawId = raw['id']?.toString().trim() ?? '';
    return SharePayload(
      id: rawId.isEmpty
          ? '${DateTime.now().microsecondsSinceEpoch}_${url.hashCode}'
          : rawId,
      url: url,
      text: text,
      note: raw['note']?.toString().trim() ?? '',
      createdAt: DateTime.tryParse(raw['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'text': text,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Paylaşılanları native kuyruktan okuyup uygulamanın işlemesini sağlar.
///
/// Güvenli akış:
/// 1. Native kuyruk boşaltılır, öğeler önce yerel "pending" listesine yazılır
///    → uygulama işleme sırasında kapansa bile hiçbir paylaşım kaybolmaz.
/// 2. Her öğe [handler] ile işlenir. handler `true` dönerse listeden silinir,
///    `false` dönerse (ör. internet yok) bir sonraki açılışta tekrar denenir.
///
/// Kullanım: main.dart'ta uygulama açılınca ve her `resumed` olduğunda
/// `ShareService.instance.processQueue(handler)` çağrılır.
class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  /// Native taraftaki kanal adıyla AYNI olmalı
  /// (ios/Runner/AppDelegate.swift ve android MainActivity.kt).
  static const MethodChannel _channel = MethodChannel('app.starter/share');
  static const String _pendingKey = 'pending_share_payloads';

  /// Her başarılı işlemden sonra artar; ekranlar dinleyip yenilenebilir.
  final ValueNotifier<int> processedCount = ValueNotifier<int>(0);

  bool _isProcessing = false;

  Future<void> processQueue(
    Future<bool> Function(SharePayload payload) handler,
  ) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = await _drainNativeQueue(prefs);
      if (pending.isEmpty) return;

      final remaining = <SharePayload>[];
      for (final payload in pending) {
        var ok = false;
        try {
          ok = await handler(payload);
        } catch (e) {
          debugPrint('ShareService: handler hatası: $e');
        }
        if (!ok) remaining.add(payload);
      }

      await _writePending(prefs, remaining);
      if (remaining.length < pending.length) processedCount.value++;
    } on MissingPluginException {
      // Platform kanalı yok (ör. web / test) — sessizce geç.
    } catch (e) {
      debugPrint('ShareService: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<List<SharePayload>> _drainNativeQueue(SharedPreferences prefs) async {
    final pending = _readPending(prefs);
    final knownIds = pending.map((p) => p.id).toSet();

    while (true) {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('popSharedPayload');
      if (raw == null) break;
      final payload = SharePayload.fromMap(raw);
      if (payload == null || knownIds.contains(payload.id)) continue;
      pending.add(payload);
      knownIds.add(payload.id);
      // Native kuyruktan çıkan her öğe hemen kalıcı listeye yazılır.
      await _writePending(prefs, pending);
    }
    return pending;
  }

  List<SharePayload> _readPending(SharedPreferences prefs) {
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return <SharePayload>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SharePayload>[];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(SharePayload.fromMap)
          .whereType<SharePayload>()
          .toList();
    } catch (_) {
      return <SharePayload>[];
    }
  }

  Future<void> _writePending(
    SharedPreferences prefs,
    List<SharePayload> payloads,
  ) async {
    await prefs.setString(
      _pendingKey,
      jsonEncode(payloads.map((p) => p.toJson()).toList()),
    );
  }
}
