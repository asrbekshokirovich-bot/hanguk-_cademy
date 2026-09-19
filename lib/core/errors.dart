import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns whatever a write threw into a sentence the person can read.
///
/// Every dialog in the app used to print `'$e'` into its error line, which on
/// a good day is `PostgrestException(message: duplicate key value violates
/// unique constraint "ol_groups_name_key", code: 23505...)` — English,
/// Postgres, and addressed to nobody in the building. On a bad day it is
/// `Null check operator used on a null value`, which is a bug report shown
/// to the one person who cannot act on it.
///
/// The repositories already throw `StateError` with Uzbek text for the cases
/// they know about (demo mode, a missing storage policy, not being signed
/// in); those come through unchanged.
String hkErrorMessage(Object error) {
  if (error is StateError) return error.message;
  if (error is PostgrestException) return _postgrest(error);
  if (error is AuthException) {
    return 'Sessiya tugagan. Ilovadan chiqib, qaytadan kiring.';
  }
  if (error is TypeError) {
    // A null that should not have been null: ours, not theirs. Named as such
    // rather than dressed up, because somebody has to be able to report it.
    return 'Ilovada ichki xatolik yuz berdi. Iltimos, qaytadan urinib '
        'ko‘ring — takrorlansa, shu oynani suratga olib yuboring.';
  }
  return 'Amal bajarilmadi: $error';
}

String _postgrest(PostgrestException e) {
  final text = e.message.toLowerCase();

  switch (e.code) {
    case '23505':
      // The unique constraint that actually gets hit here is the group name.
      return text.contains('name')
          ? 'Bunday nom allaqachon band. Boshqa nom tanlang.'
          : 'Bunday yozuv allaqachon bor.';
    case '23503':
      return 'Bog‘liq yozuv topilmadi — u o‘chirilgan bo‘lishi mumkin. '
          'Sahifani yangilab, qaytadan urinib ko‘ring.';
    case '23502':
      return 'Majburiy maydon to‘ldirilmagan.';
    case '42501':
      return 'Bu amal uchun sizda ruxsat yo‘q. Administratorga ayting.';
    case '42P01':
    case '42883':
      return 'Baza to‘liq sozlanmagan: kerakli jadval yoki funksiya yo‘q. '
          'Administratorga ayting.';
    case 'PGRST301':
      return 'Sessiya tugagan. Ilovadan chiqib, qaytadan kiring.';
  }

  if (text.contains('row-level security')) {
    return 'Bu amal uchun sizda ruxsat yo‘q. Administratorga ayting.';
  }
  if (text.contains('failed host lookup') ||
      text.contains('socketexception') ||
      text.contains('timeout')) {
    return 'Internet bilan bog‘lanib bo‘lmadi. Aloqani tekshiring.';
  }
  return 'Amal bajarilmadi: ${e.message}';
}
