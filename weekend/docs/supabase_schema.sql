-- ==========================================================
-- WEEKEND — SUPABASE POSTGRESQL DATABASE SCHEMA
-- Product: Weekend (Free, Open-Source Dating & Social Discovery)
-- Architecture: Supabase Only (PostgreSQL, Auth, Storage, Realtime, RLS)
-- ==========================================================

-- Enable PostGIS & UUID extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 1. PROFILES
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender VARCHAR(50) NOT NULL,
    city VARCHAR(100) NOT NULL,
    locality VARCHAR(100),
    bio TEXT,
    occupation VARCHAR(100),
    education VARCHAR(100),
    relationship_intent VARCHAR(100) DEFAULT 'Dating',
    weekend_status VARCHAR(100) DEFAULT 'Free for coffee ☕',
    opening_question VARCHAR(255) DEFAULT 'What is your perfect Sunday?',
    is_photo_verified BOOLEAN DEFAULT FALSE,
    trust_score INT DEFAULT 85 CHECK (trust_score BETWEEN 0 AND 100),
    risk_level VARCHAR(50) DEFAULT 'Low Risk',
    referral_code VARCHAR(50) UNIQUE,
    photos TEXT[] DEFAULT '{}',
    interests TEXT[] DEFAULT '{}',
    favorite_places TEXT[] DEFAULT '{}',
    languages TEXT[] DEFAULT '{}',
    voice_intro_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. PROFILE PHOTOS (With image optimization stages)
CREATE TABLE IF NOT EXISTS public.profile_photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    original_url TEXT NOT NULL,
    optimized_url TEXT NOT NULL,
    thumbnail_url TEXT NOT NULL,
    order_index INT DEFAULT 0,
    is_primary BOOLEAN DEFAULT FALSE,
    is_verified_human BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. PROFILE PROMPTS
CREATE TABLE IF NOT EXISTS public.profile_prompts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    prompt TEXT NOT NULL,
    answer TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. INTERESTS & PROFILE INTERESTS
CREATE TABLE IF NOT EXISTS public.interests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(100) UNIQUE NOT NULL,
    category VARCHAR(100) NOT NULL,
    icon_name VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS public.profile_interests (
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    interest_id UUID REFERENCES public.interests(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, interest_id)
);

-- 5. LIKES & PASSES
CREATE TABLE IF NOT EXISTS public.likes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    is_standout BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, target_user_id)
);

CREATE TABLE IF NOT EXISTS public.passes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, target_user_id)
);

-- 6. MATCHES
CREATE TABLE IF NOT EXISTS public.matches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_a_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    user_b_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    matched_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE (user_a_id, user_b_id)
);

-- 7. CONVERSATIONS & MESSAGES
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    translated_text TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. BLOCKS & REPORTS
CREATE TABLE IF NOT EXISTS public.blocks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blocker_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (blocker_id, blocked_id)
);

CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reported_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. PRIVACY-PRESERVING LOCATIONS & CROSSED PATHS
CREATE TABLE IF NOT EXISTS public.locations (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    city VARCHAR(100) NOT NULL,
    locality VARCHAR(100),
    geom GEOGRAPHY(Point, 4326),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.crossed_paths (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_a_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    user_b_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    mutual_area VARCHAR(150) NOT NULL,
    frequency_count INT DEFAULT 1,
    last_crossed_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. FAVORITE PLACES
CREATE TABLE IF NOT EXISTS public.favorite_places (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL, -- Cafe, Park, Bookstore, Museum, etc.
    locality VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. WEEKEND PLANS & PARTICIPANTS
CREATE TABLE IF NOT EXISTS public.weekend_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL, -- Coffee, Hiking, Dinner, Concert, Movie
    venue VARCHAR(150) NOT NULL,
    time VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.weekend_plan_participants (
    plan_id UUID REFERENCES public.weekend_plans(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (plan_id, user_id)
);

-- 12. REFERRAL PROGRAM
CREATE TABLE IF NOT EXISTS public.referral_codes (
    code VARCHAR(50) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.referrals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referral_code VARCHAR(50) NOT NULL,
    referred_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status VARCHAR(50) DEFAULT 'activated',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for maximum performance
CREATE INDEX IF NOT EXISTS idx_profiles_city ON public.profiles(city);
CREATE INDEX IF NOT EXISTS idx_likes_user_target ON public.likes(user_id, target_user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_weekend_plans_category ON public.weekend_plans(category);
