import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Uygulama yapılandırması.
///
/// Değerler proje kökündeki .env dosyasından okunur (.gitignore'da).
/// Örnek için .env.example dosyasına bak. Codemagic'te bu dosya
/// build sırasında ortam değişkenlerinden üretilir.
class AppConfig {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// Groq — birincil LLM sağlayıcı.
  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';

  /// OpenRouter — Groq rate limit / hata durumunda fallback.
  static String get openRouterApiKey => dotenv.env['OPENROUTER_API_KEY'] ?? '';

  /// Google Gemini — embedding (semantik arama) için.
  static String get googleApiKey => dotenv.env['GOOGLE_API_KEY'] ?? '';

  /// Supabase zorunlu; AI anahtarları "best effort" (yoksa AI özellikleri
  /// sessizce devre dışı kalır, uygulama yine açılır).
  static void validate() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];
    if (missing.isNotEmpty) {
      throw Exception(
        'Eksik yapılandırma: ${missing.join(", ")}. .env dosyasını kontrol et.',
      );
    }
  }
}
