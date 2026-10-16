# Admin Seller Performance & Campaign Monitoring — Phase 1 Audit

## A. Inspection summary

### Web admin (`societyeats-web`)

**Not present in this repository.** Production admin UI lives in the **Flutter** app:

| Area | Path |
|------|------|
| Shell / nav | `lib/screens/admin/admin_shell_screen.dart` |
| Dashboard + growth | `lib/screens/admin/admin_dashboard_screen.dart`, `lib/widgets/admin_growth_panel.dart` |
| Orders list | `lib/screens/admin/admin_orders_screen.dart` |
| API client | `lib/services/api_service.dart` (`getAdmin*` methods) |
| Web layout frame | `lib/web/admin_content_frame.dart` |

Hosted buyer/seller web is **Flutter web on Vercel** (`scripts/vercel_build.sh`), not Next.js.

### Authentication & authorization

| Layer | Implementation |
|-------|----------------|
| API | `middleware/requireUser.js` + JWT |
| Admin gate | `middleware/requireAdmin.js` — `super_admin`, `consoleAdmin`, or legacy `role === "admin"` |
| Mutations | `routes/admin.js`: non-GET requires `requireSuperAdmin` |
| Flutter | `SessionService` role; admin shell from profile |

**Phase 1 metrics endpoints are GET-only** → console admins and super admins may read.

### Existing admin APIs (relevant)

| Route | Purpose |
|-------|---------|
| `GET /admin/dashboard` | Global counts (orders by status, users, listings) |
| `GET /admin/growth` | IST bucketed signups (not sales) |
| `GET /admin/orders` | Paginated orders; `sellerId` via `items.listing.sellerId` |
| `GET /admin/payments` | Orders by `paymentStatus` |
| `GET /admin/reports/coupon-seller-payouts` | Coupon redemptions per seller |
| `GET /orders/seller/insights` | **Seller self-service** analytics (`lib/sellerInsights.js`) |

### Prisma models (sales)

- **Order**: `buyerId`, `societyId`, `status`, `subtotal`, `communityFee`, `deliveryCharge`, `total`, `paymentMethod`, `paymentStatus`, `type` (`regular` \| `pre_order`), `campaignId`, timestamps. **No `sellerId`** on order.
- **OrderItem**: `listingId`, `quantity`, `unitPrice` (snapshot at checkout).
- **Listing**: `sellerId`.
- **CouponRedemption**: `discountAmount`, `status` (`APPLIED` \| `REDEEMED` \| `REVERSED`), `orderId`.
- **PreOrderCampaign**: seller, schedule, `status` (`draft` \| `open` \| `closed` \| `cancelled`).

**Seller on order**: derived from items; checkout **rejects multi-seller carts** (`routes/orders.js`).

### Order & payment rules (from code)

**Statuses:** `pending`, `accepted`, `preparing`, `ready`, `picked_up`, `completed`, `cancelled`, `rejected`.

**Qualifying successful sale (aligned with `sellerInsights.js`):**

- `status === "completed"` only.
- Not `cancelled` / `rejected` / in-flight.

**Payment:** `paymentStatus` is separate from order completion (`pending`, `buyer_marked_paid`, `seller_confirmed`, `paid`, `failed`). **Do not** treat `paid` alone as a completed sale.

**Checkout totals** (`routes/orders.js`):

- `subtotal` = Σ `listing.price × qty` (food).
- `communityFee` = platform fee at create time.
- `deliveryCharge` = snapshot on order.
- `preCouponTotal` = subtotal + communityFee + deliveryCharge.
- Coupon: `discountAmount` from `discountFor(coupon, subtotal)` — **computed on food subtotal only**, subtracted from **full** `preCouponTotal` for `order.total`.
- On cancel: coupon `REVERSED`, `paymentStatus` → `failed`.

**Coupon semantics** (`schema` + `lib/coupons.js`): SocietyEats-funded; **seller food entitlement is not reduced** by discount. Admin **gross food** = `subtotal`; **net food (buyer)** = `subtotal - discount` when redemption `REDEEMED`.

### Pagination / dates / CSV

- **Pagination:** `page` + `limit` on `/admin/orders` (default 50).
- **Dates:** IST helpers in `lib/sellerInsights.js` (`resolveDateRange`: `last_7_days`, `last_30_days`, `custom`, max 366 days).
- **CSV:** **No existing pattern** — Phase 1 adds CSV on new export endpoint.

---

## B. Metric definitions (Phase 1)

| Metric | Definition |
|--------|------------|
| Gross food value | `order.subtotal` for qualifying orders |
| Net food value | `subtotal - discountAmount` (REDEEMED coupon on order; 0 if none) |
| Delivery charges | `order.deliveryCharge` (separate KPI; not in food totals) |
| Platform fee | `order.communityFee` (informational; not food) |
| Qualifying order count | `status === completed` in window (by `createdAt` IST) |
| Unique buyers | Distinct `buyerId` per seller on qualifying orders |
| Avg qualifying food order | Net food sum / qualifying count |
| New buyer | First **completed** order with seller at or before order time is in window |
| Repeat buyer | Prior completed order with same seller before this order's `createdAt` |
| Cancellations | `cancelled` + `rejected` in window |
| Cancellation rate | `(cancelled + rejected) / orders created in window` per seller |
| Payment breakdown | Counts by `paymentStatus` (+ `paymentMethod`) in window |

**Campaign:** Pre-order campaigns — orders with `type === pre_order` and `campaignId`; KPIs per campaign (placed, completed, cancelled/rejected, gross food).

**Ambiguities / limitations**

1. Discount applies to subtotal but reduces **total** including fees/delivery — net food uses subtotal-only discount (matches coupon math).
2. `rejected` included in cancellation rate; not in seller insights status breakdown as “sales”.
3. Date window uses **`createdAt`**, not `completedAt` (consistent with seller insights).
4. `all_time` can be heavy — bounded export row limits apply.
5. No `sellerId` on `Order` — all seller metrics join via `OrderItem` → `Listing`.

---

## C. Proposed API (Phase 1)

All under `GET /admin/performance/...`, `requireUser` + `requireAdmin`.

| Endpoint | Query | Response |
|----------|-------|----------|
| `/admin/performance/summary` | `preset`, `from`, `to`, `societyId?` | KPI cards + payment breakdown |
| `/admin/performance/sellers` | same + `sort`, `page`, `limit` | Leaderboard rows |
| `/admin/performance/sellers/:sellerId` | same | Seller summary + buyer new/repeat + status mix |
| `/admin/performance/sellers/:sellerId/orders` | `page`, `limit` | Order-level rows |
| `/admin/performance/campaigns` | date + `societyId?` | Campaign table |
| `/admin/performance/export` | same as summary filters | `text/csv` |

**Presets:** `last_7_days`, `last_30_days`, `custom` (YYYY-MM-DD), `all_time`.

---

## D. Security & performance

- Backend auth on every route; no new public endpoints.
- PII: leaderboard uses seller name; order lists mask buyer phone optional (show name + id only in detail).
- Max date span: 366 days except `all_time` (documented).
- Leaderboard: aggregate in one pass over filtered orders (pilot scale); paginate seller list.
- No schema changes.

---

## E. Implementation plan

1. `lib/adminSellerPerformance.js` — range parsing, aggregation, CSV.
2. Wire routes in `routes/admin.js`.
3. `tests/admin-seller-performance.test.js`.
4. Flutter: `AdminSellerPerformanceScreen` + `ApiService` + nav item.
5. No changes to checkout, orders mutations, or payments.

**Risks:** Large societies + `all_time` may need SQL aggregation or materialized views later.
