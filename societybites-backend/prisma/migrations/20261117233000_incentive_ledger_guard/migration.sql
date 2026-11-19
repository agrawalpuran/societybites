-- Phase 2E. Not applied.
-- Replaces the ledger guard with a reward-row lock before the balance sum.
-- Does not alter Coupon, Order, User, Listing, or AppSetting.
-- Rollback, after an approved apply:
-- DROP TRIGGER IF EXISTS incentive_ledger_no_update ON "IncentiveLedgerEntry";
-- DROP TRIGGER IF EXISTS incentive_ledger_no_delete ON "IncentiveLedgerEntry";
-- DROP TRIGGER IF EXISTS incentive_ledger_guard_insert ON "IncentiveLedgerEntry";
-- DROP FUNCTION IF EXISTS incentive_ledger_reject_mutation();
-- DROP FUNCTION IF EXISTS incentive_ledger_guard_insert();

CREATE OR REPLACE FUNCTION incentive_ledger_reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'IncentiveLedgerEntry is append-only';
END;
$$;

DROP TRIGGER IF EXISTS incentive_ledger_no_update ON "IncentiveLedgerEntry";
CREATE TRIGGER incentive_ledger_no_update
BEFORE UPDATE ON "IncentiveLedgerEntry"
FOR EACH ROW
EXECUTE FUNCTION incentive_ledger_reject_mutation();

DROP TRIGGER IF EXISTS incentive_ledger_no_delete ON "IncentiveLedgerEntry";
CREATE TRIGGER incentive_ledger_no_delete
BEFORE DELETE ON "IncentiveLedgerEntry"
FOR EACH ROW
EXECUTE FUNCTION incentive_ledger_reject_mutation();

-- VOLATILE is required. In READ COMMITTED, each statement inside a volatile
-- PL/pgSQL function takes its snapshot when that statement starts. The
-- SELECT FOR UPDATE waits until the other transaction commits and releases
-- the reward row. The SUM starts only after that wait, so its snapshot
-- includes the ledger rows that transaction committed. Debits for one reward
-- are serialized. Debits for different rewards lock different rows.
CREATE OR REPLACE FUNCTION incentive_ledger_guard_insert()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  locked_reward text;
  current_balance numeric(12,2);
BEGIN
  IF NEW."rewardId" IS NULL OR NEW."entryType" IS NULL OR NEW."idempotencyKey" IS NULL OR btrim(NEW."idempotencyKey") = '' THEN
    RAISE EXCEPTION 'IncentiveLedgerEntry requires a source and an idempotency key';
  END IF;

  IF NEW."entryType" = 'ISSUE' THEN
    IF NEW."amount" <= 0 THEN
      RAISE EXCEPTION 'IncentiveLedgerEntry ISSUE amount must be positive';
    END IF;
  ELSIF NEW."entryType" = 'REDEEM' THEN
    IF NEW."amount" >= 0 THEN
      RAISE EXCEPTION 'IncentiveLedgerEntry REDEEM amount must be negative';
    END IF;
  ELSIF NEW."entryType" = 'EXPIRE' THEN
    IF NEW."amount" >= 0 THEN
      RAISE EXCEPTION 'IncentiveLedgerEntry EXPIRE amount must be negative';
    END IF;
  ELSE
    RAISE EXCEPTION 'IncentiveLedgerEntry entry type is not supported';
  END IF;

  SELECT "id" INTO locked_reward
  FROM "IncentiveReward"
  WHERE "id" = NEW."rewardId"
  FOR UPDATE;

  IF locked_reward IS NULL THEN
    RAISE EXCEPTION 'IncentiveLedgerEntry reward is missing';
  END IF;

  SELECT COALESCE(SUM("amount"), 0) INTO current_balance
  FROM "IncentiveLedgerEntry"
  WHERE "rewardId" = NEW."rewardId";

  IF current_balance + NEW."amount" < 0 THEN
    RAISE EXCEPTION 'IncentiveLedgerEntry would make the balance negative';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS incentive_ledger_guard_insert ON "IncentiveLedgerEntry";
CREATE TRIGGER incentive_ledger_guard_insert
BEFORE INSERT ON "IncentiveLedgerEntry"
FOR EACH ROW
EXECUTE FUNCTION incentive_ledger_guard_insert();
