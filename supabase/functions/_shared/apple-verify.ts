// apple-verify — shared App Store verification + entitlement persistence.
//
// Verifies Apple's signed JWS payloads (a single transaction submitted by the app,
// or a Server Notification V2 from Apple) and maps the result to a row in
// `public.subscriptions`. Used by:
//   • sync-subscription        — app posts its verified transaction after purchase
//   • app-store-notifications  — Apple posts renewals / expirations / refunds
//
// Verification is done with Web Crypto (jose + @peculiar/x509) rather than
// @apple/app-store-server-library, because that library depends on Node's
// `crypto.X509Certificate` internals which the Supabase (Deno) Edge Runtime does
// not implement. For each JWS we:
//   1. take the x5c certificate chain from the JWS header,
//   2. confirm the chain terminates at a pinned Apple root certificate,
//   3. confirm each certificate is in date and signed by the next one up,
//   4. verify the JWS signature with the leaf certificate's public key,
//   5. confirm the decoded payload is for our bundle id.
//
// Config (Supabase secrets):
//   APPLE_BUNDLE_ID        e.g. LanternHours.HalfLight (defaults to it)
//   APP_STORE_ENVIRONMENT  only used as a fallback label; the real environment
//                          comes from each verified payload.
//
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import * as jose from "npm:jose@5";
import * as x509 from "npm:@peculiar/x509@1";
import { createClient } from "npm:@supabase/supabase-js@2";

// @peculiar/x509 needs a Web Crypto provider; Deno's global `crypto` is one.
x509.cryptoProvider.set(crypto);

/// The normalized entitlement we persist, independent of which Apple payload it came from.
export interface Entitlement {
  originalTransactionId: string;
  productId: string;
  /// Period end in epoch milliseconds, or null for non-expiring transactions.
  expiresMs: number | null;
  /// The Supabase user id, when Apple carried it as the appAccountToken.
  appAccountToken?: string;
  environment: string;
  /// active | expired | refunded | revoked
  status: string;
}

const BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") ?? "LanternHours.HalfLight";
const DEFAULT_ENV = Deno.env.get("APP_STORE_ENVIRONMENT") ?? "Production";

// Apple's public root certificates (DER), fetched once per cold start. App Store
// payloads chain up to AppleRootCA-G3; G2 is included for older chains.
const APPLE_ROOT_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
];

let appleRootsPromise: Promise<x509.X509Certificate[]> | null = null;
function getAppleRoots(): Promise<x509.X509Certificate[]> {
  if (!appleRootsPromise) {
    appleRootsPromise = Promise.all(
      APPLE_ROOT_URLS.map(async (url) => {
        const res = await fetch(url);
        return new x509.X509Certificate(new Uint8Array(await res.arrayBuffer()));
      }),
    ).catch((err) => {
      appleRootsPromise = null; // don't cache a transient fetch failure
      throw err;
    });
  }
  return appleRootsPromise;
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

/// SHA-256 hex of a certificate's DER, used to pin against Apple's known roots.
async function thumbprint(cert: x509.X509Certificate): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", cert.rawData);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// Verify an Apple-signed JWS (with an x5c chain) and return its decoded payload.
/// Throws if the chain isn't anchored at a pinned Apple root, a certificate is
/// out of date or improperly signed, or the JWS signature doesn't check out.
async function verifyAppleJWS<T = Record<string, unknown>>(jws: string): Promise<T> {
  const header = jose.decodeProtectedHeader(jws);
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length === 0) {
    throw new Error("JWS is missing its x5c certificate chain");
  }

  const chain = x5c.map((b64) => new x509.X509Certificate(base64ToBytes(b64)));

  // 1. The chain's root must be one of Apple's pinned roots (compared by SHA-256).
  const appleRoots = await getAppleRoots();
  const trusted = new Set(await Promise.all(appleRoots.map(thumbprint)));
  const presentedRoot = chain[chain.length - 1];
  if (!trusted.has(await thumbprint(presentedRoot))) {
    throw new Error("certificate chain does not terminate at a trusted Apple root");
  }

  // 2. Every certificate must be in date and signed by the next one up (the root
  //    is self-signed).
  const now = new Date();
  for (let i = 0; i < chain.length; i++) {
    const cert = chain[i];
    if (now < cert.notBefore || now > cert.notAfter) {
      throw new Error("a certificate in the chain is expired or not yet valid");
    }
    const issuer = chain[i + 1] ?? presentedRoot;
    const issuerKey = await issuer.publicKey.export();
    const ok = await cert.verify({ publicKey: issuerKey, signatureOnly: true });
    if (!ok) throw new Error("certificate chain signature is invalid");
  }

  // 3. Verify the JWS signature itself with the leaf certificate's public key.
  const leafKey = await jose.importX509(chain[0].toString("pem"), "ES256");
  const { payload } = await jose.compactVerify(jws, leafKey);
  return JSON.parse(new TextDecoder().decode(payload)) as T;
}

/// Reject a payload that isn't for our app.
function assertBundle(bundleId: unknown): void {
  if (bundleId !== BUNDLE_ID) {
    throw new Error(`payload bundle id (${String(bundleId)}) does not match ${BUNDLE_ID}`);
  }
}

interface DecodedTransaction {
  bundleId?: string;
  originalTransactionId?: string;
  productId?: string;
  expiresDate?: number;
  appAccountToken?: string;
  environment?: string;
  revocationDate?: number;
}

/// Map a decoded transaction (+ optional notification type) to an Entitlement.
function toEntitlement(txn: DecodedTransaction, notificationType?: string): Entitlement {
  const expiresMs = txn.expiresDate ?? null;
  let status: string;
  if (notificationType === "REFUND" || txn.revocationDate) {
    status = "refunded";
  } else if (notificationType === "REVOKE") {
    status = "revoked";
  } else if (notificationType === "EXPIRED") {
    status = "expired";
  } else if (expiresMs !== null && expiresMs < Date.now()) {
    status = "expired";
  } else {
    status = "active";
  }
  return {
    originalTransactionId: txn.originalTransactionId ?? "",
    productId: txn.productId ?? "",
    expiresMs,
    appAccountToken: txn.appAccountToken,
    environment: txn.environment ?? DEFAULT_ENV,
    status,
  };
}

/// Verify a single signed transaction JWS (from the app) into an Entitlement.
export async function verifyTransactionJWS(jws: string): Promise<Entitlement> {
  const txn = await verifyAppleJWS<DecodedTransaction>(jws);
  assertBundle(txn.bundleId);
  return toEntitlement(txn);
}

/// Verify an App Store Server Notification V2 payload into an Entitlement (or null
/// when it carries no transaction, e.g. a test notification).
export async function verifyNotification(signedPayload: string): Promise<Entitlement | null> {
  const notification = await verifyAppleJWS<{
    notificationType?: string;
    data?: { signedTransactionInfo?: string };
  }>(signedPayload);

  const signedTxn = notification.data?.signedTransactionInfo;
  if (!signedTxn) return null;

  const txn = await verifyAppleJWS<DecodedTransaction>(signedTxn);
  assertBundle(txn.bundleId);
  return toEntitlement(txn, notification.notificationType);
}

/// Service-role Supabase client (writes the RLS-protected subscriptions table).
export function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/// Statuses that must never be overwritten by a replayed older payload — once a
/// subscription is refunded or revoked, access stays closed.
const TERMINAL_STATUSES = new Set(["refunded", "revoked"]);

/// Upsert the entitlement for a known user. Returns the Supabase error, if any.
export async function upsertEntitlement(
  admin: ReturnType<typeof adminClient>,
  userId: string,
  e: Entitlement,
) {
  // Apple retries notifications and does not guarantee ordering, and the app
  // posts its own transaction alongside them — so an older payload can land
  // after a newer one. Applying it blindly would roll an entitlement backwards
  // (shortening a renewed period, or re-opening a refunded subscription), so
  // drop anything that would not move this subscription forward.
  if (e.originalTransactionId && !TERMINAL_STATUSES.has(e.status)) {
    const { data: current } = await admin
      .from("subscriptions")
      .select("expires_at, status")
      .eq("user_id", userId)
      .eq("original_transaction_id", e.originalTransactionId)
      .maybeSingle();

    const storedMs = current?.expires_at ? Date.parse(current.expires_at) : NaN;
    if (Number.isFinite(storedMs)) {
      // A shorter period than the one already recorded is a stale payload.
      if (e.expiresMs !== null && e.expiresMs < storedMs) return null;
      // Don't let a replay of the pre-refund transaction reopen a closed
      // subscription; only a genuinely later period may revive it.
      if (
        TERMINAL_STATUSES.has(current!.status) &&
        (e.expiresMs === null || e.expiresMs <= storedMs)
      ) {
        return null;
      }
    }
  }

  // One Apple subscription (keyed by originalTransactionId) can end up recorded
  // under a different app account than the one now signed in — e.g. the same
  // Apple ID was used across multiple HalfLight accounts. The unique index on
  // original_transaction_id would otherwise make the user_id-keyed upsert below
  // fail and silently leave this account with no entitlement, so first release
  // any other account's claim on this transaction.
  if (e.originalTransactionId) {
    await admin
      .from("subscriptions")
      .delete()
      .eq("original_transaction_id", e.originalTransactionId)
      .neq("user_id", userId);
  }

  const { error } = await admin.from("subscriptions").upsert({
    user_id: userId,
    original_transaction_id: e.originalTransactionId,
    product_id: e.productId,
    status: e.status,
    expires_at: e.expiresMs ? new Date(e.expiresMs).toISOString() : null,
    environment: e.environment,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  return error;
}
