-- Migration: 019_weekend_availability_shape_fix.sql
-- Fix a live-blocking bug in migration 016's shape CHECK.
--
-- 016 guarded the JSON shape of `user_settings.weekend_availability` with
--
--     weekend_availability <@ '{"Saturday": true, "Sunday": true}'::jsonb
--
-- JSONB containment on objects compares **values**, not just keys. The client
-- writes {"Saturday": true, "Sunday": false} (an unselected day is `false`),
-- and {"Sunday": false} is NOT contained in {"Sunday": true}
-- (`'{"Sunday":false}'::jsonb <@ '{"Sunday":true}'::jsonb` -> false), so every
-- Edit Profile save that carried an availability map was rejected with
--     23514 new row for relation "user_settings" violates check constraint
--     "user_settings_weekend_availability_shape"
-- which surfaced in the app as "unable to proceed".
--
-- The replacement validates the *key set* and the value types instead:
--   * only 'Saturday' / 'Sunday' keys are allowed (`v - keys = '{}'`)
--   * each present value must be a JSON boolean
-- No subquery is used, so this is a legal CHECK expression.
--
-- Nothing is loosened beyond removing the false rejection: a payload with an
-- unexpected key or a non-boolean value is still refused.

create or replace function public.weekend_availability_is_valid(v jsonb)
returns boolean
language sql
immutable
as $$
    select v is null
        or (
            jsonb_typeof(v) = 'object'
            -- key set: nothing left after removing the two allowed keys
            and (v - 'Saturday' - 'Sunday') = '{}'::jsonb
            -- value types: booleans only, when present
            and (
                v -> 'Saturday' is null
                or jsonb_typeof(v -> 'Saturday') = 'boolean'
            )
            and (
                v -> 'Sunday' is null
                or jsonb_typeof(v -> 'Sunday') = 'boolean'
            )
        );
$$;

alter table public.user_settings
    drop constraint if exists user_settings_weekend_availability_shape;

alter table public.user_settings
    add constraint user_settings_weekend_availability_shape
    check (public.weekend_availability_is_valid(weekend_availability));

comment on function public.weekend_availability_is_valid(jsonb) is
'Validates the weekend_availability JSON shape: object, keys limited to Saturday/Sunday, boolean values (or absent).';
