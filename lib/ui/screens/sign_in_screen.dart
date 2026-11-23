import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../labels.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^\[.*?\]\s*'), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final auth = ref.read(authServiceProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: ref.watch(settingsProvider).anim(const Duration(milliseconds: 1200)),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: 0.5 + 0.5 * v, child: child),
                child: const Text('🧊', textAlign: TextAlign.center, style: TextStyle(fontSize: 88)),
              ),
              Text('Gleba',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(l.signInSubtitle, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(auth.signInWithGoogle),
                icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                label: Text(l.signInGoogle),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: l.email),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(labelText: l.password),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _run(() => _register
                        ? auth.registerWithEmail(_email.text.trim(), _password.text)
                        : auth.signInWithEmail(_email.text.trim(), _password.text)),
                child: Text(_register ? l.register : l.signIn),
              ),
              TextButton(
                onPressed: () => setState(() => _register = !_register),
                child: Text(_register ? l.haveAccount : l.noAccount),
              ),
              if (!_register)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await auth.sendPasswordReset(_email.text.trim());
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.passwordResetSent)));
                            }
                          }),
                  child: Text(l.forgotPassword),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
