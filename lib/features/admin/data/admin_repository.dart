import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../lessons/data/lessons_repository.dart';
import '../domain/managed_user.dart';

/// Account administration.
///
/// Reads go straight to the `ol_v_users` view — row-level security already
/// restricts it to staff. Writes that touch auth (create, delete, reset a
/// password) go through the `admin-users` Edge Function, because they need the
/// service-role key and that key must never be inside this app.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient? _client;

  bool get isDemo => _client == null;

  SupabaseClient get _db => _client!;

  static const _function = 'admin-users';

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
    final data = await _invoke({
      'action': 'create',
      'username': username,
      'full_name': fullName,
      'role': role,
      'level': level,
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
    final data = await _invoke({
      'action': 'reset_password',
      'user_id': userId,
    });
    return data['password'] as String;
  }

  Future<void> deleteUser(String userId) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _invoke({'action': 'delete', 'user_id': userId});
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

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final response = await _db.functions.invoke(_function, body: body);
    final data = response.data;

    if (response.status >= 400) {
      // The function answers with {"error": "..."} in Uzbek; surface that
      // rather than "FunctionsHttpError: 400", which tells the admin nothing.
      final message = data is Map && data['error'] != null
          ? '${data['error']}'
          : 'Server xatosi (${response.status})';
      throw AdminActionException(message);
    }
    if (data is! Map) {
      throw const AdminActionException('Serverdan kutilmagan javob keldi');
    }
    return Map<String, dynamic>.from(data);
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
