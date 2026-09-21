-- Recording the room, part one of two: the pipe, and a way to see it work.
--
-- Everything needed to record a lesson on the server is already here except
-- one thing. `ol_livekit_config` holds the LiveKit API key and secret,
-- `ol_jwt_hs256` already signs LiveKit tokens, and `ol_livekit_join` already
-- proves the pair works — what the database cannot do is make an outbound
-- HTTP request, and LiveKit's Egress API is an HTTP request.
--
-- This migration adds that, plus somewhere to keep the storage credentials,
-- plus one diagnostic. Nothing here records anything. That is deliberate:
-- the combination of LiveKit Egress and an S3 bucket has enough moving parts
-- (credentials, endpoint style, signature versions) that starting a real
-- recording before the pipe is known to work produces silence and no error.
-- Part two — starting, stopping and harvesting a recording — is written once
-- `ol_egress_ping()` below has answered.
--
-- Run this in the SQL Editor. It is idempotent; running it twice is safe.

-- --------------------------------------------------------- the request ---

-- pgsql-http, not pg_net. pg_net is asynchronous — the response lands in a
-- table a moment later, which is right for a fire-and-forget notification and
-- wrong for a diagnostic, where the whole point is to see what came back.
-- Wrapped so a project without the extension available gets a notice rather
-- than a failed migration.
do $$
begin
  create extension if not exists http with schema extensions;
exception when others then
  raise notice 'http extension unavailable: %. Enable it in Dashboard → Database → Extensions.', sqlerrm;
end;
$$;

-- ------------------------------------------------------ where files go ---

-- S3-compatible storage for the recorded files: Cloudflare R2, Backblaze B2,
-- AWS S3, or Supabase Storage's own S3 endpoint. Kept out of
-- `ol_livekit_config` because it is a different vendor's secret with a
-- different lifetime, and rotating one should not touch the other.
create table if not exists ol_egress_config (
  -- One row, enforced, for the same reason as `ol_livekit_config`.
  id            boolean primary key default true check (id),
  s3_endpoint   text not null,
  s3_region     text not null default 'auto',
  s3_bucket     text not null,
  s3_access_key text not null,
  s3_secret     text not null,
  -- Where the finished file can be read from, if the bucket has a public
  -- base. Null means the app will sign a link instead.
  public_base   text,
  updated_at    timestamptz not null default now()
);

alter table ol_egress_config enable row level security;

-- No policies, deliberately — the same mechanism as `ol_livekit_config`. RLS
-- with an empty policy list denies everyone but the owner and definer
-- functions, which is exactly what a bucket's write credentials deserve.
revoke all on ol_egress_config from anon, authenticated;

-- ------------------------------------------------- talking to LiveKit ---

-- The HTTPS base of this project's LiveKit, derived from the socket URL.
--
-- Derived rather than stored, so the two cannot disagree: `wss://x.livekit.
-- cloud` is the same deployment as `https://x.livekit.cloud`, and a second
-- column would be a second chance to typo it.
create or replace function ol_livekit_base()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select regexp_replace(ws_url, '^wss?://', 'https://')
    from ol_livekit_config
   where id;
$$;

-- An API token for the server side of LiveKit.
--
-- Not a room token: `roomRecord` and `roomList` are the grants the Egress
-- API checks, and there is no room in them at all. Short-lived, minted per
-- call, and never leaves the database.
create or replace function ol_livekit_api_token()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_cfg ol_livekit_config%rowtype;
  v_now bigint := extract(epoch from now())::bigint;
begin
  select * into v_cfg from ol_livekit_config where id;
  if not found then
    raise exception 'LiveKit sozlanmagan: ol_livekit_config bo''sh'
      using errcode = '42704';
  end if;

  return ol_jwt_hs256(
    jsonb_build_object(
      'iss', v_cfg.api_key,
      'sub', 'hanguk-egress',
      'nbf', v_now - 10,
      -- Five minutes. A token that signs one API call does not need to
      -- outlive the call.
      'exp', v_now + 300,
      'video', jsonb_build_object(
        'roomRecord', true,
        'roomList', true
      )
    ),
    v_cfg.api_secret
  );
end;
$$;

-- One Twirp call to the Egress service, with the answer.
--
-- Returns `{status, body}` rather than raising, because the body is where
-- LiveKit puts the reason: a wrong key is a 401 with a message, a bad
-- storage config is a 200 with an egress that fails a second later, and a
-- function that swallowed either would be the fourth silent failure in this
-- app's short life.
create or replace function ol_livekit_egress(p_method text, p_body jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_base text := ol_livekit_base();
  v_res  extensions.http_response;
begin
  if v_base is null then
    raise exception 'LiveKit sozlanmagan: ol_livekit_config bo''sh'
      using errcode = '42704';
  end if;

  -- Ten seconds: long enough for a slow region, short enough that a caller
  -- is not left holding a transaction open on somebody else's outage.
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '10');

  select * into v_res from extensions.http((
    'POST',
    v_base || '/twirp/livekit.Egress/' || p_method,
    array[
      extensions.http_header('Authorization', 'Bearer ' || ol_livekit_api_token())
    ],
    'application/json',
    p_body::text
  )::extensions.http_request);

  return jsonb_build_object(
    'status', v_res.status,
    'body', case
              when v_res.content is null or v_res.content = '' then null
              else v_res.content::jsonb
            end
  );
exception when others then
  -- A malformed body, a DNS failure, a timeout. Reported, not hidden.
  return jsonb_build_object('status', 0, 'error', sqlerrm);
end;
$$;

-- ------------------------------------------------------- the diagnostic ---

-- "Can this database reach LiveKit, and does LiveKit accept our signature?"
--
-- `ListEgress` is the safest call in the API: it changes nothing and it
-- answers from the same authentication path a real recording would use. A
-- 200 with an (empty) list means everything up to and including the
-- signature works, and part two can be written. Anything else names what is
-- wrong before a lesson is lost proving it.
create or replace function ol_egress_ping()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_cfg  ol_egress_config%rowtype;
  v_live jsonb;
begin
  -- An administrator from the app, or somebody typing into the SQL Editor.
  --
  -- The editor runs as the database owner with no JWT at all, so `auth.uid()`
  -- is null there and an admin-only guard refuses the one person who is
  -- allowed to do anything — which is how this first failed. A null uid
  -- cannot reach here from the app: `anon` has no execute grant, and an
  -- `authenticated` call always carries a subject.
  if auth.uid() is not null and not ol_is_admin() then
    raise exception 'Faqat administrator' using errcode = '42501';
  end if;

  select * into v_cfg from ol_egress_config where id;
  v_live := ol_livekit_egress('ListEgress', '{}'::jsonb);

  return jsonb_build_object(
    'livekit_url',   ol_livekit_base(),
    'livekit_call',  v_live,
    -- The storage half is reported, never returned: an access key in a query
    -- result is an access key in somebody's screenshot.
    'storage_set',   v_cfg.id is not null,
    'storage_bucket', v_cfg.s3_bucket,
    'storage_endpoint', v_cfg.s3_endpoint
  );
end;
$$;

revoke execute on function ol_livekit_api_token() from public, anon, authenticated;
revoke execute on function ol_livekit_egress(text, jsonb) from public, anon, authenticated;
revoke execute on function ol_livekit_base() from public, anon;
grant execute on function ol_egress_ping() to authenticated;

-- What to run after this, in order:
--
--   1. insert into ol_egress_config
--        (s3_endpoint, s3_region, s3_bucket, s3_access_key, s3_secret)
--      values ('https://<account>.r2.cloudflarestorage.com', 'auto',
--              '<bucket>', '<access key>', '<secret>')
--      on conflict (id) do update set
--        s3_endpoint   = excluded.s3_endpoint,
--        s3_region     = excluded.s3_region,
--        s3_bucket     = excluded.s3_bucket,
--        s3_access_key = excluded.s3_access_key,
--        s3_secret     = excluded.s3_secret,
--        updated_at    = now();
--
--   2. select ol_egress_ping();
--
-- `livekit_call.status` must be 200. Send that result back before part two
-- is written — it is the difference between a recording that works and a
-- lesson taught into a bucket nobody is writing to.
