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
| GET | `/listings/:id/partner-delivery` | User | `{ eligible }` for this buyer and listing. Query `paymentMethod`, `fulfilmentMethod`. Does not return the allowlist |
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
| GET | `/orders` | Orders for the signed-in buyer or seller. Optional `deliveryProvider` and `delivery`. Buyer sees drop OTP only; seller sees pickup OTP and fare |
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
| POST | `/orders` | Creates the order. Optional header `Idempotency-Key`. Optional coupon. 409 when stock is insufficient, with `availableQuantity`. Eligible partner-delivery UPI orders may include a Prorouting estimate in `deliveryCharge` / `total`; otherwise those fields match today’s path |
| PATCH | `/orders/:id/status` | Body `{ status, reason fields, deliveryCharge when marking ready }`. Partner-delivery orders skip the charge field. Partner `completed` is blocked while the rider is in flight; `Order-delivered` auto-completes. Status patch may include `delivery`. See transitions in [ARCHITECTURE.md](ARCHITECTURE.md) |
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
| GET | `/admin/settings` | Includes fee, WhatsApp, payment provider, FSSAI requirement, `deliveryProvider`, `deliveryAllowlist`. optional `?cityKey=` adds `platformFeeGlobal`, `platformFee` (effective), `cityPlatformFeeOverride`, `usesGlobalPlatformFee`, and `cityPlatformFeeOverrides` |
| PATCH | `/admin/settings` | Super admin. Same settings plus `deliveryProvider` (`seller` \| `prorouting`) and `deliveryAllowlist` (phone array). `?cityKey=` plus `platformFee` writes `city_platform_fees` for that city. No `cityKey` still writes global `platform_fee`. Body `useGlobalPlatformFee: true` with `cityKey` deletes that city's override |
| POST | `/webhooks/prorouting/:token` | Prorouting callbacks. Token must match `PROROUTING_WEBHOOK_TOKEN`. Always 200 after auth. `Order-delivered` completes the SocietyEats order (`completed`) when payment rules pass |
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
