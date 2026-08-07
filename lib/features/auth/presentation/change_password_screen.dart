import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/ambient_background.dart';
import '../../lessons/data/providers.dart';
import '../data/auth_repository.dart';
import 'auth_scaffold.dart';

/// Forced after signing in with an admin-issued password.
///
/// The router sends every route here while `ol_profiles.must_change_password`
/// is true. That flag is set when an account is created and when its password
/// is reset, so a password the administrator has seen — and may have written
/// on paper — never stays the account's real password.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState
    extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).changeOwnPassword(_password.text);
      // The profile carries must_change_password; refetch it so the router's
      // redirect sees the new value and lets the user through.
      ref.invalidate(profileProvider);
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
          title: 'Yangi parol qo‘ying',
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hisobingiz administrator bergan parol bilan ochilgan. '
                  'Davom etish uchun faqat o‘zingiz biladigan parol qo‘ying.',
                  style: HkType.body.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 20),
                AuthField(
                  controller: _password,
                  label: 'Yangi parol',
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscure,
                  textInputAction: TextInputAction.next,
                  helperText: 'Kamida 8 ta belgi',
                  suffix: ObscureToggle(
                    obscured: _obscure,
                    onChanged: (v) => setState(() => _obscure = v),
                  ),
                  validator: (v) {
                    final value = v ?? '';
                    if (value.isEmpty) return 'Parol kiriting';
                    // Supabase's own floor is 6; 8 is this app's, because the
                    // accounts belong to minors who will reuse it elsewhere.
                    if (value.length < 8) {
                      return "Kamida 8 ta belgi bo'lsin";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _confirm,
                  label: 'Parolni takrorlang',
                  icon: Icons.lock_reset_rounded,
                  obscure: _obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  validator: (v) =>
                      v != _password.text ? 'Parollar mos kelmadi' : null,
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
                  label: 'Saqlash',
                  busy: _busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => ref.read(authRepositoryProvider).signOut(),
                    child: Text(
                      'Chiqish',
                      style: HkType.muted.copyWith(fontSize: 12.5),
                    ),
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
