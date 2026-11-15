# SocietyEats project context

Verified against the repository on 15 November 2026. Where an older document or the local Cursor skill disagrees with this page, this page and the source code are the current description.

Repository: `agrawalpuran/societybites`  
Package and folder name: SocietyBites  
Product name in the app: SocietyEats

## Business overview

SocietyEats is a hyperlocal food marketplace aimed first at India. It connects people who want homemade and small-kitchen food with people who cook it, inside and around residential societies.

Three parties use the product:

1. Buyers, usually residents, who discover food, keep a cart, and place orders.
2. Home kitchens and small food sellers, who publish dishes, receive orders, and update them.
3. Platform administrators, who configure societies, safety checks, promotions, and operations.

The first product idea was food inside one apartment society, pickup only, with the buyer paying the seller directly. That idea is still visible in older docs and in the default payment provider. The running application has grown past it: many societies, a serving-city list, a seller radius beyond the home society, seller delivery as well as pickup, pre-orders, coupons, reviews, issue reports, and public kitchen pages.

## Product objectives

- Make it practical for a resident to buy from a kitchen they can actually reach.
- Make it practical for a home cook to sell without the platform holding their money by default.
- Keep optional paid services off until the owner turns them on.
- Add capability in small steps on top of working code.
- Stay understandable by one owner and by any future developer or AI assistant.

## Target users

| User | What they need | How the app models them |
|---|---|---|
| Buyer | Browse, order, pay, pick up or receive, review, report a problem | `User.role` defaults to `buyer` |
| Seller | List food, set reach and fulfilment, accept work that needs a decision, get notified, confirm payment | Same `User` row, `role` set to `seller` after seller terms |
| Seller owner (staff) | Look at a kitchen they do not operate | `SellerStaffMembership` with role `owner`, view-only in the current API |
| Super admin | Change platform configuration | `User.role = super_admin` |
| Console admin | Read the admin portal | `User.consoleAdmin = true`, or legacy `role = admin`. Writes are rejected |

A person is one `User` row keyed by phone number. They are not both a buyer and a seller at the same time in `User.role`. Enabling selling changes the role. Buyers can save several places. The selected place is copied onto `User.societyId` and `User.flatId`. Sellers do not use the saved-place list. A seller kitchen stays in one society until an admin approves a kitchen move.

## Buyer journey

Verified from `lib/main.dart`, `lib/screens/main_shell_screen.dart`, and the order and payment routes.

1. Open the app. Web opens the marketplace shell. Mobile opens a guest landing page when signed out.
2. Sign in with a phone OTP. The default client build uses 2Factor (`AUTH_PROVIDER` defaults to `2factor`). A build can fall back to Firebase phone auth with `--dart-define=AUTH_PROVIDER=firebase`.
3. Join a society, or pick a saved place. Society search can use Google Places when the backend key is set. SocietyBites remains the source of truth after a place is saved.
4. Browse the home feed for the selected society, nearby kitchens inside the seller's radius, guest kitchens, pre-order campaigns, and a public kitchen page when a slug or `/kitchen/{slug}` link is opened.
5. Open a dish, choose a size when the dish has variants, and add it to the cart.
6. Checkout creates an order with `POST /orders`. An optional `Idempotency-Key` header replays the same order instead of creating a second one. An optional coupon is validated and redeemed in the same transaction.
7. Ready-now regular orders are created already `accepted`. Made-to-order and pre-order orders stay `pending` until the seller accepts.
8. Pay by the method the seller allows: direct UPI, cash, or a split of UPI for food and cash for an outside delivery fee. If an admin has switched the platform to Cashfree, UPI checkout can go through Cashfree instead. The provider is locked onto the order at checkout.
9. Follow status until `ready`, then handover. The seller marks `completed` when the payment rules allow it. Outside UPI-plus-cash-delivery orders can complete when the seller confirms the delivery cash.
10. Review a completed order. Message the other party on the order. Report an issue if something goes wrong.

Guests can see guest kitchens and a public kitchen site without an account. Placing an order requires a signed-in user who has a society.

## Seller journey

1. Sign in, then accept seller terms and turn the account into a seller (`POST /auth/me/seller-terms` and profile updates).
2. Set the kitchen: UPI id and account type, payment preference, fulfilment mode, delivery charges, selling reach, kitchen hours, flat privacy, and an optional public slug.
3. Create listings as drafts and publish them. Listings can be ready-now or made-to-order, regular or pre-order catalog, recurring, discounted, and grouped into sizes.
4. Receive a new order by in-app state, Firebase push when a device token is registered, and WhatsApp only when that channel is enabled and configured. WhatsApp failure does not roll back the order.
5. Accept made-to-order and pre-order work. Decline with a reason while the decline rule still allows it (`POST /orders/:id/reject`).
6. Mark the order `ready`, including an actual delivery charge when the order requires one. Mark `completed` after payment rules pass.
7. Confirm direct UPI (`I Have Paid` then seller confirm), cash, or delivery-fee cash on the payment routes.
8. Read seller stats, insights, and payment reconciliation. Pause, resume, renew, reorder, or remove listings.
9. Optionally submit FSSAI details, request help, upload address proof, invite a view-only owner, or ask to move the kitchen. The move does not change the live society until an admin approves it.

## Admin journey

The admin shell is `lib/screens/admin/admin_shell_screen.dart`. Every `/admin` route requires a signed-in portal user. GET is allowed for console admins. Any other method requires `super_admin`.

The shell includes dashboard, societies, FSSAI, address proof, kitchen moves, listings, orders, seller performance, reviews, issues, coupons, and audit log. Further screens cover users, console access, serving cities, city reach, payment splits, festival banners, and settings such as platform fee, WhatsApp notifications, payment provider, and force-update builds.

This commit adds city chips on the dashboard, societies, listings, orders, performance, reviews, issues, and coupons, plus a per-city platform fee that checkout uses. It follows `2d6871c`. The full behavior is in [LATEST_HANDOVER.md](LATEST_HANDOVER.md).

## Business model

- Sellers sell their own food. The platform lists them and coordinates the order.
- The default money path is direct. The buyer pays the seller's UPI id, or pays cash on handover. The platform does not take the funds.
- A platform fee (`AppSetting` key `platform_fee`, default 0) can be stored on the order as `communityFee`. It is off in the sense that the default amount is zero until an admin sets it.
- Coupons are funded by SocietyEats (`CouponFundedBy.SOCIETYEATS` only). The coupon reduces what the buyer pays. Seller entitlement is not reduced by that discount.
- Cashfree Easy Split exists in code so a future or admin-enabled mode can collect through a gateway and split to a seller vendor. It is not the default. Turning it on is an owner decision, not an automatic next step.
- Delivery charges are set by the seller and snapshotted onto the order. They are not a platform delivery network.

## Monetization

| Mechanism | State in code |
|---|---|
| Platform fee | Implemented, default ₹0 |
| SocietyEats-funded coupons | Implemented. Seller payout of the funded discount is an admin report |
| Payment gateway fees | Only relevant if Cashfree is enabled. Live setting was not read |
| Subscription or commission percentage | Not implemented |
| Paid WhatsApp | WhatsApp Cloud API is optional and default-off |

No new paid integration should be introduced without the owner's approval.

## Product philosophy

Taken from the owner's standing direction and checked against how the code is actually shaped:

- Keep the product simple and practical.
- Prefer a modular Express route plus a library module over a new service.
- Avoid extra infrastructure and extra vendors.
- Leave optional services behind an admin setting or an environment variable.
- Preserve a working flow when adding the next one.
- Build one increment at a time.

## What exists today

The short list is in [PROJECT_STATUS.md](PROJECT_STATUS.md). In product language, a buyer can discover food across societies in a serving city, order, pay the seller directly, and review. A seller can publish a kitchen, including a public page at `/kitchen/{slug}`, and run orders. An admin can operate the platform from the in-app console. Push notifications and WhatsApp are both implemented as optional notification channels. Cashfree is implemented behind a switch.

## Future roadmap

Confirmed product ideas versus recommendations are separated in [ROADMAP.md](ROADMAP.md).

Seller microsites of the form `{slug}.societyeats.com` are partly built. The app serves `/kitchen/{slug}` and `GET /public/kitchens/:slug`. `vercel.json` redirects only `puran.societyeats.com`. A comment in the admin users screen says wildcard `*.societyeats.com` is not live. Treat full subdomain tenancy as unfinished, not as a green-field idea.

Twilio, Razorpay, and PayU were discussed or rejected in tests as unknown providers. They are not integrations.

## What this page does not claim

- Which host is answering production traffic right now. The Flutter default API URL is a DigitalOcean app URL. Backend env comments still mention Render. See [ARCHITECTURE.md](ARCHITECTURE.md).
- Whether the live database has WhatsApp, Cashfree, or a non-zero platform fee turned on.
- Legal, tax, or Meta business-verification status. Those were reported as historical obstacles and are not stored as facts in this repository.
