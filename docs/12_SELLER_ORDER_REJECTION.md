# Manual test cases — Seller order rejection

## Setup
- Buyer and seller in the same society with an active listing.
- Backend running with latest schema (`rejectReason`, `rejectedAt`, `rejectedBy`).

## Cases

### 1. Reject pending order
1. Buyer places order.
2. Seller opens Dashboard → Active → **Reject Order**.
3. Choose **Food sold out** → Confirm Reject.
4. Expect: order leaves Active; appears under Past as **REJECTED** with reason.
5. Buyer Past shows **ORDER REJECTED** + reason. No Pay Now.

### 2. Reject accepted order
1. Seller accepts order.
2. Reject with **Kitchen closed**.
3. Expect: rejected; inventory restored; buyer cannot pay.

### 3. Reject preparing order
1. Accept → confirm payment → preparing.
2. Reject with **Unable to prepare today**.
3. Expect: success; past history shows reason.

### 4. Cannot reject ready / completed
1. Move order to Ready — Reject button must be **hidden**.
2. Completed orders have no reject action.

### 5. Other reason validation
1. Select **Other** without text → Confirm disabled.
2. Enter text ≤ 200 chars → reject succeeds; buyer sees custom text.
3. (API) otherText > 200 → 400.

### 6. Non-seller cannot reject
- Buyer calling `POST /orders/:id/reject` → 403.

### 7. Buyer cancel still works
- Buyer can still cancel pending/accepted; status remains `cancelled` (not `rejected`).
