// apple-verify — shared App Store verification + entitlement persistence.
//
// Verifies Apple's signed JWS payloads (a single transaction submitted by the app,
// or a Server Notification V2 from Apple) against Apple's root certificates, then
// maps the result to a row in `public.subscriptions`. Used by:
//   • sync-subscription        — app posts its verified transaction after purchase
//   • app-store-notifications  — Apple posts renewals / expirations / refunds
//
// Config (Supabase secrets):
//   APPLE_BUNDLE_ID        e.g. LanternHours.HalfLight
//   APP_STORE_ENVIRONMENT  which environment to try FIRST: "Production" (release,
//                          default) or "Sandbox". Verification automatically falls
//                          back to the other environment on a mismatch, so a single
//                          deployment serves both real customers (Production) and
//                          Apple's App Review reviewers (who purchase in Sandbox).
//
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@1";
import { createClient } from "npm:@supabase/supabase-js@2";

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

// The environment to attempt first. Real customers are Production, so that's the
// default; we always fall back to the other environment on a mismatch (see
// `verifyWithFallback`), which is what lets Apple's reviewers — who buy in
// Sandbox during App Review — pass verification without a manual toggle.
const PRIMARY_ENV = (Deno.env.get("APP_STORE_ENVIRONMENT") ?? "Production") === "Sandbox"
  ? Environment.SANDBOX
  : Environment.PRODUCTION;
const FALLBACK_ENV = PRIMARY_ENV === Environment.PRODUCTION
  ? Environment.SANDBOX
  : Environment.PRODUCTION;

// Apple's public root certificates, fetched once per cold start. The signing
// chain for App Store payloads roots in AppleRootCA-G3; the others are included
// so the verifier accepts older chains too.
const APPLE_ROOT_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
];

let rootsPromise: Promise<Buffer[]> | null = null;
function getRoots(): Promise<Buffer[]> {
  if (!rootsPromise) {
    rootsPromise = Promise.all(
      APPLE_ROOT_URLS.map(async (url) => {
        const res = await fetch(url);
        return Buffer.from(await res.arrayBuffer());
      }),
    );
  }
  return rootsPromise;
}

// One verifier per environment, memoized. A verifier validates the signature +
// chain + bundle id and that the payload's environment matches its own, so we
// keep both on hand and pick the one the payload was actually signed in.
const verifiers = new Map<Environment, Promise<SignedDataVerifier>>();
function getVerifier(env: Environment): Promise<SignedDataVerifier> {
  let p = verifiers.get(env);
  if (!p) {
    p = (async () => {
      const roots = await getRoots();
      // enableOnlineChecks=false: skip OCSP (no outbound cert-revocation calls);
      // signature + chain + bundle/environment checks still run.
      return new SignedDataVerifier(roots, false, env, BUNDLE_ID);
    })();
    verifiers.set(env, p);
  }
  return p;
}

// Run a verify operation against the primary environment and, if that fails,
// retry against the other. This makes one deployment accept both Production
// (real customers) and Sandbox (App Review reviewers + our own sandbox testing)
// payloads. The original error is surfaced if a payload is invalid in BOTH
// environments, so genuinely bad signatures still fail closed.
async function verifyWithFallback<T>(
  op: (verifier: SignedDataVerifier) => Promise<T>,
): Promise<T> {
  try {
    return await op(await getVerifier(PRIMARY_ENV));
  } catch (primaryError) {
    try {
      return await op(await getVerifier(FALLBACK_ENV));
    } catch {
      throw primaryError;
    }
  }
}

/// Map a decoded transaction (+ optional notification type) to an Entitlement.
function toEntitlement(
  txn: {
    originalTransactionId?: string;
    productId?: string;
    expiresDate?: number;
    appAccountToken?: string;
    environment?: string;
    revocationDate?: number;
  },
  notificationType?: string,
): Entitlement {
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
    environment: txn.environment ?? (PRIMARY_ENV === Environment.SANDBOX ? "Sandbox" : "Production"),
    status,
  };
}

/// Verify a single signed transaction JWS (from the app) into an Entitlement.
export async function verifyTransactionJWS(jws: string): Promise<Entitlement> {
  return verifyWithFallback(async (verifier) => {
    const txn = await verifier.verifyAndDecodeTransaction(jws);
    return toEntitlement(txn);
  });
}

/// Verify an App Store Server Notification V2 payload into an Entitlement (or null
/// when it carries no transaction, e.g. a test notification).
export async function verifyNotification(signedPayload: string): Promise<Entitlement | null> {
  return verifyWithFallback(async (verifier) => {
    const payload = await verifier.verifyAndDecodeNotification(signedPayload);
    const signedTxn = payload.data?.signedTransactionInfo;
    if (!signedTxn) return null;
    const txn = await verifier.verifyAndDecodeTransaction(signedTxn);
    return toEntitlement(txn, payload.notificationType);
  });
}

/// Service-role Supabase client (writes the RLS-protected subscriptions table).
export function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/// Upsert the entitlement for a known user. Returns the Supabase error, if any.
export async function upsertEntitlement(
  admin: ReturnType<typeof adminClient>,
  userId: string,
  e: Entitlement,
) {
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
