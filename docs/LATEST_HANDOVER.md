# Latest handover

## 19 November 2026 — Incentive work is on its own branch

The incentive and referral code is committed on `feature/incentive-referral-engine` at `54c4a4e` and pushed to GitHub. `main` stays at `407e2ae`. No pull request was opened. Switches stay off. No campaign was activated.

## 19 November 2026 — Local super admin and local API

`9000000000` (`+919000000000`, name “Local super admin”, role `super_admin`) was created on `127.0.0.1:5432/societybites_incentive_integration_v2`. The password was typed into a local prompt and was not saved. `.env` `DATABASE_URL` still points at the hosted database. A separate API process on port 3000 was started with that variable overridden for the process only. `GET /health` returned 200. The hosted database was not opened. Incentive switches were not changed and no campaign was created. `scripts/seed-local-super-admin.js` refuses every database other than that local v2 database. Sign in only while that local API window is running, as `9000000000` with OTP `123456`. Closing the window stops the local API.

## 19 November 2026 — Super admin referral switches

`PUT /incentive/admin/flags` stores `master`, `referral`, `buyerReferral`, or `sellerReferral` for a super admin. The value is the exact text `true` or `false`. A missing row stays off. Issuance, redemption, and promotional campaigns are rejected with `FLAG_NOT_WRITABLE`. A console admin receives 403 and does not see the Settings tab. The tab asks before turning a switch on or off. `GET /incentive/flags` now includes `stored` so a saved switch can show as on while Master still keeps it off. A change writes one `FLAG_CHANGED` audit row. No switch was set to `true`. No migration was applied. The hosted database still has no incentive tables, so a save there returns 503.

## 19 November 2026 — Local v2 regression passed

`npm run test:regression` on `127.0.0.1:5432/societybites_incentive_integration_v2` printed `All suites passed` and exited 0. The 13 suites that had failed for missing seed data were run individually first and each exited 0. Phase 3A printed `incentive rewards v2 integration ok` again after the Prisma client was regenerated. The nine in-memory incentive suites printed ok. Flags, campaigns, and reward rows were still empty. The three ledger triggers stayed enabled. `_prisma_migrations` is still absent and `migrate deploy` was not run.

The seed seller `+919901844776` is stored as `UPI_AND_COD` so the local fixture can place both cash and UPI orders. New sellers still default to `COD_IN_SOCIETY_UPI_OUTSIDE`. `POST /listings` no longer sends undefined description or image fields to Prisma. `prisma generate` wrote `Listing.firstPublishedAt` into the client. Replacing the query-engine DLL returned `EPERM` because the file was in use; the existing engine DLL stayed in place and the regenerated client then passed the suite. Explicit `OTP_RESEND_COOLDOWN_MS=0` is honored. Nearby catalog fixtures use names outside the automated-test name filter. Order-message cleanup deletes leftover orders for its own fixture phones before deleting those users.

v2 was left with 15 societies and 5 app settings. That includes the three named seed societies and rows created by the regression suites. Those rows were not deleted. `.env` was not changed. Supabase was not opened. No Git command was run. Switches stay off.

`flutter test` on `test/incentive_account_screen_test.dart`, `test/admin_incentives_screen_test.dart`, and `test/admin_incentive_insights_test.dart` was run again after the referral Settings tab and printed `All tests passed!` with exit 0. The super-admin test confirms a referral switch change before saving it. A portal admin still has no Settings tab. `node tests/incentive-flags.test.js` printed `incentive flags ok`. The expected missing-table log stayed in that test. No switch was turned on.

## 19 November 2026 — Local v2 authentication and Phase 3A

Local PostgreSQL 18 is running. `pg_hba.conf` requires SCRAM for `127.0.0.1`. No password file is stored. `scripts/run-incentive-v2-local.ps1` asks for the local `postgres` password in the console, overrides any inherited `DATABASE_URL`, and refuses every host, port, and database other than `127.0.0.1:5432/societybites_incentive_integration_v2`. The password is not written to the repository.

The read-only check confirmed that database. The incentive tables, enabled ledger triggers, and nullable `Listing.firstPublishedAt` are present. `_prisma_migrations` is absent, so the history was not applied through Prisma and `migrate deploy` was not run. `IncentiveSetting` had no rows. No campaign or reward rows were present before the tests.

`node tests/incentive-rewards-v2.integration.js` printed `incentive rewards v2 integration ok`. A second identity check still named the v2 database. The first run of `whatsapp-settings` and `payment-provider` failed `seed society required` because v2 had no society. Regression then created societies and passed 14 of 27 suites. The 13 failures are suites that expect pre-seeded users. Completed-order journeys recorded `ORDER_QUALIFIED` events. After that, the same two suites were run again and both printed passed. The final read showed flags still absent, no campaigns, and `IncentiveReward` still empty. v2 now has 3 societies and 5 app settings from these test runs. `.env` was not changed. Supabase was not opened.

## 19 November 2026 — Local database validation stopped before a connection

The configured `DATABASE_URL` host is the Supabase pooler. It was not opened. The process environment already had a passwordless `DATABASE_URL` for `127.0.0.1:5432/societybites_incentive_unit`. `whatsapp-settings` and `payment-provider` inherit that value because `dotenv` does not override an existing variable, then Prisma reports authentication failed for `postgres` at `127.0.0.1` before any query succeeds. No local password is available in `PGPASSWORD` or `pgpass.conf`. Trying the configured password against `127.0.0.1:5432/societybites_incentive_integration_v2` failed authentication and did not open a session. No migration was applied. Phase 3A was not run again. `.env` was not modified. Incentive switches were not changed.

## 19 November 2026 — Caller offers and decision notifications

`GET /incentive/offers` returns published active campaigns for the JWT role. Buyers do not see seller-acquisition or listing campaigns, and sellers see only those two. Budget, rules, audience payloads, and the creator id are omitted. While the master switch is off the list is empty. The account screen shows that empty state. Approval, rejection, and a non-duplicate redemption each send one FCM message after the reward transaction commits. Expiry reminders are not scheduled. No migration was added. Flags stay off. Phase 3A was not run again.

## 19 November 2026 — Completed-order qualification and pilot preparation

The order machine has no delivered status. `qualifyOrder` already required `completed`. Tests now cover `pending`, `accepted`, `preparing`, `picked_up`, and a failed payment. A failed incentive insert is retried once and still cannot change the completed order. `GET /incentive/admin/rewards/reconciliation` explains a campaign budget without rewriting it. A new reward sends one FCM message only after the event transaction commits. Post-completion refunds and ledger reversal remain an open business decision. Flags stay off. Phase 3A was not run again.

## 19 November 2026 — Phase 3B reward validation

Phase 3A was not run again. `node tests/incentive-rewards.test.js` printed `incentive rewards ok`. `node tests/incentive-events.test.js`, `node tests/incentive-read.test.js`, and `node tests/incentive-analytics.test.js` printed ok. No migration was added. Flags stay off.

The reward path now skips a closed replay, refuses credit redemption after `expiresAt`, rejects a repeated redemption key that names a different amount, and requires a redemption order to belong to the recipient. Rejection of a percentage coupon releases `maxDiscount`. Expiry and redemption hold the reward lock across the status write. The in-memory lock waits for a concurrent caller instead of treating that caller as re-entrant. `REVERSED` is still not written. The matrix is [INCENTIVE_REWARDS_VALIDATION.md](INCENTIVE_REWARDS_VALIDATION.md).

## 18 November 2026 — Integration database migration stopped

`societybites_incentive_integration` was created on `127.0.0.1:5432`. `prisma migrate deploy` stopped on `20260822110000_add_preorder_campaign_cover_image` with `P3018` and `relation "PreOrderCampaign" does not exist`. That migration is recorded in `_prisma_migrations` with no finish time. The only public table is `_prisma_migrations`. The database was not dropped and deploy was not retried. `.env` was not modified. `societybites_incentive_foundation` statistics were unchanged. Flags were not enabled.

## 18 November 2026 — Phase 2G local PostgreSQL acceptance

Local checks against `127.0.0.1:5432/societybites_incentive_foundation` printed success for events, referral concurrency, the rewards ledger guard, and the read-only reporting harness. The reporting session left incentive row counts unchanged. Those runs do not accept shared deployment.

Still open: reporting pages were empty because that database has no campaign or event rows, and `performance()` was not called. Leaderboard and risk name lookups stay blocked because `User` is absent. Two simultaneous `approveReward` calls have not been run. Coupon-row rollback is unproven. Buyer and seller journeys are unverified. `Listing.firstPublishedAt` is not applied. Flags stay off.

## 18 November 2026 — Phase 2G reporting harness

`scripts/run-incentive-reporting-pg.ps1` was run from an interactive terminal against `127.0.0.1:5432/societybites_incentive_foundation`. The session was read-only and incentive row counts were unchanged. It printed `incentive reporting postgresql read ok`. Referral, reward, failure, audit, and event queries returned empty pages because the foundation database has no campaign or event rows. `performance()` was not called for that reason; the same aggregates ran directly and returned zeros. `User`, `Order`, `Listing`, `SellerTermsAcceptance`, `Coupon`, and `CouponEligibleUser` are absent. The leaderboard name lookup was reported `BLOCKED` and was not called because no referral is `QUALIFIED`. Flags stay off.

## 17 November 2026 — Phase 2F reporting

Campaign duplicate copies configuration into a new draft and leaves consumed budget at zero. Admin performance, referral analytics, reward report, audit, and risk routes aggregate stored rows. Portal admins can read them. Duplicate and event replay stay super-admin. The caller leaderboard returns display names only and ignores a query user id. A rejected referral claim is audited after the claim transaction rolls back. The campaign form uses a nested AND/OR builder and still saves the existing rule JSON. The account screen can open the platform share sheet through `share_plus`, keeps WhatsApp on `url_launcher`, and shows an in-app expiry notice. No migration was added. Flags stay off. `incentive analytics ok`.

## 17 November 2026 — Phase 2G acceptance

Phase 2G did not add a feature and did not enable a switch. One routing defect was fixed: `GET /incentive/rewards` had attached sign-in to the whole router, so an unknown `/incentive` path returned 401 instead of 404. Sign-in is now only on the two caller reward reads. `POST /incentive/flags` stays 404.

The in-memory incentive unit files printed ok: flags, campaigns, events, referral codes, referral lifecycle, product events, rewards, and read. The product-event failure log is the expected swallowed incentive error. Flutter `test/admin_incentives_screen_test.dart` and `test/incentive_account_screen_test.dart` passed. The PostgreSQL incentive scripts were not run in that pass. Later local runs are in the 18 November acceptance section. Shared regression was not run. Flags stay off. No campaign was activated.

All Phase 2A–2F work is uncommitted on `feature/incentive-engine-foundation` at `407e2ae`, the same commit as `main`. That branch has no upstream. `feature/incentive-referral-engine` does not exist. Do not rename or merge until the owner asks.

## 17 November 2026 — Incentive read APIs

Caller rewards are `GET /incentive/rewards` and `GET /incentive/rewards/history`. Both use `req.user.id` and delete `userId` and `recipientUserId` from the query before reading. Balances are ledger sums for that caller's promotional credit and points. They are not cash.

`GET /incentive/admin/overview` returns campaign, referral, and issued-reward counts, split by the reward definition type. `GET /incentive/admin/ledger` pages ledger rows with `limit`, `cursor`, `entryType`, `rewardId`, `userId`, and `rewardType`. Portal admins can read both. Neither route writes.

`rewardType` on a reward or ledger row comes from `IncentiveRewardDefinition` for that version and slot. No column was added and no migration was applied.

The campaign editor saves every audience kind, every configurable trigger, reward fields the parser accepts, and `PUT /incentive/admin/campaigns/:id/referral-policy`. A rules group can be AND or OR. Nested groups are sent as advanced rule JSON. A flag write route was reviewed and not added.

`node tests/incentive-read.test.js` printed `incentive read ok`. `node tests/incentive-rewards.test.js` printed `incentive rewards ok`. `flutter test test/admin_incentives_screen_test.dart` and `flutter test test/incentive_account_screen_test.dart` passed. Flags stayed off. No campaign was activated and no reward was issued.

## 17 November 2026 — Incentive engine Phase 2F

Flutter screens now sit inside the existing admin shell, buyer profile, and seller settings. `AdminShellScreen` adds **Incentives & Rewards** after Coupons. Portal admins see the data and do not see create, approve, or lifecycle controls. Super admins see those controls. Settings stay read-only because `GET /incentive/flags` is the only settings route. The screens do not write `IncentiveSetting` and do not activate a campaign during tests.

Overview counts come from `GET /incentive/admin/campaigns`, `/referrals`, `/rewards`, and `/events`. There is no statistics route. The reward list does not separate points from promotional credit; a row with `couponId` is shown as a coupon and the rest as credit or points. Ledger rows are loaded from `GET /incentive/admin/rewards/:id` and have no edit or delete action. There is no ledger index.

Buyer and seller screens call `GET /incentive/flags`, `/incentive/referral-codes`, and `/incentive/referrals`. Code creation uses `POST /incentive/referral-codes` with `audience` `BUYER` or `SELLER`. While referral is off, those code routes return 403 and the screen says the codes are off. A share link is copied or opened with `url_launcher` only when the API returns `url`. There is no buyer or seller route for that user's coupons, credit balance, points, or reward history, so those sections explain the gap instead of calling an admin route.

The campaign editor can create a draft, save one audience, one trigger, one reward, a budget, and run simulation. Saving a published campaign uses `PATCH`, which forks a draft. There is no separate schedule route. Activate is the route that becomes `SCHEDULED` or `ACTIVE`, and it returns 403 while the master switch is off. The editor does not collect a referral policy. Referral categories still cannot activate until that policy exists. No backend file, checkout path, coupon calculation, or migration changed. All switches remain off.

`flutter analyze` on the touched Flutter files reported 14 existing infos and one existing unused-field warning in `profile_screen.dart`. It reported no error in the new screens. `flutter test test/admin_incentives_screen_test.dart` printed `All tests passed!` (2 tests). The same run of `test/admin_coupons_test.dart`, `test/profile_photo_test.dart`, and `test/seller_onboarding_flow_test.dart` passed. Backend incentive tests were not rerun because no backend file changed.

## 17 November 2026 — Incentive engine Phase 2E

Reward issuance runs inside the existing event `finish()` transaction, after referral projection. It runs only when `issuance_enabled` is exactly `true` and a campaign match passed. Flags stay off, so no reward is issued in normal operation. `FIXED_COUPON` and `PERCENTAGE_COUPON` call `createAssignedCoupon` in `lib/coupons.js`. Checkout validation and redemption are unchanged. `PROMOTIONAL_CREDIT` and `POINTS` post an `ISSUE` ledger row. There is no cash withdrawal and no payment or seller-settlement change.

A definition with `requireAdminApproval: true` stores `PENDING_APPROVAL` and does not create the coupon or ledger row until a super admin approves. Rejection releases the reserved budget. Approval and rejection of the same decision return the existing row. Portal admins can read `GET /incentive/admin/rewards`. Only a super admin can approve, reject, redeem credit, or expire credit.

`prisma/migrations/20261117233000_incentive_ledger_guard/migration.sql` is revised. It is applied only on the local foundation database, not through Prisma migration history and not on Supabase. Its insert trigger locks `IncentiveReward` with `SELECT ... FOR UPDATE` before it sums that reward's ledger. `ISSUE` must be positive. `REDEEM` and `EXPIRE` must be negative. Any other entry type is rejected. Rejection and issuance lock the same `IncentiveBudget` row before changing `issuedAmount`. Approval and event-flag evaluation accept issuance only when the stored value, after removing spaces, tabs, and newlines, is exactly `true`. `node tests/incentive-rewards.test.js`, `node tests/incentive-events.test.js`, `node tests/incentive-flags.test.js`, and `node tests/incentive-campaigns.test.js` printed ok. The owner applied `20261117233000_incentive_ledger_guard` with `psql` to `127.0.0.1:5432/societybites_incentive_foundation` only. The first `scripts/run-incentive-rewards-pg.ps1` run then failed while reading `to_regclass('"Coupon"')`, before the success line. That probe now casts the result to text. A cleanup failure is printed as `LEDGER_CLEANUP_FAILED` and is not replaced by the original test error. A later run printed `incentive rewards postgresql guard ok` and `COUPON_TABLE_ABSENT_ON_FOUNDATION`. Coupon-row rollback remains unproven. Do not enable issuance.

## 17 November 2026 — Incentive engine Phase 2D-4

Product routes now record three incentive events after their own writes commit. A failed incentive insert is logged and does not change the product response. No reward, coupon, or ledger row is written. Feature flags stay off.

`USER_BECAME_SELLER:{userId}` is recorded from `acceptSellerTermsAndEnable` only when that call changes the user into a seller. `occurredAt` is `SellerTermsAcceptance.acceptedAt`. `LISTING_PUBLISHED:{listingId}` is recorded from `PATCH /listings/:id/publish` and `PATCH /listings/bulk/publish` when a draft first becomes active, and from `POST /listings` when `publish` is true. `Listing.firstPublishedAt` is set once in that same transaction from the server clock. A draft create does not stamp it or emit. Resume and renew do not emit it. `ORDER_QUALIFIED:{orderId}` is recorded by `emitOrderQualifiedIfReady` after order completion, UPI confirmation, cash confirmation, delivery-cash confirmation, and a Cashfree paid webhook. It re-reads the order and uses `qualifyOrder`. `occurredAt` is the latest of `completedAt` and the confirmation timestamps that rule needs. `updatedAt` is not used. There is no admin route that writes `paymentStatus`.

`prisma/migrations/20261117223000_listing_first_published_at/migration.sql` is not applied. Do not deploy the publication change to a database that does not have `Listing.firstPublishedAt`. `POST /incentive/admin/events/backfill` is super-admin only. Listings that are no longer drafts and have no `firstPublishedAt` are reported as unreconstructable.

`node tests/incentive-product-events.test.js` printed `incentive product events ok`, including the logged incentive failure that left the product result intact. `node tests/incentive-events.test.js` and `node tests/incentive-referrals-lifecycle.test.js` printed ok. Regression suites that write the shared database were not run.

## 17 November 2026 — Local referral migrations applied

`20261117203000_incentive_referral_code_pin` and `20261117213000_incentive_referral_attribution` were applied with `psql` to `127.0.0.1:5432/societybites_incentive_foundation` only. `prisma migrate deploy` was not used. Supabase was not contacted. `societybites_incentive_empty` still has no application objects. All 17 Incentive tables were empty after `tests/incentive-referrals-pg.integration.js` printed `incentive referral postgresql integration ok`. Feature flags stay off. Phase 2D-4 has not started.

## 17 November 2026 — Incentive engine Phase 2D-2 and 2D-3

Phase 2D-2 and 2D-3 add referral attribution and qualification on `feature/incentive-engine-foundation`. Still not committed and not pushed. The engine stays off. No reward, coupon, ledger row, or redemption is written. Product routes are unchanged. Phase 2D-4 hooks have not been added.

A repeat `POST /incentive/referral-codes` for an inactive code returns 409 `CODE_INACTIVE` and does not create a replacement. `POST /incentive/referrals` records one referrer per user per acquisition kind. The referrer id comes from the code. Self-referral and a direct reverse pair are rejected. Buyer claims use account age and prior qualifying orders. Seller claims use seller-terms acceptance, a non-draft listing, and a prior qualifying sale. Caps are counted inside a transaction that locks all of the referrer's codes for the pinned version.

Qualification runs inside the event `finish()` transaction. It uses `occurredAt`, not the processing time. Seller milestones can arrive in any order. A qualified cap leaves the referral `ATTRIBUTED` and audits the skip. Admin approval, rejection, disqualification, expiry, and reconciliation are under `/incentive/admin/referrals`. Reconciliation is the path that reverses a qualification when the stored order no longer passes `qualifyOrder`.

`prisma/migrations/20261117213000_incentive_referral_attribution/migration.sql` is not applied. It adds nullable milestone columns and a check that the two user ids differ. `tests/incentive-referrals-pg.integration.js` is not part of `npm test` and has not been run.

`node tests/incentive-referrals-codes.test.js` printed `incentive referral codes ok`. `node tests/incentive-referrals-lifecycle.test.js` printed `incentive referral lifecycle ok`. `node tests/incentive-events.test.js` and `node tests/incentive-campaigns.test.js` printed ok. No database was queried.

## 17 November 2026 — Incentive engine Phase 2D-1

Phase 2D-1 adds referral code creation and retrieval on `feature/incentive-engine-foundation`. Still not committed and not pushed. The engine stays off. No referral is attributed. No reward, coupon, ledger row, or redemption is written. Event processing and `finish()` are unchanged. Auth, listing, order, payment, WhatsApp, FCM, and Flutter files are unchanged.

`GET` and `POST /incentive/referral-codes` require the existing user JWT and use `req.user.id`. `POST` pins the code to the current published campaign version and stores `expiresAt` once, using the earlier of the code lifetime and that version's campaign end. A repeat call returns the same row. The public preview is `GET /incentive/referral-codes/preview?code=`, limited to 30 requests a minute per IP, and returns only `{ valid, audience, expiresAt }`. `REFERRAL_LINK_BASE_URL` is used only when it is an absolute HTTPS origin. Otherwise `url` is null.

Referral campaigns now fail readiness without a valid `referralPolicy`. `BUYER_ACQUISITION` and `REFERRAL` require `buyer.maxAccountAgeHours`. A code needs `codeExpiresInDays` or a campaign end. Super admins store that policy with `PUT /incentive/admin/campaigns/:id/referral-policy`. This does not activate a campaign.

`prisma/migrations/20261117203000_incentive_referral_code_pin/migration.sql` adds nullable `expiresAt` and `campaignVersionId` to `IncentiveReferralCode`. It is not applied. `campaignVersionId` has no foreign key. The existing unique key `(userId, audience, scopeKey)` makes concurrent creation of the same code idempotent. A colliding random code is retried.

`node tests/incentive-referrals-codes.test.js` printed `incentive referral codes ok`. `node tests/incentive-campaigns.test.js` printed `incentive campaigns ok`. `node tests/incentive-flags.test.js` printed `incentive flags ok` and its existing simulated `P2021`. No database was queried by the new test. Phase 2D-2 has not started.

## 17 November 2026 — Incentive engine Phase 2C

Phase 2C adds event ingestion and evaluation on `feature/incentive-engine-foundation`. Still not committed and not pushed. The engine stays off. No scheduler was added. No product route was hooked. No reward, coupon, referral, ledger row, or redemption is written.

Admin event routes live under `/incentive/admin/events`. Reads use the existing portal check. Writes require `super_admin`. The server assigns `eventId`. One order can store only one terminal event, enforced by a partial unique index in `prisma/migrations/20261117183000_incentive_event_processing`. That migration and the foundation SQL were applied only to local `societybites_incentive_foundation` on `127.0.0.1`. They were not applied to Supabase.

A valid event stays `PENDING` while the master switch is off. `POST /events/process-due` returns 403 `ENGINE_DISABLED` and does not claim. The claim is one parameterised `UPDATE` with an `EXISTS` check that `master_enabled` is exactly `true` after `btrim`. A switch committed before that statement blocks the claim. A claim that already committed may finish. Each claim stores a new `claimToken`. Outcome and recovery updates must match that token and insert their audit in the same transaction. There is no lease renewal. The lease is two minutes. Retry delay starts at 30 seconds and doubles, up to one hour. Attempt 8 becomes `DEAD`. Replay keeps `attempts` and records the super-admin id. The next claim increments the stored count. Replaying a dead event allows one more claim; a failure of that claim is `DEAD` again. Manual recovery records the super-admin id. Duplicate ingest does not write an audit row.

`node tests/incentive-events.test.js` printed `incentive events ok`. `node tests/incentive-campaigns.test.js` and `node tests/incentive-flags.test.js` also printed ok. The flag test still logs its own simulated `P2021`. `tests/incentive-events-pg.integration.js` is not part of `npm test`. Its first local run stopped at `expected ORDER_TERMINAL_CONFLICT but got P2002` and did not print `CLEANUP_FAILED`. A partial-index violation on `entityId` now maps to `ORDER_TERMINAL_CONFLICT`. A duplicate `eventId` stays idempotent. Other unique violations stay `P2002`. The integration script has not been run again.

## 17 November 2026 — Incentive engine Phase 2B

Phase 2B adds campaign configuration on the same branch, `feature/incentive-engine-foundation`. Still not committed and not pushed. This section supersedes the Phase 2A note that Phase 2B had not started. The engine stays off. Phase 2C has not started.

Campaign admin routes live under `/incentive/admin`. Reads use the existing portal check. Writes, including simulation, require `super_admin`. Create always stores `DRAFT`. Activation is a separate action and returns 403 `ENGINE_DISABLED` while the master switch is off. There is no route that writes `IncentiveSetting`.

Drafts edit in place. A published version is frozen. Editing `SCHEDULED`, `ACTIVE`, or `PAUSED` forks a new draft version and leaves the old snapshot in place. `COMPLETED`, `EXPIRED`, and `TERMINATED` cannot be edited and are not deleted. `READY_FOR_REVIEW` was not added.

Rules are a declarative tree: `AND` / `OR`, depth 4, 30 conditions, and the operators named in the Phase 2B approval. Fields come from an allowlist. Triggers can be stored for later campaigns and are marked `NOT_IMPLEMENTED`. Simulation explains the sample and does not write.

The readiness correction is in the same uncommitted tree. A draft may be incomplete. Activation and simulation share `assessCampaign`. An empty audience or a missing rule tree does not match everyone. `ALL_USERS` is the only explicit every-user audience, and it cannot be combined with another audience. The snapshot stores `eligibility` as `RULES` or `AUDIENCE_AND_TRIGGER_ONLY`. No migration was added. Switches stay off. Phase 2C has not started.

No new migration was added. `20261117120000_incentive_engine_foundation` is still unapplied. `npm run test:unit` and `npm run test:regression` were not run again in Phase 2B because several of those suites write the shared database. The isolated runs were `node tests/incentive-campaigns.test.js` and `node tests/incentive-flags.test.js`. Both printed ok. The flag read still failed closed with `P2021`, which matches the tables being absent. The earlier regression and Flutter failures are unchanged and were not re-run.

`IncentiveLedgerEntry` is append-only only by convention. Do not add the database trigger until a separate approval before Phase 2E. The proposed statement is in [DATABASE_REFERENCE.md](DATABASE_REFERENCE.md).

## 17 November 2026 — Incentive engine Phase 2A

Branch `feature/incentive-engine-foundation`, created from a clean `main` at `407e2ae` (`Enhancement 17-Nov`). Not pushed. Not committed in this session.

Phase 2A only. The engine is mounted at `/incentive` and every switch stays off. `GET /incentive/flags` is the only new route. It requires the existing user JWT. There is no route that turns a switch on. No campaign, referral, reward, event hook, worker, or Flutter screen was added.

The migration `societybites-backend/prisma/migrations/20261117120000_incentive_engine_foundation/migration.sql` was generated with `prisma migrate diff` and was not applied. It only creates `Incentive*` tables, indexes, and foreign keys among those tables. Do not run `npm start` or `prisma migrate deploy` against production until that migration is approved. `npm run dev` does not apply migrations.

Rollback is in [DATABASE_REFERENCE.md](DATABASE_REFERENCE.md). Do not delete coupon rows as part of that rollback.

Phase 2B has not been started. Enabling the master, issuance, or redemption switch needs a separate approval.

Tests run on 17 November 2026 from this working tree:

- `npm run test:unit` passed, including `tests/incentive-flags.test.js`.
- `npm run test:regression` finished with three failures: `order-messages` (assertions passed, then cleanup hit existing `Order_buyerId_fkey`), `society-scoping` (`other-society listing detail must be hidden`), and `listing-catalog` (`nearby seller with a REGULAR listing should appear`). These paths do not use the incentive module. The failures were not fixed.
- `flutter test` finished with one failure: `test/session_restore_guest_test.dart`, `MissingPluginException` for `flutter_secure_storage` delete. No Flutter incentive UI was added.

A read of `pg_tables` after those runs showed `IncentiveSetting` is absent, so the new migration was not applied.

The 15 November handover below was not rewritten. Its git facts are older than `407e2ae`.

## 15 November 2026 handover

Written 15 November 2026 after a documentation pass. Facts below were checked with Git and by reading source. Assumptions are marked.

## Current project state

SocietyEats is a working hyperlocal marketplace, not a blank MVP. Buyers order from society kitchens. Sellers publish listings, choose pickup or delivery and a radius, and confirm direct UPI or cash. Admins operate an in-app console. Optional WhatsApp and Cashfree exist and default off or to direct UPI.

The product name in the UI is SocietyEats. The repo, package, and backend folder are still SocietyBites.

## Git

| Item | Value |
|---|---|
| Remote | `https://github.com/agrawalpuran/societybites.git` |
| Branch | `main`, tracking `origin/main` |
| HEAD | `2d6871cbe957c01b5c1def46b12bb2733a99b9a3` |
| HEAD subject | `Enhancement 14-Nov` |
| HEAD date | 14 November 2026, 16:56 +0530 |
| Author | Puranmal Agrawal |
| Stashes | None (`git stash list` was empty) |
| Other local branches | `backup-before-github-merge`, `rename-to-societyeats` |

This handover did not fetch from origin. "Tracking origin/main" was true at the start of the documentation session. A newer remote commit may exist if someone pushed later.

## Admin city work included with the knowledge base

On 15 November 2026 the admin city filter, the per-city platform fee, and this knowledge base were committed together, on top of `2d6871c` (`Enhancement 14-Nov`). The behavior below is the source of truth for that commit. A browser pass of the admin chips was still open when the commit was made. The two unit tests had already printed OK.

### What this commit adds

Admins can pin the console to one active serving city. The choice is stored on the device under the preferences key `admin_city_scope_key`. An empty choice means all cities. A saved city that is no longer an active serving city is cleared.

The chip bar is on these shell tabs: Dashboard, Societies, Listings, Orders, Performance, Reviews, Issues, and Coupons. It is not on FSSAI, Address proof, Kitchen moves, Audit log, Users, or Console access. Switching the chip reloads the list on that tab. A line above the chips says the tab is filtered to the selected city.

`?cityKey=` is optional. Missing, empty, or `all` means no city filter. Any other value must be an active serving-city key, lowercased. Otherwise the API returns 400 with code `INVALID_CITY_KEY`. Societies are grouped by `canonicalCityKey`, so `Bangalore` and `Bengaluru` count as `bengaluru`. A city with no societies is queried as an empty set, not as every society.

These GETs accept `cityKey`: `/admin/dashboard`, `/admin/growth`, `/admin/growth/members`, `/admin/societies`, `/admin/listings`, `/admin/orders`, `/admin/reviews`, `/admin/issues`, `/admin/coupons`, `/admin/settings`, and the performance routes that pass `req.query` into `adminSellerPerformance.js` (`/admin/performance/summary`, `/sellers`, `/sellers/:sellerId`, `/sellers/:sellerId/orders`, `/campaigns`, `/export`).

`GET /admin/dashboard/cities` is new. It returns `activeCities`, one `rows` entry per active city (societies, sellers, 7-day orders, 7-day food GMV), `totals`, and `periodDays` (7). The dashboard table can select a city from a row.

Coupon list filtering keeps coupons with no eligible societies, plus coupons whose eligible societies intersect the city. Issues are filtered by the reporter's current society. Reviews are filtered by the order's society.

Platform fee can now differ by city without a Prisma migration. `AppSetting.platform_fee` stays the global fee. `AppSetting.city_platform_fees` is a JSON object of city key to amount. `POST /orders` calls `resolvePlatformFee({ societyId })`, which uses the society's city override when one exists and otherwise the global fee. A signed-in buyer reads that amount from `GET /settings/platform-fee`. `GET /settings` still returns the global fee for force-update and serving-city data.

`PATCH /admin/settings` with `?cityKey=` and `{ "platformFee": number }` writes that city's override. The same patch without `cityKey` still updates the global fee. `{ "useGlobalPlatformFee": true }` with `?cityKey=` deletes that city's override. The dashboard fee card shows the city amount, says when it is still using the global fee, and can switch back to global. Negative values are rejected. Amounts are rounded to two decimals.

`npm test` in `package.json` now includes `tests/admin-city-dashboard.test.js` and `tests/platform-fee-city.test.js`. Both were run on 15 November 2026 and printed OK. They do not hit the database. The admin screens were not clicked through in a browser for this review.

`pubspec.yaml` in this commit moves the app version from `1.0.0+57` to `1.0.0+58`. That bump is not required by the city logic.

Saving active serving cities clears the in-memory society-to-city map in `adminCityDashboard.js`.

Files that implement the feature:

- `lib/screens/admin/admin_coupons_screen.dart`
- `lib/screens/admin/admin_dashboard_screen.dart`
- `lib/screens/admin/admin_issues_screen.dart`
- `lib/screens/admin/admin_listings_screen.dart`
- `lib/screens/admin/admin_orders_screen.dart`
- `lib/screens/admin/admin_reviews_screen.dart`
- `lib/screens/admin/admin_seller_performance_screen.dart`
- `lib/screens/admin/admin_shell_screen.dart`
- `lib/screens/admin/admin_societies_screen.dart`
- `lib/services/api_service.dart`
- `lib/services/session_service.dart`
- `lib/widgets/admin_growth_panel.dart`
- `lib/widgets/admin_city_scope_bar.dart`
- `lib/widgets/admin_dashboard_cities_table.dart`
- `lib/admin/`
- `pubspec.yaml`
- `societybites-backend/lib/adminGrowth.js`
- `societybites-backend/lib/adminSellerPerformance.js`
- `societybites-backend/lib/adminCityDashboard.js`
- `societybites-backend/lib/coupons.js`
- `societybites-backend/lib/issueReports.js`
- `societybites-backend/lib/platformFee.js`
- `societybites-backend/lib/servingCities.js`
- `societybites-backend/package.json`
- `societybites-backend/routes/admin.js`
- `societybites-backend/routes/orders.js`
- `societybites-backend/routes/settings.js`
- `societybites-backend/tests/admin-city-dashboard.test.js`
- `societybites-backend/tests/platform-fee-city.test.js`

`GET /admin/dashboard/cities` and `GET /settings/platform-fee` arrived in this commit. They were not in `2d6871c`.

The knowledge-base files (`AGENTS.md`, `docs/PROJECT_CONTEXT.md`, and the other new docs) describe the product. Application logic was not rewritten to match the docs.

## Last completed committed work

Commit `2d6871c` (`Enhancement 14-Nov`) is the parent of the city-scope and knowledge-base commit. Its message does not describe its own diff. Before that commit, the product already included kitchen moves, buyer addresses, coupons, Cashfree scaffolding, storefront slugs, FSSAI, and the admin console.

## Current development focus

The admin city filter and per-city platform fee are in the repository. The next check is the admin UI in the browser: city chips, the city comparison table, and the fee card. Do not start a different feature until that pass is done.

## Pending tasks

1. Click through the admin city chips and the dashboard fee card. The unit tests passed before the commit. The browser flow had not been confirmed.
2. Confirm production API host (DigitalOcean URL in the client versus Render comments in `.env.example`).
3. Rotate and untrack the APNs private key. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## Known blockers

No code blocker was proven for the city-scope work. These items are unverified external facts, not current build failures:

- Meta WhatsApp approval. Historical. Not re-checked.
- Cashfree account and Easy Split. Needed only if that provider is enabled.
- Wildcard `*.societyeats.com`. Not in `vercel.json`.

## Important files to inspect next

- `societybites-backend/lib/adminCityDashboard.js`
- `societybites-backend/routes/admin.js`
- `societybites-backend/tests/admin-city-dashboard.test.js`
- `lib/admin/admin_city_scope.dart`
- `lib/screens/admin/admin_shell_screen.dart`
- `lib/screens/admin/admin_dashboard_screen.dart`
- `lib/services/api_service.dart`

## Recommended next step

Exercise the admin city chips and the city platform-fee card in the browser. The two unit tests already passed on 15 November 2026.

## Assumptions

- Origin was level with `2d6871c` when status was read. Not re-fetched later.
- The `pubspec.yaml` diff is only the version bump `1.0.0+57` to `1.0.0+58`.
- No second developer is editing the same files. Only this working tree was inspected.
