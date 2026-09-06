-- Migration: 002_rls_policies.sql
-- Enable Row Level Security on all sensitive tables and define policies

-- ============================================================
-- ROW LEVEL SECURITY - ENABLE RLS
-- ============================================================
alter table public.profiles enable row level security;
alter table public.profile_photos enable row level security;
alter table public.user_interests enable row level security;
alter table public.user_settings enable row level security;
alter table public.preferences enable row level security;
alter table public.likes enable row level security;
alter table public.passes enable row level security;
alter table public.matches enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.notifications enable row level security;
alter table public.plans enable row level security;
alter table public.plan_participants enable row level security;
alter table public.favorite_places enable row level security;
alter table public.crossed_paths enable row level security;
alter table public.referrals enable row level security;
alter table public.referral_events enable row level security;
alter table public.verification_requests enable row level security;
alter table public.moderation_events enable row level security;

-- ============================================================
-- PROFILES POLICIES
-- ============================================================
-- Users can read public profiles (city, photo_verified, etc.) but not raw location
create policy "profiles are visible to authenticated users"
    on public.profiles
    for select
    using (auth.uid() is not null);

-- Users can only update their own profile (excluding admin-managed fields)
create policy "users can update own profile"
    on public.profiles
    for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- Users can insert their own profile
create policy "users can insert own profile"
    on public.profiles
    for insert
    with check (auth.uid() = id);

-- No deletes allowed for users (admin only)
-- Users cannot set verification_status, trust_score, moderation_status

-- ============================================================
-- PROFILE PHOTOS POLICIES
-- ============================================================
create policy "users can read approved photos"
    on public.profile_photos
    for select
    using (
        moderation_status = 'approved'
        or user_id = auth.uid()
    );

create policy "users can upload own photos"
    on public.profile_photos
    for insert
    with check (auth.uid() = user_id);

create policy "users can update own photos metadata"
    on public.profile_photos
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "users can delete own photos"
    on public.profile_photos
    for delete
    using (auth.uid() = user_id);

-- ============================================================
-- USER INTERESTS POLICIES
-- ============================================================
create policy "users can read own interests"
    on public.user_interests
    for select
    using (auth.uid() = user_id);

create policy "users can manage own interests"
    on public.user_interests
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ============================================================
-- USER SETTINGS POLICIES
-- ============================================================
create policy "users can manage own settings"
    on public.user_settings
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ============================================================
-- PREFERENCES POLICIES
-- ============================================================
create policy "users can manage own preferences"
    on public.preferences
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = id);

-- ============================================================
-- LIKES POLICIES
-- ============================================================
create policy "users can read likes sent or received"
    on public.likes
    for select
    using (liker_id = auth.uid() or liked_id = auth.uid());

create policy "users can create likes for themselves"
    on public.likes
    for insert
    with check (liker_id = auth.uid());

create policy "users can delete their own likes"
    on public.likes
    for delete
    using (liker_id = auth.uid());

-- ============================================================
-- PASSES POLICIES
-- ============================================================
create policy "users can manage own passes"
    on public.passes
    for all
    using (user_id = auth.uid())
    with check (auth.uid() = user_id);

-- ============================================================
-- MATCHES POLICIES
-- ============================================================
create policy "users can read matches they are part of"
    on public.matches
    for select
    using (user_a_id = auth.uid() or user_b_id = auth.uid());

-- Matches are created by the database trigger, not directly by users
-- No INSERT/UPDATE/DELETE for regular users

-- ============================================================
-- CONVERSATIONS POLICIES
-- ============================================================
create policy "users can read conversations they participate in"
    on public.conversations
    for select
    using (
        match_id in (
            select id from public.matches
            where user_a_id = auth.uid() or user_b_id = auth.uid()
        )
    );

-- ============================================================
-- CONVERSATION MEMBERS POLICIES
-- ============================================================
create policy "users can manage own conversation membership"
    on public.conversation_members
    for select
    using (user_id = auth.uid());

-- ============================================================
-- MESSAGES POLICIES
-- ============================================================
create policy "users can read messages in their conversations"
    on public.messages
    for select
    using (
        conversation_id in (
            select cm.conversation_id
            from public.conversation_members cm
            where cm.user_id = auth.uid()
        )
    );

create policy "users can send messages to their conversations"
    on public.messages
    for insert
    with check (
        sender_id = auth.uid()
        and conversation_id in (
            select cm.conversation_id
            from public.conversation_members cm
            where cm.user_id = auth.uid()
        )
    );

create policy "users can update their own messages"
    on public.messages
    for update
    using (sender_id = auth.uid())
    with check (sender_id = auth.uid());

create policy "users can delete their own messages"
    on public.messages
    for delete
    using (sender_id = auth.uid());

-- ============================================================
-- BLOCKS POLICIES
-- ============================================================
create policy "users can manage own blocks"
    on public.blocks
    for all
    using (blocker_id = auth.uid())
    with check (auth.uid() = blocker_id);

create policy "users can read blocks involving them"
    on public.blocks
    for select
    using (blocker_id = auth.uid() or blocked_id = auth.uid());

-- ============================================================
-- REPORTS POLICIES
-- ============================================================
create policy "users can create reports"
    on public.reports
    for insert
    with check (reporter_id = auth.uid());

create policy "users can read reports they created"
    on public.reports
    for select
    using (reporter_id = auth.uid());

-- Reports are not modifiable by users after creation
-- Only moderators (via service role) can update

-- ============================================================
-- NOTIFICATIONS POLICIES
-- ============================================================
create policy "users can read own notifications"
    on public.notifications
    for select
    using (user_id = auth.uid());

create policy "users can mark own notifications as read"
    on public.notifications
    for update
    using (user_id = auth.uid())
    with check (auth.uid() = user_id);

-- ============================================================
-- PLANS POLICIES
-- ============================================================
create policy "public plans are visible to authenticated users"
    on public.plans
    for select
    using (auth.uid() is not null);

create policy "users can manage own plans"
    on public.plans
    for insert
    with check (creator_id = auth.uid());

create policy "users can update own plans"
    on public.plans
    for update
    using (auth.uid() = creator_id)
    with check (auth.uid() = creator_id);

create policy "users can delete own plans"
    on public.plans
    for delete
    using (auth.uid() = creator_id);

-- ============================================================
-- PLAN PARTICIPANTS POLICIES
-- ============================================================
create policy "users can read plans they participate in"
    on public.plan_participants
    for select
    using (
        plan_id in (
            select id from public.plans
            where creator_id = auth.uid()
        )
        or user_id = auth.uid()
    );

create policy "users can join plans"
    on public.plan_participants
    for insert
    with check (auth.uid() = user_id);

create policy "users can leave plans"
    on public.plan_participants
    for delete
    using (auth.uid() = user_id);

-- ============================================================
-- FAVORITE PLACES POLICIES
-- ============================================================
create policy "users can manage own favorite places"
    on public.favorite_places
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ============================================================
-- CROSSED PATHS POLICIES
-- ============================================================
-- Crossed paths is internal - no direct user access
-- Views will be used for display

-- ============================================================
-- REFERRALS POLICIES
-- ============================================================
create policy "users can read referrals they are part of"
    on public.referrals
    for select
    using (referrer_id = auth.uid() or referee_id = auth.uid());

create policy "users can create referrals for themselves as referrer"
    on public.referrals
    for insert
    with check (referrer_id = auth.uid());

-- ============================================================
-- REFERRAL EVENTS POLICIES
-- ============================================================
create policy "users can read referral events for their referrals"
    on public.referral_events
    for select
    using (
        referral_id in (
            select id from public.referrals
            where referrer_id = auth.uid() or referee_id = auth.uid()
        )
    );

-- ============================================================
-- VERIFICATION REQUESTS POLICIES
-- ============================================================
create policy "users can read own verification requests"
    on public.verification_requests
    for select
    using (user_id = auth.uid());

create policy "users can create verification requests"
    on public.verification_requests
    for insert
    with check (auth.uid() = user_id);

-- Users cannot update verification status directly

-- ============================================================
-- MODERATION EVENTS POLICIES
-- ============================================================
-- Only accessible by service role / moderators
-- No direct user policies
