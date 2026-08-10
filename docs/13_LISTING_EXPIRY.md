# Manual test cases — Listing expiry & renew

## Setup
- Backend running with latest listing routes (no DB migration required).
- Seller has at least one listing with **Available Until** set.
- Buyer and seller in the same society.

## Cases

### 1. Listing automatically expires
1. Create/edit a listing with Available Until a few minutes ahead (or set past via DB/API).
2. Wait until time passes, then refresh Home / My Listings.
3. Expect: status becomes **EXPIRED** (lazy on read, no cron).

### 2. Buyer cannot see expired listing
1. Expire a listing.
2. Open Home as buyer — dish must **not** appear.
3. Category filters must not show it.

### 3. Buyer search excludes expired listing
1. Search the dish name while expired.
2. Expect: no results for that listing.
3. Renew it → search finds it again.

### 4. Seller sees expired listing
1. Open **My Listings**.
2. Expect grey **EXPIRED** badge.
3. Actions: **Renew**, Edit, Delete — **no Pause**.

### 5. Renew updates Available Until
1. Tap **Renew** → pick a future date/time → Renew.
2. Expect snackbar success; Available Until updated.

### 6. Renew changes status back to ACTIVE
1. After renew, badge is **ACTIVE** (green).
2. Buyer Home shows the listing again.

### 7. Edit expired listing
1. Edit an expired listing; set Available Until to future → save.
2. Expect status **ACTIVE** without creating a new listing.
3. Edit other fields only (past Available Until unchanged) → stays expired.

### 8. Cannot order expired listing
1. Add listing to cart before expiry (optional), then let it expire.
2. Checkout / place order → API error: has expired and cannot be ordered.
3. Paused listing order → paused error.

### 9. Existing ACTIVE listings continue working
1. Active listing with future Available Until still shows for buyers.
2. Pause / Resume / Edit / Delete still work as before.
3. Sold out behavior unchanged.
