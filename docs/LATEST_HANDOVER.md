# Latest handover

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
