# HalfLight Pro — Setup & Test Guide

HalfLight Pro puts the AI features (Analyze with AI, Auto-tag, AI titles) behind an
auto-renewable subscription:

- **Monthly** — `LanternHours.HalfLight.pro.monthly` — $9.99 / month
- **Yearly** — `LanternHours.HalfLight.pro.yearly` — $49.99 / year, **1-week free trial**

The app gates the UI (StoreKit 2); the Supabase edge functions verify a real entitlement
before calling Claude, so the Anthropic bill is protected even if someone bypasses the app.

**A HalfLight account is required to subscribe.** Everything Pro buys runs server-side,
keyed to the dreamer's Supabase user, so a guest purchase would take the money and unlock
nothing. The paywall's button reads *Sign In to Subscribe* when signed out, and
`SubscriptionManager.purchase` refuses outright — no path can charge a guest. Tapping an AI
feature while signed out opens sign-in, not the paywall.

---

## 1. Test locally first (no App Store Connect needed)

1. In Xcode, the file `HalfLight/HalfLight.storekit` is already in the project.
2. **Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration** → select
   `HalfLight.storekit`.
3. Run on a simulator. As a non-subscriber, every AI button shows a lock and opens the paywall.
4. Buy the yearly trial in the StoreKit test sheet → AI buttons unlock.
5. Use **Debug → StoreKit → Manage Transactions** (or the Transaction Manager) to expire/refund
   and confirm the buttons re-lock.

> Note: with the local `.storekit` config, the server entitlement check is **not** exercised
> (StoreKit test purchases aren't signed by Apple). To test the full server path, use Sandbox
> (step 4 below) on a real device.

---

## 2. App Store Connect (one-time)

1. **Apple Developer Program** paid membership, and sign the **Paid Applications Agreement**
   (App Store Connect → Business). Products won't load until this is signed.
2. **App Store Connect → your app → Subscriptions** → create a subscription group named
   **HalfLight Pro**, then add two auto-renewable subscriptions:

   | Product ID | Duration | Price | Intro offer |
   |---|---|---|---|
   | `LanternHours.HalfLight.pro.monthly` | 1 month | $9.99 | — |
   | `LanternHours.HalfLight.pro.yearly`  | 1 year  | $49.99 | **1 week free** |

   For the yearly product, add an **Introductory Offer → Free → 1 week**.
3. Add a localized display name, description, and a review screenshot to each (required for
   review).

> The product IDs above must match `SubscriptionManager.ProductID` and `HalfLight.storekit`.
> If you change them, update both.

---

## 3. Supabase (deploy the backend)

```sh
# Secrets used by the verification functions
supabase secrets set APPLE_BUNDLE_ID=LanternHours.HalfLight
supabase secrets set APP_STORE_ENVIRONMENT=Production   # use Sandbox while testing pre-release

# Apply the new entitlements table + RPC
supabase db push    # applies supabase/migrations/20260623150000_subscriptions.sql

# Apple posts to these with no Supabase JWT, so the gateway check must be off;
# they verify Apple's signed payloads themselves instead.
supabase functions deploy sync-subscription --no-verify-jwt
supabase functions deploy app-store-notifications --no-verify-jwt

# The AI functions are called with a real user token, so leave the gateway's JWT
# check ON (no flag) — `ai-guard.ts` re-verifies and checks the subscription on
# top of it. Passing --no-verify-jwt here would drop the outer layer.
supabase functions deploy analyze-dream
supabase functions deploy suggest-tags
supabase functions deploy suggest-title
```

> Redeploy all three AI functions whenever `_shared/ai-guard.ts` changes — it's bundled
> into each of them, and it's the only thing standing between a non-subscriber and the
> Anthropic bill. `supabase functions list` shows each one's deploy time; if any predates
> your last change to `ai-guard.ts`, it's running a stale copy of the gate.

`ANTHROPIC_API_KEY`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY` are already set / injected.

---

## 4. App Store Server Notifications V2 (keeps entitlements current)

Renewals, expirations, and refunds happen when the app isn't open, so Apple must notify the
server. After deploying, set the notification URL to the `app-store-notifications` function:

- URL: `https://kbklwrvhocyibesvsqqa.supabase.co/functions/v1/app-store-notifications`
- App Store Connect → your app → **App Information → App Store Server Notifications** → set the
  **Production** and **Sandbox** URLs to the above, **Version 2**.
- Use the "Request a Test Notification" button to confirm it returns `200`.

---

## 5. Sandbox end-to-end (real device)

1. Create a **Sandbox Apple ID** (App Store Connect → Users and Access → Sandbox).
2. On a device, sign into the Sandbox account (Settings → App Store → Sandbox Account).
3. Run the app (without the local `.storekit` config so it hits real Sandbox products).
4. Subscribe via the paywall → the app posts the signed transaction to `sync-subscription` →
   the `subscriptions` row is created → AI features unlock and the server allows Claude calls.
5. Verify the **server gate**: with a signed-in but **non-subscribed** user, call an AI function
   directly and confirm it returns **402**:
   ```sh
   curl -i -X POST \
     -H "apikey: <anon key>" \
     -H "Authorization: Bearer <a non-subscriber's access token>" \
     -H "Content-Type: application/json" \
     -d '{"entry":"test","mood":"vivid","title":""}' \
     https://kbklwrvhocyibesvsqqa.supabase.co/functions/v1/analyze-dream
   # → HTTP 402  {"error":"Subscribe to HalfLight Pro to use AI features."}
   ```
6. In Sandbox, subscriptions renew on an accelerated clock — watch the `subscriptions` row
   update from the webhook, and let it expire to confirm AI re-locks.

---

## 6. Stress-test matrix

Run these before shipping. Steps 1–8 work against the local `.storekit` config (Xcode's
**Debug → StoreKit → Manage Transactions** drives most of them); 9–12 need Sandbox.

| # | Scenario | Expected |
|---|---|---|
| 1 | Tap an AI feature signed out | Sign-in sheet (not the paywall); after signing in the tap resumes — analysing if entitled, paywall if not |
| 2 | Open the paywall signed out (Settings → Pro card) | Button reads **Sign In to Subscribe**; no purchase is possible |
| 3 | Buy yearly as a first-time subscriber | Trial badge shown; AI unlocks; a `subscriptions` row appears |
| 4 | Open the paywall again after cancelling/expiring | **No** trial copy anywhere — button says *Subscribe*, caption says "billed yearly" |
| 5 | Airplane mode, then open the paywall | No prices invented; "couldn't be loaded" card + **Try Again** button |
| 6 | Kill the Supabase function, then buy | Purchase succeeds, AI's first call 402s, `ensureServerEntitlement` retries and it works |
| 7 | Restore with no subscription | Alert: none found |
| 8 | Restore signed out, with a subscription | Alert explains the account requirement — *not* "contact support" |
| 9 | Background the app, cancel in Settings.app, return | Entitlement recomputed on foreground; AI re-locks at period end |
| 10 | Ask-to-Buy (`_askToBuyEnabled`) | "Pending approval"; approving later unlocks via the updates listener |
| 11 | Refund via App Store Connect | Webhook writes `refunded`; AI 402s |
| 12 | Replay an older notification after a newer one | Ignored — `upsertEntitlement` refuses to move an entitlement backwards |
| 13 | Delete the account while subscribed | Confirmation warns Apple keeps billing, and offers **Manage Subscription** |
| 14 | Switch the app language (Settings → Language) | The whole paywall translates, including plan cards and purchase errors |

### Known, accepted

- **Sandbox entitlements are honoured in production.** `has_active_subscription` doesn't
  filter on `environment`, which is deliberate: App Review buys in Sandbox, and TestFlight
  purchases are always Sandbox. The `environment` column is recorded for auditing. Only
  Apple IDs you've added as sandbox testers (plus TestFlight builds) can produce them.
- **One Apple subscription follows the account that last synced it.** Signing a second
  HalfLight account in on the same Apple ID moves the entitlement to it (see
  `upsertEntitlement`); it's never active on two accounts at once.

---

## How the pieces connect

| Piece | File |
|---|---|
| StoreKit client (entitlement, purchase, restore) | `HalfLight/SubscriptionManager.swift` |
| Paywall UI | `HalfLight/PaywallView.swift` |
| AI buttons gated → paywall | `HalfLight/AddDreamView.swift`, `HalfLight/DreamDetailView.swift` |
| Settings: status / restore / manage | `HalfLight/SettingsView.swift` (`ProSettingsView`) |
| Entitlement table + `has_active_subscription` | `supabase/migrations/20260623150000_subscriptions.sql` |
| Apple JWS verification + upsert | `supabase/functions/_shared/apple-verify.ts` |
| App-initiated sync after purchase | `supabase/functions/sync-subscription/index.ts` |
| Apple renewal/refund webhook | `supabase/functions/app-store-notifications/index.ts` |
| AI gate (requires active subscription) | `supabase/functions/_shared/ai-guard.ts` |

The purchase is tagged with the Supabase user id via StoreKit's `appAccountToken`, so Apple's
server notifications resolve back to the right dreamer.
