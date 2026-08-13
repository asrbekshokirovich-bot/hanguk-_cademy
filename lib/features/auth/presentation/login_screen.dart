import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/ambient_background.dart';
import '../data/auth_repository.dart';
import '../data/username.dart';
import 'auth_scaffold.dart';

/// Sign in with the login an administrator issued.
///
/// There is no "create an account" here, by design: accounts are issued, not
/// self-served. The screen says so, because a student who cannot find the
/// sign-up button will otherwise assume the app is broken.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signIn(
            username: _username.text,
            password: _password.text,
          );
      // The router redirects on the auth event; nothing to do here.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = hkAuthErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HkColors.canvasBottom,
      body: AmbientBackground(
        child: AuthCard(
          title: 'Tizimga kirish',
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AuthField(
                  controller: _username,
                  label: 'Login',
                  icon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  // Typed logins arrive capitalised off a slip of paper often
                  // enough that fixing it up beats rejecting it.
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (_, next) => next.copyWith(text: next.text.toLowerCase()),
                    ),
                  ],
                  validator: (v) => HkAuthNaming.validationError(v ?? ''),
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _password,
                  label: 'Parol',
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _busy ? null : _submit(),
                  suffix: ObscureToggle(
                    obscured: _obscure,
                    onChanged: (v) => setState(() => _obscure = v),
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Parol kiriting' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  AuthBanner(
                    text: _error!,
                    icon: Icons.error_outline_rounded,
                    color: HkColors.dangerBright,
                    background: const Color(0x1FDC2626),
                  ),
                ],
                const SizedBox(height: 22),
                AuthSubmitButton(
                  label: 'Kirish',
                  busy: _busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x0FFFFFFF),
                    borderRadius: BorderRadius.circular(HkRadius.cardSmall),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: HkColors.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Login va parolni administrator beradi. Parolni '
                          'unutgan bo‘lsangiz, unga murojaat qiling.',
                          style: HkType.body.copyWith(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Which build this is. Small and grey — nobody signing in
                // needs it — but it is the only thing on screen that can
                // answer "am I running the version with the fix in it?",
                // and without it that question costs a round trip and a
                // guess. See HkEnv.buildStamp.
                Center(
                  child: Text(
                    'Build ${HkEnv.buildStamp}',
                    style: HkType.muted.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
