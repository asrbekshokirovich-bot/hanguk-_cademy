-- Promote an account to admin.
--
-- Run AFTER creating the user (Supabase Dashboard → Authentication → Users →
-- Add user, or by signing up from the app once the login screen exists).
--
-- Replace the email below with your own, then run. The migration's signup
-- trigger already created the ol_profiles row; this only changes its role.
--
-- Admin unlocks the schedule's "Yangi dars" button, the edit column and the
-- per-lesson auto-record toggle. Without it the same screens render read-only.

update ol_profiles p
   set role = 'admin',
       full_name = 'Asrbek'          -- ← ismingizni yozing
 where p.user_id = (
   select id from auth.users where email = 'siz@example.com'  -- ← email
 );

-- Check it took. Should print one row with role = admin.
select p.user_id, p.full_name, p.role, p.level
  from ol_profiles p
  join auth.users u on u.id = p.user_id
 where u.email = 'siz@example.com';                            -- ← email
