# Roadmap

Completed items are in the repository. Later items are either a stated product idea or a recommendation. This page does not invent dates or pretend the owner ranked the recommendations.

## Completed capabilities

These are in the source and wired through the API. Detail and limits are in [PROJECT_STATUS.md](PROJECT_STATUS.md).

- Phone OTP login, backend JWT, and account deletion.
- Societies, Google Places discovery, buyer saved places, and seller kitchen moves.
- Listings with drafts, pause, expiry, variants, discounts, recurring availability, and made-to-order.
- Pre-order campaigns.
- Cart, checkout, idempotent order create, coupons, and the current order state machine.
- Direct UPI, cash, and outside delivery-fee cash confirmation.
- Seller radius, pickup, and seller delivery.
- Reviews, order messages, and issue reports.
- FCM device registration and order pushes.
- Admin console for societies, users, listings, orders, reviews, FSSAI, address proof, coupons, performance, and settings.
- Public kitchen page by slug.
- Configurable platform fee, default zero.
- Optional WhatsApp Cloud API and optional Cashfree, both behind switches.

## Immediate priorities

**Shipped in the knowledge-base commit, browser pass still open:** admin city chips and a per-city platform fee. Behavior is in [LATEST_HANDOVER.md](LATEST_HANDOVER.md). Unit tests `admin-city-dashboard.test.js` and `platform-fee-city.test.js` passed on 15 November 2026. The admin screens still need a browser pass.

**Recommendation, not an owner-confirmed rank:**

- Verify the production API host and write the answer into this file and [ARCHITECTURE.md](ARCHITECTURE.md).
- Rotate the tracked APNs private key.
- Keep WhatsApp and Cashfree off until the owner explicitly enables them.
- Partner delivery through Prorouting is in source behind a kill switch ([PARTNER_DELIVERY_POC.md](PARTNER_DELIVERY_POC.md)). Default off. Empty allowlist books nobody. Migration not applied. uEngage is not in that POC.

## Medium-term features

**Partly built, finish only if the owner still wants it:**

- Kitchen subdomains `{slug}.societyeats.com` for every seller. The app and `GET /public/kitchens/:slug` exist. Wildcard hosting does not.
- Seller staff beyond a view-only owner, including revoke.
- FSSAI enforcement, which is implemented and default off.

**Recommendation:**

- Bring `docs/01` through `docs/10` in line with the code, or leave them as archives and keep using the newer docs.
- Update the local Cursor skill `societybites-development-guide` so it stops describing pickup-only and one society. That skill is outside the repo.

## Long-term product vision

The owner's stated direction is a scalable hyperlocal marketplace that stays simple, modular, and inexpensive. SocietyEats should keep connecting residents and small kitchens, with admin control of optional fees and optional vendors.

These were discussed and are not commitments:

- A WhatsApp vendor other than Meta, if Meta stays blocked.
- Gateway collection through Cashfree when the owner wants the platform in the payment flow.
- Broader city coverage. The code list is Bengaluru, Pune, Hyderabad, Mumbai, Delhi, and Chennai.

Not a vision item: replacing Flutter, Express, Prisma, or Supabase.

## Technical dependencies

| Future slice | Depends on |
|---|---|
| Another serving city | A new entry in `lib/launchCity.js`, then the admin serving-city setting |
| Cashfree in production | Owner approval, Cashfree account, Easy Split, seller payout profiles, webhook URL, `CASHFREE_ENV` |
| Prorouting POC | Apply the additive migration on a chosen database. Env keys. Public callback URL. Phone allowlist. Do not run `npm start` against production until migrate is accepted |
| WhatsApp in production | Owner approval, credentials, approved templates, admin toggle |
| More than one API instance | A shared store for OTP challenges and rate limits. In-memory maps will not do |
| Kitchen subdomains | DNS and Vercel host config, not only the Flutter slug |

## Business dependencies

| Topic | Dependency |
|---|---|
| Turning on a platform fee | Owner sets `platform_fee`. No code deploy is required |
| Holding customer funds | Owner approval. Default remains direct UPI |
| FSSAI as a selling gate | Owner turns `fssai_selling_requirement` on after the review process is trusted |
| Meta verification and tax eligibility | Historical obstacles. Not stored as a current vendor status in Git |
