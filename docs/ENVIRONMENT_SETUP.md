# Environment setup

A new machine can build SocietyEats from this repository. No real passwords, tokens, or connection strings belong in this file. Copy values from the owner's password store into local env files and into the host dashboards.

## Software

| Tool | Version evidence |
|---|---|
| Git | Repository is a Git repo |
| Flutter | SDK constraint `^3.11.4` in `pubspec.yaml`. Vercel build script clones Flutter `3.44.0` |
| Dart | Comes with Flutter |
| Node.js | GitHub Actions uses Node 20 |
| npm | `societybites-backend/package-lock.json` is present |
| PostgreSQL | Supabase hosted Postgres. Local Postgres also works if both URLs are set |

Android builds need Android Studio and an SDK. iOS builds need Xcode on macOS. This setup was written from Windows evidence. iOS signing was not performed here.

## Clone

```bash
git clone https://github.com/agrawalpuran/societybites.git
cd societybites
```

Stay on `main` unless the owner names another branch. Run `git status` before editing. Uncommitted work may already be present. Do not discard it.

## Backend

```bash
cd societybites-backend
npm ci
```

`postinstall` runs `prisma generate`.

Create `societybites-backend/.env`. It is gitignored. Start from `.env.example` and fill values locally. Never commit the filled file.

### Database

`DATABASE_URL` is the runtime URL. The example comments say to use the Supabase transaction pooler on port 6543 with `pgbouncer=true` and a small `connection_limit`.

`DIRECT_URL` is for Prisma migrate, `db push`, and Studio. The example prefers the direct Supabase host on port 5432. If that host is unreachable over IPv6, the comments say to use the session pooler on 5432 with `connection_limit=1`.

Apply migrations:

```bash
npx prisma migrate deploy
```

`npm start` also tries to migrate unless `SKIP_DB_MIGRATE=true`. Use `npm run dev` for local watch mode, which does not run that boot migration.

Seed is optional and writes demo data:

```bash
npm run db:seed
```

Do not point seed or cleanup scripts at production.

### Run the API

```bash
npm run dev
```

Default port is `PORT=3000`. Check `GET http://localhost:3000/health` and `GET http://localhost:3000/ready`.

### Backend tests

From `societybites-backend`:

```bash
npm run test:unit
npm run test:regression
```

Unit tests do not need a database. Regression journeys do. Use a staging database, never production. CI uses the secret names `CI_DATABASE_URL`, `CI_DIRECT_URL`, and `CI_JWT_SECRET`.

## Frontend

From the repository root:

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

`API_BASE_URL` defaults in source to the DigitalOcean app URL. A local API must be passed with `--dart-define`.

Auth defaults to 2Factor. A Firebase login build is:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=AUTH_PROVIDER=firebase
```

Flutter tests:

```bash
flutter test
```

### Android

```bash
flutter build apk
```

`android/app/google-services.json` is already in the repo. Signing keys for Play are not in this guide. Do not create a new keystore inside the repo.

### iOS

On macOS, open `ios/Runner.xcworkspace` or run `flutter build ios`. `ios/Runner/GoogleService-Info.plist` is in the repo. The APNs private key file that is currently tracked must not be copied to more machines than necessary. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

### Web

```bash
flutter build web --release --dart-define=API_BASE_URL=https://your-api-host
```

Vercel runs `scripts/vercel_build.sh`, which passes `API_BASE_URL` and `AUTH_PROVIDER` from the Vercel environment when those variables are set.

## Firebase

Client config is already generated for Flutter (`lib/firebase_options.dart`).

Server Admin SDK uses these env names:

| Name | Required for |
|---|---|
| `FIREBASE_PROJECT_ID` | Firebase login verification and FCM |
| `FIREBASE_CLIENT_EMAIL` | Same |
| `FIREBASE_PRIVATE_KEY` | Same. Newlines are part of the PEM. Keep it only in the env |

Firebase login builds need a real Firebase phone-auth project. 2Factor builds still initialize the Firebase SDK in `main.dart` because messaging uses it.

## Environment variables

Names and purpose only. Required means the feature fails without them. The process can boot with a subset.

| Name | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | Yes, for any real API call | Runtime Postgres |
| `DIRECT_URL` | Yes, for migrate | Prisma direct connection |
| `JWT_SECRET` | Yes | Signs access tokens |
| `JWT_EXPIRY` | No | Firebase-login JWT lifetime. Example `7d` |
| `ACCESS_TOKEN_EXPIRY` | No | 2Factor access JWT. Example `15m` |
| `REFRESH_TOKEN_TTL_MS` | No | Refresh lifetime. Example 30 days in milliseconds |
| `TWOFACTOR_API_KEY` | Yes for default login | 2Factor SMS |
| `TWOFACTOR_OTP_TEMPLATE` | No | Template name when set |
| `TWOFACTOR_TLS_INSECURE` | No | Local corporate proxy only. Never in production |
| `OTP_TTL_MS`, `OTP_RESEND_COOLDOWN_MS`, `OTP_MAX_SENDS_PER_HOUR`, `OTP_MAX_VERIFY_ATTEMPTS`, `OTP_IP_MAX` | No | OTP limits |
| `TEST_OTP_ENABLED` | No | Must be `true` to enable the bypass. Default off |
| `TEST_PHONE_NUMBERS`, `TEST_OTP` | No | Used only when the bypass is on. Keep them off the client |
| `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` | Yes for Firebase login and FCM | Admin SDK |
| `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID` | Yes only if WhatsApp is turned on | Cloud API |
| `WHATSAPP_ENABLED` | No | `false` is an emergency off switch |
| `WHATSAPP_API_VERSION` | No | Example `v21.0` |
| `WHATSAPP_TIMEOUT_MS` | No | |
| `WHATSAPP_BUSINESS_ACCOUNT_ID` | No | Used by the status script |
| `WHATSAPP_TEMPLATE_NAME`, `WHATSAPP_TEMPLATE_READY`, `WHATSAPP_TEMPLATE_COMPLETED`, `WHATSAPP_TEMPLATE_LANGUAGE` | No | Template names. Buyer ready and completed sends are skipped when unset |
| `CASHFREE_CLIENT_ID`, `CASHFREE_CLIENT_SECRET` | Yes only if provider is Cashfree | Gateway |
| `CASHFREE_ENV` | No | `sandbox` until set to `production` |
| `GOOGLE_PLACES_API_KEY` | Yes for live place search | Server only |
| `GOOGLE_PLACES_REGION_CODE` | No | Defaults from launch country |
| `SOCIETY_LAUNCH_CITY`, `SOCIETY_LAUNCH_STATE`, `SOCIETY_LAUNCH_COUNTRY` | No | Example Bengaluru, Karnataka, IN. Overridden when `serving_cities` is stored |
| `SOCIETY_LAUNCH_LAT`, `SOCIETY_LAUNCH_LNG`, `SOCIETY_LAUNCH_RADIUS_M` | No | Places bias |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | Yes for image upload | Storage. Service role is a secret |
| `SUPABASE_STORAGE_BUCKET` | No | Default `listing-images` |
| `PORT` | No | Default 3000 |
| `LOG_LEVEL` | No | Example `info` |
| `NODE_ENV` | No | |
| `SKIP_DB_MIGRATE` | No | `true` skips migrate on `npm start` |

Force-update numbers are admin settings in the database, not env vars. See [DATABASE_REFERENCE.md](DATABASE_REFERENCE.md).

## Deployment

Verified from files, not from the vendor dashboards.

1. **API.** Run `npm start` on the Node host so migrations and the server both run. Set every required env var on that host. The Flutter source default points at a DigitalOcean app. Env comments also mention Render. Confirm which host is live before changing DNS.
2. **Web.** Vercel uses `vercel.json` and `scripts/vercel_build.sh`. Set `API_BASE_URL` on the Vercel project. Set `AUTH_PROVIDER` only when the web build should not use 2Factor.
3. **Database.** Supabase Postgres. Take a backup before `prisma migrate deploy` against production.
4. **WhatsApp and Cashfree.** Leave them unset or off until the owner enables them. The app works on direct UPI without either.
5. **CI.** GitHub Actions workflow `.github/workflows/regression.yml`. Add `CI_DATABASE_URL` only if API journey tests should run, and point it at staging.

Do not commit `.env`, service-role keys, or new private keys.
