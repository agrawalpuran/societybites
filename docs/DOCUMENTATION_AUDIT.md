# Documentation audit

Audit date: 15 November 2026. Method: read source, Prisma schema, route registrations, env example, Vercel and GitHub Actions config, and Git status. The test suite was not run. Production dashboards were not opened. Secret values were not copied.

## Repository areas inspected

- Git status, branch, stash list, remote, HEAD, and first commit.
- `lib/` Flutter entry, shell, auth config, API base URL, storefront host, admin shell, city-scope files in the working tree.
- `societybites-backend/index.js`, `package.json`, route files, auth and admin middleware, order transitions, payments, WhatsApp, platform fee, storefront, serving cities, buyer addresses.
- `societybites-backend/prisma/schema.prisma` and the migration directory list.
- `.env.example` names only. `.env` is gitignored and was not transcribed.
- `vercel.json`, `scripts/vercel_build.sh`, `.github/workflows/regression.yml`.
- Existing `docs/` pages, at least the overview, architecture, tech stack, business rules, order flow, payment flow, roadmap, AI context, 2Factor checkpoint, and regression page.
- `pubspec.yaml` dependencies.
- Tracked sensitive filenames via `git ls-files`. The APNs key file was not opened.

Not inspected line by line: every Flutter screen, every test, every migration SQL file, Android and iOS project settings beyond the Firebase plist and json being tracked, and the body of `api_service.dart` past the base URL and the fact that it is the HTTP client.

## Documentation created

| File | Role |
|---|---|
| `AGENTS.md` | Instructions for future coding agents |
| `docs/PROJECT_CONTEXT.md` | Business and product |
| `docs/ARCHITECTURE.md` | Technical architecture |
| `docs/PROJECT_STATUS.md` | Feature tracker |
| `docs/DATABASE_REFERENCE.md` | Schema |
| `docs/API_REFERENCE.md` | HTTP routes |
| `docs/DECISION_LOG.md` | Decisions versus discussions |
| `docs/KNOWN_ISSUES.md` | Verified issues |
| `docs/ENVIRONMENT_SETUP.md` | New-machine setup |
| `docs/LATEST_HANDOVER.md` | Session transfer |
| `docs/ROADMAP.md` | Done, in progress, and recommendations |
| `docs/NEW_AI_SESSION_PROMPT.md` | Prompt for a new assistant |
| `docs/DOCUMENTATION_AUDIT.md` | This file |
| `.cursor/rules/*.mdc` | Cursor rules |

Existing numbered docs were kept. `docs/09_AI_CONTEXT.md` and `README.md` gained a pointer to `AGENTS.md`. Application source was not changed by the documentation pass. On 15 November 2026 the uncommitted admin city filter and per-city platform fee were reviewed against the working tree and written into [LATEST_HANDOVER.md](LATEST_HANDOVER.md), [PROJECT_STATUS.md](PROJECT_STATUS.md), [API_REFERENCE.md](API_REFERENCE.md), [ARCHITECTURE.md](ARCHITECTURE.md), [DATABASE_REFERENCE.md](DATABASE_REFERENCE.md), and [DECISION_LOG.md](DECISION_LOG.md). `node tests/admin-city-dashboard.test.js` and `node tests/platform-fee-city.test.js` printed OK. The admin UI was not clicked through.

## Features checked against code

Login and JWT, society and places routes, listings and guest kitchens, orders and status transitions, payment routes, WhatsApp isolation, Cashfree switch, coupons, FSSAI default-off, storefront slug, admin write protection, buyer addresses, kitchen moves, serving cities, and the uncommitted city dashboard route.

## Historical information reconstructed

- Initial commit `6805c51` on 16 June 2026, message `Initial commit`. About 203 commits to `2d6871c`.
- Migration folders start 22 August 2026. Earlier schema history was not rebuilt from SQL.
- 2Factor was added beside Firebase and later became the client default. The checkpoint doc still describes the earlier state.
- Pickup-only, single-society rules were the early product and are still written in `docs/04_BUSINESS_RULES.md` and the local skill. The schema now has delivery, reach, saved places, and kitchen moves.
- Render is named in env comments. DigitalOcean is named in the Flutter default URL. The sequence of hosts was not reconstructed beyond those two artifacts.
- Meta verification trouble and Twilio evaluation are owner history. The repo still contains WhatsApp Cloud API code and no Twilio client.

## Missing information

- Live `AppSetting` values in production.
- Which host currently receives API traffic.
- Store release status and which auth provider the installed binaries were built with.
- Meta template approval state.
- Whether `CI_DATABASE_URL` is configured on GitHub.
- A human-readable commit history. Messages are mostly `Enhancement <date>`.
- Contents of commits before August 2026, not read one by one.

## Inconsistencies

| Source A | Source B | Resolution used here |
|---|---|---|
| Older docs and the local skill: pickup only, one society, no delivery | `User.fulfilmentMode`, `BuyerAddress`, selling reach | Code wins |
| `docs/02_ARCHITECTURE.md` folder `/backend` | Folder `societybites-backend` | Code wins |
| 2Factor checkpoint: Firebase default, uncommitted | `auth_config.dart` default `2factor` | Code wins |
| `.env.example` Render | `ApiService` DigitalOcean URL | Both recorded. Live host unverified |
| Skill: reviews only after completed orders, one per order | `Review` unique on order plus reviewer, and review route | Still consistent. Not re-tested |
| Display name SocietyEats | Repo name societybites | Both are intentional. UI string is SocietyEats |

## Manual verification still required

- Run `flutter test`, `npm run test:unit`, and a staging `npm run test:regression`.
- Click through admin city scope in the browser after the local API is up.
- Confirm production env flags for test OTP, WhatsApp, and Cashfree without pasting the values into Git.
- Rotate the tracked APNs key.
- Ask the owner before treating any recommendation in [ROADMAP.md](ROADMAP.md) as a commitment.
