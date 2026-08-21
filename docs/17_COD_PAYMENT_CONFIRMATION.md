# Manual test cases — COD cash payment confirmation

## Setup
- Backend with `POST /payments/:orderId/confirm-cash` and cash complete gate.
- COD uses `paymentMethod = "cash"`.

## Cases

### 1. Create cash order
- Expect `paymentStatus = pending`.

### 2. Picked-up cash order
- After buyer marks picked up, seller Dashboard shows **Confirm Payment Received**.

### 3. Confirm cash
- Seller confirms dialog → `paymentStatus = paid`, `sellerConfirmedPaidAt` set.
- Badge shows PAID / Payment Received.

### 4. Complete after paid
- Seller **Complete Order** available and succeeds.

### 5. Complete without payment
- Backend rejects with confirm-payment-first message.
- Buyer Mark Complete blocked with same guidance.

### 6. Double confirm
- Second confirm-cash returns current paid order; timestamp unchanged.

### 7. UPI order
- Existing mark-paid → confirm → preparing unchanged.
- No Confirm Payment Received cash block.

### 8–9. Buyer / wrong seller
- 403 on confirm-cash.

### 10. Cancelled / rejected
- confirm-cash unavailable / rejected.

### 11. Buyer view after confirm
- Shows Payment Received ✓ after refresh.

### 12. Notification failure
- Payment still becomes `paid`.
