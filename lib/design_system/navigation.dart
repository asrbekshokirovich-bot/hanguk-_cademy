import 'package:flutter/material.dart';

/// One destination in the dock.
///
/// The second design round gives each role its own navigation rather than
/// hiding items from a shared bar: a teacher's "Darsim" and a student's
/// "Jonli" are the same route seen from opposite sides, and the admin shares
/// almost nothing with either. Modelling that as one enum with visibility
/// flags produced a dock that read as "things you cannot have".
class HkDestination {
  const HkDestination(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

/// Navigation per role. The role comes from the account — there is no role
/// switcher. The prototype has one so a designer can preview all three; in
/// the product it would be either a lie (a student cannot be an admin) or a
/// hole (if it worked).
abstract final class HkNav {
  static const student = <HkDestination>[
    HkDestination('Asosiy', Icons.grid_view_rounded, '/'),
    HkDestination('Jonli', Icons.videocam_rounded, '/live'),
    HkDestination('Yozuvlar', Icons.play_circle_outline_rounded, '/recordings'),
    HkDestination('Jadval', Icons.calendar_month_rounded, '/schedule'),
  ];

  static const teacher = <HkDestination>[
    HkDestination('Asosiy', Icons.grid_view_rounded, '/teacher'),
    HkDestination('Darsim', Icons.videocam_rounded, '/live'),
    HkDestination('Talabalarim', Icons.people_alt_rounded, '/teacher/students'),
    HkDestination('Baholash', Icons.check_circle_outline_rounded,
        '/teacher/grading'),
    // Read-only for them — the create button on that screen is gated on
    // `isAdmin`. It is here because a teacher could otherwise see only today:
    // "Bugungi darslarim" was their whole view of the timetable, so the
    // question "when is my next class" had no answer inside the app.
    HkDestination('Jadval', Icons.calendar_month_rounded, '/schedule'),
    HkDestination('Yozuvlar', Icons.play_circle_outline_rounded, '/recordings'),
  ];

  /// Runs the school day. No Moliya — money belongs to the tier above.
  static const admin = <HkDestination>[
    HkDestination('Boshqaruv', Icons.insights_rounded, '/admin'),
    HkDestination('Talabalar', Icons.people_alt_rounded, '/admin/students'),
    HkDestination('O‘qituvchilar', Icons.school_rounded, '/admin/teachers'),
    HkDestination('Guruhlar', Icons.groups_2_rounded, '/admin/groups'),
    HkDestination('Jadval', Icons.calendar_month_rounded, '/schedule'),
    // Taking a student's fee is front-desk work; reading the month's takings
    // is not. This is the first, "Moliya" is the second.
    HkDestination('To‘lovlar', Icons.receipt_long_rounded, '/admin/payments'),
    // The library had no entry in this dock at all. The owner's account is an
    // administrator's, so "why is the recording not in Yozuvlar" was asked by
    // the one person who could not open Yozuvlar — his only ways in were the
    // student dashboard's quick action and the search sheet.
    HkDestination('Yozuvlar', Icons.play_circle_outline_rounded, '/recordings'),
  ];

  /// The admin's dock plus the two screens that are the top tier's alone.
  ///
  /// It was the two on their own for a while, on the theory that the owner
  /// issues accounts and reads the books while somebody else runs the school
  /// day. In practice the two accounts are one person: he could not open the
  /// live room to end a lesson, or look at the timetable he had just been
  /// asked about, without signing in as his own administrator. The split that
  /// earns its keep is the one in SQL — `ol_is_super()` still guards the
  /// money and the administrator accounts — not a shorter menu.
  ///
  /// Moliya and Adminlar come last because they are the rarer errands; the
  /// school day is what the dock is opened for.
  static const superAdmin = <HkDestination>[
    HkDestination('Boshqaruv', Icons.insights_rounded, '/admin'),
    // The admin dock has no live entry — an administrator does not teach. The
    // owner does drop into a room, to end one a teacher left on air, and that
    // is the screen he was locked out of.
    HkDestination('Jonli', Icons.videocam_rounded, '/live'),
    HkDestination('Talabalar', Icons.people_alt_rounded, '/admin/students'),
    HkDestination('O‘qituvchilar', Icons.school_rounded, '/admin/teachers'),
    HkDestination('Guruhlar', Icons.groups_2_rounded, '/admin/groups'),
    HkDestination('Jadval', Icons.calendar_month_rounded, '/schedule'),
    HkDestination('To‘lovlar', Icons.receipt_long_rounded, '/admin/payments'),
    HkDestination('Yozuvlar', Icons.play_circle_outline_rounded, '/recordings'),
    HkDestination('Moliya', Icons.payments_rounded, '/admin/finance'),
    HkDestination('Adminlar', Icons.admin_panel_settings_rounded, '/super'),
  ];

  static List<HkDestination> forRole(String? role) => switch (role) {
        'superadmin' => superAdmin,
        'admin' => admin,
        'teacher' => teacher,
        _ => student,
      };

  /// Routes only the top tier may open. It reads one way now, not two: the
  /// superadmin goes everywhere an admin goes and these two besides, so this
  /// is what turns an *admin* away from the books, not what fenced the owner
  /// in. A plain admin asking for them is sent home, the same as a student
  /// asking for the admin panel.
  static bool isSuperAdminRoute(String location) =>
      location == '/super' || location.startsWith('/admin/finance');

  /// Where a role lands after signing in.
  static String homeFor(String? role) => forRole(role).first.route;

  /// The dock item to highlight for the current location. Longest matching
  /// route wins, so `/admin/students` does not light up `/admin`.
  static HkDestination? currentFor(String? role, String location) {
    HkDestination? best;
    for (final d in forRole(role)) {
      final matches = d.route == '/'
          ? location == '/'
          : location == d.route || location.startsWith('${d.route}/');
      if (matches && (best == null || d.route.length > best.route.length)) {
        best = d;
      }
    }
    return best;
  }

  /// Routes only staff may open, checked in the router. The dock already
  /// hides them, but a hidden menu item is not access control.
  static bool isTeacherRoute(String location) =>
      location.startsWith('/teacher');

  static bool isAdminRoute(String location) => location.startsWith('/admin');
}
