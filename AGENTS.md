# SocietyEats agent instructions

SocietyEats is a hyperlocal food marketplace for India. The GitHub repository and many folders still use the older name SocietyBites. The in-app display name is SocietyEats (`kAppDisplayName` in `lib/widgets/app_header.dart`). The live site host used in code is `societyeats.com`.

This file is the permanent instruction manual for every AI coding assistant. Read it before changing the product.

## Read this first

1. [docs/LATEST_HANDOVER.md](docs/LATEST_HANDOVER.md) for the current branch, uncommitted work, and the next step.
2. [docs/PROJECT_CONTEXT.md](docs/PROJECT_CONTEXT.md) for the business.
3. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the system is built.
4. [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) before assuming a feature is missing or finished.
5. The source that the task touches. Documentation can lag. The code wins.

Older pages `docs/01_PROJECT_OVERVIEW.md` through `docs/17_COD_PAYMENT_CONFIRMATION.md` are kept as history. They still describe an earlier pickup-only, single-society MVP. Do not treat them as the current product when they conflict with the code or with the documents linked above.

A local Cursor skill named `societybites-development-guide` may also describe that older MVP. When it conflicts with this repository, follow this repository.

## Working rules

- Inspect the existing implementation before writing code. Search for the route, service, screen, and Prisma model that already own the behavior.
- Extend the existing module. Do not add a second service, API, or widget for the same job.
- Make the smallest change that solves the requested problem. Do not refactor unrelated code.
- Keep API contracts stable unless the owner explicitly approves a breaking change.
- Keep order status values stable. `preparing` and `picked_up` are retired and must not be assigned to new orders. See `VALID_STATUSES`, `RETIRED_STATUSES`, and `TRANSITIONS` in `societybites-backend/routes/orders.js`.
- Derive `userId`, seller, buyer, and society on the server from the verified JWT. Do not trust those ids from the client.
- Validate on the server. The Flutter app is not a security boundary.
- WhatsApp and Firebase Cloud Messaging are independent. A notification failure must not fail order creation or a status change. WhatsApp stays in `societybites-backend/lib/whatsappCloud.js` and must keep swallowing its own errors.
- Do not add a payment gateway, a new paid vendor, or a new infrastructure service unless the owner approves it. Direct UPI is the default payment provider when `AppSetting.payment_provider` is missing. Cashfree code already exists and is admin-switchable.
- Do not hardcode secrets, tokens, database URLs, or OTP values. Do not copy secrets into docs, commits, logs, or chat.
- Do not claim tests passed unless you actually ran them and saw the result.
- Preserve uncommitted work and Git stashes. Do not reset, force-push, or discard user changes. Do not commit or push unless the owner asks.

## Where code lives

| Area | Path |
|---|---|
| Flutter app | `lib/` |
| Backend API | `societybites-backend/` |
| HTTP routes | `societybites-backend/routes/` |
| Business logic | `societybites-backend/lib/` |
| Prisma schema | `societybites-backend/prisma/schema.prisma` |
| Backend tests | `societybites-backend/tests/` |
| Flutter tests | `test/` |

Flutter UI should stay thin. Backend route handlers should stay thin and call `societybites-backend/lib/`. Database access goes through Prisma.

## After a significant change

Update the knowledge base in the same change, so the next session does not rediscover it:

1. [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md)
2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) when the architecture changes
3. [docs/DATABASE_REFERENCE.md](docs/DATABASE_REFERENCE.md) when the schema changes
4. [docs/API_REFERENCE.md](docs/API_REFERENCE.md) when an API contract changes
5. [docs/DECISION_LOG.md](docs/DECISION_LOG.md) when a decision is made
6. [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) when an issue is found or fixed
7. [docs/LATEST_HANDOVER.md](docs/LATEST_HANDOVER.md)
8. [docs/ROADMAP.md](docs/ROADMAP.md) when priorities change

Document what the code does. Do not document a plan as if it already shipped.

## Verification

- Backend unit tests: `npm run test:unit` from `societybites-backend`.
- Backend API journeys need a database: `npm run test:regression`.
- Flutter: `flutter test` from the repository root.
- UI changes need the affected flow exercised, not only a screenshot. Say what you could not run.

## Security

Never write real passwords, API tokens, database URLs with credentials, Firebase private keys, JWT secrets, WhatsApp tokens, or Cashfree secrets into documentation or source. Environment variable names belong in [docs/ENVIRONMENT_SETUP.md](docs/ENVIRONMENT_SETUP.md). A tracked APNs private key is a known issue; see [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md). Do not open or copy that file into chat.
