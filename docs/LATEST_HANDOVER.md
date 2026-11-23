# Latest handover

## 23 November 2026 — A missing login token does not show the server sentence

Profile still shows the saved name and society when the web login token is gone. The address list no longer calls the server in that case, and it no longer prints "Missing or invalid Authorization header". It keeps the place already on screen and offers "Sign in to manage addresses". Other screens that use `userFacingError` say "Please sign in again to continue." Not committed.

## 23 November 2026 — Web like needs a stored login token

Liking a dish calls `POST /listings/:id/like` with the bearer token. The button used to treat a saved user id as signed in, then send the request with no Authorization header. The server answered "Missing or invalid Authorization header". On web, the access token and refresh token are now also kept in browser preferences, because secure storage was empty after a reload while the user id remained. If neither token is available, the heart asks the buyer to sign in instead of showing that server error. Not committed.

## 23 November 2026 — Web Nearby kitchens follows the Up to chip

The dish count and category chips already used the selected distance. Web Nearby kitchens was still built from the feed before that filter, so "0 dishes within 1 km" could sit above cards at 3 km and 6 km. That section now uses the same distance list as the count, which the phone home already did. The section subtitle uses the selected distance. Own-society dishes stay visible at any chip. Not committed.

## 23 November 2026 — UPI type removed from the app

Seller Settings, first-time setup, the UPI edit sheet, and the admin order screen no longer ask or show Personal vs Merchant UPI. Checkout still uses the UPI ID and display name. QR, copying the ID, and opening a UPI app are unchanged. `User.upiAccountType` stays in the database with default `PERSONAL`. The server still stores the value when an older app sends it, so the build already in review does not fail on save. The current app does not send the field. No migration. Not committed.

## 20 November 2026 — Discovery home

State 1 is one screen with two layouts. Both stay Discovery, and nearby dishes do not change the marketplace state. With no eligible nearby dishes, the screen shows the hero, six inspiration categories, and the community section. When eligible nearby dishes are already in the loaded feed, web and mobile keep the existing home so those dishes can be ordered there. Discovery is only the screen for a society with nothing nearby. Its hero says no kitchens are selling in the society or within the city's configured reach. The chef button says First until a dish from that society is in the loaded feed. A failed or ineligible nearby load hides the section. There is no share flow, so Invite neighbours is not shown. Become a seller uses the existing start-selling callback. The cook card stays for a new signup and for a seller who has not listed a product. It is hidden only when that signed-in seller already has a listing. A previous seller flag on the device does not hide it. After login, every home state ends with the community chef hunt card. All Items shows 5 dishes at random, and See all opens the rest. Home asks whether a seller already has a listing only after the society feed has painted, and reuses that answer until the kitchen changes. First-screen photos are the ones warmed. The phone home builds each discovery section as its own sliver, so sections below the fold wait. Its button opens the resident's WhatsApp with a prefilled note, https://www.societyeats.com, and the Android Play Store link. Guests do not see that card. The search row did nothing, so it is not shown. Categories do not filter the catalogue. A society that already has listings keeps the existing home. The Growing placeholder is no longer shown. State 3 is still the existing home screen. Zooming across the wide-web width used to drop the Discovery cover and show the existing web home; the cover now stays with the shell. Not committed.

## 20 November 2026 — Adaptive home framework

`MainShellScreen` now opens `AdaptiveHome`, which keeps `HomeScreen` and covers it only for Discovery or Growing. Active, at least 5 sellers and 20 available listings, returns `HomeScreen` by itself. Thresholds live in `MarketplaceHomeThresholds.standard`. Counts use the listings Home already loaded: active, not pre-order, not FSSAI-blocked, inside the default distance. Search and the distance chip do not change the state. A failed load stays on `HomeScreen`. `flutter test test/marketplace_home_state_test.dart` passed, 8 tests. Existing home feed tests passed in the same session. No backend, API, database, or config file was changed. This is not committed.

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
