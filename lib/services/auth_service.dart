import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kimlik doğrulama.
///
/// Akış: Kullanıcı uygulamayı açar → sessizce anonim oturum açılır
/// (kayıt sürtünmesi yok) → istediğinde Apple veya e-posta ile hesabını
/// kalıcı hale getirir. user_id değişmez, veriler korunur.
///
/// Supabase Dashboard ön koşulları:
/// - Authentication > Providers > Anonymous Sign-Ins: AÇIK
/// - Authentication > Providers > Apple: AÇIK (Services ID + key)
/// - Authentication > "Manual Linking": AÇIK (anonim → Apple bağlama için)
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;
  bool get isLoggedIn => _client.auth.currentUser != null;
  bool get isAnonymous => _client.auth.currentUser?.isAnonymous == true;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signInAnonymously() async {
    await _client.auth.signInAnonymously();
  }

  Future<void> signInWithEmail(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUpWithEmail(String email, String password) async {
    await _client.auth.signUp(email: email, password: password);
  }

  /// Anonim kullanıcıyı e-posta + şifre ile kalıcı hesaba dönüştürür.
  /// user_id DEĞİŞMEZ.
  Future<void> convertAnonymousWithEmail(String email, String password) async {
    await _client.auth.updateUser(
      UserAttributes(email: email, password: password),
    );
  }

  /// Sign in with Apple (native).
  ///
  /// Anonim kullanıcıda `signInWithIdToken` KULLANILMAZ — Apple kimliği ilk
  /// kez görülüyorsa yeni bir user_id üretir ve anonim veriler kaybolur.
  /// Bunun yerine `linkIdentityWithIdToken` ile Apple kimliği mevcut
  /// user_id'ye bağlanır. Bağlama başarısız olursa (ör. Manual Linking
  /// kapalı) normal Apple girişine düşülür.
  ///
  /// Xcode'da "Sign in with Apple" capability açık olmalı
  /// (Runner.entitlements içinde zaten tanımlı).
  Future<void> signInWithApple() async {
    final wasAnonymous = isAnonymous;

    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) throw Exception('Apple identity token alınamadı');

    if (wasAnonymous) {
      try {
        await _client.auth.linkIdentityWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );
        return;
      } catch (e) {
        debugPrint('AuthService: Apple link başarısız, normal girişe düşülüyor: $e');
      }
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// App Store zorunluluğu: kullanıcı hesabını uygulama içinden silebilmeli.
  /// supabase/functions/delete-account edge function'ını çağırır.
  Future<void> deleteAccount() async {
    final session = _client.auth.currentSession;
    if (session == null) throw Exception('Oturum bulunamadı');
    final response = await _client.functions.invoke(
      'delete-account',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
    if (response.status != 200) {
      final data = response.data;
      final message = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Hesap silinemedi';
      throw Exception(message);
    }
    await _client.auth.signOut();
  }

  String _generateNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)])
        .join();
  }
}
