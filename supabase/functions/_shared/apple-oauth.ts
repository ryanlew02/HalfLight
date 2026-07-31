// apple-oauth.ts — Sign in with Apple OAuth: code exchange and token revocation.
//
// App Store Review Guideline 5.1.1(v) has required since 2022-06-30 that an app
// offering Sign in with Apple revoke the user's Apple token when they delete
// their account. Deleting the Supabase auth user is NOT enough — the grant stays
// live in the dreamer's Apple ID settings until we call /auth/revoke.
//
// Revoking needs a refresh token, which Apple only hands out in exchange for the
// short-lived `authorizationCode` the app receives at sign-in. So the flow is:
//
//   sign-in  → app posts authorizationCode → exchangeCode() → refresh token
//              stored in `apple_refresh_tokens` (service-role only)
//   deletion → revoke() burns it → Supabase user deleted
//
// Required secrets:
//   APPLE_SIWA_KEY_ID      — Key ID of a .p8 key with Sign in with Apple enabled
//   APPLE_SIWA_PRIVATE_KEY — that .p8's contents (full PEM incl. BEGIN/END)
//   APPLE_TEAM_ID          — 10-char Apple Team ID (same as APNS_TEAM_ID)
//   APPLE_SIWA_CLIENT_ID   — for a native iOS app this is the BUNDLE ID
//                            (LanternHours.HalfLight), not a Services ID
//
// Note the client_id subtlety: a native app authenticates against Apple with its
// bundle identifier. Using a Services ID here (the web flow's identifier) makes
// Apple reject the exchange with invalid_client.

const KEY_ID = Deno.env.get("APPLE_SIWA_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APPLE_TEAM_ID") ?? "";
const PRIVATE_KEY = Deno.env.get("APPLE_SIWA_PRIVATE_KEY") ?? "";
const CLIENT_ID = Deno.env.get("APPLE_SIWA_CLIENT_ID") ?? "";

const TOKEN_URL = "https://appleid.apple.com/auth/token";
const REVOKE_URL = "https://appleid.apple.com/auth/revoke";

/** Whether the Sign in with Apple secrets are present. */
export function appleOAuthConfigured(): boolean {
  return !!(KEY_ID && TEAM_ID && PRIVATE_KEY && CLIENT_ID);
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
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

let cached: { secret: string; exp: number } | null = null;

/// The ES256 `client_secret` JWT Apple expects on both endpoints. Apple caps its
/// lifetime at 6 months; we use 30 minutes and cache it, since it's only needed
/// during a sign-in or a deletion.
async function clientSecret(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - now > 60) return cached.secret;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(PRIVATE_KEY),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const exp = now + 30 * 60;
  const header = base64url(new TextEncoder().encode(
    JSON.stringify({ alg: "ES256", kid: KEY_ID }),
  ));
  const payload = base64url(new TextEncoder().encode(JSON.stringify({
    iss: TEAM_ID,
    iat: now,
    exp,
    aud: "https://appleid.apple.com",
    sub: CLIENT_ID,
  })));
  const signingInput = `${header}.${payload}`;
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  ));
  const secret = `${signingInput}.${base64url(sig)}`;
  cached = { secret, exp };
  return secret;
}

export interface AppleExchange {
  ok: boolean;
  refreshToken?: string;
  error?: string;
}

/// Trade the app's one-time `authorizationCode` for a refresh token.
export async function exchangeCode(code: string): Promise<AppleExchange> {
  if (!appleOAuthConfigured()) return { ok: false, error: "not_configured" };

  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    client_secret: await clientSecret(),
    code,
    grant_type: "authorization_code",
  });

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { ok: false, error: payload?.error ?? `http_${res.status}` };
  }
  const refreshToken = payload?.refresh_token;
  if (!refreshToken) return { ok: false, error: "no_refresh_token" };
  return { ok: true, refreshToken };
}

/// Revoke a stored refresh token, severing the Sign in with Apple grant.
///
/// Apple answers 200 with an empty body on success. An already-revoked or
/// unknown token comes back as `invalid_grant`/`invalid_request`, which we treat
/// as success — the goal is that the grant is gone, and it is.
export async function revokeRefreshToken(
  refreshToken: string,
): Promise<{ ok: boolean; error?: string }> {
  if (!appleOAuthConfigured()) return { ok: false, error: "not_configured" };

  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    client_secret: await clientSecret(),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });

  const res = await fetch(REVOKE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (res.ok) return { ok: true };

  const payload = await res.json().catch(() => ({}));
  const reason = payload?.error ?? `http_${res.status}`;
  if (reason === "invalid_grant" || reason === "invalid_request") {
    return { ok: true };
  }
  return { ok: false, error: reason };
}
