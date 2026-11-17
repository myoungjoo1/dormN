BEGIN;

ALTER TABLE public.participations
ADD COLUMN pickup_completed_at TIMESTAMPTZ NULL;

COMMIT;
