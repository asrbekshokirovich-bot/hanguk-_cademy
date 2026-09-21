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
| `teacher` | Asosiy · Darsim · Talabalarim · Baholash · Jadval · Yozuvlar |
| `admin` | Boshqaruv · Talabalar · O'qituvchilar · Guruhlar · Jadval · To'lovlar |
| `superadmin` | the admin's six, plus Jonli · Moliya · Adminlar |

The admin tier is split in two, because the two jobs carry different risk.
An `admin` runs the school day. A `superadmin` is the school's owner: it
runs the school day too, and does the two things an admin may not — it
issues the administrator accounts, and it reads the books.

That is a change from the first cut, which held the top tier to Adminlar and
Moliya and nothing else so the split could not go decorative. It read well
and worked badly. The two accounts are one person: he could not open a live
room to end a lesson a teacher had walked away from, or look at the
timetable he had just been asked about, without signing out and back in as
his own administrator. The separation that earns its keep is the money and
the accounts — the one SQL enforces — not a shorter menu.

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

All of that is held in SQL, which is why the dock could be opened up without
touching it. `ol_is_super()` guards the totals, the ledger and the
administrator accounts whatever the router lets through; `ol_is_admin()`
deliberately includes the top tier everywhere else, because issuing accounts
needs that reach.

The app's own rule is now one-directional: `HkNav.isSuperAdminRoute` sends an
*admin* home from `/super` and `/admin/finance`. Nothing sends a superadmin
anywhere. `test/superadmin_test.dart` guards both halves, the second by
driving the real router.

One layout consequence, in `app_shell.dart`: nine labelled sections is half
again the width of the admin's six, and at 1440 the dock printed over the
logo capsule and had "Adminlar" covered by the user cluster. The dock is now
capped at the width between them and scaled down past it. No other role
comes close to that width, so no other dock changed.

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

For a Windows build *he* can get, use the Actions tab instead:
`.github/workflows/windows-release.yml` builds the .exe on a runner that
already has the C++ workload and uploads `hanguk-academy-windows.zip`. He
unzips it and runs `hanguk_online.exe` — nothing to install on his machine.
The whole Release folder is zipped, not just the .exe: on its own the .exe
opens a dialog about a missing `flutter_windows.dll`.

### Shipping the Android app

`docs/play-store.md` is the whole Play procedure, written for the owner.
Three things in it are easy to get wrong and were:

- **INTERNET.** Flutter declares it only in the debug and profile manifests.
  A release built from the template has no network at all, and fails as a
  connection error on a device nobody is watching. It is in the main manifest
  now.
- **R8.** Minification pulls in the engine's Play-deferred-components code,
  whose library is not on the classpath, and the build stops with "Missing
  class com.google.android.play.core…". `-dontwarn` for that package.
- **Signing.** `android/key.properties` (gitignored) supplies the release
  key; without it the build falls back to the debug key and says so, rather
  than quietly producing something Play will reject.

The bundle is built by `.github/workflows/android-release.yml` — Actions tab,
"Run workflow" — so the owner never installs the Android SDK. The keystore
lives in repository secrets.

Store screenshots come from `test/store_screenshots_test.dart`, tagged out of
the default run:

```bash
flutter test test/store_screenshots_test.dart --tags store --update-goldens
```

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
flutter test             # 148 tests
flutter build linux --release
```

**Goldens are Linux PNGs.** They are tagged `golden` (`dart_test.yaml`
declares the tag; nothing is excluded by default, so the command above still
runs everything). The tag exists so a run on another platform can opt out:
the Windows job uses `flutter test --exclude-tags golden`, because a golden
compares how one machine rasterised text and on a Windows runner all of them
differ by a percent or two while the app is fine. If you ever regenerate
goldens, do it on Linux, or every other machine will disagree with you.

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
  migrations/      11 files; the last one is storage policy, see §5
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

Supabase project `iohchwogpzhqmtqyjrrz` — the id `lib/core/env.dart` builds
against, which is the one to trust. Every table is prefixed `ol_`. The rest
of this section was written on 2026-08-07 and the migration list below has
not been re-checked since; read it as history, and confirm anything you are
about to rely on against the live project by the method at the end.

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
| `20260919120000_storage_uploads` | RLS on the `uploads` storage bucket |

`200000` and `210000` cannot be pasted into the SQL Editor together:
Postgres will not let a newly added enum value be used in the transaction
that added it.

**All but the last are applied to the live project.** So is
`seed/003_remove_starter_data.sql` — the demo fixtures are gone from the real
database. Do not re-run `001_starter_data.sql`.

### The `uploads` storage bucket

Homework attachments live here, not in a table. One bucket, two folders, told
apart by the first path segment because they have different rules:

```
submissions/<assignment_id>/<student_id>/<file>   written and read by that
                                                  student, read by staff
materials/<lesson_id>/<file>                      written by staff, read by
                                                  anyone signed in
```

The student id is a **folder** and not part of the filename, so that
`storage.foldername(name)[3]` can be compared against `auth.uid()`. Path
segments are 1-indexed.

Two things have to be true or uploads fail, and they fail differently:

- **The bucket must be private.** A public bucket serves every object to
  anyone holding the URL with no policy consulted, so one student could read
  another's homework by guessing an id. `LessonsRepository.signedUploadUrl`
  assumes private: it signs a link for 600 seconds, which is the only address
  a private object has.
- **`20260919120000_storage_uploads.sql` must be run.** The bucket was created
  in the dashboard, which creates it with **no policies at all**, and
  `storage.objects` has RLS on. With no policy, every upload comes back
  `42501` — "new row violates row-level security policy". A bucket that exists
  is not a bucket that works; check Storage → uploads → Policies shows four.

### Recording, and where the files live

LiveKit Egress writes each live room to Cloudflare R2, and a `pg_cron` job
files the result. Two migrations set it up
(`20260921120000_livekit_egress_step1.sql`, `..._step2.sql`) and both are
applied.

```
ol_egress_config     one row: R2 endpoint, region, bucket, key, secret.
                     RLS on, zero policies — same mechanism as
                     ol_livekit_config.
ol_lesson_egress     one row per lesson being (or having been) recorded:
                     egress_id, filepath, status, error.
ol_v_lesson_recording  lesson_id + status only, readable by anyone signed
                     in. Everyone in a room is entitled to know they are
                     being recorded; nobody else's business is the rest.
```

The job (`ol_egress_tick`, every minute) does three separable things: starts
a recording once a live lesson has somebody in the room, stops it when the
lesson ends, and writes the `ol_recordings` row when LiveKit reports the
file finished. A **job rather than a trigger** on `ol_lessons.status`,
because a room-composite egress needs a room and a room exists only after
somebody joins.

`video_url` therefore holds two shapes: a Supabase Storage path
(`materials/<lesson>/…`) for a teacher's own upload, and `r2://<key>` for a
server recording. The second is signed by `ol_recording_url()` →
`ol_s3_presign()`, AWS SigV4 in SQL, good for an hour. **The bucket stays
private**: R2 is one toggle away from world-readable, and a lesson full of
named children is not a thing to leave on an unlisted URL.

Traps, all of them paid for once:

- `pgsql-http`, not `pg_net`. The response has to be visible to debug any of
  this; pg_net delivers it to a table a moment later.
- pgcrypto has `hmac(bytea, bytea)` and `hmac(text, text)` and nothing in
  between, and there is no implicit cast. Every SigV4 argument goes through
  `convert_to(..., 'UTF8')`.
- `force_path_style: true`. R2, B2 and Supabase all address buckets by path.
- Never store LiveKit's reply verbatim: it echoes the request, and the
  request carries the bucket's access key.
- To check the whole chain from the SQL Editor:
  `select (extensions.http_get(ol_s3_presign('<key>'))).status;` → 200.

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
U=https://iohchwogpzhqmtqyjrrz.supabase.co
K=sb_publishable_zkcqpOhM_thc6J0pfwsnTg_eqgXqfcW
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
- **A comment that described a poll nothing performed.** `liveLessonProvider`
  was a `FutureProvider` under a doc comment about a thirty-second poll. A
  future resolves once, so the app asked what was on air at launch and never
  again: a student who opened it before their lesson read "Hozir jonli dars
  yo'q" for the whole hour it then ran, and the timetable called a finished
  lesson "Rejalashtirilgan" until some other event rebuilt the screen. It is
  a `StreamProvider` on a twenty-second loop now, with `_statusTick` putting
  the day and the week on the same cadence. `test/status_polling_test.dart`
  fails if any of it is reverted. Two things there are load-bearing: the loop
  **stops after one pass in demo mode**, or every widget test in the suite
  waits on a timer forever; and the tick is read through a plain `Provider`
  rather than watched as a stream, because a `StreamProvider` starts at
  `AsyncLoading` and that first transition would cost a second round trip on
  every screen open.
- **The same disease in the live room's participant list.**
  `roomParticipantsProvider` also described a timer it did not have. Presence
  expires by a 75-second heartbeat cutoff applied where the rows arrive, so
  in a room that has gone quiet it is never applied again — the last person
  to shut their laptop stayed listed for good, and whoever walked in next was
  shown a roomful of people who had left. It asks for a fifteen-second
  recheck now. Note **how**: `reEmittedEvery` re-sends the rows already in
  hand so the filter re-reads the clock. Re-running the provider on a timer
  would be three lines and the wrong three — a Supabase `.stream()` is a
  realtime channel, and rebuilding it four times a minute for everyone in a
  sixty-student room buys a timestamp comparison with a channel join and a
  full table read. `test/room_presence_test.dart` covers the mechanism; that
  demo mode starts no timer is covered by the live-room tests in
  `lesson_lifecycle_test.dart`, which would fail on a pending timer.
- **A microphone button that reported the tap, not the track.** It flipped a
  local boolean, so the button lit and `mic_on: true` went to
  `ol_room_presence` whether or not anything was published — on a denied
  permission, on a failed media connection, and on a project with no LiveKit
  at all. Everyone else in the room saw a live microphone beside a name they
  could not hear, and the person talking had nothing on screen suggesting
  otherwise. The control bar reads `LiveMediaSession.micOn` now, which is the
  published track; the buttons are disabled when there is nothing to speak
  into; and a refused device gets its own notice, because it is a different
  failure from a failed connection and it is one the person can go and fix.
- **Browsers will not play a room's audio, and will not say so.** Sound needs
  a user gesture first. Untreated, a lesson looks perfect and is silent in
  both directions — everyone waits for somebody else to speak. `connect()`
  calls `room.startAudio()` and listens for `AudioPlaybackStatusChanged`;
  while it is blocked the room shows a notice with an "Ovozni yoqish" button,
  because the permission is granted to a tap and there is no way to clear it
  on the person's behalf.
- **`LiveMediaSession.connect(null)` is idempotent, and has to be.** The room
  calls it from a post-frame callback, so notifying on an unchanged state
  rebuilds the screen, which schedules the callback, which calls it again.
  `test/live_media_test.dart` counts the notifications.
- **Controls and badges that described intentions rather than facts.** Four
  more of the same family, all in the live room, all fixed together with the
  microphone: the **screen-share button** was wired to `() {}` — pressable,
  silent, inert, now `setScreenShare`; the **self preview** was a box with
  "Siz" written in it whatever the camera was doing, so there was no way to
  learn whether your own camera worked except to ask; the **speaking ring**
  around the teacher's avatar was a 1.8-second loop with no audio behind it,
  announcing that somebody was talking through an entire silence; and the
  **nameplate** carried a lit microphone icon unconditionally.
- **`ol_room_presence.mic_on` is a claim, not an observation.** It is written
  by each client about itself, so a browser that crashed leaves a lit
  microphone beside a name for the length of the heartbeat cutoff. The
  participant list prefers `LiveMediaSession.micOf()`, which is the published
  track, and falls back to the presence row only where the media room has
  never heard of that person. The two line up because `ol_livekit_join()`
  signs the account id into the token's `sub`, which is what LiveKit calls
  the identity — the same id `ol_room_presence.user_id` holds. Note that
  `lesson.teacher.id` is **not** that id: it is an `ol_teachers` row id and
  matches nothing in the media room, which is why the stage takes the
  teacher's identity from the presence row flagged `is_host`.
- **Recording was announced everywhere and happened nowhere.** A switch in
  the lesson dialog, a column in the week table, a "Avto-yozuv yoniq" badge
  above it, a "Yozib olinmoqda" pill with a running clock on the live stage
  and another on the dashboard hero, and a play button over a scrubber in the
  recordings library that had no tap handler at all. Nothing recorded
  anything: there is no egress and no storage bucket. All of it now hangs off
  `HkEnv.recordingEnabled`, which is false, and the player surface says so in
  words. Turning the flag on is not enough on its own — there is still no
  decoder behind that surface.
- **The captions were one sentence, hard-coded.** A band under the live stage
  held `오늘은 자기소개를 연습하겠습니다` and its Uzbek translation — the same
  words in every lesson, for every person, with a "Subtitrlar" switch next to
  the microphone implying that something was listening, on by default. In a
  language school that is not a harmless placeholder: it is a lesson aid
  students would have leant on. The band and the switch are gone until there
  is speech recognition behind them.
- **Two buttons whose only job was to apologise.** "Testni boshlash" and
  "Vazifani ochish" were a full-width lime button and an outlined one that
  did nothing but raise a snackbar saying the module was not built. A control
  that looks like the thing to press should be the thing to press; both are
  now a line of text saying the feature is not available yet, which is the
  same news without the invitation.
- **Homework had a middle and no ends.** `ol_assignments` has been in the
  schema since the first migration and "Baholash" is built on what comes back
  against it, but nothing in the app ever wrote a row — a teacher was asked
  to mark work that could not be set, on a screen with no way of ever ceasing
  to be empty. And the only place an assignment was ever shown was the
  recording-detail page, which is reachable through a recording, of which
  there are none: so even a hand-written row would have been invisible to the
  student who owed it.
  Both ends exist now. A teacher sets work from **one** door —
  `showAssignmentDialog` on Baholash, outside the AsyncSection for the reason
  in `test/empty_roster_test.dart` — and a student sees and answers it on the
  dashboard's "Uy vazifalari" card. No SQL was needed: `ol_assignments_write`
  already allowed `ol_is_staff()`, and `ol_assignment_submissions_insert`
  already allowed `student_id = auth.uid()`. Two things to know about the
  shape: there is **one assignment per lesson**, which the read path assumes
  and `setAssignment` maintains by updating rather than inserting a second
  (there is no unique index to upsert against); and a submission is **text
  only**, because `file_url` still has no storage bucket behind it and an
  upload button would be the play button all over again.
  Two holes the same size were found on the way and closed with it: the
  **grade was written where nobody could read it** — the grading dialog has
  always collected a score and a comment, and no student screen showed
  either, so a teacher was marking into a void — and a **teacher could not
  see the timetable at all**. Their dock had no Jadval, so "Bugungi
  darslarim" was their whole view of the week and "when is my next class" had
  no answer inside the app. `/schedule` gates its create button on `isAdmin`,
  so they get it read-only and the router needed no change.
- **Every attendance percentage was a fixture.** `ol_attendance` has been in
  the schema since the first migration and is what all of them are computed
  from — the admin dashboard's average, the teacher's, the figure beside each
  name in "Talabalarim" — dividing `seconds_attended` by the lesson's length.
  Nothing wrote a row, so against the real database every one of those
  numbers was zero and what appeared on screen came from `*_demo_data.dart`.
  The live room banks the time now, on the same 30-second heartbeat that
  refreshes presence and again on the way out. Measured, not marked: the room
  already knows who is in it, which is a better record than a register
  somebody has to remember to fill in, and it is what the columns were shaped
  for — `seconds_attended` accumulates across rejoins so a dropped connection
  does not zero a lesson. **Students only.** A teacher is present by
  definition and averaging their perfect attendance in with the class would
  lift every figure on the dashboard for no reason.
- **Nothing had ever created a notification.** `ol_notifications` is what the
  bell, the red dot and the whole panel are built on, and no trigger, no RPC
  and no line of client code had ever inserted a row — so against the real
  database the bell was permanently empty and the three notices on screen
  came from the fixtures. Staff actions announce themselves now: setting
  homework tells everyone enrolled in that lesson, marking it tells the one
  student. Sent from the client because `ol_notifications_insert` already
  admits `ol_is_staff()`, and best-effort because an announcement that fails
  must not fail the thing it was announcing. The wording follows what
  happened — a teacher fixing a typo a week later does not tell twenty
  students they have new homework.
- **Every student was flagged "Diqqat".** `TeacherStudent.needsAttention` was
  `attendance < 0.8 || progress < 0.6`, and `progress` is the share of the
  available recordings a student has watched — computed from
  `ol_recording_progress`, which has no writer, because there is no player
  and nothing to play. It reads zero for everybody, so the second half of
  that rule was always true and a teacher opening "Talabalarim" found their
  entire class marked as needing attention, on the screen whose whole job is
  to pick out the two who do. The rule now ignores the half that is not
  measured, and the "O'zlashtirish" column goes with it, both behind
  `HkEnv.recordingEnabled`. Attendance, the other half, became real in the
  same pass.
- **The app declared no localisations at all, and a date picker cannot be
  built without them.** No `flutter_localizations`, no `supportedLocales`, no
  delegates — which nothing noticed until the first Material widget that
  needs `MaterialLocalizations` appeared. `showDatePicker` is one: pressing
  "Muddat qo'yish" threw while building, and a thrown build is a **white
  window with nothing written in it**. The three values are named in
  `main.dart` (`hkLocale`, `hkSupportedLocales`, `hkLocalizationsDelegates`)
  so `test/assignment_dialog_test.dart` asserts against the ones the app
  actually uses rather than a copy; empty any of them and that test says "No
  MaterialLocalizations found". Flutter ships Uzbek material strings, so the
  picker is in Uzbek.
- **A teacher was asked to mark work they could not read.** The student's
  answer goes into `ol_assignment_submissions.note`, through
  `ol_v_submissions`, into `Submission.note` — and no screen displayed it. So
  the grade dialog showed a name and a title and asked for a mark out of 100
  on writing the teacher had no way of seeing. It shows the answer now, above
  the box the mark goes in.
- **A teacher could not put a lesson on the timetable, so could not set any
  homework.** Homework hangs off `ol_assignments.lesson_id`, scheduling was
  gated on `UserProfile.isAdmin`, and the app's whole answer to a teacher
  with an empty timetable was a sentence telling them to go and find an
  administrator. `ol_lessons_write` admits any staff account, so the gate was
  the app's alone: a teacher may now add a lesson (from "Jadval", or from the
  set-homework dialog's empty state, which is where they find out they need
  one) and may edit **their own**. The timetable is still the
  administrator's; owning your own class is not the same as rearranging the
  school. NB `myTeacherId()` answers with the demo teacher's id for anybody
  in demo mode, so read it only when the profile is staff — otherwise a
  student is handed an edit pencil by a fixture.
- **`'$e'` straight into the error line.** Every dialog printed the raw
  exception, so a duplicate group name read `PostgrestException(message:
  duplicate key value violates unique constraint "ol_groups_name_key", code:
  23505...)` and a null in our own code read `Null check operator used on a
  null value` — English, addressed to nobody in the building. `hkErrorMessage`
  (lib/core/errors.dart) is the one translator; the repositories keep throwing
  `StateError` with Uzbek text and it passes those through untouched. That
  null was real: when a teacher has no lessons, the picker is a sentence
  rather than a dropdown, so `validate()` had no field to refuse and
  `_lessonId!` threw. Guard the value and disable the button — a form whose
  field is conditional cannot rely on its validator.
- **The teacher could not see the homework they had set.** "Baholash" is
  built on `ol_v_submissions`, which has a row only once a student has handed
  something in — so setting homework changed nothing on screen, and *saved
  but nobody enrolled*, *saved on somebody else's lesson* and *not saved at
  all* all read as "Hali vazifa topshirilmagan". There is a "Berilgan
  vazifalar" strip above the queue now, with `handedIn/enrolled` per
  assignment and a warning where the lesson has no group. `ol_assignments` is
  readable by anyone signed in (`ol_assignments_select using (true)`), so it
  needed no migration.
- **Every list was read once per launch.** A Riverpod 3 provider is kept
  alive by default (`isAutoDispose: false`), so each staff list was fetched
  when its screen first opened and never again. An admin put three students
  in a teacher's group; the teacher's "Talabalarim", open since the morning,
  went on saying "Sizga hali guruh biriktirilmagan" while the admin panel
  showed the same three students under that teacher's name. The database was
  right throughout — `ol_v_teacher_students` returns them for that account,
  which is how this was finally pinned down (emulate the session in the SQL
  editor: `select set_config('request.jwt.claims', json_build_object('sub',
  <uid>, 'role', 'authenticated')::text, false);` then query the view). The
  admin never noticed because their own dialogs invalidate what they wrote.
  The staff lists are `isAutoDispose: true` now, so leaving a screen drops
  the cache; homework and notifications ride the 20-second status tick.
  **A provider that is kept alive pins everything it watches**, so a derived
  one (`pendingSubmissionsProvider`) has to be auto-dispose as well or it
  quietly undoes the fix.
- **Handouts with nowhere to be handed out.** `ol_materials` has been in the
  schema from the first migration and `LessonDetailScreen` has always listed
  it — but that screen hangs off a **recording**, and there are none, so a
  worksheet was unreachable even if a row had existed. Nothing ever inserted
  one either. Both ends are wired now: "Yangi vazifa" uploads a handout to
  `materials/<lesson_id>/` and records the row, and the student's homework
  card lists the handouts for that lesson. `ol_materials.url` therefore holds
  **two kinds of thing** — an ordinary link on a hand-written row, an object
  path on an uploaded one — so open it through
  `LessonsRepository.materialLink`, never `launchUrl` directly, or the path
  goes to the browser as a relative URL and nothing happens.
- **Homework that could only be typed.** Half of what this school sets is a
  photograph of an exercise book or a recording of somebody reading aloud.
  `file_url` has been in the schema from the first migration and
  `ol_v_submissions` has always selected it; nothing wrote or read it, and
  there was no bucket behind it. There is one now (§5) and the round trip is
  wired: the student attaches, the teacher opens a signed link, and both see
  the filename in between. **`file_picker` 13.x is not the API in every
  tutorial**: `FilePicker.pickFile()` is static and returns a handle, there is
  no `FilePicker.platform`, and `PlatformFile` has no `.bytes` or `.size` —
  it has `readAsBytes()`, `lengthSync()` and `length()`. The handle shape is
  the better one here: the bytes are read when the work is sent, not when the
  file is chosen, so picking a 40 MB video and then closing the dialog costs
  nothing.

---

## 8. Not built yet

Roughly in the order they matter:

1. **Payment recording UI.** `StaffRepository.recordPayment` and
   `confirmPayment` exist and work; no button is wired to them. The finance
   screen is read-only.
2. **Live captions.** Removed rather than faked — see §7. Bringing them back
   means real speech recognition: a transcription service, a stream of it per
   room, and a decision about who pays for it. The band and the toggle can
   come back the moment there is something to put in them.
3. **A player inside the app.** A recording opens in whatever the machine
   plays video with, because there is no decoder in the app — `pubspec.yaml`
   declares no `video_player`, no `media_kit`. That is why
   `ol_recording_progress` still has no writer and why
   `HkEnv.watchProgressEnabled` is false: a file playing in another program
   cannot report a position, and every percentage derived from it is zero.
4. **Was: recording the room on the server.** Done — see §5. Kept here only
   as a note on what it took: A lesson is kept today because the
   teacher uploads their own capture from "Yozuvlar" — `ol_recordings_write`
   admits `ol_is_staff()`, so the row needs no migration, and the file goes
   to `materials/<lesson_id>/`, which every signed-in account may read. The
   app has no decoder, so the play button hands the file to the machine.
   Doing it properly means **LiveKit egress**: the API key and secret are
   already in `ol_livekit_config` and `ol_jwt_hs256` can already sign a
   `roomRecord` token, so the only missing capability in the database is an
   outbound HTTP request. That needs `pg_net` enabled, a migration (an egress
   config table, start/stop functions, and a `pg_cron` poll to insert the row
   when egress completes) and S3-compatible storage. Prove it by hand from
   the LiveKit dashboard before writing any of it. **Do not** revive the Edge
   Function route (§7) and do not try `flutter_webrtc`'s MediaRecorder: it is
   not implemented on Windows at all and is single-track where it exists.
4. **Quizzes.** `ol_quizzes` is read and drawn; there is no screen for
   setting one and no screen for taking one. Homework is done — see §7 — but
   a quiz is a different shape and still has nothing behind it.
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
