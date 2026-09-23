-- Migration: 013_plans_rls_recursion_fix.sql
-- Weekend Plans were completely broken: the `plans` SELECT policy checked
-- membership in `plan_participants`, whose own SELECT policy checked
-- ownership in `plans`. Postgres detects this mutual recursion and fails
-- every query with 42P17 "infinite recursion detected in policy for
-- relation plan_participants".
--
-- Break the cycle with SECURITY DEFINER helpers (they run without RLS on the
-- tables they read), then express both policies purely in terms of them.

-- ============================================================
-- 1. VISIBILITY HELPERS (bypass RLS internally)
-- ============================================================
create or replace function public.is_plan_participant(
    p_plan_id uuid,
    p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.plan_participants pp
        where pp.plan_id = p_plan_id
          and pp.user_id = p_user_id
    );
$$;

create or replace function public.is_plan_creator(
    p_plan_id uuid,
    p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.plans p
        where p.id = p_plan_id
          and p.creator_id = p_user_id
    );
$$;

create or replace function public.is_plan_public(p_plan_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select p.privacy_level = 'public' from public.plans p where p.id = p_plan_id),
        false
    );
$$;

grant execute on function public.is_plan_participant(uuid, uuid) to authenticated;
grant execute on function public.is_plan_creator(uuid, uuid) to authenticated;
grant execute on function public.is_plan_public(uuid) to authenticated;

-- ============================================================
-- 2. PLANS: visibility without touching plan_participants directly
-- ============================================================
drop policy if exists "plans are visible per privacy level" on public.plans;
drop policy if exists "public plans are visible to authenticated users" on public.plans;

create policy "plans are visible per privacy level"
    on public.plans
    for select
    using (
        auth.uid() is not null
        and (
            privacy_level = 'public'
            or creator_id = auth.uid()
            or public.is_plan_participant(id, auth.uid())
        )
    );

-- ============================================================
-- 3. PLAN PARTICIPANTS: readable by the participant or the creator
-- ============================================================
drop policy if exists "users can read plans they participate in" on public.plan_participants;

create policy "users can read plans they participate in"
    on public.plan_participants
    for select
    using (
        user_id = auth.uid()
        or public.is_plan_creator(plan_id, auth.uid())
    );

-- ============================================================
-- 4. JOINING: public plans, or your own plan (recursion-free)
-- ============================================================
drop policy if exists "users can join plans" on public.plan_participants;

create policy "users can join plans"
    on public.plan_participants
    for insert
    with check (
        auth.uid() = user_id
        and (
            public.is_plan_public(plan_id)
            or public.is_plan_creator(plan_id, auth.uid())
        )
    );