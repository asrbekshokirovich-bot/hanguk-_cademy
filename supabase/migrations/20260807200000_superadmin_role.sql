-- Step 1 of 2. Run this on its own, then run 20260807210000.
--
-- Postgres will not let a newly added enum value be *used* in the same
-- transaction that added it, and the SQL Editor wraps a script in one. So the
-- value is added here and everything that mentions it lives in the next file.
-- Running them together fails with "unsafe use of new value of enum type".

alter type ol_role add value if not exists 'superadmin';
