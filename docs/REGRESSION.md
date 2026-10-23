# Phase-1 regression suite

Automated checks that must stay green. No device farm, no production `TEST_OTP`.

## What CI runs

GitHub Action `.github/workflows/regression.yml` on every pull request:

1. `flutter test` — all widget/unit tests, including `test/regression/`
2. `npm run test:unit` — backend tests that do not need a database
3. `npm run test:regression` — order journeys + FCM payload **when** `CI_DATABASE_URL` is set

Add repository secrets:

- `CI_DATABASE_URL` — **staging** Postgres (never production)
- `CI_JWT_SECRET` — optional; must match the JWT the test process uses (defaults work if unset)

## Run locally

From the Flutter repo root:

```bash
flutter test
flutter test test/regression test/order_lifecycle_test.dart test/kitchen_order_organization_test.dart test/order_push_coordinator_test.dart test/ios_push_config_test.dart
```

From `societybites-backend` (needs `.env` `DATABASE_URL` for journeys):

```bash
npm run test:unit
npm run test:regression
```

## Pack map

| Journey | Test |
|---|---|
| Completed kitchen chip is COMPLETED, not ACTIVE | `test/regression/order_fixtures_test.dart`, `test/kitchen_order_organization_test.dart` |
| Seeded push order survives empty Kitchen refresh | `test/kitchen_order_organization_test.dart` |
| Push hint / payload `orderId` + `notificationType` | `test/order_push_coordinator_test.dart`, `societybites-backend/tests/notifications-payload.test.js` |
| Place order → seller active bucket, auto-accept | `societybites-backend/tests/regression-order-journeys.test.js` |
| Ready → cash paid → completed; buyer and seller GET match | same file |
| Second complete does not rewrite status | same file |
| Reject restores stock; buyer sees reason | same file |
| MY_SOCIETY seller rejects another society's buyer | same file |
| Confirm delivery cash auto-completes | `societybites-backend/tests/delayed-delivery-charge.test.js` (full `npm test`) |
| iOS foreground banner requested | `test/ios_push_config_test.dart` |

Shared API shapes live in `test/fixtures/orders/*.json`. If you add a field both clients read, add it there and extend `order_fixtures_test.dart`.

Backend HTTP helper: `societybites-backend/tests/helpers/httpHarness.js`.

## Bug policy

Escaped production bug → add a failing test in this pack (or a fixture) → then fix.

Do not enable `TEST_OTP_ENABLED` on the production API.
