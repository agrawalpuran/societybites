# Partner delivery POC (Prorouting)

**Status: backend plus Flutter rider/admin UI in source. Default remains off.** Written 25 November 2026. Missing `AppSetting.delivery_provider` or an empty allowlist still means today's seller-delivery path. Apply the additive Prisma migration before Ready can persist a `DeliveryTask`. Do not run `npm start` against production until you accept that migrate-on-boot. Local watch is `npm run dev` (skips boot migrate) or `SKIP_DB_MIGRATE=true`.

SocietyEats already has seller delivery. This POC adds an optional third-party rider through [Prorouting](https://prorouting.in/), behind a kill switch. uEngage is out of scope because of the quoted onboarding fee.

## Goal

Prove one cross-society **seller delivery** order end to end with a real Prorouting booking and webhooks, **without changing today’s path** for anyone when the switch is off.

Food payment stays direct UPI to the seller. The platform pays Prorouting from a pre-funded wallet. Cashfree is not part of this POC.

## Strong guardrail: default off

Partner booking runs only when **all** of the following are true. If any check fails, the request continues on the **current** seller-delivery code. Eligibility errors are swallowed: they must not 400/500 checkout or Ready.

1. **`AppSetting.delivery_provider`** is exactly `prorouting`.  
   Missing key, empty, `seller`, or any other value → **today**. Same idea as `payment_provider` defaulting to `direct_upi`.
2. **Allowlist is non-empty and matches both parties.**  
   `AppSetting.delivery_prorouting_allowlist` is a JSON array of phone numbers.  
   **Empty or missing list → nobody**, even if the provider is `prorouting`.  
   Buyer phone **and** seller phone must both appear on the list.
3. Order is **regular** (not pre-order), **cross-society**, `fulfilmentMethod` is `seller_delivery`, **UPI** (not cash).
4. Seller society and buyer society both have **latitude, longitude, and pincode** (Prorouting also needs city and state on the payload; fill from `Society` when present).
5. Env `PROROUTING_API_KEY` and `PROROUTING_BASE_URL` are set. Missing env → today.

Flipping the setting to `seller` never rewrites existing orders. An order that already has `deliveryProvider = prorouting` can still receive webhooks so an in-flight rider can finish.

## What does not change

- `Order.status` values. Rider progress is **not** a new order status. `preparing` and `picked_up` stay retired.
- Pickup, in-society delivery, cash orders, pre-orders.
- Direct UPI: mark paid / seller confirm.
- Delayed delivery charge and confirm-delivery-cash for orders whose `deliveryProvider` is null.
- Partner-locked UPI orders: Prorouting **estimate** runs at create. Food and delivery are shown as separate lines; the **seller UPI amount is the clubbed total** until split payment exists. Estimate failure does **not** lock the order (today’s path). Toggle off never estimates.
- Identity: seller, buyer, and society still come from the JWT and server-side listing rows.

## Toggle on: happy path (test users only)

Same journey as today until Ready.

1. **Checkout** (`POST /orders`). If eligible, call `/partner/estimate`. On a valid quote, set `Order.deliveryProvider = prorouting`, store `quotedFare`, set `deliveryCharge` and `total` to include that fare, and insert a `DeliveryTask` in `quoted`. If not eligible or estimate fails, identical to today.
2. **Seller accepts** if the listing type requires it. Unchanged.
3. **Buyer pays food by UPI.** Unchanged.
4. **Seller marks Ready.** Skip the actual-delivery-charge field. After the status row is committed, call Prorouting `POST /partner/order/createasync` **outside** the transaction (their instruction: book only when the order is ready to ship). Swallow API errors. Cancel uses `/partner/order/cancel`. `/partner/order/track` exists in the client for live location if we need it later.
5. **Status callback** maps `UnFulfilled` → `Agent-assigned` → `At-pickup` → `Order-picked-up` → `At-delivery` → `Order-delivered` onto `DeliveryTask.state`. `Order-delivered` sets `Order.status` to `completed` when the order is `ready` (or legacy `picked_up`) and `assertCanCompleteOrder` passes. No new order status.
6. **Seller Complete** stays a fallback if the partner trip fails, is cancelled, or RTO. While the rider is in flight, the kitchen cannot complete early. Skip `deliveryCashConfirmedAt` for these orders.

Prorouting mode for F&B: `fastest_agent` is their documented default for short pickup+drop. Prefer `estimated_price` when a still-valid estimate id exists so the billed amount matches the quote.

## Data (planned, not migrated)

- `Order.deliveryProvider` `String?` — null means current behaviour.
- `DeliveryTask`: `orderId`, `provider`, `state`, `externalId`, rider fields, OTPs, tracking URL, quoted/billed fare, last payload, last error.

Coordinates stay on **`Society`**, not on each user. Pickup/drop lat-lng are the two societies’ points; block and flat go in address text. Seller `hideFlatNumber` still hides the flat from the **buyer**; the partner payload may include pickup contact and address.

## HTTP (planned)

Module layout, same as payments:

- `societybites-backend/lib/delivery/deliverySetting.js`
- `societybites-backend/lib/delivery/proroutingClient.js` with an injectable fetch seam
- `societybites-backend/lib/delivery/deliveryService.js`
- `societybites-backend/routes/deliveryWebhooks.js` at `POST /webhooks/prorouting/:token`

Admin: extend `PATCH /admin/settings` with `deliveryProvider` and the allowlist. Do not log phone lists in chat or commits beyond what admin already stores.

Serialized order may add optional `delivery`. Old apps ignore unknown fields.

Env names only (never commit values):

- `PROROUTING_API_KEY`
- `PROROUTING_BASE_URL` (preprod first: `https://preprod.logistics-buyer.prorouting.in`)
- `PROROUTING_WEBHOOK_TOKEN`

Header: `x-pro-api-key`. Callbacks have no documented signature; the URL token is the gate. Re-read `/partner/order/status` before trusting a payload. Reply 200 quickly; persist first, notify after. Notification failure must not fail the webhook.

## Failure

| Event | Behaviour |
|---|---|
| Toggle off, empty allowlist, missing coords | Today’s path, no vendor HTTP |
| Create/update fails after Ready | Order stays `ready`; seller can fall back to typing a charge |
| LSP cancel / no rider | Same fallback |
| Still UnFulfilled after 15 minutes | One cancel + `createasync`. Card: Trying another rider, then Finding a rider. Order stays `ready` |
| Still hunting after 60 minutes | Cancel partner, `seller_fallback`, unlock Complete |
| Duplicate or older webhook | Ignore |
| WhatsApp/FCM fail | Log only |

## Tests (when coding starts)

Unit, no Postgres: default setting is off; empty allowlist means no HTTP; eligible payload shape; webhook order. Suites that need Prisma stay in **regression**, not `UNIT` (see the 24 November CI note in [LATEST_HANDOVER.md](LATEST_HANDOVER.md)). Do not run regression against the production database.

## Out of scope

uEngage, Cashfree collection of the delivery fee, one-payment split, pre-orders, per-user GPS, buyer-facing live quote at checkout (optional later).

## Owner decisions locked for this design

- Vendor: Prorouting.  
- Kill switch defaults off.  
- Empty allowlist means no bookings.  
- POC fare: platform wallet, not charged through `Order.total`.  
- No uEngage in this POC.

Still open when coding starts: public callback URL (existing API host vs an approved tunnel), preprod vs first live trip, who is on the allowlist (admin-entered phones, not source).
