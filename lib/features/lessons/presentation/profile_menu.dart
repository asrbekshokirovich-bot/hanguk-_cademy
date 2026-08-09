import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/data/auth_repository.dart';
import '../data/lessons_repository.dart';
import '../data/providers.dart';

/// The menu behind the avatar: who is signed in, and sign out.
Future<void> showHkProfileMenu(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x80000000),
    builder: (_) => const _ProfileDialog(),
  );
}

class _ProfileDialog extends ConsumerWidget {
  const _ProfileDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 760;
    final profile = ref.watch(profileProvider).value;

    return Dialog(
      backgroundColor: Colors.transparent,
      alignment: isWide ? Alignment.topRight : Alignment.center,
      insetPadding: isWide
          ? const EdgeInsets.only(top: 78, right: 28)
          : const EdgeInsets.symmetric(horizontal: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(18),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HkAvatar(initials: profile?.initials ?? '?', size: 46),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.fullName ?? '—',
                          style: HkType.sectionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          profile?.subtitle ?? '',
                          style: HkType.muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(
                label: 'Rol',
                value: profile?.roleLabel ?? 'Talaba',
              ),
              if (profile?.level != null)
                _InfoRow(label: 'Daraja', value: '${profile!.level}'),
              _InfoRow(
                label: "Ma'lumot manbai",
                // Asked of the repository, not of HkEnv: the build can be
                // configured for Supabase while the running app is still on
                // fixtures (a test override, a failed init), and this row is
                // the only place that difference is visible on screen.
                value: ref.watch(lessonsRepositoryProvider).isDemo
                    ? 'Demo (offline)'
                    : 'Supabase',
              ),
              if (!ref.watch(authRepositoryProvider).isDemo) ...[
              const Divider(color: HkGlass.border, height: 26),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    try {
                      await ref.read(authRepositoryProvider).signOut();
                      // The router's redirect sends us to /login on the auth
                      // event; this only closes the menu on top of it.
                      navigator.pop();
                    } catch (e) {
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text('Chiqib bo‘lmadi: $e')),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0x33DC2626)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HkRadius.control),
                    ),
                  ),
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 17,
                    color: HkColors.dangerBright,
                  ),
                  label: const Text(
                    'Chiqish',
                    style: TextStyle(
                      fontFamily: HkType.family,
                      fontWeight: FontWeight.w600,
                      color: HkColors.dangerBright,
                    ),
                  ),
                ),
              ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: HkType.muted)),
          Text(value, style: HkType.label.copyWith(fontSize: 12.5)),
        ],
      ),
    );
  }
}
