# Auto-refresh + FCM push notifications

## What shipped

1. **Auto-refresh (no polling)**  
   - Home / Orders / Dashboard refresh when that tab is selected.  
   - Visible tab refreshes when the app resumes (`AppLifecycleState.resumed`).  
   - Foreground FCM data messages also refresh the visible tab.

2. **Device tokens**  
   - Prisma `DeviceToken` (multi-device, unique token, `active` flag).  
   - `POST /devices/register`, `DELETE /devices`.

3. **FCM sends (post-commit)**  
   - New order → seller  
   - Accepted / preparing / ready / rejected / ready-by → buyer  
   - Cancelled / picked up → seller  
   - Buyer marked paid → seller  
   - Payment confirmed → buyer (single notify; no duplicate preparing from confirm path)

Payload data: `{ type: "order_update", orderId, notificationType }` plus notification title/body.

## Setup notes

- Backend needs Firebase Admin service account env vars (same as Auth).
- Flutter uses `firebase_messaging` (Android/iOS). Web/Chrome skips register gracefully.
- Permission is optional — denial does not block login or orders.
- Deploy backend to Render before closed-testing devices can receive pushes (app `baseUrl` points at Render).

## Manual tests

1. Tab to Dashboard → orders reload without pull-to-refresh.  
2. Background app, change order on other device, resume → visible tab refreshes.  
3. Allow notifications → token appears in `DeviceToken`.  
4. Deny notifications → app still works; auto-refresh still works.  
5. Place order → seller push (device) / Dashboard refresh.  
6. Accept / Ready / Reject → buyer push + Orders refresh.  
7. Tap notification → Opens Orders (buyer types) or Dashboard (seller types).  
8. Stop FCM / invalid token → order status still commits; stale tokens deactivated.  
9. Logout → device token deactivated.  
10. Multi-device: both tokens receive until one is invalidated.
