import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// Genel LLM istemcisi: önce Groq, hata/rate limit olursa OpenRouter.
///
/// Kullanım:
/// ```dart
/// final ai = AiService(groqApiKey: AppConfig.groqApiKey,
///                      openRouterApiKey: AppConfig.openRouterApiKey);
/// final text = await ai.complete('Bu metni özetle: ...');
/// final json = await ai.completeJson('... JSON döndür');
/// ```
///
/// Not: Groq web'de CORS nedeniyle çalışmaz; test için telefon/simülatör kullan.
class AiService {
  final String groqApiKey;
  final String openRouterApiKey;

  /// Varsayılan modeller — ihtiyaca göre değiştir.
  final String groqModel;
  final String openRouterModel;

  static const String _groqUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _openRouterUrl =
      'https://openrouter.ai/api/v1/chat/completions';

  AiService({
    required this.groqApiKey,
    this.openRouterApiKey = '',
    this.groqModel = 'openai/gpt-oss-20b',
    this.openRouterModel = 'openai/gpt-oss-20b',
  });

  bool get isConfigured => groqApiKey.isNotEmpty || openRouterApiKey.isNotEmpty;

  /// Cihaz diline göre "şu dilde cevap ver" talimatı.
  static String languageInstruction(String localeCode) {
    return switch (localeCode.split('_').first.toLowerCase()) {
      'tr' => 'Respond in Turkish only.',
      'pt' => 'Respond in Brazilian Portuguese only.',
      'es' => 'Respond in Spanish only.',
      _ => 'Respond in English only.',
    };
  }

  /// Düz metin cevap döner; iki sağlayıcı da başarısızsa null.
  Future<String?> complete(
    String prompt, {
    String? system,
    double temperature = 0.3,
    int maxTokens = 1024,
    bool jsonMode = false,
  }) async {
    if (!isConfigured) return null;

    final messages = [
      if (system != null && system.isNotEmpty)
        {'role': 'system', 'content': system},
      {'role': 'user', 'content': prompt},
    ];

    if (groqApiKey.isNotEmpty) {
      final result = await _call(
        url: _groqUrl,
        apiKey: groqApiKey,
        model: groqModel,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        jsonMode: jsonMode,
      );
      if (result != null) return result;
    }

    if (openRouterApiKey.isNotEmpty) {
      debugPrint('AiService: Groq başarısız, OpenRouter fallback deneniyor');
      return _call(
        url: _openRouterUrl,
        apiKey: openRouterApiKey,
        model: openRouterModel,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        jsonMode: jsonMode,
      );
    }
    return null;
  }

  /// JSON nesnesi bekleyen çağrılar için. Model cevabı ```json bloklarıyla
  /// sarsa bile ayıklar. Parse edilemezse null.
  Future<Map<String, dynamic>?> completeJson(
    String prompt, {
    String? system,
    double temperature = 0.2,
    int maxTokens = 1024,
  }) async {
    final raw = await complete(
      prompt,
      system: system,
      temperature: temperature,
      maxTokens: maxTokens,
      jsonMode: true,
    );
    if (raw == null) return null;
    return _parseJsonObject(raw);
  }

  Future<String?> _call({
    required String url,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    required double temperature,
    required int maxTokens,
    required bool jsonMode,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': temperature,
              'max_tokens': maxTokens,
              if (jsonMode) 'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        debugPrint('AiService: HTTP ${response.statusCode} ${response.body}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final message = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      if (content == null || content.trim().isEmpty) return null;
      return content.trim();
    } catch (e) {
      debugPrint('AiService: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _parseJsonObject(String raw) {
    var text = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return null;

    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
