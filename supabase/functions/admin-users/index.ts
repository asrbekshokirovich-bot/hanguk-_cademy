// Account administration for Hanguk Academy.
//
// Creating, deleting and re-passwording an auth user all require the
// service-role key, which bypasses every row-level security policy. That key
// can never ship inside the Flutter app — anyone who unpacked the binary
// would own the database. So it lives here, in a function the client calls,
// and this file is the only place that has to be trusted.
//
// Every request is checked twice:
//   1. the caller presents a valid session (their own JWT), and
//   2. that caller's ol_profiles.role is 'admin'.
//
// A student calling this directly gets 403, whatever they put in the body.
//
// Deploy:
//   supabase functions deploy admin-users
// or paste this file into Dashboard → Edge Functions → Deploy a new function.
// No secrets to configure: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
// injected by the platform.

import { createClient } from 'jsr:@supabase/supabase-js@2'

// Must match `HkAuthNaming.internalEmailDomain` in the Flutter app and the
// note in 20260807140000_username_accounts.sql.
const EMAIL_DOMAIN = 'users.hanguk-academy.uz'

const USERNAME_RE = /^[a-z0-9]([a-z0-9._-]{1,30})[a-z0-9]$/

// Ambiguous glyphs are left out on purpose: these passwords get read aloud or
// copied off a screen onto paper, and 0/O, 1/l/I cost more support time than
// the extra entropy is worth.
const PASSWORD_ALPHABET = 'abcdefghjkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

function generatePassword(length = 12): string {
  // crypto.getRandomValues, not Math.random: this value is the only thing
  // standing between a stranger and a student's account.
  const bytes = new Uint32Array(length)
  crypto.getRandomValues(bytes)
  let out = ''
  for (const b of bytes) out += PASSWORD_ALPHABET[b % PASSWORD_ALPHABET.length]
  return out
}

function emailFor(username: string): string {
  return `${username}@${EMAIL_DOMAIN}`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'POST kutilmoqda' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.replace(/^Bearer\s+/i, '')
  if (!token) return json({ error: 'Avtorizatsiya talab qilinadi' }, 401)

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  // 1. Who is calling?
  const { data: caller, error: callerError } = await admin.auth.getUser(token)
  if (callerError || !caller?.user) {
    return json({ error: 'Sessiya yaroqsiz' }, 401)
  }

  // 2. Are they an admin? Read through the service client so this does not
  // depend on the caller's own read policy.
  const { data: profile } = await admin
    .from('ol_profiles')
    .select('role')
    .eq('user_id', caller.user.id)
    .maybeSingle()

  if (profile?.role !== 'admin') {
    return json({ error: 'Bu amal uchun administrator huquqi kerak' }, 403)
  }

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: "So'rov JSON emas" }, 400)
  }

  const action = String(body.action ?? '')

  try {
    switch (action) {
      case 'create': {
        const username = String(body.username ?? '').trim().toLowerCase()
        const fullName = String(body.full_name ?? '').trim()
        const role = String(body.role ?? 'student')
        const levelRaw = body.level
        const level = levelRaw == null || levelRaw === ''
          ? null
          : Number(levelRaw)

        if (!USERNAME_RE.test(username)) {
          return json({
            error: "Login 3–32 ta belgidan iborat bo'lsin: kichik harflar, " +
              'raqamlar, nuqta, tire, pastki chiziq.',
          }, 400)
        }
        if (fullName.length < 2) {
          return json({ error: 'Ism familiya kiriting' }, 400)
        }
        if (!['student', 'teacher', 'admin'].includes(role)) {
          return json({ error: "Rol noto'g'ri" }, 400)
        }
        if (level !== null && (!Number.isInteger(level) || level < 1 || level > 6)) {
          return json({ error: "Daraja 1–6 orasida bo'lsin" }, 400)
        }

        // Checked up front so the caller gets a clear message rather than a
        // raw duplicate-key error out of the auth schema.
        const { data: taken } = await admin
          .from('ol_profiles')
          .select('user_id')
          .eq('username', username)
          .maybeSingle()
        if (taken) {
          return json({ error: `"${username}" logini band` }, 409)
        }

        const password = generatePassword()

        const { data: created, error } = await admin.auth.admin.createUser({
          email: emailFor(username),
          password,
          // No mailbox exists behind that address, so leaving this false
          // would create an account that can never confirm and never log in.
          email_confirm: true,
          user_metadata: {
            username,
            full_name: fullName,
            role,
            level,
            must_change_password: true,
          },
        })
        if (error) return json({ error: error.message }, 400)

        return json({
          user_id: created.user.id,
          username,
          full_name: fullName,
          role,
          level,
          password,
        })
      }

      case 'reset_password': {
        const userId = String(body.user_id ?? '')
        if (!userId) return json({ error: 'user_id kerak' }, 400)

        const password = generatePassword()
        const { error } = await admin.auth.admin.updateUserById(userId, {
          password,
        })
        if (error) return json({ error: error.message }, 400)

        // Force a change on next sign-in, so a password the admin has seen
        // does not remain the account's real password.
        await admin
          .from('ol_profiles')
          .update({ must_change_password: true })
          .eq('user_id', userId)

        return json({ user_id: userId, password })
      }

      case 'delete': {
        const userId = String(body.user_id ?? '')
        if (!userId) return json({ error: 'user_id kerak' }, 400)
        if (userId === caller.user.id) {
          return json({ error: "O'z hisobingizni o'chira olmaysiz" }, 400)
        }

        const { error } = await admin.auth.admin.deleteUser(userId)
        if (error) return json({ error: error.message }, 400)
        // ol_profiles cascades from auth.users, so the profile row goes too.
        return json({ user_id: userId, deleted: true })
      }

      default:
        return json({ error: `Noma'lum amal: ${action}` }, 400)
    }
  } catch (e) {
    return json({ error: `${e}` }, 500)
  }
})
