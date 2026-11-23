# SocietyEats project status

Status comes from reading the source on 15 November 2026. The full test suite was not executed. `admin-city-dashboard.test.js` and `platform-fee-city.test.js` were run and passed. "Tests exist" means a test file is in the repo.

Statuses:

- **COMPLETE** — backend behavior, data model, and a user-facing path are wired together in source.
- **PARTIALLY COMPLETE** — a real slice works, and a named part does not.
- **NOT IMPLEMENTED** — no product path in this repo.
- **UNDER INVESTIGATION** — code exists, but a production fact was not checked.
- **NEEDS VERIFICATION** — a claim depends on a host, a database row, or a vendor account.

## Identity and access

| Feature | Status | Source | API | Data | Limits | Remaining |
|---|---|---|---|---|---|---|
| 2Factor phone OTP, access JWT, rotating refresh token | COMPLETE | `lib/services/auth_config.dart`, `routes/auth.js`, `lib/twoFactor.js`, `lib/otpStore.js`, `lib/refreshTokens.js` | `POST /auth/send-otp`, `/verify-otp`, `/refresh`, `/logout` | `User`, `RefreshToken` | OTP challenges are in memory. Default client build uses this path | Confirm the shipped store build was compiled without `AUTH_PROVIDER=firebase` |
| Firebase phone login | COMPLETE as fallback | `routes/auth.js`, `lib/firebase.js`, `lib/firebase_options.dart` | `POST /auth/firebase-login` | `User` | Longer JWT, no refresh token. Build must pass `AUTH_PROVIDER=firebase` | `docs/2FACTOR_AUTH_CHECKPOINT.md` is stale |
| Profile, photo, account delete | COMPLETE | `routes/auth.js`, `lib/accountDeletion.js`, `lib/profileImage.js` | `GET/PATCH /auth/me`, `POST /auth/me/profile-photo`, `DELETE /auth/me` | `User` | Tests exist for deletion | — |
| Society join and Google Places discovery | COMPLETE | `routes/societies.js`, `lib/placesGoogle.js`, `lib/societyFromPlace.js` | `GET /societies`, `GET /societies/places/search`, `POST /societies/places/preview`, `POST /societies/join` | `Society`, `Block`, `Flat` | Places calls need `GOOGLE_PLACES_API_KEY` | — |
| Buyer saved places | COMPLETE | `lib/buyerAddresses.js`, `routes/buyerAddresses.js` | `/auth/me/addresses` | `BuyerAddress` | Sellers are rejected. Selecting a place rewrites `User.societyId` | — |
| Seller terms and seller role | COMPLETE | `lib/sellerTerms.js` | `POST /auth/me/seller-terms` | `SellerTermsAcceptance`, `User.role` | One role field, not two simultaneous roles | — |
| View-only seller owner | PARTIALLY COMPLETE | `lib/sellerStaff.js`, `routes/sellerStaff.js` | `GET/POST /seller-staff/owners`, `GET /seller-staff/access` | `SellerStaffMembership` | Comments say no revoke API. MVP invites create `owner` only | Revoke and a real manager role, if the owner wants them |
| Console admin and super admin | COMPLETE | `middleware/requireAdmin.js`, `routes/admin.js` | `/admin/*` | `User.consoleAdmin`, `User.role` | Non-GET admin routes require super admin | — |
| Test OTP bypass | COMPLETE and dangerous if left on | `lib/testOtp.js`, `.env.example` | send and verify OTP | none | Off unless `TEST_OTP_ENABLED=true` | Keep off in production |

## Discovery and catalog

| Feature | Status | Source | API | Data | Limits | Remaining |
|---|---|---|---|---|---|---|
| Listings, publish, pause, resume, renew, soft delete | COMPLETE | `routes/listings.js`, `utils/listingExpiry.js` | `/listings` | `Listing` | Expiry is evaluated on read, not by a cron. Delete sets `inactive` | — |
| Adaptive home states | PARTIALLY COMPLETE | `lib/home/adaptive_home.dart`, `lib/home/discovery_home.dart`, `lib/home/marketplace_home_state.dart`, `lib/screens/home_screen.dart` | Existing `GET /listings` and nearby sellers. No new route | Own-society counts only. Nearby dishes do not raise the state | Discovery is 0 own-society listings and no eligible nearby dishes. The hero names that empty reach, using the city's configured kilometres when that setting exists. When nearby dishes can be ordered, web and mobile keep the existing home. Any society with its own listings also keeps the existing home | Design a Growing screen later. Until then, those societies use the existing home. Invite neighbours has no share flow, so that button is hidden. The cook card is hidden only when the signed-in seller already has a listing. That check waits until the society feed has painted and then reuses the kitchen snapshot. After login, a chef-hunt card at the bottom of every home state opens WhatsApp with a prefilled message. All Items shows 5 random dishes until See all. Phone discovery sections below the fold are separate slivers, and image warmup follows the first screen |
| Food type, categories, portions, ready-by copy | COMPLETE | `utils/foodType.js`, `utils/listingCategories.js`, listing screens | listing APIs | `Listing` | — | — |
| Ready-now, made-to-order, recurring windows | COMPLETE | `lib/listingAvailability.js`, `lib/recurringAvailability.js` | listing fields | `Listing` | Daily caps are optional | — |
| Size variants and shared stock | COMPLETE | `lib/listingVariants.js` | `GET /listings/:id/variants` | `Listing.variantGroupId` and related fields | Like is per dish key, not a foreign key to one size | — |
| Listing discounts | COMPLETE | `lib/listingDiscount.js` | listing write | `Listing.discount*` | Regular price stays on `price` | — |
| Catalog reorder | COMPLETE | `lib/listingCatalogOrder.js` | `PUT /listings/catalog-order` | `Listing.displayOrder` | — | — |
| Likes | COMPLETE | `lib/listingLikes.js` | `POST /listings/:id/like`, `GET /listings/:id/likes` | `ListingLike` | — | — |
| Guest kitchens | COMPLETE | `lib/guestDiscovery.js` | `GET /listings/guest-kitchens` | `Listing`, `User` | Public, no JWT | — |
| Nearby sellers and selling radius | COMPLETE | `lib/nearbyDiscovery.js`, `lib/sellingReach.js`, `lib/geoDistance.js` | `GET /listings/nearby-sellers` | `User.sellingReachLevel`, `CityReachConfig` | Nearby routes require a joined society. Web Nearby kitchens uses the Home “Up to” chip, same as the dish count | — |
| Serving cities | COMPLETE | `lib/servingCities.js`, `lib/launchCity.js` | `GET /settings`, `GET/PUT /admin/serving-cities` | `AppSetting.serving_cities` | Known cities in code: Bengaluru, Pune, Hyderabad, Mumbai, Delhi, Chennai | Adding a city is a code change in `launchCity.js`, not only a database row |
| Pre-order campaigns | COMPLETE | `lib/preorder.js`, `routes/preorderCampaigns.js` | `/preorder-campaigns` | `PreOrderCampaign`, campaign `Listing` rows | Products lock after orders exist | — |
| Public kitchen page | PARTIALLY COMPLETE | `lib/storefront.js`, `lib/services/storefront_host.dart`, `vercel.json` | `GET /public/kitchens/:slug` | `User.storefrontSlug` and branding fields | Path `/kitchen/{slug}` works in the app. Only `puran.societyeats.com` is redirected in `vercel.json`. Wildcard DNS is described as not live in an admin-screen comment | Finish DNS and hosting for `{slug}.societyeats.com` only if the owner still wants it |
| Image upload | COMPLETE when storage env is set | `routes/media.js`, `lib/objectStorage.js` | `POST /media/upload` | Supabase bucket, URL on the row | Server boots without the keys and then cannot store new images | — |

## Orders, pay, and aftercare

| Feature | Status | Source | API | Data | Limits | Remaining |
|---|---|---|---|---|---|---|
| Cart and checkout | COMPLETE | `lib/services/cart_controller.dart`, `lib/screens/checkout_screen.dart`, `routes/orders.js` | `POST /orders` | `Order`, `OrderItem`, `OrderIdempotency` | Optional `Idempotency-Key` of 8 to 128 characters | — |
| Order lifecycle | COMPLETE | `routes/orders.js`, `lib/orderAcceptance.js` | `PATCH /orders/:id/status`, `POST /orders/:id/reject` | `Order.status` | `preparing` and `picked_up` are retired. See [ARCHITECTURE.md](ARCHITECTURE.md) | — |
| Direct UPI | COMPLETE | `routes/payments.js`, `lib/services/upi_payment_service.dart` | `POST /payments/:orderId/mark-paid`, `/confirm`, `GET /payments/:orderId` | `User.upiId`, `Order.paymentStatus` | Seller screens no longer ask Personal vs Merchant. `User.upiAccountType` remains and older apps can still send it. In-app UPI intent is not sent. Buyer marks paid, seller confirms | — |
| Cash and in-society COD rules | COMPLETE | `lib/sellerPaymentPreference.js`, `routes/payments.js` | `POST /payments/:orderId/confirm-cash` | `Order.paymentMethod`, `paymentStatus` | Cash confirm sets `paid` and does not by itself complete the order | — |
| Outside delivery fee in cash | COMPLETE | `lib/delayedDeliveryCharge.js` | `POST /payments/:orderId/confirm-delivery-cash` | `Order.deliveryCharge`, `deliveryCollectBy`, `deliveryCashConfirmedAt` | Can auto-complete when checks pass | — |
| Cashfree | PARTIALLY COMPLETE | `lib/payments/*`, `routes/paymentWebhooks.js` | `POST /payments/:orderId/checkout`, `PUT /payments/payout-profile`, `POST /webhooks/cashfree` | `Order.paymentProvider`, `SellerPayoutProfile`, `AppSetting.payment_provider` | Code path exists. Default is direct UPI. Live setting was not read. Do not enable it without owner approval | Owner decision, then vendor onboarding and webhook URL |
| Platform fee | PARTIALLY COMPLETE | `lib/platformFee.js`, `routes/orders.js`, `routes/settings.js`, `routes/admin.js`, `lib/screens/admin/admin_dashboard_screen.dart` | `GET /settings` is the global fee. `GET /settings/platform-fee` is the signed-in buyer's society fee. `POST /orders` uses `resolvePlatformFee({ societyId })`. `PATCH /admin/settings?cityKey=` sets or clears a city override | `AppSetting.platform_fee` and JSON key `city_platform_fees` | No schema migration. Unit test `tests/platform-fee-city.test.js` passed on 15 Nov 2026. Checkout UI was not re-tested in the browser | Click through checkout after a city fee is set |
| Coupons | COMPLETE | `lib/coupons.js`, `routes/coupons.js`, `routes/admin.js` | `POST /coupons/validate`, `/admin/coupons` | `Coupon`, `CouponRedemption`, eligibility tables | Only `SOCIETYEATS` funding. Society and seller scope exist | — |
| Reviews | COMPLETE | `routes/reviews.js` | `POST /reviews`, `GET /reviews/listing/:listingId`, `GET /reviews/seller/me` | `Review` | One review per order and reviewer. Hidden flag for admin | — |
| Order messages | COMPLETE | `lib/orderMessages.js` | `GET/POST /orders/:id/messages` | `Message` | This is order chat, not a general inbox | — |
| Issue reports | COMPLETE | `lib/issueReports.js`, `routes/issues.js` | `/issues`, `/admin/issues` | `IssueReport`, `IssueMessage` | Separate from order status | — |
| Seller insights and reconciliation | COMPLETE | `lib/sellerInsights.js`, `lib/sellerPaymentReconciliation.js` | `/orders/seller/stats`, `/insights`, `/seller/reconciliation/*` | `Order` | Payment reminder has a cooldown column | — |
| Push notifications | COMPLETE in code | `utils/notifications.js`, `routes/devices.js`, `lib/services/push_notification_service.dart` | `POST /devices/register`, `DELETE /devices` | `DeviceToken` | Delivery depends on Firebase and device permission. Not re-tested here | — |
| WhatsApp seller and buyer templates | PARTIALLY COMPLETE | `lib/whatsappCloud.js`, `lib/whatsappSetting.js` | called from order create and status paths. Admin toggle on `PATCH /admin/settings` | `AppSetting.whatsapp_order_notifications` | Default off. Isolated from order success. Meta template approval and live delivery were not verified. Twilio is not in the repo | Owner decision on vendor and templates |
| Fulfilment and delivery radius | COMPLETE | `lib/sellerFulfilment.js`, `lib/sellingReach.js` | `PATCH /auth/me/profile` | `User.fulfilmentMode`, delivery charge fields, `sellingReachRadiusKm` | Older docs that say pickup-only are wrong | — |

Payment status values used in `routes/payments.js` include `pending`, `buyer_marked_paid`, `seller_confirmed`, `paid`, and `failed`.

## Trust, safety, and admin

| Feature | Status | Source | API | Data | Limits | Remaining |
|---|---|---|---|---|---|---|
| FSSAI capture and review | COMPLETE | `lib/fssai.js`, `lib/fssaiCompliance.js`, `routes/fssai.js` | `/fssai/me`, `/admin/fssai/*` | `SellerFssai`, `FssaiAssistanceRequest` | Selling requirement defaults off (`fssai_selling_requirement`) | Turn enforcement on only when the owner wants it |
| Address proof review | COMPLETE | `lib/addressProofReview.js` | `/admin/address-proofs` | `User.addressProof*` | Does not by itself block selling | — |
| Kitchen move | COMPLETE | `lib/kitchenMove.js`, `routes/kitchenMoves.js` | `/auth/me/kitchen-move`, `/admin/kitchen-moves` | `KitchenMove` | Live society changes only on admin approve | — |
| Festival banners | COMPLETE | `lib/festivalBanners.js` | `GET /festival-banners/active`, `/admin/festival-banners` | `FestivalBanner` | Comment says at most one should be active | — |
| Force update | COMPLETE | `lib/appForceUpdate.js`, `lib/screens/force_update_screen.dart` | `GET /settings` | `AppSetting` min build keys | Defaults disabled at 0 | — |
| Admin operations console | COMPLETE for the committed screens | `lib/screens/admin/`, `routes/admin.js` | `/admin/*` | many models | View-only vs super admin is enforced | — |
| Admin city scope | PARTIALLY COMPLETE | `lib/adminCityDashboard.js`, `lib/admin/admin_city_scope.dart`, `lib/widgets/admin_city_scope_bar.dart`, `lib/widgets/admin_dashboard_cities_table.dart`, admin list screens, `api_service.dart`, `session_service.dart` | Optional `?cityKey=` on dashboard, growth, societies, listings, orders, reviews, issues, coupons, settings, and performance GETs. `GET /admin/dashboard/cities` | `Society.city` grouped by `canonicalCityKey`. No new table | Chips on Dashboard, Societies, Listings, Orders, Performance, Reviews, Issues, Coupons. Choice saved in `admin_city_scope_key`. Unknown city returns 400 `INVALID_CITY_KEY`. Unit test passed on 15 Nov 2026. Browser pass not done | Click through the chips. Full behavior is in [LATEST_HANDOVER.md](LATEST_HANDOVER.md) |
| Marketing push | COMPLETE in code | `lib/marketingPush.js` | `GET/POST /admin/marketing-push` | `AppSetting.marketing_push_last_sent_at` | Super admin POST | — |
| Audit log | COMPLETE | admin routes | `GET /admin/audit-log` | `AuditLog` | Not a full security audit trail of every table | — |

## Explicitly not implemented

| Item | Evidence |
|---|---|
| Twilio WhatsApp | No Twilio client or env names in application code |
| Razorpay or PayU | Unknown provider names are rejected or normalized away in tests |
| A separate WhatsApp deployable | Logic is in-process by design |
| Platform escrow as the default | Default provider is direct UPI |
| Wildcard kitchen DNS | Not configured in `vercel.json` beyond one host |
| Firestore as a database | Dependency present, no `lib/` usage |

## Needs verification outside the repo

- Whether production API traffic uses the DigitalOcean URL, Render, or both.
- The live `AppSetting` values for payment provider, WhatsApp, platform fee, and FSSAI enforcement.
- Meta business verification and template approval.
- Store listing status for Android and iOS. `pubspec.yaml` in this commit is `1.0.0+58`.
