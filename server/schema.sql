-- Fei schema for PostgreSQL. Mirrors the app's local SQLite schema (drift
-- schema v2), so rows sync across without reshaping. When a drift migration
-- changes lib/data/tables.dart, change this file to match.
-- test/drift/fei/server_schema_test.dart fails until the two agree.
--
-- * ids are UUID v7s generated on the device, so the server never assigns them.
-- * updated_at is bumped on every write; deleted_at marks soft deletes.
-- * Foreign keys are deferred to commit, so one sync batch can insert rows in
--   any order (a transaction before the recurring series it came from).

CREATE TABLE category_groups (
  id          uuid        PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz,
  name        text        NOT NULL,
  kind        text        NOT NULL CHECK (kind IN ('income', 'expense')),
  sort_order  integer     NOT NULL DEFAULT 0
);

CREATE TABLE categories (
  id          uuid        PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz,
  group_id    uuid        NOT NULL REFERENCES category_groups (id) DEFERRABLE INITIALLY DEFERRED,
  name        text        NOT NULL,
  kind        text        NOT NULL CHECK (kind IN ('income', 'expense')),
  emoji       text        NOT NULL DEFAULT '🏷️',
  color       bigint      NOT NULL DEFAULT 4287137928, -- ARGB (0xFF888888); too big for integer
  is_fixed    boolean     NOT NULL DEFAULT false,      -- left out of "flexible" spending (e.g. Rent)
  sort_order  integer     NOT NULL DEFAULT 0
);

CREATE TABLE recurring_series (
  id                 uuid        PRIMARY KEY,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz,
  kind               text        NOT NULL CHECK (kind IN ('income', 'expense')),
  amount_cents       bigint      NOT NULL CHECK (amount_cents >= 0),
  category_id        uuid        NOT NULL REFERENCES categories (id) DEFERRABLE INITIALLY DEFERRED,
  merchant           text,
  notes              text,
  frequency          text        NOT NULL CHECK (frequency IN ('weekly', 'biweekly', 'monthly', 'quarterly', 'yearly')),
  start_date         date        NOT NULL,
  end_date           date,
  generated_through  date        -- last date occurrences were created for
);

CREATE TABLE transactions (
  id            uuid        PRIMARY KEY,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz,
  kind          text        NOT NULL CHECK (kind IN ('income', 'expense')),
  amount_cents  bigint      NOT NULL CHECK (amount_cents >= 0), -- always positive; kind gives the direction
  date          date        NOT NULL,
  category_id   uuid        NOT NULL REFERENCES categories (id) DEFERRABLE INITIALLY DEFERRED,
  merchant      text,       -- the source on an income row; imports can leave it empty
  notes         text,
  recurring_id  uuid        REFERENCES recurring_series (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX idx_transactions_date ON transactions (date);
