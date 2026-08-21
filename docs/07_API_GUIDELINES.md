# API Guidelines

- Use REST APIs.

- Return proper HTTP status codes.

- Validate all inputs.

- Authenticate protected APIs.

- Never trust userId from frontend.

- Never trust societyId from frontend.

- Always derive user from JWT.

- Return meaningful error messages.

## Listing status

Stored as lowercase strings on `Listing.status`:

| Value | Meaning |
| --- | --- |
| `active` | Visible to buyers (default) |
| `paused` | Hidden from buyers; seller can resume |
| `expired` | Past Available Until; hidden from buyers; seller can renew |
| `sold_out` | Quantity exhausted; may still be managed by seller |
| `inactive` | Soft-deleted / removed |

### Seller pause / resume / renew

- `PATCH /listings/:id/pause` — owner only; sets `paused`. Errors if already paused or expired.
- `PATCH /listings/:id/resume` — owner only; sets `active`. Errors if already active, not paused, or expired.
- `PATCH /listings/:id/renew` — owner only; body `{ "availableAt": "<ISO>" }`; sets `active` + new Available Until. Only for `expired`.

### Lazy expiry

- No cron. On listing list/detail (and before order create), listings with `availableAt < now` and status in `active|paused|sold_out` are persisted as `expired`.
- Editing an expired listing with a future `availableAt` sets status back to `active`.

### Browse / search

- `GET /listings?societyId=…` defaults to `status=active` (buyers never see paused/expired).
- Seller My Listings uses `status=all` to load `active`, `paused`, `sold_out`, and `expired`.

## Order rejection (seller)

- `POST /orders/:id/reject` — seller only.
- Allowed when status is `pending`, `accepted`, or `preparing`.
- Body: `{ "reason": "<preset>", "otherText"?: "<string>" }`.
- Preset reasons: `Food sold out`, `Unable to prepare today`, `Kitchen closed`, `Ingredients unavailable`, `Other`.
- When `reason` is `Other`, `otherText` is required (trimmed, max 200 chars) and stored as `rejectReason`.
- Sets `status=rejected`, `rejectReason`, `rejectedAt`, `rejectedBy`; restores listing quantity.
- Do not set `rejected` via `PATCH /orders/:id/status` — use the reject endpoint.

## Optional Ready by (seller)

- `PATCH /orders/:id/ready-time` — seller only.
- Body: `{ "expectedReadyAt": "<ISO datetime>" | null }`.
- Allowed only when status is `accepted` or `preparing`.
- Non-null values must be in the future; `null` clears the estimate.
- Informational only — never required for accept / prepare / ready / cancel / reject.
- Returned on existing order APIs as `expectedReadyAt` (no extra query).

## Device tokens (FCM)

- `POST /devices/register` — JWT required. Body `{ "token": "<fcm>", "platform"?: "android"|"ios" }`. Upserts by token.
- `DELETE /devices` — JWT required. Body `{ "token"?: "<fcm>" }`; omit token to deactivate all of the user’s tokens (logout).
- Push sends happen **after** order/payment commits; FCM failure never rolls back the order.

## Cash on delivery (paymentMethod = `cash`)

- Cash stays `paymentStatus=pending` until after pickup.
- `POST /payments/:orderId/confirm-cash` — seller only; order must be `picked_up`; sets `paymentStatus=paid` + `sellerConfirmedPaidAt`.
- Idempotent if already `paid` (does not overwrite timestamp).
- `PATCH /orders/:id/status` → `completed` is blocked for cash until `paymentStatus=paid`.
- UPI mark-paid / confirm endpoints reject cash orders (seller uses confirm-cash instead).

## Auth (2Factor — parallel to Firebase)

- `POST /auth/firebase-login` — **unchanged**. Body `{ "firebaseToken" }`. Returns `{ token, user }` (7d JWT).
- `POST /auth/send-otp` — Body `{ "phone" }`. Phone is normalized to `+91XXXXXXXXXX`. Does not return OTP.
- `POST /auth/verify-otp` — Body `{ "phone", "otp" }`. Returns `{ token, refreshToken, expiresIn, user }`. Finds existing user by canonical phone.
- `POST /auth/refresh` — Body `{ "refreshToken" }`. Rotates refresh token; returns new access JWT.
- `POST /auth/logout` — Body `{ "refreshToken" }`. Revokes that refresh token.
- Protected APIs still use `Authorization: Bearer <access token>`.
