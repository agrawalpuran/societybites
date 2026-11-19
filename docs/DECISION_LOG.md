# Decision log

Each entry says whether the decision is confirmed in code, only discussed, or superseded. A decision can be changed when the owner asks. Do not change a confirmed payment, auth, or order-status decision as a side effect of another task.

## Confirmed in the current code

### Direct UPI is the default money path

- **Decision:** Buyers pay sellers directly. The platform does not hold funds unless an admin has switched the payment provider.
- **Reason:** Avoid payment-gateway cost, compliance, and custody at the start. Seller confirms payment in the app.
- **Alternatives:** Razorpay, PayU, and Cashfree were considered. Razorpay and PayU have no client in this repo. Tests treat unknown provider names as invalid.
- **Tradeoff:** Simple and cheap. The platform cannot prove a UPI payment by itself. Seller confirmation is manual.
- **Status:** Confirmed. `getPaymentProvider()` returns `direct_upi` when `AppSetting.payment_provider` is missing.
- **Can it change:** Yes, by an owner decision. Cashfree is already behind that setting. Do not flip it without approval.

### Cashfree is optional and locked per order

- **Decision:** An admin may set the provider to `cashfree`. Checkout stores the provider on the order. Later setting changes do not rewrite existing orders. Webhooks must verify a signature. Manual UPI confirm is rejected for Cashfree orders.
- **Reason:** Allow a gateway later without a second order lifecycle.
- **Alternatives:** Always-on gateway, or no gateway code at all.
- **Tradeoff:** The code is present, so it must be maintained. Easy Split needs a Cashfree account and seller vendor profiles before payouts work.
- **Status:** Confirmed in code. Whether production has the setting on was not read.
- **Can it change:** Yes. Removing it would be a deliberate project, not a cleanup.

### Platform fee defaults to zero, with a per-city override

- **Decision:** `communityFee` is snapshotted from `AppSetting.platform_fee`. Missing setting means 0. A different fee per serving city can live in `AppSetting.city_platform_fees` without a migration. Checkout uses the society's city when an override exists.
- **Reason:** Monetization stays configurable and off until the owner sets a number. City pricing can differ, for example Bengaluru versus Pune, without a new table.
- **Status:** Included with the 15 November 2026 knowledge-base commit. See [LATEST_HANDOVER.md](LATEST_HANDOVER.md).
- **Can it change:** Yes. Clearing a city override returns that city to the global fee.

### Coupons are funded by SocietyEats

- **Decision:** `CouponFundedBy` has only `SOCIETYEATS`. The discount lowers the buyer total and does not reduce seller entitlement.
- **Reason:** Promotions are a platform cost.
- **Status:** Confirmed by the Prisma enum.
- **Can it change:** Only with a schema change and an owner decision. Seller-funded coupons are not implemented.

### WhatsApp must not fail the order

- **Decision:** WhatsApp Cloud API runs in-process, behind an admin toggle that defaults off, with an env kill switch `WHATSAPP_ENABLED=false`. Send errors are logged and swallowed. Idempotent order replay does not send a second message. FCM is a separate path.
- **Reason:** Seller notification is useful. Order creation is the business transaction and must succeed when Meta is down, unverified, or misconfigured.
- **Alternatives:** Twilio and other providers were discussed. No Twilio code exists. A separate microservice was requested historically. The implementation is a library with a hard failure boundary, not a second deployable.
- **Tradeoff:** One Node process still does the work. The safety property is "errors do not propagate", which is implemented in `sendWhatsAppSafely`.
- **Status:** Confirmed in `lib/whatsappCloud.js` and the order create path. Meta verification history is not re-proven here.
- **Can it change:** The isolation rule should not be changed. The vendor can change if the owner approves, and the new vendor must keep the same failure boundary.

### Phone OTP with a backend JWT

- **Decision:** The default app build uses 2Factor SMS, a short access JWT, and a rotating refresh token. Firebase phone auth remains available when the app is compiled with `AUTH_PROVIDER=firebase`, and it still exchanges a Firebase ID token for a backend JWT.
- **Reason:** OTP proves the phone. The API trusts its own JWT, not a phone number sent by the client.
- **Alternatives:** Firebase-only, which was the earlier default. The August 2026 checkpoint doc still describes that older default.
- **Tradeoff:** Two login implementations must both keep working. 2Factor session state is in memory.
- **Status:** Confirmed in `lib/services/auth_config.dart` and `routes/auth.js`.
- **Can it change:** Not as a drive-by. Pick one provider only with an owner decision and a migration plan for existing sessions.

### One user row, one current role, one current society pointer

- **Decision:** `User.role` is a single string. `User.societyId` is the current society. Buyers may store several `BuyerAddress` rows and select one, which updates `societyId`. Sellers change society only through an approved `KitchenMove`.
- **Reason:** The original rule was one society for life. Saved places and kitchen moves were added without a second user table.
- **Status:** Confirmed. The sentence "a user can never change society" in `docs/04_BUSINESS_RULES.md` is superseded.
- **Can it change:** Yes, but existing orders store `societyId` as history and must stay coherent.

### Order states, with two retired

- **Decision:** Assignable states are `pending`, `accepted`, `ready`, `completed`, `cancelled`, and `rejected`. `preparing` and `picked_up` remain in the transition table only so old rows can move forward. Ready-now regular orders are created as `accepted`. Made-to-order and pre-orders wait for the seller.
- **Reason:** Ready-now stock is already published, so a second accept click only delays the buyer. The shorter status list matches the current UI.
- **Status:** Confirmed in `routes/orders.js` and `lib/orderAcceptance.js`.
- **Can it change:** Do not add or remove a state unless the owner asks. Update both clients, the transition map, and the tests together.

### Pickup and seller delivery both exist

- **Decision:** `fulfilmentMode` is `BUYER_PICKUP`, `SELLER_DELIVERY`, or `BOTH`. Reach is `MY_SOCIETY` or `BEYOND_SOCIETY` with a radius. Delivery charges are seller-entered and snapshotted.
- **Reason:** The product grew from a single-society pickup pilot into a hyperlocal marketplace.
- **Status:** Confirmed. "Pickup only / no delivery" in older docs and in the local skill is superseded.
- **Can it change:** Yes, per seller, from the seller profile. Do not delete the delivery fields as a cleanup.

### FSSAI is collected before it is enforced

- **Decision:** Sellers can submit licence details and ask for help. `fssai_selling_requirement` defaults off, so missing FSSAI does not block selling until an admin turns the requirement on.
- **Reason:** Capture the data without stopping the pilot.
- **Status:** Confirmed.
- **Can it change:** Yes, through admin settings.

### Images on Supabase Storage, database on Supabase Postgres

- **Decision:** Prisma talks to Postgres. Listing images go to the Supabase Storage bucket named by `SUPABASE_STORAGE_BUCKET` (default `listing-images`) when the URL and service role key exist.
- **Status:** Confirmed in code and `.env.example`.
- **Can it change:** Not without an owner decision. Do not introduce a second blob store for the same images.

### Flutter, Express, and Prisma stay

- **Decision:** The client is Flutter. The API is Express 5. The database access layer is Prisma. GitHub holds the repo.
- **Status:** Confirmed by the repository layout.
- **Can it change:** Not as an unsolicited rewrite.

### Admin city filter uses the serving-city list

- **Decision:** An admin can focus the console on one active serving city. The API takes optional `?cityKey=`. The app remembers the choice locally. Cities that are not active are rejected.
- **Reason:** The platform spans more than one city, and the console needs one city at a time without a new database table.
- **Status:** Included with the 15 November 2026 commit. Browser verification was still open.
- **Can it change:** Yes. Keep `cityKey` optional so "all cities" remains the default.

### Admin writes are super-admin only

- **Decision:** Console admins can open the portal and call GET. Mutations require `super_admin`.
- **Status:** Confirmed by the middleware installed on the admin router.
- **Can it change:** Yes, if the owner wants a finer permission model. Do not give console admins write access by accident.

### Incentive reward reversal stays unimplemented

- **Decision:** Phase 3B does not add a `REVERSED` reward writer. The ledger guard accepts only `ISSUE`, `REDEEM`, and `EXPIRE`.
- **Reason:** Cancelling an issued coupon, releasing budget, and posting a new ledger type are one product choice. The schema comment names `REVERSED`, but no route writes it.
- **Status:** Recorded on 19 November 2026. Flags stay off.
- **Can it change:** Yes, with a separate approval that names the coupon, budget, and ledger effect.

### Incentive engine is additive and off

- **Decision:** Referral and rewards live in `societybites-backend/modules/incentive-engine/` and `Incentive*` tables. Switches default off. Missing setting rows stay off. The engine does not add columns to `User`, `Order`, `Listing`, `Coupon`, or `AppSetting`, and it does not take a foreign key to `Coupon`. `couponId` on a future reward is a plain string.
- **Reason:** The owner approved an isolated engine on 17 November 2026 and withheld activation.
- **Status:** Phases 2A through 2F are in the source on `feature/incentive-engine-foundation`. Phase 2E issues coupons and promotional credit only when the issuance switch is exactly `true`. That switch is off. Phase 2F adds Flutter screens in the existing admin shell, buyer profile, and seller settings. Those screens do not add routes and do not turn a switch on. `Listing.firstPublishedAt` is not applied. The ledger guard was applied with `psql` only to local `societybites_incentive_foundation`. Later local runs passed for events, referral concurrency, the rewards guard, and empty read-only reporting. Phase 3A later passed coupon rollback and concurrent approval on `societybites_incentive_integration_v2`. Buyer and seller journeys remain unverified.
- **Can it change:** Activation, issuance, and redemption require a separate owner approval. Do not set those setting values to `true` as part of development. A flag write API was reviewed on 17 November 2026 and not added. On 19 November 2026 the owner approved a super-admin write for four switches, recorded below. Campaign performance, referral analytics, the reward report, audit, and risk are read models. They do not turn a switch on or issue a reward.

### Super admin can switch referral codes

- **Decision:** A super admin can turn Master, Referral, Buyer referral, and Seller referral on or off from Incentives & Rewards → Settings. The control asks before either change. A console admin does not see that tab. The server accepts only those four keys and stores the exact text `true` or `false`. A missing row stays off. Issuance, redemption, and promotional campaigns stay without a writer.
- **Reason:** The owner asked for a super-admin toggle, with the programme off until someone turns it on.
- **Status:** Added on 19 November 2026. No switch was set to `true` in this change. The hosted database still has no `IncentiveSetting` table, so the save returns 503 there.
- **Can it change:** Yes. Turning a switch on in a database still needs the owner to do it. Do not add a writer for issuance from this control.

### Ledger append-only needs a database guard before issuance

- **Decision:** Phase 2B does not change the ledger. `IncentiveLedgerEntry` has no `updatedAt` and no update route. That is convention only. Before Phase 2E writes ledger rows, add a new migration that rejects `UPDATE` and `DELETE`. Do not put that statement in the unapplied foundation migration.
- **Reason:** A later bug or a direct database session could rewrite a posted amount if the database still allows it.
- **Status:** The statement is in `prisma/migrations/20261117233000_incentive_ledger_guard/migration.sql`. The insert guard checks entry type and sign, locks `IncentiveReward` before the balance sum, and rejects a negative result. The owner applied that file with `psql` to local `societybites_incentive_foundation` only. It is not in Prisma migration history and it is not on Supabase.
- **Can it change:** Apply it only to a database the owner names, before issuance is enabled.

## Discussed, not confirmed as a shipped product

### Twilio or another WhatsApp vendor

Discussed because Meta verification and tax eligibility were obstacles. No Twilio integration is in the repo. Treat any switch as a new decision.

### Razorpay and PayU

Named in historical evaluation and in tests as values that must not be accepted as the payment provider. They are not integrations.

### A standalone WhatsApp microservice

The requirement was independence from order creation. That requirement is met inside the API process. A separate deployable was not built. Do not split it out unless the owner asks.

### Seller subdomains for every kitchen

`{slug}.societyeats.com` is a product goal and is partly implemented. See [PROJECT_STATUS.md](PROJECT_STATUS.md). Wildcard DNS is not confirmed.

### Render versus DigitalOcean

`.env.example` talks about Render. The Flutter client default is a DigitalOcean app URL. Both can be true across time. The live process was not checked on 15 November 2026. Do not delete either mention until someone verifies production.

## Historical documents that are easy to misuse

| Document | What is outdated |
|---|---|
| `docs/01_PROJECT_OVERVIEW.md`, `docs/04_BUSINESS_RULES.md`, `docs/05_ORDER_FLOW.md`, `docs/06_PAYMENT_FLOW.md`, `docs/10_ROADMAP.md` | Pickup-only, single-society, no delivery, shorter feature list |
| `docs/02_ARCHITECTURE.md` | Says the backend folder is `/backend`. The folder is `societybites-backend` |
| `docs/2FACTOR_AUTH_CHECKPOINT.md` | Says 2Factor was not the default and was not committed. The current client default is 2Factor |
| Local skill `societybites-development-guide` | Same early MVP rules. It is outside this repo and will not travel with a new machine unless copied |

Those files were kept. They still hold useful detail on individual features such as listing expiry, portion availability, and COD confirmation. Read the feature page, then check the code.
