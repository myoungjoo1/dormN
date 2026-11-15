-- DormN post image upload metadata.
--
-- Apply this migration only after the existing users and posts tables exist.
-- This file does not create a Supabase Storage bucket or upload files.

BEGIN;

CREATE TABLE public.post_image_uploads (
    id UUID PRIMARY KEY,

    user_id UUID NOT NULL
        REFERENCES public.users(id)
        ON DELETE CASCADE,

    storage_path TEXT NOT NULL UNIQUE
        CHECK (storage_path <> ''),

    content_type VARCHAR(32) NOT NULL
        CHECK (
            content_type IN (
                'image/jpeg',
                'image/png',
                'image/webp'
            )
        ),

    size_bytes INTEGER NOT NULL
        CHECK (size_bytes > 0 AND size_bytes <= 5242880),

    expires_at TIMESTAMPTZ NOT NULL,

    claimed_post_id BIGINT UNIQUE
        REFERENCES public.posts(id)
        ON DELETE RESTRICT,

    claimed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (expires_at > created_at),

    -- A claimed upload must always identify both its post and claim time.
    CHECK (
        (claimed_post_id IS NULL AND claimed_at IS NULL)
        OR
        (claimed_post_id IS NOT NULL AND claimed_at IS NOT NULL)
    )
);

-- Cleanup scans only unclaimed uploads by expiry time.
CREATE INDEX post_image_uploads_unclaimed_expiry_idx
    ON public.post_image_uploads (expires_at)
    WHERE claimed_post_id IS NULL;

COMMIT;
