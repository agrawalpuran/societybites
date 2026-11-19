# API reference

Routes mounted by `societybites-backend/index.js` on 15 November 2026. Paths below are complete paths. Authentication is what the route file applies.

`user` means `Authorization: Bearer <JWT>` and `requireUser`. A suspended user receives 403 `Account suspended`. An expired JWT receives 401 `Token expired` with code `TOKEN_EXPIRED`.

Admin routes also require a portal user. GET and HEAD are allowed for console admins. Every other method on `/admin` requires `role = super_admin`, except where a GET is also marked super-admin only.

This page does not invent response schemas. Serializers live next to the routes, mainly `utils/listingSerializer.js` and the library module named in each group. Read that module before relying on a field.

## Platform

| Method | Path | Auth | Behavior |
|---|---|---|---|
| GET | `/health` | Public | `{ status: "ok", timestamp }` |
| GET | `/ready` | Public | `{ status: "ready", database: "connected" }`, or 503 when Postgres is down |
| GET | `/` | Public | Text `Backend running` |
| GET | `/settings` | Public | Global platform fee, force-update fields, and serving-city payload. Does not apply a city override |
| GET | `/settings/platform-fee` | User | Fee for `req.user.societyId`: city override when `city_platform_fees` has that society's city, otherwise the global fee |

Global errors from the Express error handler:

| Condition | HTTP | Body |
|---|---|---|
| Unique constraint `P2002` | 409 | `{ error: "Record already exists" }` |
| Missing record `P2025` | 404 | `{ error: "Record not found" }` |
| Stale Prisma client | 503 | `{ error, code: "PRISMA_CLIENT_STALE" }` |
| `err.statusCode` set by a library | that code | `{ error: message }`, plus `code` when the error code is a non-Prisma string, plus `availableQuantity` when set |
| Anything else | 500 | `{ error: "Internal server error" }` |

Static files: `GET /uploads/...` and `GET /seed-images/...`.

## Auth

File: `routes/auth.js`. The `/auth` router allows 20 requests per minute per IP. OTP send has an additional 15-minute IP limit.

| Method | Path | Auth | Body and result |
|---|---|---|---|
| POST | `/auth/firebase-login` | Public | `{ firebaseToken }`. Verifies the Firebase ID token and returns a longer JWT. 401 if the token is invalid |
| POST | `/auth/send-otp` | Public | `{ phone }`. Sends SMS through 2Factor. Does not return the OTP. 429 when cooldown or hourly cap hits |
| POST | `/auth/verify-otp` | Public | `{ phone, otp }`. Returns access token, refresh token, and user. 401 invalid OTP. 403 suspended |
| POST | `/auth/refresh` | Public | `{ refreshToken }`. Rotates the refresh token. Reuse of the old raw token fails |
| POST | `/auth/logout` | Public | `{ refreshToken }`. Revokes it. Idempotent |
| GET | `/auth/me` | User | Current user |
| POST | `/auth/me/profile-photo` | User | Image upload |
| POST | `/auth/me/seller-terms` | User | Accept terms and enable selling |
| GET | `/auth/me/selling-reach-change-preview` | User | Preview of a reach decrease |
| PATCH | `/auth/me/profile` | User | Profile, UPI, reach, fulfilment, kitchen hours, storefront fields. Server validates seller settings |
| DELETE | `/auth/me` | User | Account deletion |

Buyer places, file `routes/buyerAddresses.js`, mounted at `/auth/me/addresses` and still behind `requireUser`:

| Method | Path | Notes |
|---|---|---|
| GET | `/auth/me/addresses` | List |
| POST | `/auth/me/addresses` | Create |
| POST | `/auth/me/addresses/:id/select` | Selects the place and updates `User.societyId` |
| DELETE | `/auth/me/addresses/:id` | Delete |

Kitchen move, file `routes/kitchenMoves.js`:

| Method | Path | Notes |
|---|---|---|
| GET | `/auth/me/kitchen-move` | Current request |
| POST | `/auth/me/kitchen-move` | Create |
| POST | `/auth/me/kitchen-move/cancel` | Cancel |

## Societies

File: `routes/societies.js`.

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/societies` | Public | Active societies and blocks |
| GET | `/societies/places/search` | User | Rate limit 30/minute. Google Places plus database matches in the launch city |
| POST | `/societies/places/preview` | User | Preview a place before join |
| GET | `/societies/:id` | User | One society |
| POST | `/societies/join` | User | Join |
| POST | `/societies/:id/validate-flat` | User | Flat check |

## Listings

File: `routes/listings.js`.

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/listings/guest-kitchens` | Public | Guest discovery |
| GET | `/listings/guest-kitchens/:sellerId` | Public | One guest kitchen |
| GET | `/listings/nearby-sellers` | User with society | Radius discovery |
| GET | `/listings/nearby-sellers/:sellerId` | User with society | One nearby kitchen |
| GET | `/listings` | User with society | Query `sellerId`, `status` default `active`, `search`, `category`, `catalogType` |
| POST | `/listings/:id/like` | User | |
| GET | `/listings/:id/likes` | User | |
| GET | `/listings/:id/variants` | User | |
| GET | `/listings/:id` | User | |
| POST | `/listings` | User | Creates a draft. Seller is the JWT user |
| PUT | `/listings/catalog-order` | User | Seller sort order |
| PATCH | `/listings/:id/catalog` | User | |
| PATCH | `/listings/:id` | User | Edit |
| PATCH | `/listings/bulk/publish` | User | |
| PATCH | `/listings/bulk/pause` | User | |
| PATCH | `/listings/bulk/resume` | User | |
| PATCH | `/listings/:id/publish` | User | |
| PATCH | `/listings/:id/pause` | User | |
| PATCH | `/listings/:id/resume` | User | |
| PATCH | `/listings/:id/renew` | User | |
| DELETE | `/listings/:id` | User | Soft delete to `inactive` |

`PUT /listings/catalog-order` is declared before `/:id` routes that would otherwise swallow it. Keep that order if you add routes.

## Pre-order campaigns

File: `routes/preorderCampaigns.js`. All listed routes use `requireUser`. Seller ownership is checked in the handlers.

| Method | Path |
|---|---|
| GET | `/preorder-campaigns` |
| GET | `/preorder-campaigns/:id` |
| GET | `/preorder-campaigns/:id/summary` |
| GET | `/preorder-campaigns/:id/orders` |
| POST | `/preorder-campaigns` |
| PATCH | `/preorder-campaigns/:id` |
| POST | `/preorder-campaigns/:id/products` |
| PATCH | `/preorder-campaigns/:id/products/:productId` |
| DELETE | `/preorder-campaigns/:id/products/:productId` |

## Orders

File: `routes/orders.js`. All listed routes use `requireUser`. Buyer and seller are checked per handler.

| Method | Path | Notes |
|---|---|---|
| GET | `/orders` | Orders for the signed-in buyer or seller |
| GET | `/orders/seller/stats` | |
| GET | `/orders/seller/insights` | |
| GET | `/orders/seller/reconciliation/summary` | |
| GET | `/orders/seller/reconciliation/orders` | |
| POST | `/orders/seller/reconciliation/orders/:orderId/payment-reminder` | Seller reminder. Cooldown stored on the order |
| GET | `/orders/:id/messages` | |
| POST | `/orders/:id/messages` | |
| POST | `/orders/:id/buyer-contact` | |
| POST | `/orders/:id/seller-contact` | |
| GET | `/orders/:id` | |
| POST | `/orders` | Creates the order. Optional header `Idempotency-Key`. Optional coupon. 409 when stock is insufficient, with `availableQuantity` |
| PATCH | `/orders/:id/status` | Body `{ status, reason fields, deliveryCharge when marking ready }`. See transitions in [ARCHITECTURE.md](ARCHITECTURE.md) |
| POST | `/orders/:id/reject` | Seller decline with a required reason |
| PATCH | `/orders/:id/ready-time` | Informational ready-by estimate |

Seller-only paths are registered before `/:id`, so `seller` is not parsed as an order id.

Reject reasons in code: `Not available today`, `Ingredients unavailable`, `Too many orders`, `Not enough time`, `Unable to fulfil by requested date`, `Other`.

Buyer cancel reasons in code: `Changed my mind`, `Ordered by mistake`, `No longer needed`, `Delivery or timing issue`, `Other`.

## Payments

File: `routes/payments.js`. All use `requireUser`.

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/payments/payout-profile` | Seller | Cashfree vendor profile. Empty when unset |
| PUT | `/payments/payout-profile` | Seller | PAN and UPI or bank |
| POST | `/payments/:orderId/checkout` | Buyer | Starts direct UPI or Cashfree. Order must already be `accepted`, `preparing`, or `ready`. Optional `returnOrigin` |
| POST | `/payments/:orderId/mark-paid` | Buyer | Direct UPI. Sets `buyer_marked_paid`. Optional `upiTransactionRef`. Rejected for Cashfree orders |
| POST | `/payments/:orderId/confirm` | Seller | Confirms UPI. Sets `seller_confirmed` |
| POST | `/payments/:orderId/confirm-cash` | Seller | Sets `paid`. Does not auto-complete |
| POST | `/payments/:orderId/confirm-delivery-cash` | Seller | Outside UPI plus cash delivery. Can set `completed` |
| GET | `/payments/:orderId` | Buyer or seller | Payment view |

Webhook, file `routes/paymentWebhooks.js`:

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/webhooks/cashfree` | Cashfree signature | Headers `x-webhook-timestamp` and `x-webhook-signature`. 401 `Invalid signature` when verification fails |

## Reviews, media, devices, issues, coupons, FSSAI, staff, banners, public

| Method | Path | Auth | File | Notes |
|---|---|---|---|---|
| GET | `/reviews/seller/me` | User | `reviews.js` | Optional `kitchenSellerId` for a view-only owner |
| GET | `/reviews/listing/:listingId` | Public | `reviews.js` | Hidden reviews omitted |
| POST | `/reviews` | User | `reviews.js` | `orderId`, `listingId`, and `rating` required |
| POST | `/media/upload` | User | `media.js` | Image upload |
| POST | `/devices/register` | User | `devices.js` | FCM token |
| DELETE | `/devices` | User | `devices.js` | Remove token |
| POST | `/issues` | User | `issues.js` | New report |
| GET | `/issues/my` | User | `issues.js` | |
| POST | `/issues/:id/messages` | User | `issues.js` | |
| GET | `/issues/:id` | User | `issues.js` | |
| POST | `/coupons/validate` | User | `coupons.js` | Preview. Redemption happens inside order create |
| GET | `/fssai/me` | User | `fssai.js` | |
| POST | `/fssai/me/document` | User | `fssai.js` | |
| POST | `/fssai/me/submit` | User | `fssai.js` | |
| POST | `/fssai/me/draft` | User | `fssai.js` | |
| POST | `/fssai/me/defer` | User | `fssai.js` | |
| GET | `/fssai/me/document-url` | User | `fssai.js` | |
| POST | `/fssai/me/assistance` | User | `fssai.js` | |
| GET | `/seller-staff/owners` | User | `sellerStaff.js` | |
| POST | `/seller-staff/owners/invite` | User | `sellerStaff.js` | |
| GET | `/seller-staff/access` | User | `sellerStaff.js` | Kitchens this user can view |
| GET | `/festival-banners/active` | Public | `festivalBanners.js` | |
| GET | `/public/kitchens/:slug` | Public | `public.js` | Branded kitchen |

## Incentive engine

File: `modules/incentive-engine/`. Prefix `/incentive`. Every switch is off when its `IncentiveSetting` row is missing or is not exactly `true`. The master switch forces the others off. Buyer and seller referral also require the referral switch. A database error on the read returns the same all-off payload. `GET /incentive/flags` also returns `stored`, the saved on/off value before the master and referral gates. `PUT /incentive/admin/flags` is super-admin only and accepts `{ key, enabled }` for `master`, `referral`, `buyerReferral`, or `sellerReferral`. `enabled` must be a boolean. `true` stores the text `true`. `false` stores the text `false`. Issuance, redemption, and promotional campaigns have no writer. A console admin receives 403. A missing incentive table returns 503 `INCENTIVE_TABLES_MISSING`. A change writes one `FLAG_CHANGED` audit row. The Flutter admin Settings tab is shown only to a super admin. Reward responses include `rewardType` from `IncentiveRewardDefinition` for the reward's version and slot.

Campaign routes are configuration only. They do not create coupons, rewards, ledger rows, or referral attributions. Stored triggers are marked `processor: "NOT_IMPLEMENTED"` on the campaign snapshot. Phase 2C can ingest and evaluate those event types from `/incentive/admin/events`. It does not hook registration, orders, payments, listings, or reviews, and it does not issue rewards.

Phase 2D-1 adds referral code creation and retrieval. `GET` and `POST /incentive/referral-codes` use the JWT user id and ignore any user id in the body. `POST` returns 201 for a new code and 200 for the same caller's existing code. The code is pinned to the published campaign version, and its expiry is stored once. A later campaign edit does not change that row. `GET /incentive/referral-codes/preview?code=` is public, limited to 30 requests per minute per IP, and returns only `{ valid, audience, expiresAt }`. `url` is an absolute link only when `REFERRAL_LINK_BASE_URL` is an HTTPS origin with no path, query, or credentials. Otherwise `url` is null. These routes do not attribute a referral. Referral categories cannot activate until the snapshot has a valid `referralPolicy`. `BUYER_ACQUISITION` and `REFERRAL` require `buyer.maxAccountAgeHours`. A code also needs `codeExpiresInDays` or a campaign end.

Statuses are `DRAFT`, `SCHEDULED`, `ACTIVE`, `PAUSED`, `COMPLETED`, `EXPIRED`, and `TERMINATED`. Create always returns `DRAFT`. A draft edits its current unpublished version. Editing a scheduled, active, or paused campaign forks a new version and returns the campaign to `DRAFT`. Finished campaigns stay readable and reject edits. There is no delete route.

`POST /incentive/admin/campaigns/:id/activate` requires the master switch. Referral categories also require the referral switch. `PROMOTIONAL` and `FESTIVE` also require the promotional switch. While those switches are off the route returns 403 `ENGINE_DISABLED`, `REFERRAL_DISABLED`, or `PROMOTIONAL_DISABLED` and does not change the campaign. Pause, terminate, complete, and expire do not issue rewards. Expire requires the end date to be in the past.

A draft may omit its audience, eligibility policy, trigger, reward definition, or budget. Activation rejects that incomplete snapshot with 400 and a code such as `AUDIENCE_REQUIRED`, `ELIGIBILITY_REQUIRED`, `RULES_REQUIRED`, `TRIGGER_REQUIRED`, `REWARD_REQUIRED`, or `BUDGET_REQUIRED`. An empty audience does not mean every user. `ALL_USERS` is the explicit every-user audience and cannot be combined with another kind. The eligibility policy is stored on the version snapshot as `RULES` or `AUDIENCE_AND_TRIGGER_ONLY`. `RULES` requires a non-empty rule tree. `AUDIENCE_AND_TRIGGER_ONLY` requires an audience and a trigger and stores no rule tree. A missing policy does not make the campaign eligible.

Simulation uses the same readiness check as activation. An incomplete campaign returns `passed: false`, `matchesEveryone: false`, and a reason. `matchesEveryone: true` is returned only when the campaign is ready and its audience is exactly `ALL_USERS`, with the reason `Explicit all-user audience`. The response still shows the configured reward with `issued: false` and the budget with `consumed: false`. It does not write. Event processing calls `assessCampaign` in `modules/incentive-engine/campaign/readiness.js`.

Event routes accept the eight configured event types. The server builds `eventId`. One order can have only one of `ORDER_QUALIFIED`, `ORDER_CANCELLED`, or `ORDER_REJECTED`. A duplicate of the same event returns the stored row and does not add an audit row. While the master switch is off, `POST /incentive/admin/events/process-due` returns 403 `ENGINE_DISABLED` and leaves valid events `PENDING`. The claim itself is one `UPDATE` that requires `master_enabled` to be exactly `true` after `btrim`. A claim that already committed may finish. Each claim stores a new `claimToken`. A later outcome write must match that token, so an expired worker cannot replace a newer result. Retry delay starts at 30 seconds and doubles, up to one hour. The eighth failure is `DEAD`. Replay is super-admin only and accepts `FAILED`, `DEAD`, or `SKIPPED`. Replay keeps `attempts`. The next claim increments that count, so a repeated outcome gets a new audit row. Replaying a dead event allows one more claim. If that claim fails, the event is dead again. There is no scheduler.

| Method | Path | Auth | Result |
|---|---|---|---|
| GET | `/incentive/flags` | User | Effective booleans plus `stored` for the same keys. A missing row is off |
| PUT | `/incentive/admin/flags` | Super admin | `{ key, enabled }` for `master`, `referral`, `buyerReferral`, or `sellerReferral`. Other keys are 400 `FLAG_NOT_WRITABLE`. Does not issue a reward |
| GET | `/incentive/admin/campaigns` | Portal read | Campaign headers |
| POST | `/incentive/admin/campaigns` | Super admin | Creates a `DRAFT` |
| GET | `/incentive/admin/campaigns/:id` | Portal read | Campaign plus current version snapshot |
| PATCH | `/incentive/admin/campaigns/:id` | Super admin | Edits a draft, or forks a published campaign |
| GET | `/incentive/admin/campaigns/:id/versions` | Portal read | Version list |
| GET | `/incentive/admin/campaigns/:id/versions/:versionId` | Portal read | Frozen snapshot |
| PUT | `/incentive/admin/campaigns/:id/audience` | Super admin | `{ audiences: [{ kind, payload? }] }` |
| PUT | `/incentive/admin/campaigns/:id/triggers` | Super admin | `{ triggers: [eventType] }`. Stored only |
| PUT | `/incentive/admin/campaigns/:id/rules` | Super admin | `{ eligibility, rules? }`. `eligibility` is `RULES` or `AUDIENCE_AND_TRIGGER_ONLY` |
| PUT | `/incentive/admin/campaigns/:id/rewards` | Super admin | Reward definitions. Nothing is issued |
| PUT | `/incentive/admin/campaigns/:id/budget` | Super admin | Cap and limits. `issuedAmount` stays `0.00` |
| PUT | `/incentive/admin/campaigns/:id/referral-policy` | Super admin | Stores `referralPolicy` on a referral-category draft. It does not issue a code |
| POST | `/incentive/admin/campaigns/:id/simulate` | Super admin | Explanation only. No writes |
| POST | `/incentive/admin/campaigns/:id/duplicate` | Super admin | Copy configuration into a new `DRAFT`. Requires a different name. Does not copy issued rewards, events, referrals, or consumed budget |
| GET | `/incentive/admin/campaigns/:id/performance` | Portal read | Stored referral, reward, budget, schedule, daily series, and status timeline |
| GET | `/incentive/admin/referral-analytics` | Portal read | Funnel, buyer and seller comparison, recorded failure reasons, and a name-only leaderboard |
| GET | `/incentive/admin/referral-leaderboard` | Portal read | Qualified referrers. Display name, count, and user id. No phone |
| GET | `/incentive/admin/reward-report` | Portal read | Status counts, credit and points balances, expiry rows, ledger timeline, and recorded exceptions |
| GET | `/incentive/admin/audit` | Portal read | Sanitised audit page. Query `campaignId`, `action`, `from`, `to`, `cursor` |
| GET | `/incentive/admin/risk` | Portal read | Review indicators. `automaticAction` is `none`. No phone |
| POST | `/incentive/admin/campaigns/:id/activate` | Super admin | Blocked while the master switch is off |
| POST | `/incentive/admin/campaigns/:id/pause` | Super admin | `PAUSED` |
| POST | `/incentive/admin/campaigns/:id/terminate` | Super admin | `TERMINATED`. History remains |
| POST | `/incentive/admin/campaigns/:id/complete` | Super admin | `COMPLETED` |
| POST | `/incentive/admin/campaigns/:id/expire` | Super admin | `EXPIRED` after the end date |
| POST | `/incentive/admin/events` | Super admin | Ingest one event. `201` when created, `200` when it already exists |
| POST | `/incentive/admin/events/backfill` | Super admin | Rebuilds missing seller, listing, and qualifying-order events from stored source timestamps. A listing without `firstPublishedAt` is reported and not invented |
| GET | `/incentive/admin/events` | Portal read | Recent events. Optional `status` |
| GET | `/incentive/admin/events/reconciliation` | Portal read | Expired claims, dead letters, due failures, and stale pending rows |
| POST | `/incentive/admin/events/reconciliation/recover` | Super admin | Fence expired claims. Records the super-admin actor |
| POST | `/incentive/admin/events/process-due` | Super admin | Process a batch. `403` `ENGINE_DISABLED` when the master switch is off |
| GET | `/incentive/admin/events/:id` | Portal read | One event. The claim token is not returned |
| POST | `/incentive/admin/events/:id/replay` | Super admin | Requeue `FAILED`, `DEAD`, or `SKIPPED` |
| GET | `/incentive/referral-codes` | User | The caller's codes. 403 `REFERRAL_DISABLED` when master or referral is off |
| POST | `/incentive/referral-codes` | User | `{ audience, campaignId }`. 201 new, 200 existing. Does not accept a trusted user id |
| GET | `/incentive/referral-codes/preview?code=` | Public, rate limited | `{ valid, audience, expiresAt }` only |
| GET | `/incentive/referrals` | User | The caller's referral rows. Names only, no phone or user id. Includes `qualificationNote` |
| GET | `/incentive/referrals/leaderboard` | User | Top display names and qualified counts when referral is on. Ignores a query user id. No phone or user id |
| POST | `/incentive/referrals` | User | `{ code, acquisitionKind }`. 201 new, 200 same claim. The body user id is ignored |
| GET | `/incentive/admin/referrals` | Portal read | Referral rows with ids and milestone times |
| GET | `/incentive/admin/referrals/:id` | Portal read | One referral |
| POST | `/incentive/admin/referrals/:id/approve` | Super admin | `PENDING_REVIEW` to `QUALIFIED` |
| POST | `/incentive/admin/referrals/:id/reject` | Super admin | `PENDING_REVIEW` to `DISQUALIFIED` |
| POST | `/incentive/admin/referrals/:id/disqualify` | Super admin | Fraud or admin reversal |
| POST | `/incentive/admin/referrals/expire-due` | Super admin | Expires open rows whose window has ended |
| POST | `/incentive/admin/referrals/reconcile` | Super admin | Re-reads stored orders and reverses qualification when `qualifyOrder` fails |
| GET | `/incentive/admin/overview` | Portal read | Counts for campaigns, referrals, issued rewards by type, and the eight most recent events |
| GET | `/incentive/admin/ledger` | Portal read | Ledger page. Query `limit` (max 50), `cursor`, `entryType`, `rewardId`, `userId`, `rewardType`. Read-only |
| GET | `/incentive/offers` | User | Active published offers for the JWT role. Buyers do not receive seller listing or seller-acquisition campaigns. Sellers do not receive the other categories. The body omits budget, rules, audience payloads, and `createdBy`. While the master switch is off the list is empty and `reason` is `ENGINE_OFF` |
| GET | `/incentive/rewards` | User | The caller's rewards and credit/points balances. `recipientUserId` and `userId` query values are ignored |
| GET | `/incentive/rewards/history` | User | The caller's ledger page. Same ignored user-id query values. Query `limit`, `cursor`, `entryType`, `rewardType` |
| GET | `/incentive/admin/rewards` | Portal read | Reward rows, including `rewardType`. No phone, flat, or society |
| GET | `/incentive/admin/rewards/reconciliation` | Portal read | Query `campaignId`. Configured cap, reserved amount, remainder, reward counts, and signed ledger totals. It does not write |
| GET | `/incentive/admin/rewards/:id` | Portal read | One reward and its ledger entries |
| POST | `/incentive/admin/rewards/:id/approve` | Super admin | `PENDING_APPROVAL` to `ISSUED` only when `issuance_enabled` trims to exactly `true`. Otherwise `403 ISSUANCE_DISABLED`. A repeat of an already issued reward returns that row |
| POST | `/incentive/admin/rewards/:id/reject` | Super admin | `PENDING_APPROVAL` to `REJECTED` and releases that reward's reserved budget once. A percentage coupon releases `maxDiscount`. A missing snapshot returns `409 REWARD_DEFINITION_MISSING` and does not change the budget. A later event for that reward is skipped as `REWARD_CLOSED` |
| POST | `/incentive/admin/rewards/:id/redeem` | Super admin | Debits promotional credit or points when redemption is on. Does not change checkout. `409 REWARD_EXPIRED` when `expiresAt` has passed. `409 COUPON_REDEMPTION_UNCHANGED` for a coupon reward. The same idempotency key with another amount returns `409 IDEMPOTENCY_CONFLICT`. An `orderId` must be that recipient's order, or the response is `404 ORDER_NOT_FOUND` or `409 REWARD_ORDER_MISMATCH` |
| POST | `/incentive/admin/rewards/expire-due` | Super admin | Expires due credit and posts the remaining balance. Re-reads the reward under its row lock, so a redemption that already committed is left as `REDEEMED` |

## Admin

File: `routes/admin.js`. Prefix `/admin`. Portal user required. Non-GET requires super admin. `GET /admin/console-admins` is super admin even though it is a GET.

| Method | Path | Purpose |
|---|---|---|
| GET | `/admin/console-admins` | List console admins. Super admin |
| POST | `/admin/console-admins` | Grant |
| DELETE | `/admin/console-admins/:userId` | Revoke |
| GET | `/admin/dashboard` | Summary counts. optional `?cityKey=` limits counts to that active serving city and adds a `scope` object |
| GET | `/admin/dashboard/cities` | `{ activeCities, rows, totals, periodDays }`. Each row has `cityKey`, `displayName`, `societies`, `sellers`, `orders7d`, `foodGmv7d`. `periodDays` is 7 |
| GET | `/admin/performance/summary` | Seller performance |
| GET | `/admin/performance/sellers` | Leaderboard |
| GET | `/admin/performance/sellers/:sellerId` | Detail |
| GET | `/admin/performance/sellers/:sellerId/orders` | |
| GET | `/admin/performance/campaigns` | |
| GET | `/admin/performance/export` | CSV |
| GET | `/admin/growth` | Growth series |
| GET | `/admin/growth/members` | |
| GET | `/admin/fssai/summary` | |
| GET | `/admin/fssai/submissions` | |
| GET | `/admin/fssai/submissions/:sellerId/document-url` | |
| POST | `/admin/fssai/submissions/:sellerId/approve` | |
| POST | `/admin/fssai/submissions/:sellerId/reject` | |
| GET | `/admin/festival-banners` | |
| GET | `/admin/festival-banners/:id` | |
| POST | `/admin/festival-banners` | |
| PATCH | `/admin/festival-banners/:id` | |
| POST | `/admin/festival-banners/:id/activate` | |
| POST | `/admin/festival-banners/:id/deactivate` | |
| GET | `/admin/address-proofs` | |
| GET | `/admin/address-proofs/:userId` | |
| POST | `/admin/address-proofs/:userId/review` | |
| GET | `/admin/kitchen-moves` | |
| GET | `/admin/kitchen-moves/:id` | |
| GET | `/admin/kitchen-moves/:id/fssai-document-url` | |
| POST | `/admin/kitchen-moves/:id/address-proof` | |
| POST | `/admin/kitchen-moves/:id/fssai/needs-review` | |
| POST | `/admin/kitchen-moves/:id/fssai/approve` | |
| POST | `/admin/kitchen-moves/:id/fssai/reject` | |
| POST | `/admin/kitchen-moves/:id/approve` | Applies the society change |
| POST | `/admin/kitchen-moves/:id/reject` | |
| GET | `/admin/fssai/assistance` | |
| GET | `/admin/fssai/assistance/:id` | |
| PATCH | `/admin/fssai/assistance/:id` | |
| GET | `/admin/users` | |
| PATCH | `/admin/users/:id` | Suspend and related admin edits |
| GET | `/admin/societies` | |
| POST | `/admin/societies` | |
| PATCH | `/admin/societies/:id` | |
| POST | `/admin/societies/:id/regenerate-code` | |
| GET | `/admin/listings` | |
| PATCH | `/admin/listings/:id` | |
| GET | `/admin/orders` | |
| GET | `/admin/orders/:id` | |
| GET | `/admin/reviews` | |
| PATCH | `/admin/reviews/:id` | Hide or restore |
| GET | `/admin/payments` | |
| GET | `/admin/audit-log` | |
| GET | `/admin/search` | |
| GET | `/admin/payment-splits` | Cashfree split view |
| GET | `/admin/settings` | Includes fee, WhatsApp, payment provider, FSSAI requirement. optional `?cityKey=` adds `platformFeeGlobal`, `platformFee` (effective), `cityPlatformFeeOverride`, `usesGlobalPlatformFee`, and `cityPlatformFeeOverrides` |
| PATCH | `/admin/settings` | Super admin. Same settings. `?cityKey=` plus `platformFee` writes `city_platform_fees` for that city. No `cityKey` still writes global `platform_fee`. Body `useGlobalPlatformFee: true` with `cityKey` deletes that city's override |
| GET | `/admin/city-reach-configs` | |
| PUT | `/admin/city-reach-configs/:cityKey` | |
| GET | `/admin/serving-cities` | |
| PUT | `/admin/serving-cities` | |
| GET | `/admin/issues` | |
| GET | `/admin/issues/:id` | |
| PATCH | `/admin/issues/:id` | |
| GET | `/admin/reports/coupon-seller-payouts` | Funded-discount report |
| POST | `/admin/coupons` | |
| GET | `/admin/coupons` | |
| GET | `/admin/coupons/:id` | |
| PATCH | `/admin/coupons/:id` | |
| POST | `/admin/coupons/:id/pause` | |
| POST | `/admin/coupons/:id/activate` | |
| PUT | `/admin/coupons/:id/eligible-users` | |
| PUT | `/admin/coupons/:id/eligible-societies` | |
| GET | `/admin/marketing-push` | |
| POST | `/admin/marketing-push` | |

Optional `?cityKey=` on these GETs limits rows to societies in that active serving city: `/admin/growth`, `/admin/growth/members`, `/admin/societies`, `/admin/listings`, `/admin/orders`, `/admin/reviews`, `/admin/issues`, `/admin/coupons`, and `/admin/performance/summary`, `/sellers`, `/sellers/:sellerId`, `/sellers/:sellerId/orders`, `/campaigns`, and `/export`. An unknown or inactive city returns 400 `{ error: "City is not an active serving city", code: "INVALID_CITY_KEY" }`. The full rules are in [LATEST_HANDOVER.md](LATEST_HANDOVER.md).

## Clients

The Flutter client calls these paths through `lib/services/api_service.dart`. A new endpoint is not done until that client, or a confirmed non-UI caller, uses it. Do not add a parallel client.
