import 'package:flutter/material.dart';

import '../../../core/clock.dart';
import '../../../design_system/tokens.dart';
import '../../auth/data/username.dart';

/// A row in the admin roster.
class ManagedUser {
  const ManagedUser({
    required this.userId,
    required this.fullName,
    required this.role,
    this.username,
    this.level,
    this.mustChangePassword = false,
    this.createdAt,
    this.lastSignInAt,
  });

  final String userId;
  final String fullName;

  /// 'student' | 'teacher' | 'admin' | 'superadmin'
  final String role;

  /// Null for an account created by hand with a real email rather than a
  /// generated handle — the first admin, typically.
  final String? username;
  final int? level;
  final bool mustChangePassword;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;

  bool get hasNeverSignedIn => lastSignInAt == null;

  bool get isAdministrator => role == 'admin' || role == 'superadmin';

  String get roleLabel => switch (role) {
        'superadmin' => 'Super admin',
        'admin' => 'Administrator',
        'teacher' => "O'qituvchi",
        _ => 'Talaba',
      };

  Color get roleColor => switch (role) {
        'superadmin' => HkColors.warningBright,
        'admin' => HkColors.dangerBright,
        'teacher' => HkColors.lime,
        _ => HkColors.infoText,
      };

  Color get roleBackground => switch (role) {
        'superadmin' => const Color(0x26E0A93A),
        'admin' => const Color(0x26DC2626),
        'teacher' => const Color(0x26D4E94C),
        _ => const Color(0x266EA0E0),
      };

  String get initials {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  factory ManagedUser.fromMap(Map<String, dynamic> map) {
    final email = map['email'] as String?;
    return ManagedUser(
      userId: map['user_id'] as String,
      fullName: (map['full_name'] as String?) ?? '—',
      role: (map['role'] as String?) ?? 'student',
      // Falls back to deriving the handle from the address, so an account
      // made before usernames existed still shows something sensible.
      username: (map['username'] as String?) ??
          (email == null ? null : HkAuthNaming.toDisplayName(email)),
      level: (map['level'] as num?)?.toInt(),
      mustChangePassword: (map['must_change_password'] as bool?) ?? false,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String).toLocal(),
      lastSignInAt: map['last_sign_in_at'] == null
          ? null
          : DateTime.parse(map['last_sign_in_at'] as String).toLocal(),
    );
  }

  /// Shown in demo mode so the panel's layout can be reviewed without a
  /// backend. Creating or deleting anything is refused there.
  static List<ManagedUser> demoRoster() {
    // hkNow, not DateTime.now: these dates are rendered, so a golden over
    // this screen would otherwise fail on any run a minute later.
    final now = hkNow();
    return [
      ManagedUser(
        userId: 'u1',
        username: 'aziza.k',
        fullName: 'Aziza Karimova',
        role: 'student',
        level: 2,
        createdAt: now.subtract(const Duration(days: 40)),
        lastSignInAt: now.subtract(const Duration(hours: 3)),
      ),
      ManagedUser(
        userId: 'u2',
        username: 'jasur.k',
        fullName: 'Jasur Karimov',
        role: 'teacher',
        createdAt: now.subtract(const Duration(days: 120)),
        lastSignInAt: now.subtract(const Duration(minutes: 14)),
      ),
      ManagedUser(
        userId: 'u5',
        username: 'ofis',
        fullName: 'Ofis xodimi',
        role: 'admin',
        createdAt: now.subtract(const Duration(days: 30)),
        lastSignInAt: now.subtract(const Duration(hours: 6)),
      ),
      ManagedUser(
        userId: 'u3',
        username: 'bekzod.t',
        fullName: 'Bekzod Toshev',
        role: 'student',
        level: 1,
        mustChangePassword: true,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      ManagedUser(
        userId: 'u4',
        username: 'admin',
        fullName: 'Asrbek',
        role: 'superadmin',
        createdAt: now.subtract(const Duration(days: 200)),
        lastSignInAt: now.subtract(const Duration(minutes: 2)),
      ),
    ];
  }
}

/// Returned once, when an account is created. The password exists in readable
/// form only in this object — nothing stores it — so it has to reach the admin
/// before the dialog closes.
class CreatedAccount {
  const CreatedAccount({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.password,
  });

  final String userId;
  final String username;
  final String fullName;
  final String password;
}
