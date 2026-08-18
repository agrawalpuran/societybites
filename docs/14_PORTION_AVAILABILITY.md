# Manual test cases — Portion availability

## Setup
- Backend running with latest `orders.js` inventory errors (409).
- Seller creates a listing with known QUANTITY AVAILABLE.

## Cases

### 1. Create listing qty = 10
- Buyer Home shows **10 left**.
- Food detail AVAILABILITY shows **10** / portions left.

### 2. Order 2
- Remaining **8 left** after home refresh (checkout success already reloads Home).

### 3. Order remaining 8
- Listing becomes sold out / disappears from buyer Home (`sold_out`).

### 4. Order sold-out
- API rejects (409 / not available).

### 5. Concurrent oversell
- Available 5; two clients each request 3.
- Total sold ≤ 5; loser gets 409 with remaining count.

### 6. Request more than available
- Available 2; order 5 → 409; inventory stays 2.

### 7–8. Reject / cancel
- Inventory restored; listing active again if qty > 0.

### 9. Double cancel/reject
- Second attempt blocked; inventory not double-restored.

### 10. Seller edit quantity
- Field is **remaining** stock; saving sets remaining to entered value.

### 11. Checkout stepper
- Cannot increase cart qty above listing.quantity shown at load time.
- Stale cart still revalidated on place order.

### 12. Regression
- Pause, pay, auth, existing orders unchanged.
