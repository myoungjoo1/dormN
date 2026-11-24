-- Persist only the minimum GPS verification progress.
-- Raw coordinates and accuracy values are intentionally not stored.

BEGIN;

CREATE TABLE dormn_private.location_verifications (
    user_id UUID PRIMARY KEY
        REFERENCES public.users(id)
        ON DELETE CASCADE,

    verification_date DATE,
    status VARCHAR(30) NOT NULL DEFAULT 'NOT_STARTED'
        CHECK (
            status IN (
                'NOT_STARTED',
                'IN_PROGRESS',
                'COMPLETED',
                'OUT_OF_RANGE',
                'EXPIRED'
            )
        ),

    valid_check_count INTEGER NOT NULL DEFAULT 0
        CHECK (valid_check_count >= 0),

    first_valid_at TIMESTAMPTZ,
    last_valid_at TIMESTAMPTZ,
    last_check_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

REVOKE ALL ON TABLE dormn_private.location_verifications
    FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE dormn_private.location_verifications
    TO postgres;

COMMIT;
