-- Migration: 001_initial_schema.sql
-- Weekend Supabase Database Schema - Core tables, RLS, and constraints

-- ============================================================
-- EXTENSIONS
-- ============================================================
create extension if not exists "uuid-ossp";
create extension if not exists "postgis" schema if not exists public;

-- ============================================================
-- PROFILES TABLE
-- ============================================================
create table public.profiles (
    id uuid primary key references auth.users on delete cascade,
    display_name text,
    date_of_birth date,
    gender text check (gender in ('Man', 'Woman', 'Non-binary', 'Prefer not to say')),
    bio text default '',
    city text,
    locality text,
    country text,
    latitude double precision,
    longitude double precision,
    relationship_intent text check (relationship_intent in ('Dating', 'Long-term relationship', 'New people & Friendsships', 'Dating & Weekend Plans')),
    verification_status text check (verification_status in ('unverified', 'pending', 'verified', 'rejected')) default 'unverified',
    trust_score integer check (trust_score >= 0 and trust_score <= 100) default 50,
    profile_completion integer check (profile_completion >= 0 and profile_completion <= 100) default 0,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    last_active_at timestamp with time zone default now()
);

-- ============================================================
-- PROFILE PHOTOS TABLE
-- ============================================================
create table public.profile_photos (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles on delete cascade,
    photo_url text not null,
    thumbnail_url text,
    is_primary boolean default false,
    storage_path text,
    width integer,
    height integer,
    file_size_bytes bigint,
    mime_type text,
    moderation_status text check (moderation_status in ('pending', 'approved', 'rejected')) default 'pending',
    created_at timestamp with time zone default now()
);

-- ============================================================
-- INTERESTS TABLE (master list)
-- ============================================================
create table public.interests (
    id uuid primary key default uuid_generate_v4(),
    name text unique not null,
    created_at timestamp with time zone default now()
);

-- ============================================================
-- USER INTERESTS (junction table)
-- ============================================================
create table public.user_interests (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles on delete cascade,
    interest_id uuid references public.interests on delete cascade,
    created_at timestamp with time zone default now(),
    unique (user_id, interest_id)
);

-- ============================================================
-- USER SETTINGS TABLE
-- ============================================================
create table public.user_settings (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid unique references public.profiles on delete cascade,
    show_me_in_search boolean default true,
    discovery_emails_enabled boolean default true,
    push_notifications_enabled boolean default true,
    language text default 'en',
    theme_preference text check (theme_preference in ('dark', 'light', 'system')) default 'dark',
    max_distance_km integer default 25 check (max_distance_km >= 5 and max_distance_km <= 200),
    preferred_genders text[],
    preferred_age_min integer default 18 check (preferred_age_min >= 18),
    preferred_age_max integer default 65 check (preferred_age_max >= preferred_age_min),
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

-- ============================================================
-- PREFERENCES TABLE (discovery preferences)
-- ============================================================
create table public.preferences (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid unique references public.profiles on delete cascade,
    show_me_to text check (show_me_to in ('everyone', 'verified_only', 'none')) default 'everyone',
    discovery_mode text check (discovery_mode in ('for_you', 'nearby', 'crossed_paths', 'interests', 'weekend_plans', 'global')) default 'for_you',
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

-- ============================================================
-- LIKES TABLE
-- ============================================================
create table public.likes (
    id uuid primary key default uuid_generate_v4(),
    liker_id uuid references public.profiles on delete cascade,
    liked_id uuid references public.profiles on delete cascade,
    is_stand_out boolean default false,
    created_at timestamp with time zone default now(),
    unique (liker_id, liked_id),
    check (liker_id <> liked_id)
);

-- ============================================================
-- PASSES TABLE (user passed on someone)
-- ============================================================
create table public.passes (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles on delete cascade,
    target_id uuid references public.profiles on delete cascade,
    created_at timestamp with time zone default now(),
    unique (user_id, target_id),
    check (user_id <> target_id)
);

-- ============================================================
-- MATCHES TABLE
-- ============================================================
create table public.matches (
    id uuid primary key default uuid_generate_v4(),
    user_a_id uuid references public.profiles on delete cascade,
    user_b_id uuid references public.profiles on delete cascade,
    created_at timestamp with time zone default now(),
    unique (user_a_id, user_b_id),
    check (user_a_id <> user_b_id)
);

-- ============================================================
-- CONVERSATIONS TABLE
-- ============================================================
create table public.conversations (
    id uuid primary key default uuid_generate_v4(),
    match_id uuid references public.matches on delete cascade,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

-- ============================================================
-- CONVERSATION MEMBERS TABLE
-- ============================================================
create table public.conversation_members (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid references public.conversations on delete cascade,
    user_id uuid references public.profiles on delete cascade,
    joined_at timestamp with time zone default now(),
    last_read_at timestamp with time zone,
    unread_count integer default 0,
    unique (conversation_id, user_id)
);

-- ============================================================
-- MESSAGES TABLE
-- ============================================================
create table public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid references public.conversations on delete cascade,
    sender_id uuid references public.profiles on delete cascade,
    text text,
    translated_text text,
    target_language text,
    is_translated boolean default false,
    is_read boolean default false,
    created_at timestamp with time zone default now()
);

-- ============================================================
-- BLOCKS TABLE
-- ============================================================
create table public.blocks (
    id uuid primary key default uuid_generate_v4(),
    blocker_id uuid references public.profiles on delete cascade,
    blocked_id uuid references public.profiles on delete cascade,
    created_at timestamp with time zone default now(),
    unique (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);

-- ============================================================
-- REPORTS TABLE
-- ============================================================
create table public.reports (
    id uuid primary key default uuid_generate_v4(),
    reporter_id uuid references public.profiles on delete cascade,
    reported_id uuid references public.profiles on delete cascade,
    report_type text check (report_type in ('profile', 'photo', 'message', 'scam', 'harassment', 'inappropriate_content', 'impersonation')),
    target_id text,
    description text,
    status text check (status in ('pending', 'reviewed', 'resolved', 'dismissed')) default 'pending',
    resolved_by uuid,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone default now(),
    check (reporter_id <> reported_id)
);

-- ============================================================
-- NOTIFICATIONS TABLE
-- ============================================================
create table public.notifications (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles on delete cascade,
    type text check (type in ('new_match', 'new_message', 'referral_success', 'plan_invitation', 'safety_alert', 'verification_result')),
    title text,
    body text,
    data jsonb,
    is_read boolean default false,
    created_at timestamp with time zone default now()
);

-- ============================================================
-- PLANS TABLE (Weekend Plans)
-- ============================================================
create table public.plans (
    id uuid primary key default uuid_generate_v4(),
    creator_id uuid references public.profiles on delete cascade,
    title text,
    category text check (category in ('Coffee', 'Dinner', 'Hiking', 'Concert', 'Movies', 'Travel', 'Sports', 'Art', 'Gaming', 'Events')),
    venue text,
    time text,
    description text,
    privacy_level text check (privacy_level in ('public', 'friends_only', 'private')) default 'public',
    latitude double precision,
    longitude double precision,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

-- ============================================================
-- PLAN PARTICIPANTS TABLE
-- ============================================================
create table public.plan_participants (
    id uuid primary key default uuid_generate_v4(),
    plan_id uuid references public.plans on delete cascade,
    user_id uuid references public.profiles on delete cascade,
    joined_at timestamp with time zone default now(),
    unique (plan_id, user_id)
);

-- ============================================================
-- FAVORITE PLACES TABLE
-- ============================================================
create table public.favorite_places (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles on delete cascade,
    name text,
    latitude double precision,
    longitude double precision,
    created_at timestamp with time zone default now(),
    unique (user_id, name)
);

-- ============================================================
-- CROSSED PATHS TABLE
-- ============================================================
create table public.crossed_paths (
    id uuid primary key default uuid_generate_v4(),
    user_a_id uuid references public.profiles on delete cascade,
    user_b_id uuid references public.profiles on delete cascade,
    first_crossed_at timestamp with time zone default now(),
    last_crossed_at timestamp with time zone default now(),
    cross_count integer default 1,
    unique (user_a_id, user_b_id)
);

-- ============================================================
-- REFERRALS TABLE
-- ============================================================
create table public.referrals (
    id uuid primary key default uuid_generate_v4(),
    referrer_id uuid references public.profiles on delete cascade,
    referee_id uuid references public.profiles on delete cascade,
    referral_code text,
    status text check (status in ('pending', 'successful', 'invalid')) default 'pending',
    credited_at timestamp with time zone,
    created_at timestamp with time zone default now(),
    unique (referrer_id, referee_id),
    check (referrer_id <> referee_id)
);

-- ============================================================
-- REFERRAL EVENTS TABLE
-- ============================================================
create table public.referral_events (
    id uuid primary key default uuid_generate_v4(),
    referral_id uuid references public.referrals on delete cascade,
    event_type text check (event_type in ('invited', 'registered', 'email_verified', 'profile_completed', 'successful')),
    created_at timestamp with time zone default now()
);

-- ============================================================
-- VERIFICATION REQUESTS TABLE
-- ============================================================
create table public.verification_requests (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles on delete cascade,
    photo_id uuid references public.profile_photos on delete set null,
    status text check (status in ('pending', 'approved', 'rejected')) default 'pending',
    confidence_score integer check (confidence_score >= 0 and confidence_score <= 100),
    detection_signals jsonb,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    created_at timestamp with time zone default now()
);

-- ============================================================
-- MODERATION EVENTS TABLE
-- ============================================================
create table public.moderation_events (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles on delete cascade,
    report_id uuid references public.reports on delete set null,
    action text check (action in ('warn', 'suspend', 'delete', 'no_action')),
    reason text,
    performed_by uuid,
    created_at timestamp with time zone default now()
);

-- ============================================================
-- INDEXES
-- ============================================================

-- Profile indexes
create index idx_profiles_city on public.profiles(city);
create index idx_profiles_gender on public.profiles(gender);
create index idx_profiles_relationship_intent on public.profiles(relationship_intent);
create index idx_profiles_verification_status on public.profiles(verification_status);
create index idx_profiles_last_active on public.profiles(last_active_at desc);
create index idx_profiles_location on public.profiles using gist (
    ST_Point(longitude, latitude)::geography
) where latitude is not null and longitude is not null;

-- Photo indexes
create index idx_profile_photos_user_id on public.profile_photos(user_id);
create index idx_profile_photos_moderation on public.profile_photos(moderation_status);
create index idx_profile_photos_primary on public.profile_photos(user_id) where is_primary = true;

-- Likes / Passes indexes
create index idx_likes_liker on public.likes(liker_id);
create index idx_likes_liked on public.likes(liked_id);
create index idx_passes_user on public.passes(user_id);

-- Matches indexes
create index idx_matches_user_a on public.matches(user_a_id);
create index idx_matches_user_b on public.matches(user_b_id);

-- Conversations / Messages indexes
create index idx_conversations_match on public.conversations(match_id);
create index idx_conversation_members_user on public.conversation_members(user_id);
create index idx_messages_conversation on public.messages(conversation_id);
create index idx_messages_created_at on public.messages(created_at);

-- Blocks / Reports indexes
create index idx_blocks_blocker on public.blocks(blocker_id);
create index idx_blocks_blocked on public.blocks(blocked_id);
create index idx_reports_reporter on public.reports(reporter_id);
create index idx_reports_reported on public.reports(reported_id);

-- Plans indexes
create index idx_plans_creator on public.plans(creator_id);
create index idx_plan_participants_plan on public.plan_participants(plan_id);

-- Referrals indexes
create index idx_referrals_referrer on public.referrals(referrer_id);
create index idx_referrals_referree on public.referrals(referree_id);
