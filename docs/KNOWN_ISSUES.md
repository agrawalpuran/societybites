# Known issues

Verified from source on 15 November 2026 unless a row says historical. Do not paste secret file contents into chat, commits, or docs.

## Security

| Issue | Evidence | What to do |
|---|---|---|
| An Apple APNs private key is tracked in Git | `git ls-files` includes `Apple key/Firebase/AuthKey_9AUWT34P9F.p8` | Rotate the key in Apple Developer, revoke the committed key, remove the file from the tree, and purge it from history only with an explicit owner request. Do not open the file into a chat transcript |
| Firebase client config is tracked | `lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist` | Normal for a Flutter client. Do not add server credentials next to these files. Restrict the Firebase and Google keys in their consoles |
| CORS allows every origin | `app.use(cors())` in `societybites-backend/index.js` | Acceptable only while the API is meant to be called from arbitrary browsers. Tighten it if the owner wants a known web origin list |
| Rate limits and OTP challenges are in memory | `middleware/rateLimit.js`, `lib/otpStore.js` | A second API instance, or a restart, resets both. OTP verify then fails closed until the user requests a new code. This is a scaling limit, not a silent auth bypass |
| Test OTP can impersonate fixed phone numbers | `TEST_OTP_ENABLED`, `TEST_PHONE_NUMBERS`, `TEST_OTP` in `.env.example` | Leave `TEST_OTP_ENABLED` false for real users. The numbers and code must stay on the server |
| Cashfree, WhatsApp, Firebase Admin, database, and Places secrets live in the server environment | `.env.example` names only | `.env` is gitignored. Do not commit it. Do not print it while debugging |
| Admin GET is broad for every portal user | `requireAdmin` plus super-admin on non-GET | Console admins can read orders, users, and payout views. That is the current design. Do not add write routes that forget the super-admin check |
| JWT secret has a hardcoded fallback | `lib/jwt.js` uses a fixed development secret when `JWT_SECRET` is unset | Production must set `JWT_SECRET`. Do not copy the fallback into docs or chat beyond locating it in that file |
| Profile writes reissue a 7-day JWT | `signToken` in profile photo, seller terms, and `PATCH /auth/me/profile` | 2Factor verify and refresh use the 15-minute token. Those three responses replace it with `JWT_EXPIRY`. Confirm with the owner before changing it |

No production password or token was copied into this knowledge base.

## Product gaps

| Issue | Evidence | Label |
|---|---|---|
| Seller `/s/{id}` share links needed web-only routing fixes | Flutter web used to treat a saved seller id like a branded `/kitchen/{slug}` and called `GET /public/kitchens/:slug` | Fixed in web startup and `DeepLinkNavigation`: `/s/...` opens guest storefront via `GET /listings/guest-kitchens/:id`. Redeploy Vercel to ship |
| Wildcard kitchen host is not configured | `vercel.json` redirects only `puran.societyeats.com`. Admin users screen text says wildcard `*.societyeats.com` is not live | Verified in repo. DNS itself was not queried |
| `preparing` and `picked_up` still exist for old rows | `RETIRED_STATUSES` in `routes/orders.js` | By design. Do not assign them to new orders |
| Seller staff cannot be revoked through the API | Comment on `SellerStaffMembership` and the absence of a revoke route | Verified |
| Firestore package is unused | `cloud_firestore` in `pubspec.yaml`, no `lib/` usage | Dependency debt |
| `docs/04_BUSINESS_RULES.md` still says pickup only and one society forever | File text versus `User.fulfilmentMode` and `BuyerAddress` | Documentation drift. The code is the rule |
| 2Factor checkpoint doc contradicts the client default | `docs/2FACTOR_AUTH_CHECKPOINT.md` versus `auth_config.dart` | Documentation drift |

## Integration limits

| Issue | Evidence | Label |
|---|---|---|
| WhatsApp send depends on Meta templates, an admin toggle, and env credentials | `lib/whatsappCloud.js` | Code is isolated. Live delivery was not verified. Historical notes say Meta verification and tax eligibility blocked progress. That history was not re-checked with Meta |
| Cashfree does nothing until the admin setting, seller vendor profile, and webhook are in place | `lib/payments/` | By design. Do not turn it on without approval |
| Google Places is a paid API and is server-side | `.env.example` | Discovery degrades if the key is missing. Database society search still exists |
| Serving cities are a fixed list in code | `lib/launchCity.js` | An admin can activate cities from that list. A brand-new city needs a code change |
| Image uploads need Supabase Storage env | `index.js` log line | The API still boots without it |

## Deployment

| Issue | Evidence | Label |
|---|---|---|
| API host comments disagree | Flutter default is a DigitalOcean app URL. `.env.example` tells operators to set variables on Render | Needs verification. Do not remove either until production is identified |
| API regression in CI is skipped when `CI_DATABASE_URL` is empty | `.github/workflows/regression.yml` | The workflow prints a skip message. Unit tests still run |
| Boot runs migrations | `npm start` calls `scripts/ensure-db-migrations.js` | A bad migration blocks production start. `npm run dev` does not run that script |

## Performance and structure

| Issue | Evidence | Label |
|---|---|---|
| In-memory maps do not coordinate across instances | Rate limit, OTP store, platform-fee cache, serving-city cache | Fine for one Node process. Wrong if the API is scaled out without a change |
| `Block` is not referenced by `Flat` | Prisma schema. `Flat.block` is a string | Duplicate concepts. Do not "fix" this without an owner request and a data migration |
| `ListingLike.listingId` is not a foreign key | Schema comment | Intentional so a size can be removed without deleting the dish like |
| Commit messages are mostly "Enhancement <date>" | `git log` | History is hard to read. The code and this knowledge base have to carry the decisions |

## Not listed as bugs

Features that are merely unfinished are in [PROJECT_STATUS.md](PROJECT_STATUS.md), not here. An unused future idea is not a defect.
