-- Migration: 015_signup_profile_fields.sql
-- Sign-up wizard support:
--   1. Fix the relationship-intent CHECK introduced by 001: 'Friendsships'
--      was a typo, so the corrected label the app now shows would be
--      rejected on insert/update.
--   2. handle_new_user carries sign-up wizard answers (date_of_birth, gender,
--      relationship_intent) from auth.raw_user_meta_data into the new
--      profile row, so they survive the email-confirmation round trip that
--      created the old "wizard answers lost / form reset" regression.

-- 1. Constraint typo: migrate existing rows, then correct the allowed set.
update public.profiles
   set relationship_intent = 'New people & Friendships'
 where relationship_intent = 'New people & Friendsships';

alter table public.profiles
    drop constraint if exists profiles_relationship_intent_check;

alter table public.profiles
    add constraint profiles_relationship_intent_check
    check (relationship_intent in (
        'Dating',
        'Long-term relationship',
        'New people & Friendships',
        'Dating & Weekend Plans'
    ));

-- 2. Same side effects as 003 (profiles + user_settings + preferences rows),
--    plus the wizard answers from signup metadata. Metadata keys are snake
--    case to match the column names; missing values become NULL, which every
--    constraint accepts (all three columns are nullable).
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (
        id,
        display_name,
        date_of_birth,
        gender,
        relationship_intent,
        created_at,
        updated_at,
        last_active_at
    ) values (
        new.id,
        new.raw_user_meta_data->>'full_name',
        nullif(new.raw_user_meta_data->>'date_of_birth', '')::date,
        nullif(new.raw_user_meta_data->>'gender', ''),
        nullif(new.raw_user_meta_data->>'relationship_intent', ''),
        now(),
        now(),
        now()
    );

    insert into public.user_settings (user_id) values (new.id);
    insert into public.preferences (user_id) values (new.id);

    return new;
end;
$$ language plpgsql security definer;
