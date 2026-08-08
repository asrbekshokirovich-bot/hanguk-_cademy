# Hanguk Academy — Onlayn ta'lim · Handoff

**Read this first.** It is written for the next assistant picking the project
up cold, and for the owner reading over their shoulder. Everything below is
what the project actually is on 2026-08-07, not a plan.

The owner is **Asrbek** (asrbekshokirovich@gmail.com). He runs a Korean
language academy in Uzbekistan. **He is not a programmer** — he works from
Windows CMD, and the working assumption should be that every instruction needs
the exact command and the exact folder, in Uzbek. Past sessions lost real time
to him running `git pull` from `C:\Users\Xojamurod` instead of the project
folder, and to pasting TypeScript into the SQL editor. Say where, then what.

---

## 1. What this is

One Flutter codebase for an academy's online-lessons platform: **Windows
desktop, Android, iOS and web**. It replaces nothing — the academy has no
existing system.

The UI came from two rounds of a designer's HTML prototype
(`Hanguk_Academy_Online_Design.zip`, then `..._Design_1.zip`). The prototype
is the specification: dark glass panels over an ambient orb background, a
vibrant lime accent, a floating command dock instead of a sidebar. It has
been transcribed, not reinterpreted.

The interface language is **Uzbek (Latin)**. All user-facing strings are
Uzbek. Code, comments and commits are English.

### The three roles

The role comes from the account. **There is no role switcher** — the
prototype has one so a designer can preview all three; in the product it
would be either a lie or a hole. `HkNav.forRole` gives each role its own
dock:

| Role | Sections |
|---|---|
| `student` | Asosiy · Jonli · Yozuvlar · Jadval |
| `teacher` | Asosiy · Darsim · Talabalarim · Baholash · Yozuvlar |
| `admin` | Boshqaruv · Talabalar · O'qituvchilar · Guruhlar · Jadval · To'lovlar |
| `superadmin` | Adminlar · Moliya — **and nothing else** |

The admin tier is split in two, because the two jobs carry different risk.
An `admin` runs the school day. A `superadmin` does exactly two things: it
issues the administrator accounts that run the school day, and it reads the
books. The two docks **do not overlap** — a superadmin cannot open the
roster, the groups or the timetable at all.

The money line is drawn between *a payment* and *the totals*, not around
payments as a whole. The person a student hands cash to is the one at the
desk, so an admin records and confirms that student's fee and sees its
amount ("To'lovlar"). What the academy took in altogether, what is
outstanding, the whole ledger — that is Moliya, and superadmin only.
`ol_admin_kpis` is the only thing in the schema that sums money and it
returns zero for both figures below the top tier, so the separation does not
rest on a screen declining to add a column up. Deleting a payment row is
superadmin-only too: correcting a mistake is an update, and an update leaves
the row behind to be looked at.

That last part is the app's job alone, and it is easy to undo by accident.
The database deliberately lets a superadmin outrank an admin everywhere
(`ol_is_admin()` includes it), because issuing accounts needs that reach —
so nothing in SQL would turn a superadmin away from `/admin/students`. The
router does, in one rule: anything outside `HkNav.isSuperAdminRoute` sends
the top tier home. `test/superadmin_test.dart` guards it.

### How the academy is meant to work

This is the part to internalise, because most design decisions fall out of it:

1. **Nobody signs up.** There is no public registration, no email login. The
   admin issues every account — username + a system-generated password shown
   exactly once. First sign-in forces a password change.
2. **The admin creates lessons.** Teachers teach what is on the timetable;
   they do not schedule.
3. **A student's teacher is whoever teaches their group.** There is
   deliberately no "assign a teacher" action. Setting the two independently
   is how a roster ends up disagreeing with the schedule, so assignment goes
   through the group and only through the group.
4. **A lesson attached to a group enrols that group's members**, by database
   trigger. Joining a group enrols the student in that group's *future*
   lessons only — they did not attend the past ones.

---

## 2. Running it

Flutter 3.44.9 / Dart 3.12.2.

```bash
flutter pub get
flutter run -d chrome      # or: -d windows / -d linux / -d android
```

No flags needed — the Supabase URL and publishable key are compile-time
defaults in `lib/core/env.dart`. Overriding them:

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

**Demo mode.** With no credentials, `supabaseClientProvider` is null and every
repository serves fixtures from `*_demo_data.dart`. Writes throw a plain-Uzbek
`StateError` rather than hanging. This is what the tests run against, and what
makes the screens reviewable without a backend.

**Windows desktop** needs Visual Studio with "Desktop development with C++".
The owner does not have it; he has been running the web build. Do not
recommend `-d windows` to him without that caveat.

### Deploying the web build

Vercel, from the GitHub repo. There is no Flutter runtime on Vercel, so
`scripts/vercel_build.sh` fetches a **pinned** SDK (3.44.9) into the build
cache and runs `flutter build web --release`; `vercel.json` points at
`build/web`. The first deploy pays a few minutes for the download, later
ones restore it from cache.

The version is pinned deliberately. A Flutter release that changes codegen
should break a local build, where someone is reading the error, rather than
a deploy nobody is watching. Bumping it means editing both
`scripts/vercel_build.sh` and the local toolchain together.

`index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js` and
`version.json` are served `must-revalidate`; everything under `assets/` and
`canvaskit/` is immutable and cached for a year. Getting this backwards is
how a deploy lands and users keep running the previous build.

---

## 3. Verification — read this before you change anything

**There is no GPU in this environment.** Xvfb segfaults. Golden tests are the
only way to see whether a screen renders, and they have earned their keep —
four real defects were caught this way and would not have been caught
otherwise:

- `tint` never rendered anywhere. A `BoxDecoration` with both `color` and
  `gradient` silently drops the color. Found because a 94%-opaque dialog
  looked transparent in a golden.
- A fixed 620px stage overflowed the design's own 920px window.
- `LimeButton` overflowed by 7.7px inside a table cell — 24px of horizontal
  padding sized for a full-width CTA.
- `PulsingDot` crashed on dispose when `animate: false`.

Two goldens were also captured mid-animation and had to be fixed in the
*test*, not the widget — always pump past the animation:

```dart
await tester.pump();
await tester.pump(const Duration(milliseconds: 400));
```

Goldens embed rendered dates, so `lib/core/clock.dart` exists purely to make
them deterministic:

```dart
DateTime Function() hkNow = DateTime.now;   // tests pin it to a fixed instant
```

**Use `hkNow()`, never `DateTime.now()`, in anything that reaches the widget
tree.** A golden that embeds the wall clock fails on the next run a minute
later.

**Desktop goldens cannot see phone bugs.** Everything was verified at
1440×920 for weeks while the compact layout was quietly broken: the header
overlaid the first paragraph of every screen, two of the admin's six
sections were unreachable, and the stat tiles overflowed. `phone_golden_test`
renders at 390×844 with a notch and is now part of the check.

Full check before pushing:

```bash
flutter analyze          # must be "No issues found!"
flutter test             # 61 tests
flutter build linux --release
```

To review a screen you changed, regenerate and *look at the PNG*:

```bash
flutter test --update-goldens
# then read test/golden/goldens/<name>.png
```

---

## 4. Layout of the code

```
lib/
  core/            env, clock, router
  design_system/   tokens, layout breakpoints, navigation, widgets/
  features/
    auth/          login, forced password change, username rules
    admin/         account creation, issued-password dialog
    lessons/       dashboard, schedule, live room, recordings, search
    staff/         teacher + admin panels, groups, lesson dialog
supabase/
  migrations/      10 files, all applied to the live project
  seed/            starter data, make-admin, cleanup
  functions/       admin-users — DEAD, see §7
test/
  golden/          27 goldens, incl. 4 at phone size
```

**Riverpod 3** — note the API changes that cost time before:
`StateProvider` moved to `package:flutter_riverpod/legacy.dart`,
`AsyncValue.valueOrNull` is now `.value`, `Override` is exported from
`misc.dart`, and providers auto-dispose by default.

**Routing** is go_router with a role-aware `redirect`. Staff routes are gated
there as well as hidden from the dock — a hidden menu item is not access
control, and a bookmarked URL from a demoted account would otherwise open.

---

## 5. The database

Supabase project `dfduzrzqzghsiblpztdm`. Every table is prefixed `ol_`.

**The heavy lifting is in SQL.** Attendance and progress percentages, teacher
load, outstanding balances all come out of views and RPCs. Two reasons: those
numbers are aggregates over rows a single user is not allowed to read
individually, and a roster of sixty students would otherwise be sixty round
trips.

Money is `bigint` whole so'm — never floating point. "Overdue" is derived from
the due date at read time, not stored.

### Migrations, in order

| File | What it does |
|---|---|
| `..120000_online_lessons` | 12 tables, views, RLS, `ol_dashboard_stats()` |
| `..140000_username_accounts` | username + `must_change_password` |
| `..150000_fix_users_view` | `ol_v_users` as a definer view |
| `..160000_groups_grading_payments` | groups, grading, payments |
| `..170000_admin_user_rpc` | `ol_admin_create_user` / `_reset_password` / `_delete_user` |
| `..180000_teacher_sync_and_scheduling` | teacher sync trigger, `ol_v_groups`, `ol_assign_student_group`, enrolment triggers |
| `..190000_admins_are_not_teachers` | admins off the teaching roster |
| `..200000_superadmin_role` | adds the enum value — **must run alone** |
| `..210000_superadmin_rules` | the tier's policies, views and RPCs |
| `..220000_admin_takes_payments` | admin records payments; totals stay super |

`200000` and `210000` cannot be pasted into the SQL Editor together:
Postgres will not let a newly added enum value be used in the transaction
that added it.

**All seven are applied to the live project.** So is
`seed/003_remove_starter_data.sql` — the demo fixtures are gone from the real
database. Do not re-run `001_starter_data.sql`.

### Live data as of this handoff

3 accounts, all created by the owner: `admin` (Asrbek, role admin), `demo`
(student), `demo.o` (teacher). Zero lessons, groups, payments, recordings and
notifications. The system is empty and ready for real data.

### RLS lessons already learned

- `security_invoker = true` on a view that joins `auth.users` returns **42501
  for everyone**, because `authenticated` has no grant on that schema. Views
  that need `auth.users` must be **definer** views with the permission rule in
  the `WHERE` clause (`ol_is_staff()` or a self check). This was found by
  querying the live project, not by reading the SQL.
- A hand-created `auth.users` row breaks GoTrue with *"Database error querying
  schema"* if the token columns (`confirmation_token`, `recovery_token`, …)
  are NULL — GoTrue scans them into Go strings. Write `''`, never NULL. The
  create-user RPC does this.
- Verified empirically: anonymous inserts into `ol_lessons` and `ol_payments`
  both return `42501`.

### How to check the database from here

There is no working Supabase MCP access (it is bound to a different
organization — "permission denied"). Verify over the REST API instead. This
works and is how every claim in §5 was confirmed:

```bash
U=https://dfduzrzqzghsiblpztdm.supabase.co
K=sb_publishable_3B5-KHohbmx-cysPPo4e7Q_uou0x2o1
T=$(curl -s -X POST "$U/auth/v1/token?grant_type=password" \
     -H "apikey: $K" -H 'content-type: application/json' \
     -d '{"email":"admin@users.hanguk-academy.uz","password":"<parol>"}' \
   | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -s "$U/rest/v1/ol_v_admin_students?select=*" -H "apikey: $K" -H "authorization: Bearer $T"
```

Distinguishing an empty result from a broken one: `[]` means the object exists
and RLS filtered it; `42P01` means the relation is missing; `42883` means the
function is missing.

**Migrations are applied by the owner, by hand.** Give him a raw GitHub link
to paste into the Supabase SQL Editor:

```
https://raw.githubusercontent.com/asrbekshokirovich-bot/hanguk-_cademy/main/supabase/migrations/<file>.sql
```

Then verify the result yourself over REST. Do not assume it took.

---

## 6. Accounts and passwords

Usernames, not emails. `lib/features/auth/data/username.dart` maps a username
to an internal address `<username>@users.hanguk-academy.uz`, because GoTrue
wants an email. **The derivation is local arithmetic on purpose** — a server
lookup would let anyone enumerate the roster.

Creating an account calls `ol_admin_create_user`, which returns a generated
password. `showPasswordResultDialog` shows it once and **cannot be dismissed
by tapping the barrier** — that is the only moment it is readable. The account
is flagged `must_change_password`; the router refuses to route anywhere except
`/change-password` until it is cleared.

Accounts are issued from **one place**: Talabalar → "Yangi talaba" → the role
picker in the dialog. The teachers screen used to have its own button; it was
removed at the owner's request, because two doors to the same thing is how an
office ends up with two lists of the same people.

---

## 7. Things that are dead or were traps

- **`supabase/functions/admin-users/`** — an Edge Function that was never
  successfully deployed after five attempts, always 404. In the browser it
  surfaced as `FunctionsFetchException(status: 0, Failed to fetch)` because
  the gateway's 404 preflight omits `content-type` from the allowed headers,
  so the request never left Chrome. **It is dead code.** All three operations
  now live in SECURITY DEFINER database functions. Do not revive it without a
  reason.
- **`profileProvider` caching a pre-login throw.** The router read the profile
  before sign-in and kept the failure, so an admin displayed as "Talaba" and —
  worse — the password gate never fired, because the redirect bailed on a null
  profile. The fix is `ref.watch(authStateProvider)` *first* inside
  `profileProvider`. `test/profile_refresh_test.dart` fails if it is reverted.
- **Empty states hiding their own remedy.** The create buttons used to live
  inside `AsyncSection`'s data builder, so an empty roster replaced the button
  with "Hali talaba qo'shilmagan" — the one moment you certainly need it.
  Keep create buttons **outside** the AsyncSection.
  `test/empty_roster_test.dart` guards this.

---

## 8. Not built yet

Roughly in the order they matter:

1. **Payment recording UI.** `StaffRepository.recordPayment` and
   `confirmPayment` exist and work; no button is wired to them. The finance
   screen is read-only.
2. **LiveKit video.** The live room is a complete shell — participants,
   controls, chat, the "davom etmoqda" clock — with no media layer. Tables
   carry `live_room`; nothing writes it.
3. **Recording playback.** The library lists recordings and tracks watch
   progress; there is no player and no storage bucket.
4. **Homework and quizzes.** Grading reads `ol_assignment_submissions`; there
   is no screen for *setting* an assignment.
5. **App icons and store packaging.** Android/iOS build but ship with the
   default Flutter icon.

---

## 9. Working with the owner

- Reply in **Uzbek**. Code and commits in English.
- He pushes directly to `main` on
  `https://github.com/asrbekshokirovich-bot/hanguk-_cademy`. Mirror to
  `claude/flutter-desktop-android-ios-00ck9r` as well.
- Give him **one exact command per line**, with the folder to run it in. Say
  what he should see if it worked.
- When something needs the SQL Editor, give the raw GitHub link, not the SQL
  text — he has pasted the wrong thing into it before.
- He reviews by screenshotting the running app. Expect screenshots as bug
  reports, and read them carefully — the last three fixes came from one.
