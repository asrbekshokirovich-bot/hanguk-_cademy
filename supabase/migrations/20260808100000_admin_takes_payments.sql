-- The admin takes the money; the superadmin reads the books.
--
-- The previous migration put payments entirely out of an administrator's
-- reach. That was one step too far for how the academy actually works: the
-- person a student hands cash to is the one sitting at the desk, and if they
-- cannot record it, either it goes unrecorded or the owner is called in to
-- type it. Both are worse than letting the desk write the row.
--
-- So the split moves from "who may touch payments" to "who may see the
-- totals":
--
--   admin       records a payment for a student and confirms it. Sees the
--               amount, the plan, the month — everything about that one
--               student's fee. Sees no revenue, no arrears, no aggregate.
--   superadmin  the same, plus Moliya: the month's takings, what is
--               outstanding, the whole ledger.
--
-- The aggregate is the part that is genuinely the owner's, and it is already
-- handled: `ol_admin_kpis` returns zero for both money figures below
-- superadmin, and it is the only thing in the schema that sums money.

-- ------------------------------------------------------------- payments ---

-- Reading a payment row is now an administrator's business — but only row by
-- row. A student still sees their own.
drop policy if exists ol_payments_select on ol_payments;
create policy ol_payments_select on ol_payments
  for select to authenticated
  using (student_id = auth.uid() or ol_is_admin());

-- Recording and confirming: both tiers.
drop policy if exists ol_payments_write on ol_payments;

drop policy if exists ol_payments_insert on ol_payments;
create policy ol_payments_insert on ol_payments
  for insert to authenticated
  with check (ol_is_admin());

drop policy if exists ol_payments_update on ol_payments;
create policy ol_payments_update on ol_payments
  for update to authenticated
  using (ol_is_admin()) with check (ol_is_admin());

-- Deleting is not. A cashier who can erase a payment row can erase the
-- evidence of one they took and kept; correcting a mistake is an update, and
-- an update leaves the row behind to be looked at.
drop policy if exists ol_payments_delete on ol_payments;
create policy ol_payments_delete on ol_payments
  for delete to authenticated
  using (ol_is_super());

-- Tariffs stay the owner's: the amount a student is charged is a business
-- decision, not a front-desk one. Reading them is open — the admin needs the
-- figure to fill the form with.
drop policy if exists ol_plans_write on ol_plans;
create policy ol_plans_write on ol_plans
  for all to authenticated
  using (ol_is_super()) with check (ol_is_super());

-- ------------------------------------------------------------ the ledger ---

create or replace view ol_v_payments
with (security_invoker = false)
as
select
  pm.id,
  pm.student_id,
  p.full_name as student_name,
  pm.plan_code,
  pl.name as plan_name,
  pm.amount,
  pm.period,
  pm.due_date,
  pm.paid_at,
  ol_payment_effective_status(pm.status, pm.due_date) as status,
  pm.note
from ol_payments pm
join ol_profiles p on p.user_id = pm.student_id
left join ol_plans pl on pl.code = pm.plan_code
where ol_is_admin() or pm.student_id = auth.uid();

-- Should list the two tiers' access side by side, and nothing else.
select polname, polcmd
  from pg_policy
 where polrelid = 'ol_payments'::regclass
 order by polname;
