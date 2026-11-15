-- DormN protected settlement account storage.
--
-- Keep this schema out of Supabase Dashboard > API > Exposed schemas.
-- The FastAPI PostgreSQL connection uses the postgres database role through
-- Supabase Pooler; anon/authenticated and PUBLIC receive no privileges.
--
-- Apply after the existing users and posts tables exist.

BEGIN;

CREATE SCHEMA dormn_private;

CREATE TABLE dormn_private.user_settlement_accounts (
    user_id UUID PRIMARY KEY
        REFERENCES public.users(id)
        ON DELETE CASCADE,

    bank_name VARCHAR(100) NOT NULL,

    -- VARCHAR preserves leading zeroes and does not impose bank-specific rules.
    account_number VARCHAR(100) NOT NULL,

    account_holder_name VARCHAR(100) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT user_settlement_accounts_values_check
    CHECK (
        bank_name = btrim(bank_name)
        AND bank_name <> ''
        AND account_number = btrim(account_number)
        AND account_number <> ''
        AND account_holder_name = btrim(account_holder_name)
        AND account_holder_name <> ''
    )
);

CREATE TABLE dormn_private.post_settlement_accounts (
    -- The primary key makes one account snapshot possible per transaction.
    post_id BIGINT PRIMARY KEY
        REFERENCES public.posts(id)
        ON DELETE CASCADE,

    bank_name VARCHAR(100) NOT NULL,
    account_number VARCHAR(100) NOT NULL,
    account_holder_name VARCHAR(100) NOT NULL,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT post_settlement_accounts_values_check
    CHECK (
        bank_name = btrim(bank_name)
        AND bank_name <> ''
        AND account_number = btrim(account_number)
        AND account_number <> ''
        AND account_holder_name = btrim(account_holder_name)
        AND account_holder_name <> ''
    )
);

-- Defense in depth: the custom schema is not usable by Data API roles or
-- PUBLIC. The Pooler username is not used as a database role name here.
REVOKE ALL ON SCHEMA dormn_private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA dormn_private FROM PUBLIC, anon, authenticated;

GRANT USAGE ON SCHEMA dormn_private
    TO postgres;

GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE
        dormn_private.user_settlement_accounts,
        dormn_private.post_settlement_accounts
    TO postgres;

COMMIT;
