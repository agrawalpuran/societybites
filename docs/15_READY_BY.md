# Manual test cases — Optional Ready by

## Setup
- Backend running with `expectedReadyAt` on Order (nullable).
- Seller and buyer in the same society with an order flow.

## Cases

### 1. Accept without Ready by
1. Seller Accept Order → Skip on Ready by sheet.
2. Expect: order accepted; `expectedReadyAt` null; buyer sees no Ready-by chip.

### 2. Accept with Ready by
1. Accept → choose 30 min (or custom future time).
2. Expect: seller card shows Ready by; buyer Active order shows Ready by.

### 3. Update Ready by
1. On accepted/preparing order, Update Ready by → new time.
2. Buyer refresh shows updated time.

### 4. Remove estimate
1. Update Ready by → Remove estimate.
2. Buyer no longer sees Ready by.

### 5. Past time
1. API/custom pick past time → backend 400.

### 6. Unauthorized
- Buyer calling `PATCH /orders/:id/ready-time` → 403.

### 7. Mark ready
1. Seller marks Ready.
2. Buyer sees ready/pickup flow; Ready-by estimate no longer shown as active ETA.

### 8. Cancel / reject
- Existing flows work; Ready by not required.

### 9. Existing orders
- Old orders with null `expectedReadyAt` unchanged.
