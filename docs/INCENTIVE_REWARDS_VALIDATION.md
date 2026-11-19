# Incentive rewards validation

Reviewed from the source on 19 November 2026. The engine stays off. This page records what the code does. It is not approval to enable a switch.

## Completed orders

SocietyEats has no `delivered` order status and no `failed` order status. The live statuses are `pending`, `accepted`, `ready`, `completed`, `cancelled`, and `rejected`. `preparing` and `picked_up` are retired and cannot be assigned. The seller moves `ready` to `completed`. The buyer does not confirm completion, an administrator does not complete the order, and nothing moves a ready order to completed on its own. Cashfree or direct UPI confirmation can also complete an order when `assertCanCompleteOrder` allows it.

`qualifyOrder` returns `ORDER_NOT_COMPLETED` for every status other than `completed`. A completed order still needs its payment rule: direct UPI needs `seller_confirmed` or `paid`, cash and Cashfree need `paid`, and a split delivery needs both food confirmation and delivery-cash confirmation. `emitOrderQualifiedIfReady` runs after the order write commits. A failed insert is tried once more. The order response is unchanged if both attempts fail. The same `ORDER_QUALIFIED:{orderId}` event is idempotent. Reward issuance uses the reward idempotency key, so a replay does not create a second reward. Super-admin backfill reconstructs the event for a completed qualifying order. That is the recovery path. Incentive processing does not run inside the order transaction, because a missing incentive table must not block completion.

A cancelled or rejected order never reaches `completed`, so it does not earn a reward. `refundDue` means the seller owes the buyer for a UPI payment on an order that ended without food. There is no post-completion refund or chargeback flow. A reward reversal is not implemented. The ledger guard still accepts only `ISSUE`, `REDEEM`, and `EXPIRE`.

## Reconciliation

`GET /incentive/admin/rewards/reconciliation?campaignId=` is a portal read. It reports the configured cap, the reserved `issuedAmount`, the remainder, reward counts by status, and signed ledger totals. It does not update rows. `reversedRewards` stays zero until a reversal writer exists.

## Notifications

A newly created issued or pending reward sends one FCM message after the event transaction commits. A duplicate reward does not send another. Approving a reward sends the coupon-issued or reward-approved message only when that approval wrote the decision. Rejecting a pending reward sends one rejection message. Redeeming a credit sends one redemption message, and a duplicate redemption key does not. Expiry does not send a push, and there is no scheduled expiry reminder. Every send uses `notifyAsync` and cannot roll back the reward or the order.

## Migration order

Apply only on a database the owner names. Do not apply these to Supabase from this programme.

1. `20261117120000_incentive_engine_foundation`
2. `20261117183000_incentive_event_processing`
3. `20261117203000_incentive_referral_code_pin`
4. `20261117213000_incentive_referral_attribution`
5. `20261117223000_listing_first_published_at`
6. `20261117233000_incentive_ledger_guard` with `psql`. It is not part of Prisma migration history.

`societybites_incentive_integration_v2` was opened again on 19 November 2026 through `scripts/run-incentive-v2-local.ps1`. The incentive tables, three enabled ledger triggers, and nullable `Listing.firstPublishedAt` are present. `_prisma_migrations` is not present, so those objects were not recorded by Prisma and were not redeployed. Flags, campaigns, and rewards were empty before the run. Phase 3A printed `incentive rewards v2 integration ok`. `whatsapp-settings` and `payment-provider` passed on a second run after regression had created societies. After the seed and the listing-create fix, `npm run test:regression` printed `All suites passed`. Phase 3A was run once more and printed `incentive rewards v2 integration ok`. Flags were still empty and reward rows were still zero. Completed test orders recorded `ORDER_QUALIFIED` events. The database was left with 15 societies and 5 app settings.

## Emergency controls

There is no route that writes `IncentiveSetting`. Missing or non-`true` values keep issuance, redemption, and the master switch off. A super admin can pause a campaign. Turning the master switch off stops new claims. Already stored rewards are not deleted. Pending events stay pending while the master switch is off.

## Fraud controls already in code

Self-referral and a direct reverse pair are rejected. A coupon reward is limited to the recipient. A credit redemption order must belong to that recipient. Event and reward idempotency keys stop duplicate completion from issuing twice. Budget reservation stops a second reward past the cap. Rate limits on the public referral preview stay in memory. Multiple accounts, seller-buyer collusion, and a cash clawback need a business rule before any new control is added.

Phase 3A ran against `127.0.0.1:5432/societybites_incentive_integration_v2` and printed `incentive rewards v2 integration ok`. It was run again on 19 November 2026 after the Prisma client was regenerated and printed the same line. Flags stayed off.

## Operations

| Operation | Success | Invalid input | Unauthorized | Duplicate | Concurrent | Transaction failure | Rollback | Audit | Budget | Consistency |
|---|---|---|---|---|---|---|---|---|---|---|
| Issue fixed or percentage coupon | One `ISSUED` reward and one `SELECTED_USERS` coupon for the recipient | Unsupported type is skipped. No recipient skips `RECIPIENT_UNAVAILABLE` | Issuance runs only when the caller passes `flags.issuance === true`. The event path does that only when the stored switch is exactly `true` | Same idempotency key returns the open reward and does not charge again | Budget row lock. One charge wins. The other is `BUDGET_EXHAUSTED` | Coupon insert error throws to the caller | The caller transaction rolls back the reward and the charge. Phase 3A proved this on v2 | `REWARD_ISSUED`, or `REWARD_BUDGET_EXHAUSTED` when skipped for budget | Fixed uses `amount`. Percentage uses `maxDiscount`. A charge above `maxRewardAmount` is skipped | Coupon code is the hash of the idempotency key. No ledger row |
| Issue credit or points | One `ISSUED` reward and one positive `ISSUE` ledger row | Zero or the wrong sign is `LEDGER_AMOUNT_INVALID` | Same issuance switch | Same key returns the existing reward and ledger row | Two debits that cannot both fit: one `INSUFFICIENT_CREDIT` | Ledger unique conflict on the same amount returns the stored row | Caller transaction rolls back the reward, ledger row, and charge | `REWARD_ISSUED` | Credit reserves `amount`. Points reserve nothing | Balance is the sum of ledger rows |
| Pending approval | `PENDING_APPROVAL`, no coupon and no ledger row, budget already reserved | Missing actor on approve is `ACTOR_REQUIRED` | Portal admin receives 403. Super admin only | Second approve returns the issued row and does not create a second coupon, ledger row, or approval | Two approve calls lock the reward. Phase 3A left one `ISSUED` row | Flag read error returns `ISSUANCE_DISABLED` and leaves the row pending | No partial coupon. Materialisation is in the approval transaction | `REWARD_PENDING`, then `REWARD_APPROVED` | Unchanged at approval | `issuance_enabled` must be exactly `true` inside the transaction |
| Reject | `REJECTED`, reserved charge returned once | Missing definition is `REWARD_DEFINITION_MISSING` and does not change the budget | Super admin only | Second reject returns the rejected row and does not release again | Rejection and a new issue lock the same budget | — | Status stays pending when the definition is missing | `REWARD_REJECTED` | Percentage releases `maxDiscount`, not the percentage amount | A replay is `REWARD_CLOSED`, not a new issue |
| Redeem credit | Debit, redemption row, `PARTIALLY_REDEEMED` or `REDEEMED` | Coupon reward is `COUPON_REDEMPTION_UNCHANGED`. Past `expiresAt` is `REWARD_EXPIRED`. Over-debit is `INSUFFICIENT_CREDIT` | Redemption switch off is 403. Portal admin is 403 | Same key and amount returns `duplicate: true` and the matching redemption. A different amount is `IDEMPOTENCY_CONFLICT` | Reward lock covers the debit and the status write | — | No redemption row when the debit throws | `REWARD_REDEEMED`, with `campaignId` when the version has one | No budget change | `orderId` must be the recipient's order |
| Expire credit | Remaining balance posted as `EXPIRE`, status `EXPIRED` | Missing actor is `ACTOR_REQUIRED`. Coupon rows are not expired here | Super admin only | Second run finds the status and posts nothing | Re-reads under the reward lock. A committed full redemption stays `REDEEMED` | — | — | One `REWARD_EXPIRED` | No budget change | Ledger idempotency key is `EXPIRE:{rewardId}` |
| Caller read | `GET /incentive/rewards` and `/history` use `req.user.id` | — | Signed-in user. Query `userId` and `recipientUserId` are deleted before the read | — | — | — | — | — | — | No other user's rows |
| Coupon checkout redemption | Existing `lib/coupons.js` path. Expiry, usage, and `REVERSED` live there | Incentive `redeemReward` refuses coupon rewards | Checkout ownership stays in the coupon module | Coupon code uniqueness is enforced by coupon create | Not retested in Phase 3B | Eligible-user foreign key rolls back coupon issue. Phase 3A | — | Coupon audits are separate | Incentive budget is not changed at checkout | No incentive ledger row |

## Not implemented

`ORDER_CANCELLED` does not reverse an incentive reward. There is no route that sets `REVERSED`. Adding one needs an owner decision for the coupon, the reserved budget, and the ledger type. The database guard would reject a new entry type until its migration is applied on a named database.

Campaign lifecycle, referral qualification, and Flutter buyer or seller journeys were not re-run as end-to-end product tests in Phase 3B. Their existing unit tests were not all re-run. `node tests/incentive-events.test.js`, `node tests/incentive-read.test.js`, and `node tests/incentive-analytics.test.js` printed ok after the reward changes.

## Production blockers

- Every incentive switch is off. Do not turn one on from this validation.
- The ledger guard is not on Supabase.
- `Listing.firstPublishedAt` is not applied on the shared database.
- Buyer and seller reward journeys have not been exercised against a running API.
- Reward reversal is unspecified.
