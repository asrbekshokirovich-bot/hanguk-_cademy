import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/data/username.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../data/admin_repository.dart';
import '../domain/managed_user.dart';

/// Collects a new account's details. Returns the created account, including
/// its one-time password, or null if the admin backed out.
/// [roles] is what this caller is allowed to hand out, in the order the chips
/// appear. It is not a display preference: an admin cannot mint an
/// administrator, and a superadmin only ever creates administrators, so the
/// two screens that open this dialog offer different sets. The database
/// refuses the rest regardless — see `ol_admin_create_user`.
Future<CreatedAccount?> showCreateUserDialog(
  BuildContext context, {
  List<String> roles = const ['student', 'teacher'],
}) {
  return showDialog<CreatedAccount>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _CreateUserDialog(roles: roles),
  );
}

const _roleLabels = {
  'student': 'Talaba',
  'teacher': "O'qituvchi",
  'admin': 'Administrator',
  'superadmin': 'Super admin',
};

class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog({required this.roles});

  final List<String> roles;

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();

  late String _role = widget.roles.first;
  int? _level = 1;
  bool _busy = false;
  String? _error;
  bool _usernameEdited = false;

  @override
  void initState() {
    super.initState();
    _fullName.addListener(_suggestUsername);
  }

  @override
  void dispose() {
    _fullName.removeListener(_suggestUsername);
    _fullName.dispose();
    _username.dispose();
    super.dispose();
  }

  /// Proposes `aziza.k` from "Aziza Karimova" until the admin types their own.
  /// Filling in a hundred students by hand is the actual daily job here, and
  /// the handle is the field people hesitate over.
  void _suggestUsername() {
    if (_usernameEdited) return;
    final parts = _fullName.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      _username.text = '';
      return;
    }

    // Uzbek Latin carries apostrophes (o‘, g‘) and the odd diacritic; the
    // database constraint allows neither.
    String clean(String s) => s
        .replaceAll('‘', '')
        .replaceAll('’', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final first = clean(parts.first);
    final suggestion = parts.length > 1 && clean(parts[1]).isNotEmpty
        ? '$first.${clean(parts[1])[0]}'
        : first;

    if (suggestion != _username.text) {
      _username.value = TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      );
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final account = await ref.read(adminRepositoryProvider).createUser(
            username: HkAuthNaming.normalize(_username.text),
            fullName: _fullName.text.trim(),
            role: _role,
            level: _role == 'student' ? _level : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(account);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(24),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Yangi hisob', style: HkType.pageTitle),
                      ),
                      IconButton(
                        tooltip: 'Yopish',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 19,
                          color: HkColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AuthField(
                    controller: _fullName,
                    label: 'Ism familiya',
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Ism familiya kiriting'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  AuthField(
                    controller: _username,
                    label: 'Login',
                    icon: Icons.alternate_email_rounded,
                    textInputAction: TextInputAction.next,
                    helperText: 'Kichik harflar, raqamlar, nuqta, tire',
                    inputFormatters: [
                      TextInputFormatter.withFunction((prev, next) {
                        if (next.text != prev.text) _usernameEdited = true;
                        return next.copyWith(text: next.text.toLowerCase());
                      }),
                    ],
                    validator: (v) => HkAuthNaming.validationError(v ?? ''),
                  ),
                  const SizedBox(height: 18),
                  // A single option is a statement, not a choice: the chip row
                  // would read as something to decide.
                  if (widget.roles.length > 1) ...[
                    Text('Rol', style: HkType.muted),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final role in widget.roles)
                          _Choice(
                            label: _roleLabels[role] ?? role,
                            selected: _role == role,
                            onTap: () => setState(() => _role = role),
                          ),
                      ],
                    ),
                  ],
                  if (_role == 'student') ...[
                    const SizedBox(height: 18),
                    Text('Daraja', style: HkType.muted),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 1; i <= 6; i++)
                          _Choice(
                            label: '$i',
                            selected: _level == i,
                            onTap: () => setState(() => _level = i),
                          ),
                      ],
                    ),
                  ],
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
                    label: 'Yaratish',
                    busy: _busy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Parol avtomatik yaratiladi va bir marta ko‘rsatiladi.',
                    style: HkType.muted.copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? kLimeGradient : null,
            color: selected ? null : const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(HkRadius.pill),
            border: Border.all(
              color: selected ? Colors.transparent : HkGlass.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: HkType.family,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? HkColors.ink : HkColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
