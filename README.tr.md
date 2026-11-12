# App Foundation

[English README](README.md)

Yeni her mobil uygulamanın üzerine kurulduğu ortak temel.
Flutter + Supabase + Groq; iOS ve Android; 4 dil; Codemagic ile TestFlight.

Kural: Uygulamaya özel hiçbir şey bu repoya girmez. Burada sadece **her
uygulamada lazım olan** altyapı durur. Bir uygulamada geliştirdiğin genel bir
parça (ödeme, bildirim, onboarding...) olgunlaşınca buraya geri taşınır.

## İçinde ne var

| Parça | Dosya |
|---|---|
| Supabase bağlantısı + misafir giriş → Apple/e-posta ile hesabı kalıcı yapma | `lib/services/auth_service.dart` |
| Hesap silme (App Store zorunlu) | `supabase/functions/delete-account` |
| Abonelik + paywall (RevenueCat): `requirePro()`, geri yükleme, abonelik yönetimi | `lib/services/subscription_service.dart` |
| Groq → OpenRouter fallback'li LLM istemcisi (`complete`, `completeJson`) | `lib/services/ai_service.dart` |
| Gemini → OpenRouter fallback'li embedding (768d) | `lib/services/embedding_service.dart` |
| Hybrid search (full-text + pgvector, RRF) | `supabase/migrations/0001_starter_base.sql`, `lib/services/item_repository.dart` |
| iOS Share Extension + Android ShareActivity (her link/metni kabul eder) | `ios/ShareExtension`, `android/.../ShareActivity.kt` |
| Kayıpsız paylaşım kuyruğu (uygulama kapansa bile kaybolmaz) | `lib/services/share_service.dart` |
| Paylaşılanı kaydet → arka planda AI etiket + embedding | `lib/services/share_pipeline.dart` |
| 4 dil (EN/TR/PT/ES) | `lib/l10n/*.arb` |
| Codemagic → TestFlight (Mac gerekmez, Share Extension dahil) | `codemagic.yaml`, `add_share_extension.rb` |
| Yeniden adlandırma | `tool/rename.dart` |
| Build öncesi kontrol (ARB eşitliği + hardcoded string) | `tool/preflight.dart` |

Örnek ekranlar: giriş, liste + arama, ayarlar (Pro'ya geç, satın alımları geri
yükle, misafir hesabı güvenceye alma, çıkış, hesap silme). Bunlar başlangıç noktasıdır; yeni uygulamada
değiştirilir veya silinir.

## Yeni uygulama başlatma

GitHub'da bu repoda **Use this template → Create a new repository** ile yeni
repo aç (ör. `petlog`), sonra:

```bash
git clone https://github.com/your-name/myapp
cd petlog

# Adı ve bundle ID'yi her yerde değiştir
dart tool/rename.dart --name "MyApp" --bundle com.yourcompany.myapp

# Ortam değişkenleri
cp .env.example .env      # Windows: copy .env.example .env
# .env içini doldur

flutter pub get
dart tool/preflight.dart
flutter analyze
```

## Yeni uygulama kontrol listesi

**Supabase (her uygulama için yeni proje)**
- [ ] SQL Editor'de `supabase/migrations/0001_starter_base.sql` çalıştır
- [ ] Authentication > Providers > **Anonymous Sign-Ins** aç
- [ ] Authentication > Providers > **Apple** aç
- [ ] Authentication > **Manual Linking** aç (misafir → Apple bağlama için)
- [ ] `supabase functions deploy delete-account`

**Apple Developer / App Store Connect**
- [ ] Bundle ID kaydet: `com.sirket.uygulama` (Sign in with Apple + App Groups açık)
- [ ] Bundle ID kaydet: `com.sirket.uygulama.ShareExtension` (App Groups açık)
- [ ] App Group oluştur: `group.com.sirket.uygulama`, iki ID'ye de ekle
- [ ] App Store Connect'te uygulamayı oluştur, Primary Language: **English (U.S.)**

**RevenueCat (abonelik)** — anahtar girilmezse uygulama aboneliksiz çalışır
- [ ] App Store Connect'te abonelik ürünlerini oluştur (ör. aylık + yıllık, aynı Subscription Group içinde)
- [ ] RevenueCat'te yeni proje → iOS uygulaması ekle (bundle ID + App Store Connect API key)
- [ ] Entitlement oluştur, kimliği tam olarak **`pro`** olsun; ürünleri bu entitlement'a bağla
- [ ] Offering oluştur (Current) ve paketleri ekle
- [ ] Paywalls bölümünden paywall'ı tasarla (kod gerekmez)
- [ ] Public SDK anahtarlarını `.env`'e ve Codemagic'e ekle: `REVENUECAT_IOS_KEY`, `REVENUECAT_ANDROID_KEY`

Kodda bir özelliği Pro'ya kilitlemek:

```dart
if (await SubscriptionService.instance.requirePro()) {
  // kullanıcı Pro: özelliği çalıştır
}
```

**Codemagic**
- [ ] Repo'yu bağla, `app_secrets` grubuna `.env.example`'daki 7 anahtarı ekle
- [ ] App Store Connect entegrasyonu adı `Codemagic` olmalı (değilse `codemagic.yaml`'da değiştir)

**Uygulama**
- [ ] İkonlar: `ios/Runner/Assets.xcassets/AppIcon.appiconset` ve `android/app/src/main/res/mipmap-*` (şu an genel yer tutucu ikon)
- [ ] Marka rengi: `lib/theme/app_theme.dart` → `kBrandColor` (+ `ShareViewController.swift` ve `ShareActivity.kt`'deki buton rengi)
- [ ] `items` tablosunu uygulamanın ana varlığına göre uyarla; yeni tabloları `delete-account` içindeki `USER_TABLES`'a ekle
- [ ] Share Extension gerekmiyorsa: `ios/ShareExtension` klasörünü, Android'de `ShareActivity`'yi ve manifest kaydını sil

## Kurallar

- Her build öncesi: `dart tool/preflight.dart` + `flutter analyze` sıfır hata. Codemagic bunu otomatik çalıştırır; ARB anahtarları eşit değilse build durur.
- Yeni UI metni → önce 4 ARB dosyasına anahtar ekle, kodda `AppLocalizations.of(context)!.anahtar` kullan.
- Groq web'de CORS yüzünden çalışmaz; telefon veya simülatörde test et.
- `.env`, `*.p8`, keystore dosyaları asla commitlenmez (`.gitignore`'da).
