# Business Rules

- One user belongs to exactly one society.
- Users cannot change society after registration.
- Buyers can place orders.
- Sellers can create listings.
- Listings belong to one seller.
- Listings belong to one society.
- Buyers can only see listings from their own society.
- Buyers only see listings with status `active` (paused / expired / sold_out / inactive are hidden).
- Sellers can pause an active listing (`paused`) and resume it later (`active`).
- When `availableAt` (Available Until) is in the past, listings become `expired` on read (no cron).
- Sellers can renew expired listings by setting a new future Available Until (`active`).
- Sellers can still view and edit paused or expired listings in My Listings.
- Soft-delete sets status to `inactive` (removed from seller management list).
- Sellers may reject orders in `pending`, `accepted`, or `preparing` with a required reason (`rejected`).
- Buyers see rejected orders in Past with the rejection reason; payment actions are hidden.
- Reviews are allowed only after completed orders.
- Orders cannot be placed for paused or expired listings.
- One review per order.
- Pickup only.
- No delivery.
- Payment is Direct UPI.
- Seller confirms payment.
- Platform fee is configurable by admin (default ₹0) and applied at order creation.
- Cancelled orders cannot be reviewed.

