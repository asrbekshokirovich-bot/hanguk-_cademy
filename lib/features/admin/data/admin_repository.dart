import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../lessons/data/lessons_repository.dart';
import '../domain/managed_user.dart';

/// Account administration.
///
/// Reads go straight to the `ol_v_users` view — row-level security already
/// restricts it to staff.
///
/// Writes that touch auth (create, delete, reset a password) go through
/// SECURITY DEFINER database functions rather than the client, because the
/// privileges they need must never be inside this app. They were originally
/// in the `admin-users` Edge Function, which is still in the repo and does
/// exactly the same three jobs; deploying it needs dashboard access that has
/// not worked for this project, and the database is reachable from the SQL
/// editor. See `20260807170000_admin_user_rpc.sql` for the trade-off.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient? _client;

  bool get isDemo => _client == null;

  SupabaseClient get _db => _client!;

  Future<List<ManagedUser>> users() async {
    if (isDemo) return ManagedUser.demoRoster();
    final rows = await _db
        .from('ol_v_users')
        .select()
        .order('created_at', ascending: false);
    return rows.map((r) => ManagedUser.fromMap(r)).toList();
  }

  /// Creates an account and returns it together with the generated password.
  ///
  /// That password is the only time it is ever visible — it is not stored
  /// anywhere in readable form — so the caller must show it to the admin
  /// before dismissing the dialog.
  Future<CreatedAccount> createUser({
    required String username,
    required String fullName,
    required String role,
    int? level,
  }) async {
    if (isDemo) {
      throw StateError('Demo rejimda hisob yaratib bo‘lmaydi');
    }
    final data = await _rpc('ol_admin_create_user', {
      'p_username': username,
      'p_full_name': fullName,
      'p_role': role,
      'p_level': level,
    });
    return CreatedAccount(
      userId: data['user_id'] as String,
      username: data['username'] as String,
      fullName: data['full_name'] as String,
      password: data['password'] as String,
    );
  }

  /// Issues a new password. Returns it for the admin to pass on.
  Future<String> resetPassword(String userId) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    final data = await _rpc('ol_admin_reset_password', {'p_user_id': userId});
    return data['password'] as String;
  }

  Future<void> deleteUser(String userId) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _db.rpc('ol_admin_delete_user', params: {'p_user_id': userId});
  }

  /// Role and level are plain columns, so they change through the table —
  /// the admin's own RLS policy already permits it. No Edge Function round
  /// trip for something the database can authorise directly.
  Future<void> updateRole(String userId, String role, {int? level}) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _db
        .from('ol_profiles')
        .update({'role': role, 'level': level}).eq('user_id', userId);
  }

  /// Calls a `set`-returning admin function and unwraps its single row.
  ///
  /// Postgres raises are surfaced as PostgrestException with the message the
  /// function wrote — already in Uzbek — so they are passed straight through
  /// rather than wrapped in "PostgrestException(...)", which tells an
  /// administrator nothing.
  Future<Map<String, dynamic>> _rpc(
    String function,
    Map<String, dynamic> params,
  ) async {
    try {
      final data = await _db.rpc(function, params: params);
      if (data is List && data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const AdminActionException('Serverdan kutilmagan javob keldi');
    } on PostgrestException catch (e) {
      // 42883 is "function does not exist" — the migration has not been
      // applied. Saying so beats an opaque SQL error code.
      if (e.code == '42883' || e.message.contains('does not exist')) {
        throw const AdminActionException(
          'Server funksiyasi topilmadi. supabase/migrations dagi oxirgi '
          'migratsiya qo‘llanganini tekshiring.',
        );
      }
      throw AdminActionException(e.message);
    }
  }
}

/// A failure the admin can read and act on.
class AdminActionException implements Exception {
  const AdminActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

final managedUsersProvider = FutureProvider<List<ManagedUser>>((ref) {
  return ref.watch(adminRepositoryProvider).users();
});
