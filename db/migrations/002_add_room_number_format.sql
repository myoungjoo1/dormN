BEGIN;

ALTER TABLE public.users
    ADD CONSTRAINT users_room_number_format_check
    CHECK (room_number ~ '^[0-9]{3,4}-[1-9][0-9]*$');

COMMIT;
