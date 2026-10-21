# Seller Payment Reconciliation — Stage A Audit

## Schema (no separate Payment model)

`Order` holds: `subtotal`, `communityFee`, `deliveryCharge`, `total`, `paymentMethod` (`upi`|`cash`), `paymentStatus` (`pending`, `buyer_marked_paid`, `seller_confirmed`, `paid`, `failed`), `buyerMarkedPaidAt`, `sellerConfirmedPaidAt`, `deliveryCashConfirmedAt`, `buyerId`, `societyId`, `status`, `cancelReason`.

**Paid vs pending (Phase 1 UI):**

- **PAID (collected):** UPI food confirmed (`seller_confirmed` or `paid` per `isFoodUpiConfirmed`) **and** delivery cash settled when applicable (`deliveryCashSettled`).
- **PENDING:** everything else on non-terminal orders.

**Collections by date:** `sellerConfirmedPaidAt` / `deliveryCashConfirmedAt` (latest when split). **Sales by date:** `createdAt` (IST), excluding `cancelled`/`rejected`.

**Location:** `society` when buyer has `societyId`; `outside` when buyer has no society. Group societies by `order.societyId` + society name.

## Existing APIs (reused)

- `POST /payments/:id/mark-paid` (buyer UPI)
- `POST /payments/:id/confirm` (seller UPI)
- `POST /payments/:id/confirm-cash` (COD)
- `GET /orders?role=seller&scope=…` (`listSellerOrders`)
- `GET /orders/seller/insights` (IST date presets — pattern only)

## Gaps addressed in Phase 1

- Seller reconciliation summary + location/method breakdown + filtered pending list
- `POST /orders/seller/reconciliation/orders/:orderId/payment-reminder` + FCM `payment_reminder`
- `Order.lastPaymentReminderAt` (cooldown, smallest migration)

## Out of scope

Partial payments, bulk/auto reminders, SMS/WhatsApp, new gateways, checkout changes.
