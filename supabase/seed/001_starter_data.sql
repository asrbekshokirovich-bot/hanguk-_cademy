-- Starter data for hanguk-online.
--
-- Run once, after the migration, from the Supabase SQL Editor. Safe to re-run:
-- every insert is keyed on a fixed uuid and does nothing on conflict, so a
-- second run will not duplicate anything.
--
-- Times are relative to `now()`, so whenever you run this you get a lesson
-- that is live *right now*, a couple already finished today, and the rest of
-- the week scheduled ahead. That matters for reviewing the dashboard: the
-- live hero banner only appears when a lesson actually has status 'live'.
--
-- This is demonstration content, not real scheduling. Delete it with:
--   delete from ol_lessons where id::text like 'a0000000-%';
--   delete from ol_recordings where id::text like 'b0000000-%';
--   delete from ol_teachers where id::text like '10000000-%';

-- ------------------------------------------------------------- teachers ---

insert into ol_teachers (id, full_name, initials) values
  ('10000000-0000-4000-8000-000000000001', 'Jasur Karimov',   'JK'),
  ('10000000-0000-4000-8000-000000000002', 'Aziz Rahimov',    'AR'),
  ('10000000-0000-4000-8000-000000000003', 'Nodira Yusupova', 'NY'),
  ('10000000-0000-4000-8000-000000000004', 'Malika Sodiqova', 'MS')
on conflict (id) do nothing;

-- -------------------------------------------------------------- lessons ---

insert into ol_lessons
  (id, title, category, description, teacher_id, starts_at,
   duration_minutes, status, auto_record)
values
  -- Finished earlier today.
  ('a0000000-0000-4000-8000-000000000001',
   'Grammatika · Daraja 2', 'Grammatika',
   'O''tgan zamon shakllari va ularning suhbatdagi qo''llanishi.',
   '10000000-0000-4000-8000-000000000003',
   date_trunc('day', now()) + interval '9 hours', 45, 'ended', true),

  -- Live right now: started 12m45s ago, which is what the dashboard hero
  -- and the live room's running clock read.
  ('a0000000-0000-4000-8000-000000000002',
   'Koreys tili · Suhbat amaliyoti', 'Koreys tili',
   'Kundalik suhbat iboralari, savol berish shakllari va tinglab tushunish '
   'mashqlari.',
   '10000000-0000-4000-8000-000000000001',
   now() - interval '12 minutes 45 seconds', 60, 'live', true),

  -- Later today.
  ('a0000000-0000-4000-8000-000000000003',
   'TOPIK tayyorgarlik', 'TOPIK',
   'TOPIK II o''qish bo''limi: matn tuzilishi va vaqtni taqsimlash.',
   '10000000-0000-4000-8000-000000000002',
   date_trunc('day', now()) + interval '16 hours', 90, 'scheduled', true),

  ('a0000000-0000-4000-8000-000000000004',
   'Tinglab tushunish', 'Tinglash',
   'Tabiiy tezlikdagi dialoglar va asosiy fikrni ajratish.',
   '10000000-0000-4000-8000-000000000004',
   date_trunc('day', now()) + interval '18 hours 30 minutes', 45,
   'scheduled', true),

  -- Tomorrow.
  ('a0000000-0000-4000-8000-000000000005',
   'Grammatika · Daraja 2', 'Grammatika', null,
   '10000000-0000-4000-8000-000000000003',
   date_trunc('day', now()) + interval '1 day 10 hours', 60,
   'scheduled', true),

  -- The one row with auto-record switched off, so the schedule's toggle
  -- column has both states to show.
  ('a0000000-0000-4000-8000-000000000006',
   'Suhbat amaliyoti', 'Koreys tili', null,
   '10000000-0000-4000-8000-000000000001',
   date_trunc('day', now()) + interval '1 day 15 hours', 90,
   'scheduled', false),

  ('a0000000-0000-4000-8000-000000000007',
   'TOPIK · Yozma bo''lim', 'TOPIK', null,
   '10000000-0000-4000-8000-000000000002',
   date_trunc('day', now()) + interval '2 days 11 hours', 90,
   'scheduled', true)
on conflict (id) do nothing;

-- ----------------------------------------------------------- recordings ---

insert into ol_recordings
  (id, lesson_id, title, category, description, teacher_id, recorded_at,
   duration_seconds, attendee_count, published)
values
  ('b0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002',
   'Suhbat amaliyoti · 8-dars', 'Koreys tili',
   'Kundalik suhbatda ishlatiladigan iboralar, savol-javob amaliyoti va '
   'talaffuz mashqlari. Dars oxirida qisqa test bor.',
   '10000000-0000-4000-8000-000000000001',
   now() - interval '6 days', 3588, 22, true),

  ('b0000000-0000-4000-8000-000000000002',
   'a0000000-0000-4000-8000-000000000003',
   'TOPIK · O''qish bo''limi', 'TOPIK', null,
   '10000000-0000-4000-8000-000000000002',
   now() - interval '8 days', 5050, 20, true),

  ('b0000000-0000-4000-8000-000000000003',
   'a0000000-0000-4000-8000-000000000001',
   'Grammatika · Daraja 2 — 7-dars', 'Grammatika', null,
   '10000000-0000-4000-8000-000000000003',
   now() - interval '9 days', 2642, 24, true),

  ('b0000000-0000-4000-8000-000000000004',
   'a0000000-0000-4000-8000-000000000004',
   'Tinglab tushunish · 5-dars', 'Tinglash', null,
   '10000000-0000-4000-8000-000000000004',
   now() - interval '11 days', 2335, 22, true),

  ('b0000000-0000-4000-8000-000000000005',
   'a0000000-0000-4000-8000-000000000002',
   'Suhbat amaliyoti · 7-dars', 'Koreys tili', null,
   '10000000-0000-4000-8000-000000000001',
   now() - interval '13 days', 3680, 21, true),

  ('b0000000-0000-4000-8000-000000000006',
   'a0000000-0000-4000-8000-000000000007',
   'TOPIK · Yozma bo''lim', 'TOPIK', null,
   '10000000-0000-4000-8000-000000000002',
   now() - interval '15 days', 3129, 19, true)
on conflict (id) do nothing;

-- ------------------------------------------- materials / quiz / homework ---

insert into ol_materials (id, lesson_id, name, kind, url, size_bytes) values
  ('c0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002',
   'Dars taqdimoti.pdf', 'pdf', 'https://example.com/taqdimot.pdf', 2411724),
  ('c0000000-0000-4000-8000-000000000002',
   'a0000000-0000-4000-8000-000000000002',
   'Yangi so''zlar lug''ati', 'doc', 'https://example.com/lugat.docx', 184320)
on conflict (id) do nothing;

insert into ol_quizzes (id, lesson_id, title, question_count) values
  ('d0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002', 'Dars testi', 10)
on conflict (id) do nothing;

insert into ol_assignments (id, lesson_id, title, body, due_at) values
  ('e0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002',
   'Uy vazifasi',
   'Darsda ko''rilgan 20 ta yangi so''zdan foydalanib qisqa matn yozing.',
   now() + interval '3 days')
on conflict (id) do nothing;
