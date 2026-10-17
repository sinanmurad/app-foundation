import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// embed()/embedWithMeta() sonucunu, hangi sağlayıcıdan geldiği bilgisiyle
/// birlikte taşır. isFallback=true olan vektörler Gemini değil, OpenRouter
/// (farklı bir model) tarafından üretilmiştir — aynı boyutta olsa da farklı
/// bir vektör uzayından geldiği için Gemini embedding'leriyle pgvector'da
/// birebir karşılaştırılamaz. Bu bilgi DB'ye `embedding_is_fallback` olarak
/// yazılır ki ileride bir backfill job'u bu kayıtları gerçek Gemini
/// embedding'i ile değiştirebilsin.
class EmbeddingResult {
  final List<double> vector;
  final bool isFallback;

  const EmbeddingResult({required this.vector, required this.isFallback});
}

/// Metni 768 boyutlu vektöre çevirir (pgvector semantik arama için).
/// Önce Gemini, başarısız olursa OpenRouter (text-embedding-3-small, 768d).
/// Fallback vektörler farklı model uzayından geldiği için DB'ye
/// `embedding_is_fallback = true` olarak işaretlenerek yazılmalı.
class EmbeddingService {
  final String apiKey;
  final String openRouterApiKey;

  static const String _model = 'gemini-embedding-001';
  static const String _fallbackModel = 'openai/text-embedding-3-small';
  static const int _outputDimensionality = 768;
  static const String _openRouterUrl =
      'https://openrouter.ai/api/v1/embeddings';

  EmbeddingService({required this.apiKey, this.openRouterApiKey = ''});

  /// Sadece vektörü döner (ör. arama sorgusu embedding'i). DB'deki
  /// `embedding` kolonuna yazılacaksa embedWithMeta() kullan.
  Future<List<double>?> embed(String text) async {
    final result = await embedWithMeta(text);
    return result?.vector;
  }

  /// Önce Gemini denenir. Başarısız olursa (rate limit/timeout/hata) ve
  /// openRouterApiKey doluysa, OpenRouter üzerinden 768 boyutlu bir fallback
  /// denenir. Sonucun isFallback alanı, çağıran tarafın DB'ye yazarken
  /// embeddingIsFallback'i işaretlemesi için kullanılır.
  Future<EmbeddingResult?> embedWithMeta(String text) async {
    if (text.trim().isEmpty) return null;

    if (apiKey.isNotEmpty) {
      final vector = await _callGemini(text);
      if (vector != null) {
        return EmbeddingResult(vector: vector, isFallback: false);
      }
    }

    if (openRouterApiKey.isNotEmpty) {
      debugPrint(
          'EmbeddingService: Gemini başarısız, OpenRouter fallback deneniyor ($_fallbackModel, ${_outputDimensionality}d)');
      final vector = await _callFallback(text);
      if (vector != null) {
        return EmbeddingResult(vector: vector, isFallback: true);
      }
    }

    return null;
  }

  Future<List<double>?> _callGemini(String text) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:embedContent',
    );

    try {
      final response = await http
          .post(
            url,
            headers: {
              'x-goog-api-key': apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'models/$_model',
              'content': {
                'parts': [
                  {'text': text.length > 2000 ? text.substring(0, 2000) : text}
                ],
              },
              'outputDimensionality': _outputDimensionality,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        debugPrint(
            'EmbeddingService._callGemini: HTTP ${response.statusCode} ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final values = body['embedding']?['values'] as List<dynamic>?;
      if (values == null) return null;

      return values.map((v) => (v as num).toDouble()).toList();
    } catch (e, st) {
      debugPrint('EmbeddingService._callGemini: $e\n$st');
      return null;
    }
  }

  Future<List<double>?> _callFallback(String text) async {
    try {
      final response = await http
          .post(
            Uri.parse(_openRouterUrl),
            headers: {
              'Authorization': 'Bearer $openRouterApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _fallbackModel,
              'input': text.length > 2000 ? text.substring(0, 2000) : text,
              'dimensions': _outputDimensionality,
              'encoding_format': 'float',
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        debugPrint(
            'EmbeddingService._callFallback: HTTP ${response.statusCode} ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>?;
      final values = (data != null && data.isNotEmpty)
          ? data[0]['embedding'] as List<dynamic>?
          : null;
      if (values == null) return null;

      final vector = values.map((v) => (v as num).toDouble()).toList();

      // Güvenlik kontrolü: dimensions parametresi bir sebeple yok
      // sayılırsa, uyumsuz boyutlu vektör asla DB'ye ulaşmasın.
      if (vector.length != _outputDimensionality) {
        debugPrint(
            'EmbeddingService._callFallback: beklenmeyen boyut ${vector.length} (beklenen $_outputDimensionality), atlanıyor');
        return null;
      }

      return vector;
    } catch (e, st) {
      debugPrint('EmbeddingService._callFallback: $e\n$st');
      return null;
    }
  }
}
