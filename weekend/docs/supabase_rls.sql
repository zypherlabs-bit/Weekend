-- ==========================================================
-- WEEKEND — SUPABASE ROW LEVEL SECURITY (RLS) POLICIES
-- Strict user data privacy: no location leakage, no private chat snooping
-- ==========================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekend_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekend_plan_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;

-- 1. PROFILES POLICIES
CREATE POLICY "Public profiles are readable by authenticated users"
ON public.profiles FOR SELECT TO authenticated USING (
    id NOT IN (SELECT blocked_id FROM public.blocks WHERE blocker_id = auth.uid())
);

CREATE POLICY "Users can update their own profile"
ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);

-- 2. LIKES & MATCHES POLICIES
CREATE POLICY "Users can insert their own likes"
ON public.likes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view matches they are part of"
ON public.matches FOR SELECT TO authenticated USING (
    auth.uid() = user_a_id OR auth.uid() = user_b_id
);

-- 3. MESSAGES POLICIES
CREATE POLICY "Users can read messages in their conversations"
ON public.messages FOR SELECT TO authenticated USING (
    EXISTS (
        SELECT 1 FROM public.conversations c
        JOIN public.matches m ON c.match_id = m.id
        WHERE c.id = messages.conversation_id
        AND (m.user_a_id = auth.uid() OR m.user_b_id = auth.uid())
    )
);

CREATE POLICY "Users can send messages to their conversations"
ON public.messages FOR INSERT TO authenticated WITH CHECK (
    auth.uid() = sender_id
);

-- 4. WEEKEND PLANS POLICIES
CREATE POLICY "Weekend plans are visible to authenticated users"
ON public.weekend_plans FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can create weekend plans"
ON public.weekend_plans FOR INSERT TO authenticated WITH CHECK (auth.uid() = creator_id);

-- 5. BLOCKS & REPORTS POLICIES
CREATE POLICY "Users can manage their own blocks"
ON public.blocks FOR ALL TO authenticated USING (auth.uid() = blocker_id);

CREATE POLICY "Users can submit reports"
ON public.reports FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id);
