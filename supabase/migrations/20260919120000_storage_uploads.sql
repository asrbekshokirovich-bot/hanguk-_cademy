-- Row-level security for the `uploads` storage bucket.
--
-- The bucket holds two different things, told apart by the first folder in
-- the object path, because they have different rules:
--
--   submissions/<assignment_id>/<student_id>/<file>
--       A student's handed-in work. Written by that student, read by them
--       and by staff. Not readable by other students: one pupil must not be
--       able to open another's homework.
--
--   materials/<lesson_id>/<file>
--       What the teacher hands out. Written by staff, readable by everyone
--       signed in — a student cannot use a worksheet they cannot open.
--
-- The student id is a folder rather than part of the filename so that
-- `storage.foldername(name)[3]` can be compared against `auth.uid()`, which
-- is what scopes a student to their own work. Path segments are 1-indexed.
--
-- A private bucket is assumed. A public bucket serves every object to anyone
-- holding the URL, with no policy consulted at all, so the select rule below
-- would be decoration. Turn "Public bucket" off in Storage → uploads → Edit.
--
-- `ol_is_staff()` covers teacher, admin and superadmin (see
-- 20260807210000_superadmin_rules.sql) and is schema-qualified here because a
-- storage policy does not run with the app's search_path.

-- Idempotent: safe to paste twice, which is how it will be applied.
drop policy if exists ol_uploads_select on storage.objects;
drop policy if exists ol_uploads_insert on storage.objects;
drop policy if exists ol_uploads_update on storage.objects;
drop policy if exists ol_uploads_delete on storage.objects;

create policy ol_uploads_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'uploads'
    and (
      public.ol_is_staff()
      or (storage.foldername(name))[1] = 'materials'
      or (
        (storage.foldername(name))[1] = 'submissions'
        and (storage.foldername(name))[3] = auth.uid()::text
      )
    )
  );

create policy ol_uploads_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'uploads'
    and (
      (public.ol_is_staff() and (storage.foldername(name))[1] = 'materials')
      or (
        (storage.foldername(name))[1] = 'submissions'
        and (storage.foldername(name))[3] = auth.uid()::text
      )
    )
  );

-- Handing the same work in again replaces the file rather than piling up a
-- second copy, so an overwrite has to be allowed on the same terms.
create policy ol_uploads_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'uploads'
    and (
      (public.ol_is_staff() and (storage.foldername(name))[1] = 'materials')
      or (
        (storage.foldername(name))[1] = 'submissions'
        and (storage.foldername(name))[3] = auth.uid()::text
      )
    )
  )
  with check (
    bucket_id = 'uploads'
    and (
      (public.ol_is_staff() and (storage.foldername(name))[1] = 'materials')
      or (
        (storage.foldername(name))[1] = 'submissions'
        and (storage.foldername(name))[3] = auth.uid()::text
      )
    )
  );

create policy ol_uploads_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'uploads'
    and (
      (public.ol_is_staff() and (storage.foldername(name))[1] = 'materials')
      or (
        (storage.foldername(name))[1] = 'submissions'
        and (storage.foldername(name))[3] = auth.uid()::text
      )
    )
  );
