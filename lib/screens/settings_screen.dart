import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';

/// Ayarlar: misafir hesabı güvenceye alma, çıkış, hesap silme
/// (hesap silme App Store için zorunludur).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _auth = AuthService();
  bool _busy = false;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _run(Future<void> Function() action, {bool popAfter = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (popAfter) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('SettingsScreen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorGeneric)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _secureWithEmail() async {
    final l10n = AppLocalizations.of(context)!;
    final email = TextEditingController();
    final password = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.secureAccountButton),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l10n.emailLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.passwordLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    final emailText = email.text.trim();
    final passwordText = password.text;
    email.dispose();
    password.dispose();

    if (confirmed == true && emailText.isNotEmpty && passwordText.length >= 6) {
      await _run(() async {
        await _auth.convertAnonymousWithEmail(emailText, passwordText);
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAccountConfirmTitle),
        content: Text(l10n.deleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(_auth.deleteAccount, popAfter: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final isGuest = _auth.isAnonymous;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            if (isGuest)
              Card(
                margin: const EdgeInsets.all(16),
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.guestModeTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(l10n.guestModeHint),
                      const SizedBox(height: 12),
                      if (_isIOS)
                        FilledButton.icon(
                          onPressed: () => _run(() async {
                            await _auth.signInWithApple();
                            if (mounted) setState(() {});
                          }),
                          icon: const Icon(Icons.apple),
                          label: Text(l10n.continueWithApple),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _secureWithEmail,
                        child: Text(l10n.secureAccountButton),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(l10n.accountSecured),
                subtitle: Text(_auth.currentUser?.email ?? ''),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l10n.signOut),
              onTap: () => _run(_auth.signOut, popAfter: true),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
              title: Text(
                l10n.deleteAccount,
                style: TextStyle(color: scheme.error),
              ),
              onTap: _confirmDelete,
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
