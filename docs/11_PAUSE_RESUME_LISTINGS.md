# Manual test cases — Pause / Resume listings

## Setup
- Backend running; Flutter app logged in as seller (e.g. Anita) with at least one active listing.
- Prefer a second session / buyer account in the same society to verify buyer visibility.

## Cases

### 1. Pause active listing
1. Open **My Listings**.
2. Confirm an **ACTIVE** badge on a listing.
3. Tap **Pause** → confirm dialog → Pause.
4. Expect: snackbar success; badge becomes **PAUSED**; **Resume** button shown.

### 2. Resume paused listing
1. On a **PAUSED** listing, tap **Resume** → confirm.
2. Expect: badge **ACTIVE**; **Pause** button shown; listing visible on Home for buyers.

### 3. Buyer cannot see paused listing
1. Pause a listing as seller.
2. As buyer (or seller viewing Home browse), refresh Home / search.
3. Expect: paused dish does **not** appear under All or any category, and not in search.

### 4. Seller can still edit paused listing
1. Pause a listing.
2. Tap Edit, change name/price, save.
3. Expect: save succeeds; listing remains **PAUSED** until Resume.

### 5. Search excludes paused listing
1. Pause “South Indian Lemon Rice” (or similar unique name).
2. Search that name on Home.
3. Expect: no match while paused; after Resume, it appears again.

### 6. Orders already placed are unaffected
1. Place an order on an active listing (buyer).
2. Seller pauses that listing afterward.
3. Expect: existing order still appears in Orders with prior status; pause does not cancel or alter the order.

### 7. API validation (optional curl / Postman)
- Pause twice → `400` “Listing is already paused”.
- Resume an active listing → `400` “Listing is already active”.
- Non-owner pause → `403`.
