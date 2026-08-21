# 2Factor authentication — implementation checkpoint

**Date:** 21 Aug 2026  
**Status:** Local backend 2Factor end-to-end tests passed. Firebase remains the live/demo path. No cutover. Not committed.

2Factor was added **in parallel** with existing Firebase phone auth. Protected APIs still use `Authorization: Bearer <JWT>` via `requireUser`. JWT payload is unchanged (`userId`, `phone`, `role`, `societyId`).

---

## 1. Existing Firebase authentication flow (unchanged)

```
Flutter (default build)
  → Firebase Phone OTP
  → Firebase ID token
  → POST /auth/firebase-login { firebaseToken }
  → verify Firebase ID token
  → find/create User by Firebase phone_number
  → 7-day JWT (signToken / JWT_EXPIRY)
  → existing APIs
```

`POST /auth/firebase-login` still returns `{ success, token, user }` with **no** refresh token. Demo builds stay on this path unless compiled with `--dart-define=AUTH_PROVIDER=2factor`.

## 2. New 2Factor OTP flow

```
Client
  → POST /auth/send-otp { phone }
  → 2Factor AUTOGEN SMS (OTP never returned by API)
  → POST /auth/verify-otp { phone, otp }
  → find/create User by normalized +91XXXXXXXXXX
  → short-lived access JWT + raw refresh token
  → POST /auth/refresh { refreshToken }  (rotate)
  → POST /auth/logout { refreshToken }   (revoke)
  → GET /auth/me and other JWT-protected routes
```

## 3. `POST /auth/send-otp`

- Body: `{ "phone" }` (10-digit, `91…`, or `+91…`).
- Normalizes to `+91XXXXXXXXXX`; sends to 2Factor as `91XXXXXXXXXX`.
- Uses AUTOGEN2 + template when `TWOFACTOR_OTP_TEMPLATE` is set; otherwise AUTOGEN.
- Stores only the 2Factor **session id** in an in-memory store (`otpStore`). Does not return OTP.
- Cooldown / hourly send limits / IP rate limit apply.
- Response: `{ ok: true, message: "OTP sent" }`.

## 4. `POST /auth/verify-otp`

- Body: `{ "phone", "otp" }`.
- Verifies against 2Factor `SMS/VERIFY/{sessionId}/{otp}`.
- On match: `findOrCreateUserByPhone`, then `signAccessToken` + `issueRefreshToken`.
- Response: `{ success, token, refreshToken, expiresIn, user }`.
- Suspended users: `403`. Invalid OTP: `401`. Missing/expired challenge: `400`.

## 5. `POST /auth/refresh`

- Body: `{ "refreshToken" }` (raw token from verify or previous refresh).
- Hashes with SHA-256, looks up `RefreshToken.tokenHash`.
- Rejects missing/revoked (`401 Invalid refresh token`) or expired (`401 Refresh token expired`).
- Rotates: sets `revokedAt` on the used row, issues a new raw refresh token + new access JWT.
- A refresh token is **one-time**. Reusing the previous raw value after a successful refresh (or logout) returns 401.

## 6. `POST /auth/logout`

- Body: `{ "refreshToken" }`.
- Sets `revokedAt` on matching unrevoked row. Idempotent if already revoked or unknown.
- Response: `{ ok: true }`. Does not delete the user.

## 7. Access-token expiry

- 2Factor access JWT: `ACCESS_TOKEN_EXPIRY` or default **`15m`** (`signAccessToken`).
- `expiresIn` in verify/refresh responses is that same string (e.g. `"15m"`).
- Firebase login JWT: still `JWT_EXPIRY` or default **`7d`** (`signToken`).
- Same `JWT_SECRET` and payload for both.

## 8. Refresh-token TTL

- `REFRESH_TOKEN_TTL_MS` or default **`2592000000`** (30 days).
- Stored as `RefreshToken.expiresAt`. Raw token is never stored.

## 9. Refresh-token rotation / revocation

| Event | Behaviour |
| --- | --- |
| verify-otp | Insert hashed token, `revokedAt = null` |
| refresh | Revoke presented token, insert a new hashed token |
| logout / explicit revoke | Set `revokedAt` on that hash only |
| expiry | Refresh returns expired; row is not auto-deleted |

Rotation does not revoke other users’ tokens or other sessions for the same user unless those exact hashes are presented.

## 10. Phone normalization

`utils/phone.js` → `normalizeIndianPhone`:

- `9876543210` / `919876543210` / `+919845154070` / leading `0` → **`+91` + 10 digits**.
- Must be a 10-digit Indian mobile starting `6–9`.
- 2Factor send uses `toTwoFactorPhone` → `91XXXXXXXXXX` (no `+`).

## 11. Existing User lookup / creation

- Lookup key is canonical `User.phone` (`+91XXXXXXXXXX`).
- Existing user is reused; `id` does not change.
- If no row: create `{ phone, role: "buyer" }` (same pattern as firebase-login).
- Firebase login still uses `decodedToken.phone_number` as stored (typically already E.164). Do not mix formats for the same person.

## 12. Database changes

- **`RefreshToken` model** added: `id`, `userId`, `tokenHash` (unique), `expiresAt`, `revokedAt?`, `createdAt`.
- **`User.refreshTokens`** relation; `onDelete: Cascade`.
- **`User` identity fields unchanged** (no new user columns for 2Factor).
- Applied via Prisma schema (no migration files in this repo).

OTP session ids are **not** in the database (in-memory `otpStore`). A backend process restart drops pending OTP challenges, not refresh tokens.

## 13. Environment variables required (local)

| Variable | Required for | Notes |
| --- | --- | --- |
| `DATABASE_URL` | All | Existing |
| `JWT_SECRET` | All JWT | Existing |
| `JWT_EXPIRY` | Firebase JWT | Optional; default `7d` |
| `TWOFACTOR_API_KEY` | send/verify OTP | Required for 2Factor APIs |
| `TWOFACTOR_OTP_TEMPLATE` | SMS template | Optional; used locally as `OTP1` |
| `ACCESS_TOKEN_EXPIRY` | 2Factor access JWT | Optional; default `15m` |
| `REFRESH_TOKEN_TTL_MS` | Refresh TTL | Optional; default 30 days |
| `OTP_TTL_MS` / cooldown / max sends / max attempts | OTP store | Optional |
| Firebase Admin vars | firebase-login + FCM | Unchanged |

## 14. Render environment variables required later

Set on Render **before** production 2Factor traffic (do not cut over until approved):

- `TWOFACTOR_API_KEY`
- `TWOFACTOR_OTP_TEMPLATE` (if the 2Factor DLT template is required)
- `ACCESS_TOKEN_EXPIRY` (recommend `15m`)
- `REFRESH_TOKEN_TTL_MS` (recommend `2592000000`)

Keep existing `DATABASE_URL`, `JWT_SECRET`, `JWT_EXPIRY`, Firebase Admin, `PORT`, `NODE_ENV`.

**Note:** `otpStore` is in-process memory. Multiple Render instances would not share OTP challenges unless a later change adds shared storage or sticky sessions.

## 15. What has been tested successfully (local backend)

- Real 2Factor SMS send (`POST /auth/send-otp`)
- Real OTP verify (`POST /auth/verify-otp`)
- Existing SocietyBites user reused (same `User.id`, name, society/flat)
- Phone `9845154070` → stored/returned `+919845154070`
- No duplicate user created
- Access JWT accepted by existing `GET /auth/me`
- `POST /auth/refresh` issues a new access token (must use a **current**, unrevoked refresh token)
- `GET /auth/me` with the **new** access token from refresh
- Refresh-token revoke / logout of a specific hash
- 401 when refreshing a token that was already revoked or already rotated

## 16. What has NOT yet been tested

- Flutter `--dart-define=AUTH_PROVIDER=2factor` on a real device (send/verify, secure storage, startup restore)
- Access-token expiry in the app (~15 minutes) and automatic `/auth/refresh` retry
- Logout from the Flutter profile/session path
- Firebase Phone OTP **device** e2e after these parallel changes (backend firebase-login was not redesigned)
- FCM register/delivery after a 2Factor login
- Render deployment with the new env vars
- Multi-instance OTP (in-memory store)
- Concurrent refresh from two clients with the same refresh token

## 17. Exact files changed so far (2Factor work)

**Backend (new)**

- `societybites-backend/lib/twoFactor.js`
- `societybites-backend/lib/otpStore.js`
- `societybites-backend/lib/refreshTokens.js`
- `societybites-backend/utils/phone.js`

**Backend (modified)**

- `societybites-backend/routes/auth.js`
- `societybites-backend/lib/jwt.js`
- `societybites-backend/prisma/schema.prisma`
- `societybites-backend/.env.example`

**Flutter (parallel; default remains Firebase)**

- `lib/services/auth_config.dart` (new)
- `lib/services/session_service.dart`
- `lib/services/api_service.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/otp_screen.dart`
- `lib/screens/profile_screen.dart`
- `lib/main.dart`
- `pubspec.yaml` / `pubspec.lock` (`flutter_secure_storage ^9.2.4`)
- Desktop plugin registrants: `linux/flutter/generated_plugin_registrant.cc`, `linux/flutter/generated_plugins.cmake`, `macos/Flutter/GeneratedPluginRegistrant.swift`, `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake`

**Docs**

- `docs/07_API_GUIDELINES.md` (auth endpoint notes)
- `docs/2FACTOR_AUTH_CHECKPOINT.md` (this file)

Unrelated dirty files in the working tree (orders/payments/COD/docs) are **not** part of this auth checkpoint.

---

## Guardrails (still in force)

- Do not replace Firebase until explicit cutover approval.
- Do not change FCM, orders, listings, or payments as part of auth work.
- Protected APIs keep the existing JWT middleware.
- Nothing from this work has been committed or pushed.
