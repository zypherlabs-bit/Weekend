-- Migration: 028_adult_only_enforcement.sql
-- Weekend is an adults-only dating service. This migration makes that a
-- DATABASE invariant rather than a client-side date-picker restriction.
--
-- WHY THIS EXISTS (audited 2026-10-02)
-- -----------------------------------
-- The only age check in the product was `ProfileRepository.updateDateOfBirth`
-- (lib/repositories/profile_repository.dart), which throws a Dart
-- ProfileSaveException. That is not a security control: the Supabase anon key
-- ships inside the APK and is public by design, and migration 006 explicitly
-- grants the authenticated role UPDATE on `date_of_birth`:
--
--     grant update (
--         display_name, date_of_birth, gender, bio, city, locality, country,
--         relationship_intent, occupation, education, favorite_music, ideal_weekend,
--         latitude, longitude, referral_code
--     ) on public.profiles to authenticated;
--
-- So any minor could bypass the app entirely and either
--   (a) PATCH /rest/v1/profiles?id=eq.<self> {"date_of_birth":"2015-01-01"}
--       -> an under-18 profile row, or
--   (b) POST /auth/v1/signup with data.date_of_birth, where `handle_new_user`
--       (migration 020) copies the client-controlled value straight into
--       profiles with no validation at all.
--
-- Discovery filtering is NOT a substitute for this. `search_profiles` only
-- applies its age range when the caller sets one (`not v_age_set or ...`), so a
-- caller that sends no range gets every profile back; and its lower bound is
-- `coalesce(p_age_min, 18)`, so a caller passing 13 widens the floor to 13.
-- Worse, neither `record_like` nor `check_mutual_like` checked age at all, so
-- a minor could match and message.
--
-- This migration closes all of it at the database, so it holds for every
-- client: the Flutter app, the REST API, a direct RPC call, or a hand-written
-- curl request.

-- ============================================================
-- 1. Audit existing rows (never aborts the migration)
-- ============================================================
-- `ALTER TABLE ... ADD CONSTRAINT` fails outright if any existing row violates
-- it, which would leave the database partly migrated. Surface the offending
-- rows as a NOTICE first so they can be triaged deliberately rather than
-- discovered as a failed deploy.
do $$
declare
    v_minor   integer;
    v_unknown integer;
begin
    select count(*) into v_minor
    from public.profiles
    where date_of_birth is not null
      and date_part('years', age(date_of_birth))::int < 18;

    select count(*) into v_unknown
    from public.profiles
    where date_of_birth is null;

    raise notice
        'Weekend age audit: % profile(s) under 18, % profile(s) with no date of birth.',
        v_minor, v_unknown;
end;
$$;

-- ============================================================
-- 2. Reject an under-18 date of birth, on every write path
-- ============================================================
-- A CHECK constraint cannot be used: it would have to call now()/age(), which
-- are not IMMUTABLE, and Postgres rejects non-immutable expressions in CHECK.
-- A BEFORE trigger is the correct instrument, and it also yields a clear error
-- message instead of a constraint-violation string.
--
-- The trigger is deliberately NOT bypassed for the service role, unlike
-- `protect_profile_columns` (005). There is no legitimate backend pipeline that
-- needs to write a minor's date of birth, and exempting service_role would
-- reopen the hole for any future Edge Function that trusted its input.
create or replace function public.enforce_adult_date_of_birth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_age integer;
begin
    -- NULL is permitted at signup. The wizard collects the date of birth in
    -- step 2, but `handle_new_user` runs during INSERT, so a user who has not
    -- reached that step yet legitimately has no value. Profiles with a NULL
    -- date of birth are NOT discoverable and cannot match (sections 4 and 6),
    -- so an unknown age fails CLOSED rather than open.
    if new.date_of_birth is null then
        return new;
    end if;

    v_age := date_part('years', age(new.date_of_birth))::int;

    if v_age < 18 then
        raise exception
            'Weekend is for adults 18 and over. This date of birth is not eligible.'
            using errcode = 'check_violation';
    end if;

    -- An implausible date (a typo, or a deliberate attempt to look "not a
    -- child") would otherwise satisfy the >= 18 floor forever.
    if v_age > 120 then
        raise exception
            'That date of birth is not plausible.'
            using errcode = 'check_violation';
    end if;

    return new;
end;
$$;

drop trigger if exists on_adult_date_of_birth on public.profiles;
create trigger on_adult_date_of_birth
    before insert or update of date_of_birth on public.profiles
    for each row
    execute function public.enforce_adult_date_of_birth();

-- ============================================================
-- 3. Stop the date of birth being changed to dodge the check
-- ============================================================
-- The task calls out "do not allow users to arbitrarily change DOB after
-- account creation". Being able to change it at all after the profile is
-- publicly visible would also let someone re-enter the dating surface with a
-- different age than the one other users were shown.
--
-- The date of birth is therefore frozen once the profile becomes visible to
-- other people (`dating_profile_activated`, maintained by the photo-count
-- trigger from 023). Before that it stays editable, which is what lets the
-- signup wizard correct a mistake.
create or replace function public.freeze_date_of_birth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.date_of_birth is distinct from old.date_of_birth
       and old.dating_profile_activated then
        raise exception
            'Your date of birth can no longer be changed once your profile is active.'
            using errcode = 'check_violation';
    end if;

    return new;
end;
$$;

drop trigger if exists on_freeze_date_of_birth on public.profiles;
create trigger on_freeze_date_of_birth
    before update of date_of_birth on public.profiles
    for each row
    execute function public.freeze_date_of_birth();

-- ============================================================
-- 4. A minor must not be able to match or message
-- ============================================================
-- Blocking writes to `date_of_birth` (sections 2-3) stops a minor from
-- existing in a discoverable state, but the requirement is stronger than
-- "cannot be discovered": a minor must not be able to MATCH or open a
-- conversation. That has to be checked where the match is created, because
-- that is the moment a conversation becomes reachable.
--
-- `record_like` is the only path that creates a like (026 collapsed the
-- client's direct writes onto it), and `check_mutual_like` (003) is the
-- trigger that turns two likes into a match. Both are covered below.
--
-- The predicate is "age is PROVEN to be at least 18", so unknown fails closed:
-- a NULL date of birth cannot match either. That is deliberately stricter than
-- discovery, because the cost of a false negative here (a user who has not
-- finished onboarding cannot match yet) is far lower than the cost of a false
-- positive (a minor reaches chat).
create or replace function public.is_adult_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.profiles p
        where p.id = p_user_id
          and p.deleted_at is null
          and p.date_of_birth is not null
          and date_part('years', age(p.date_of_birth))::int >= 18
    );
$$;

revoke all on function public.is_adult_user(uuid) from public, anon;
grant execute on function public.is_adult_user(uuid) to authenticated;

create or replace function public.record_like(
    p_target_id uuid,
    p_is_stand_out boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_match_id uuid;
    v_conversation_id uuid;
    v_blocked boolean;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    if p_target_id is null or p_target_id = v_me then
        raise exception 'Invalid target';
    end if;

    -- Both parties must be proven adults. Checking only the liker would still
    -- let a minor be liked by an adult and receive a match notification.
    if not public.is_adult_user(v_me)
       or not public.is_adult_user(p_target_id) then
        raise exception 'Only verified adults can use Weekend matching.'
            using errcode = 'check_violation';
    end if;

    select exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_me and b.blocked_id = p_target_id)
           or (b.blocker_id = p_target_id and b.blocked_id = v_me)
    ) into v_blocked;

    if v_blocked then
        raise exception 'You cannot like this user';
    end if;

    if exists (
        select 1 from public.auth_user_state s
        where s.user_id = p_target_id and s.deleted_at is not null
    ) then
        raise exception 'Profile unavailable';
    end if;

    delete from public.passes where user_id = v_me and target_id = p_target_id;

    insert into public.likes (liker_id, liked_id, is_stand_out)
    values (v_me, p_target_id, p_is_stand_out)
    on conflict (liker_id, liked_id) do update
        set is_stand_out = public.likes.is_stand_out or excluded.is_stand_out;

    select m.id into v_match_id
    from public.matches m
    where (m.user_a_id, m.user_b_id) in (
        (least(v_me, p_target_id), greatest(v_me, p_target_id))
    )
    limit 1;

    if v_match_id is not null then
        select c.id into v_conversation_id
        from public.conversations c
        where c.match_id = v_match_id
        limit 1;
    end if;

    return jsonb_build_object(
        'liked', true,
        'is_stand_out', p_is_stand_out,
        'matched', v_match_id is not null,
        'match_id', v_match_id,
        'conversation_id', v_conversation_id
    );
end;
$$;

revoke all on function public.record_like(uuid, boolean) from public, anon;
grant execute on function public.record_like(uuid, boolean) to authenticated;

-- ============================================================
-- 5. Belt-and-braces on the match trigger itself
-- ============================================================
-- `check_mutual_like` fires AFTER INSERT on `likes`. Even though section 4
-- makes it unreachable via record_like, this trigger also fires for any future
-- write path. An exception here aborts the originating INSERT (and therefore
-- the transaction), which is exactly what is wanted: no match row, no
-- conversation row, no messageable surface.
--
-- The body below is 003's verbatim, with an adult check at the top.
create or replace function public.check_mutual_like()
returns trigger as $$
declare
    existing_like record;
    existing_match record;
    match_id uuid;
begin
    if not (public.is_adult_user(new.liker_id)
            and public.is_adult_user(new.liked_id)) then
        raise exception 'Only verified adults can match on Weekend.'
            using errcode = 'check_violation';
    end if;

    select * into existing_like
    from public.likes
    where liker_id = new.liked_id and liked_id = new.liker_id;

    if existing_like.id is not null then
        select * into existing_match
        from public.matches
        where (user_a_id = new.liker_id and user_b_id = new.liked_id)
           or (user_a_id = new.liked_id and user_b_id = new.liker_id);

        if existing_match.id is null then
            if new.liker_id < new.liked_id then
                match_id := gen_random_uuid();
                insert into public.matches (id, user_a_id, user_b_id, created_at)
                values (match_id, new.liker_id, new.liked_id, now());
            else
                match_id := gen_random_uuid();
                insert into public.matches (id, user_a_id, user_b_id, created_at)
                values (match_id, new.liked_id, new.liker_id, now());
            end if;

            insert into public.conversations (id, match_id, created_at, updated_at)
            values (gen_random_uuid(), match_id, now(), now())
            returning id into match_id;

            insert into public.conversation_members (conversation_id, user_id, joined_at)
            values (match_id, new.liker_id, now());
            insert into public.conversation_members (conversation_id, user_id, joined_at)
            values (match_id, new.liked_id, now());

            insert into public.referral_events (referral_id, event_type, created_at)
            select r.id, 'successful', now()
            from public.referrals r
            where r.referee_id = new.liked_id
              and r.status = 'pending'
            on conflict do nothing;

            update public.referrals
            set status = 'successful',
                credited_at = now()
            where referee_id = new.liked_id
              and status = 'pending';
        end if;
    end if;

    return new;
end;
$$ language plpgsql security definer;

set search_path = public;

-- ============================================================
-- 6. search_profiles must not return minors or unknown-age profiles
-- ============================================================
-- 023's age clause is
--
--     and ( not v_age_set or (p.date_of_birth is not null and ... between ...) )
--
-- which is correct for the range the caller asked for, but it is NOT an
-- adult-only guarantee:
--
--   1. When the caller sends no age range (`not v_age_set`) the clause
--      short-circuits to TRUE, so every profile is returned regardless of age.
--   2. Its lower bound is `coalesce(p_age_min, 18)`, so a caller passing
--      p_age_min = 13 widens the floor to 13 and minors appear.
--
-- The function below is migration 023's byte-for-byte EXCEPT for two
-- additive changes: an unconditional ADULT FLOOR, and greatest(...) so the
-- caller's lower bound can never widen past 18. Every other filter (gender,
-- interests with ALL semantics, languages, lifestyle, relationship intent,
-- city, PostGIS distance, blocks/passes/likes/reports/matches exclusions,
-- match_score ordering and bounded pagination) is unchanged.
create or replace function public.search_profiles(
    p_user_id uuid,
    p_genders text[] default null,
    p_age_min integer default null,
    p_age_max integer default null,
    p_max_distance_km double precision default null,
    p_city text default null,
    p_relationship_intents text[] default null,
    p_interests text[] default null,
    p_languages text[] default null,
    p_lifestyle jsonb default null,
    p_location_mode text default 'nearby',
    p_page integer default 1,
    p_page_size integer default 20
)
returns table (
    profile_id uuid,
    display_name text,
    age integer,
    gender text,
    bio text,
    city text,
    distance_km double precision,
    is_photo_verified boolean,
    trust_score integer,
    primary_photo_path text,
    interests text[],
    relationship_intent text,
    last_active_at timestamptz,
    match_score numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_viewer_lat double precision;
    v_viewer_lon double precision;
    v_offset integer;
    v_limit integer;
    -- An explicit "did the caller set this" test. `array_length(.., 1) > 0`
    -- means "no restriction", which is distinct from "restricted to empty".
    v_gender_set boolean := p_genders is not null
                          and array_length(p_genders, 1) > 0;
    v_age_set boolean := p_age_min is not null or p_age_max is not null;
    v_distance_set boolean := p_max_distance_km is not null;
    v_city_set boolean := nullif(btrim(coalesce(p_city, '')), '') is not null;
    v_intent_set boolean := p_relationship_intents is not null
                          and array_length(p_relationship_intents, 1) > 0;
    v_interests_set boolean := p_interests is not null
                           and array_length(p_interests, 1) > 0;
    v_languages_set boolean := p_languages is not null
                            and array_length(p_languages, 1) > 0;
    v_lifestyle_set boolean := p_lifestyle is not null
                             and p_lifestyle <> '{}'::jsonb;
    -- 'global' is the only mode that ignores distance entirely.
    v_enforce_distance boolean := v_distance_set
                                and coalesce(p_location_mode, 'nearby') <> 'global';
begin
    -- Only a user may search on their own behalf. Without this the function
    -- is a full-database enumeration oracle with arbitrary filters.
    perform public.assert_self(p_user_id);

    v_limit := least(greatest(coalesce(p_page_size, 20), 1), 50);
    v_offset := (greatest(coalesce(p_page, 1), 1) - 1) * v_limit;

    -- Read the viewer's own coordinates ONCE, server-side. They are never
    -- returned to the client and are never selectable via PostgREST.
    select latitude, longitude into v_viewer_lat, v_viewer_lon
    from public.profiles where id = p_user_id;

    return query
    with eligible as (
        select
            p.id as pid,
            p.display_name,
            case when p.date_of_birth is not null
                 then date_part('years', age(p.date_of_birth))::int
                 else null
            end as computed_age,
            p.gender,
            p.bio,
            p.city,
            p.latitude,
            p.longitude,
            p.relationship_intent,
            p.is_photo_verified,
            p.trust_score,
            p.last_active_at,
            (select array_agg(i.name)
               from public.user_interests ui
               join public.interests i on i.id = ui.interest_id
              where ui.user_id = p.id) as interest_names
        from public.profiles p
        where
            -- --- identity / lifecycle -----------------------------------
            p.id <> p_user_id
            and p.is_active
            and p.deleted_at is null
            and p.dating_profile_activated
            and p.display_name is not null
            and length(btrim(p.display_name)) > 0

            -- --- ADULT FLOOR (migration 028) --------------------------
            -- Unconditional, so it holds even when the caller sends no age
            -- range at all. 023's clause below short-circuits to TRUE when
            -- v_age_set is false, which returned every profile regardless of
            -- age. Unknown age is EXCLUDED, never assumed to be in range.
            and p.date_of_birth is not null
            and date_part('years', age(p.date_of_birth))::int >= 18
            -- --- HARD: gender -------------------------------------------
            -- An unknown gender can never be proven to satisfy the filter,
            -- so it is excluded whenever the caller restricted gender.
            and (
                not v_gender_set
                or (p.gender is not null and p.gender = any(p_genders))
            )

            -- --- HARD: age ----------------------------------------------
            -- An unknown age is NOT treated as "in range". Falling back to a
            -- default age here is what previously let 20-year-olds into a
            -- 35+ result set.
            and (
                not v_age_set
                or (
                    p.date_of_birth is not null
                    and date_part('years', age(p.date_of_birth))::int
                        >= greatest(coalesce(p_age_min, 18), 18)
                    and date_part('years', age(p.date_of_birth))::int
                        <= coalesce(p_age_max, 120)
                )
            )

            -- --- HARD: relationship intent -------------------------------
            and (
                not v_intent_set
                or (
                    p.relationship_intent is not null
                    and p.relationship_intent = any(p_relationship_intents)
                )
            )

            -- --- HARD: city (case-insensitive exact match) ---------------
            and (
                not v_city_set
                or (p.city is not null
                    and lower(btrim(p.city)) = lower(btrim(p_city)))
            )

            -- --- HARD: distance (PostGIS) -------------------------------
            and (
                not v_enforce_distance
                or (
                    v_viewer_lat is not null
                    and v_viewer_lon is not null
                    and p.latitude is not null
                    and p.longitude is not null
                    -- ST_Point(longitude, latitude): argument order matters.
                    and ST_DWithin(
                        ST_Point(p.longitude, p.latitude)::geography,
                        ST_Point(v_viewer_lon, v_viewer_lat)::geography,
                        p_max_distance_km * 1000
                    )
                )
            )

            -- --- HARD: interests ----------------------------------------
            -- ALL requested interests must be present, not "some of them".
            and (
                not v_interests_set
                or not exists (
                    select 1
                    from unnest(p_interests) as required(name)
                    where not exists (
                        select 1
                        from public.user_interests ui
                        join public.interests i on i.id = ui.interest_id
                        where ui.user_id = p.id
                          and lower(i.name) = lower(required.name)
                    )
                )
            )

            -- --- HARD: languages ----------------------------------------
            and (
                not v_languages_set
                or not exists (
                    select 1
                    from unnest(p_languages) as required(lang)
                    where not exists (
                        select 1
                        from unnest(coalesce(p.languages, '{}'::text[]))
                             as owned(lang)
                        where lower(owned.lang) = lower(required.lang)
                    )
                )
            )

            -- --- HARD: lifestyle ----------------------------------------
            -- Each key present in the caller's object must match exactly.
            and (
                not v_lifestyle_set
                or not exists (
                    select 1
                    from jsonb_each_text(p_lifestyle) as want(key, value)
                    where want.value is not null
                      and want.value <> ''
                      and case want.key
                            when 'smoking' then p.smoking
                            when 'drinking' then p.drinking
                            when 'exercise' then p.exercise
                            when 'pets' then p.pets
                            when 'children' then p.children
                            else null
                          end is distinct from want.value
                )
            )

            -- --- exclusions ---------------------------------------------
            and not exists (select 1 from public.blocks
                             where blocker_id = p_user_id and blocked_id = p.id)
            and not exists (select 1 from public.blocks
                             where blocker_id = p.id and blocked_id = p_user_id)
            and not exists (select 1 from public.passes
                             where user_id = p_user_id and target_id = p.id)
            and not exists (select 1 from public.likes
                             where liker_id = p_user_id and liked_id = p.id)
            and not exists (select 1 from public.reports
                             where reporter_id = p_user_id and reported_id = p.id)
            and not exists (
                select 1 from public.matches
                where (user_a_id = p_user_id and user_b_id = p.id)
                   or (user_b_id = p_user_id and user_a_id = p.id)
            )
    ),
    scored as (
        select
            e.*,
            case
                when e.latitude is not null and e.longitude is not null
                 and v_viewer_lat is not null and v_viewer_lon is not null
                then round((
                    ST_Distance(
                        ST_Point(e.longitude, e.latitude)::geography,
                        ST_Point(v_viewer_lon, v_viewer_lat)::geography
                    ) / 1000
                )::numeric, 1)::double precision
                else null
            end as real_distance_km,
            -- SOFT ranking only; never consulted for eligibility.
            (case when e.trust_score is not null then e.trust_score * 0.2 else 0 end)
            + (case when e.is_photo_verified then 15 else 0 end)
            + (case when e.last_active_at > now() - interval '14 days'
                   then 10 else 0 end)
            + (case
                when exists (
                    select 1
                    from public.user_interests mine
                    join public.interests mi on mi.id = mine.interest_id
                    join public.user_interests theirs on theirs.user_id = e.pid
                    join public.interests ti on ti.id = theirs.interest_id
                    where mine.user_id = p_user_id
                      and lower(mi.name) = lower(ti.name)
                ) then 20 else 0 end)
        ) as soft_score
        from eligible e
    )
    select
        s.pid as profile_id,
        s.display_name,
        s.computed_age as age,
        s.gender,
        s.bio,
        s.city,
        s.real_distance_km as distance_km,
        s.is_photo_verified,
        s.trust_score,
        (select storage_path from public.profile_photos pp
          where pp.user_id = s.pid and pp.moderation_status = 'approved'
          order by pp.is_primary desc, pp.created_at asc
          limit 1) as primary_photo_path,
        s.interest_names as interests,
        s.relationship_intent,
        s.last_active_at,
        round(s.soft_score::numeric, 2) as match_score
    from scored s
    order by s.soft_score desc,
             s.real_distance_km asc nulls last,
             s.last_active_at desc nulls last
    limit v_limit offset v_offset;
end;
$$;

revoke all on function public.search_profiles(
    uuid, text[], integer, integer, double precision, text, text[], text[],
    text[], jsonb, text, integer, integer
) from public, anon;
grant execute on function public.search_profiles(
    uuid, text[], integer, integer, double precision, text, text[], text[],
    text[], jsonb, text, integer, integer
) to authenticated;
