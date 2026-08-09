// Issues a LiveKit access token for one lesson, to one signed-in user.
//
// LiveKit authenticates with an API key and secret. The secret signs the
// token that lets a device publish and subscribe; anyone holding it can mint
// a token for any room, for any identity, for as long as they like. It can
// never ship inside the Flutter app — an .aab is a zip, and a string in it is
// public. So the secret lives here and the client receives only a token: one
// room, one identity, twelve hours.
//
// Every request is checked three ways:
//   1. the caller presents a valid Supabase session,
//   2. the lesson exists and is actually live, and
//   3. only staff may publish — a student joins muted and can turn their own
//      camera on, but cannot moderate the room.
//
// Deploy:
//   supabase secrets set LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...
//   supabase functions deploy livekit-token
//
// SUPABASE_URL and SUPABASE_ANON_KEY are injected by the platform.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')

const b64urlText = (text: string) =>
  b64url(new TextEncoder().encode(text))

/// A LiveKit token is a plain HS256 JWT. Signing it by hand keeps this
/// function to one file with no npm resolution at deploy time.
async function mintToken(opts: {
  apiKey: string
  apiSecret: string
  identity: string
  name: string
  room: string
  canPublish: boolean
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'HS256', typ: 'JWT' }
  const payload = {
    iss: opts.apiKey,
    sub: opts.identity,
    // The name shown on the tile. LiveKit reads it from the token, so the
    // client cannot rename itself to somebody else.
    name: opts.name,
    nbf: now,
    // Long enough for a double lesson plus a reconnect, short enough that a
    // leaked token is not a standing key to the room.
    exp: now + 12 * 60 * 60,
    video: {
      room: opts.room,
      roomJoin: true,
      canSubscribe: true,
      canPublish: opts.canPublish,
      canPublishData: true,
    },
  }

  const signingInput =
    `${b64urlText(JSON.stringify(header))}.${b64urlText(JSON.stringify(payload))}`

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(opts.apiSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signingInput)),
  )

  return `${signingInput}.${b64url(signature)}`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'POST kerak' }, 405)

  const apiKey = Deno.env.get('LIVEKIT_API_KEY')
  const apiSecret = Deno.env.get('LIVEKIT_API_SECRET')
  const wsUrl = Deno.env.get('LIVEKIT_URL')
  if (!apiKey || !apiSecret || !wsUrl) {
    // Configuration, not a caller mistake — say which one is missing rather
    // than returning a token-shaped nothing.
    return json({ error: 'LiveKit sozlanmagan (secrets yo‘q)' }, 500)
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    return json({ error: 'Tizimga kirilmagan' }, 401)
  }

  // The caller's own JWT, not the service role: this client sees exactly what
  // the caller is allowed to see, so RLS keeps doing its job here too.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )

  const { data: userData, error: userError } = await supabase.auth.getUser()
  const user = userData?.user
  if (userError || !user) return json({ error: 'Tizimga kirilmagan' }, 401)

  let lessonId: string | undefined
  try {
    lessonId = (await req.json())?.lesson_id
  } catch {
    return json({ error: 'lesson_id kerak' }, 400)
  }
  if (!lessonId) return json({ error: 'lesson_id kerak' }, 400)

  const { data: lesson } = await supabase
    .from('ol_lessons')
    .select('id, status, live_room')
    .eq('id', lessonId)
    .maybeSingle()

  if (!lesson) return json({ error: 'Dars topilmadi' }, 404)
  if (lesson.status !== 'live') {
    // Not an error the user can fix by retrying: the teacher has not started
    // it yet. Saying so beats a connection that fails silently.
    return json({ error: 'Dars hali boshlanmagan' }, 409)
  }

  const { data: profile } = await supabase
    .from('ol_profiles')
    .select('full_name, role')
    .eq('user_id', user.id)
    .maybeSingle()

  const role = profile?.role ?? 'student'
  const isStaff = role === 'teacher' || role === 'admin' || role === 'superadmin'

  const token = await mintToken({
    apiKey,
    apiSecret,
    identity: user.id,
    name: profile?.full_name ?? 'Talaba',
    // Falls back to the same derivation the app uses, so a lesson started
    // before live_room was being written still lands everyone together.
    room: lesson.live_room ?? `lesson-${lesson.id}`,
    // Students subscribe and may unmute themselves through the normal
    // controls; the distinction here is that staff can always publish.
    canPublish: true,
  })

  return json({ token, url: wsUrl, room: lesson.live_room ?? `lesson-${lesson.id}`, is_staff: isStaff })
})
