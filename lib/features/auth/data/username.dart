/// Turning a login handle into the address Supabase Auth identifies by.
///
/// Supabase needs an email or a phone number. Most students here have neither
/// in a form they use, so an admin issues a username and the app derives a
/// synthetic address from it:
///
///     aziza.k  ->  aziza.k@users.hanguk-academy.uz
///
/// Nothing is ever sent to that domain. The derivation is deliberately local
/// arithmetic rather than a server lookup: an endpoint that answers "does this
/// username exist?" before the user has signed in would let anyone enumerate
/// the roster one guess at a time.
///
/// Kept in step with `20260807140000_username_accounts.sql` and the
/// `EMAIL_DOMAIN` constant in `supabase/functions/admin-users/index.ts`.
abstract final class HkAuthNaming {
  static const internalEmailDomain = 'users.hanguk-academy.uz';

  /// Same shape the database CHECK constraint enforces: 3–32 characters,
  /// lowercase letters, digits and `. _ -` inside, alphanumeric at both ends.
  static final usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$');

  /// What the user typed, reduced to the canonical form. Someone reading a
  /// login off a slip of paper will capitalise it or add a space, and being
  /// refused for that would be indistinguishable from a wrong password.
  static String normalize(String input) => input.trim().toLowerCase();

  static bool isValid(String username) =>
      usernamePattern.hasMatch(normalize(username));

  /// The address handed to Supabase. Accepts a real email unchanged, so an
  /// admin account created by hand with a genuine address still signs in.
  static String toAuthEmail(String usernameOrEmail) {
    final value = normalize(usernameOrEmail);
    if (value.contains('@')) return value;
    return '$value@$internalEmailDomain';
  }

  /// The reverse, for display: strips the synthetic domain but leaves a real
  /// address alone.
  static String toDisplayName(String email) {
    final value = email.trim();
    if (value.endsWith('@$internalEmailDomain')) {
      return value.substring(0, value.length - internalEmailDomain.length - 1);
    }
    return value;
  }

  /// Why a username was rejected, in Uzbek, or null when it is fine.
  static String? validationError(String input) {
    final value = normalize(input);
    if (value.isEmpty) return 'Login kiriting';
    if (value.length < 3) return "Login kamida 3 ta belgidan iborat bo'lsin";
    if (value.length > 32) return "Login 32 ta belgidan oshmasin";
    if (value.contains('@')) return "Loginda @ belgisi bo'lmasin";
    if (!usernamePattern.hasMatch(value)) {
      return 'Faqat kichik harflar, raqamlar, nuqta, tire va pastki chiziq';
    }
    return null;
  }
}
