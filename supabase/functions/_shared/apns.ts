// apns.ts — minimal Apple Push Notification service client for Edge Functions.
//
// Token-based (.p8) auth: we sign a short-lived ES256 JWT with the APNs key and
// send it as the bearer on each HTTP/2 request to Apple. The provider token is
// cached and reused (Apple allows reuse for up to ~1h).
//
// Required secrets (set with `supabase secrets set ...`):
//   APNS_KEY_ID      — the 10-char Key ID of the .p8 key
//   APNS_TEAM_ID     — your 10-char Apple Team ID
//   APNS_PRIVATE_KEY — the .p8 contents (full PEM, including BEGIN/END lines)
//   APNS_BUNDLE_ID   — the app bundle id, used as apns-topic (e.g. com.you.HalfLight)
//   APNS_ENV         — "production" or "sandbox" (default: sandbox)

const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "";
const HOST = (Deno.env.get("APNS_ENV") ?? "sandbox") === "production"
  ? "https://api.push.apple.com"
  : "https://api.sandbox.push.apple.com";

export function apnsConfigured(): boolean {
  return !!(KEY_ID && TEAM_ID && PRIVATE_KEY && BUNDLE_ID);
}

function base64url(bytes: Uint8Array): string {
  let s = btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

let cachedToken: { jwt: string; iat: number } | null = null;

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // Refresh well within Apple's 1h limit.
  if (cachedToken && now - cachedToken.iat < 50 * 60) return cachedToken.jwt;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(PRIVATE_KEY),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: KEY_ID })));
  const payload = base64url(new TextEncoder().encode(JSON.stringify({ iss: TEAM_ID, iat: now })));
  const signingInput = `${header}.${payload}`;
  // Web Crypto ECDSA returns the IEEE-P1363 (r‖s) signature JWS expects.
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)),
  );
  const jwt = `${signingInput}.${base64url(sig)}`;
  cachedToken = { jwt, iat: now };
  return jwt;
}

export interface ApnsPayload {
  title: string;
  body: string;
  badge?: number;
}

export interface ApnsResult {
  ok: boolean;
  status: number;
  reason?: string;
  /** True when Apple says the token is gone and we should delete it. */
  unregistered?: boolean;
}

/** Send one alert push to a single device token. */
export async function sendPush(deviceToken: string, payload: ApnsPayload): Promise<ApnsResult> {
  const jwt = await providerToken();
  const body = JSON.stringify({
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
      ...(payload.badge !== undefined ? { badge: payload.badge } : {}),
    },
  });

  const res = await fetch(`${HOST}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": BUNDLE_ID,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body,
  });

  if (res.status === 200) {
    await res.body?.cancel();
    return { ok: true, status: 200 };
  }
  let reason = "";
  try {
    reason = (await res.json())?.reason ?? "";
  } catch { /* ignore */ }
  // 410 Unregistered, or 400 BadDeviceToken ⇒ stop sending to this token.
  const unregistered = res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered";
  return { ok: false, status: res.status, reason, unregistered };
}
