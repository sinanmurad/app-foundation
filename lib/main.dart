import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/share_pipeline.dart';
import 'services/share_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  AppConfig.validate();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  runApp(const StarterApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class StarterApp extends StatelessWidget {
  const StarterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const RootGate(),
    );
  }
}

/// Oturum kapısı + paylaşım kuyruğu tetikleyicisi.
///
/// - Açılışta oturum yoksa sessizce anonim oturum açar (kayıt sürtünmesi
///   yok). Anonim giriş başarısız olursa veya kullanıcı çıkış yaparsa
///   AuthScreen gösterilir.
/// - Oturum değiştikçe abonelik kimliğini (RevenueCat) Supabase user_id ile
///   eşler.
/// - Uygulama her öne geldiğinde Share Extension kuyruğunu işler.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  final AuthService _auth = AuthService();
  final SharePipeline _pipeline = SharePipeline();
  bool _bootstrapping = true;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = _auth.authStateChanges.listen(_onAuthChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAuthChanged(AuthState state) {
    final userId = state.session?.user.id;
    if (userId != null) {
      SubscriptionService.instance.identify(userId);
    } else if (state.event == AuthChangeEvent.signedOut) {
      SubscriptionService.instance.reset();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _processShares();
      SubscriptionService.instance.refresh();
    }
  }

  Future<void> _bootstrap() async {
    if (!_auth.isLoggedIn) {
      try {
        await _auth.signInAnonymously();
      } catch (e) {
        debugPrint('RootGate: anonim giriş başarısız: $e');
      }
    }
    if (mounted) setState(() => _bootstrapping = false);
    await _processShares();
  }

  Future<void> _processShares() async {
    if (!_auth.isLoggedIn) return;
    final locale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    await ShareService.instance.processQueue(
      (payload) => _pipeline.handle(payload, locale: locale),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _auth.authStateChanges,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) return const HomeScreen();
        if (_bootstrapping) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Anonim giriş başarısız olduysa veya kullanıcı çıkış yaptıysa.
        return const AuthScreen();
      },
    );
  }
}
