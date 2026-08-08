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
  ];

  /// Not a superset of the admin's dock — a different job. The top tier does
  /// two things and nothing else: it issues the administrator accounts that
  /// run the school day, and it reads the books. Handing it the roster and
  /// the timetable as well would make the split decorative.
  static const superAdmin = <HkDestination>[
    HkDestination('Adminlar', Icons.admin_panel_settings_rounded, '/super'),
    HkDestination('Moliya', Icons.payments_rounded, '/admin/finance'),
  ];

  static List<HkDestination> forRole(String? role) => switch (role) {
        'superadmin' => superAdmin,
        'admin' => admin,
        'teacher' => teacher,
        _ => student,
      };

  /// Routes only the top tier may open — and, read the other way, the only
  /// routes it opens at all. A superadmin asking for anything else is sent
  /// home, the same as a student asking for the admin panel.
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
