import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../config.dart';

/// Abonelik sistemi (RevenueCat).
///
/// - Paywall'ın görünümü, fiyatlar, deneme süresi ve planlar RevenueCat
///   dashboard'undan yönetilir; değiştirmek için uygulama güncellemesi
///   gerekmez.
/// - RevenueCat kullanıcı kimliği = Supabase user_id. Misafir kullanıcı
///   Apple ile hesabını kalıcı yaptığında user_id değişmediği için
///   aboneliği de korunur.
/// - .env'de RevenueCat anahtarı yoksa servis kapalı çalışır: isPro hep
///   false, paywall açılmaz, uygulama çökmez.
///
/// Kullanım:
/// ```dart
/// if (await SubscriptionService.instance.requirePro()) {
///   // Pro özelliği çalıştır
/// }
/// ValueListenableBuilder(valueListenable: SubscriptionService.instance.isPro, ...)
/// ```
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  /// Kullanıcının aktif "pro" yetkisi var mı. Ekranlar bunu dinler.
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  bool _configured = false;
  String? _currentUserId;

  bool get isEnabled => _configured;

  String get _apiKey {
    if (kIsWeb) return '';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => AppConfig.revenueCatIosKey,
      TargetPlatform.android => AppConfig.revenueCatAndroidKey,
      _ => '',
    };
  }

  /// Oturum açıldığında / kullanıcı değiştiğinde çağrılır.
  Future<void> identify(String userId) async {
    if (_currentUserId == userId) return;
    try {
      if (!_configured) {
        final apiKey = _apiKey;
        if (apiKey.isEmpty) return;
        if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
        await Purchases.configure(
          PurchasesConfiguration(apiKey)..appUserID = userId,
        );
        Purchases.addCustomerInfoUpdateListener(_apply);
        _configured = true;
        _currentUserId = userId;
        _apply(await Purchases.getCustomerInfo());
        return;
      }
      final result = await Purchases.logIn(userId);
      _currentUserId = userId;
      _apply(result.customerInfo);
    } catch (e) {
      debugPrint('SubscriptionService.identify: $e');
    }
  }

  /// Çıkış yapıldığında çağrılır.
  Future<void> reset() async {
    _currentUserId = null;
    isPro.value = false;
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      // RevenueCat anonim kullanıcıda logOut hata verir; önemsiz.
      debugPrint('SubscriptionService.reset: $e');
    }
  }

  /// Kullanıcı pro değilse paywall'ı gösterir.
  /// true = (zaten pro ya da az önce satın aldı) özelliği çalıştır.
  Future<bool> requirePro() async {
    if (isPro.value) return true;
    if (!_configured) return false;
    try {
      final result = await RevenueCatUI.presentPaywallIfNeeded(
        AppConfig.proEntitlementId,
        displayCloseButton: true,
      );
      if (result == PaywallResult.purchased ||
          result == PaywallResult.restored) {
        await refresh();
      }
    } catch (e) {
      debugPrint('SubscriptionService.requirePro: $e');
    }
    return isPro.value;
  }

  /// Paywall'ı koşulsuz gösterir (ör. ayarlardaki "Pro'ya geç" butonu).
  Future<void> showPaywall() async {
    if (!_configured) return;
    try {
      await RevenueCatUI.presentPaywall(displayCloseButton: true);
      await refresh();
    } catch (e) {
      debugPrint('SubscriptionService.showPaywall: $e');
    }
  }

  /// "Satın alımları geri yükle" — App Store bu butonu zorunlu tutar.
  Future<bool> restore() async {
    if (!_configured) return false;
    try {
      _apply(await Purchases.restorePurchases());
    } catch (e) {
      debugPrint('SubscriptionService.restore: $e');
    }
    return isPro.value;
  }

  /// Abonelik yönetimi (iptal, plan değişikliği, iade talebi).
  Future<void> manageSubscription() async {
    if (!_configured) return;
    try {
      await RevenueCatUI.presentCustomerCenter();
      await refresh();
    } catch (e) {
      debugPrint('SubscriptionService.manageSubscription: $e');
    }
  }

  Future<void> refresh() async {
    if (!_configured) return;
    try {
      _apply(await Purchases.getCustomerInfo());
    } catch (e) {
      debugPrint('SubscriptionService.refresh: $e');
    }
  }

  void _apply(CustomerInfo info) {
    isPro.value =
        info.entitlements.active.containsKey(AppConfig.proEntitlementId);
  }
}
