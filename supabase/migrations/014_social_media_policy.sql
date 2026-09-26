-- Migration: 014_social_media_policy.sql
-- Social media ID policy enforcement for profile bios and content.
--
-- This migration adds:
-- 1. A function to detect social media identifiers in text
-- 2. A trigger to prevent prohibited social media content in profile bios
-- 3. Server-side validation for profile updates

-- ============================================================
-- 1. SOCIAL MEDIA DETECTION FUNCTION
-- ============================================================
create or replace function public.detect_social_media_in_text(p_text text)
returns jsonb
language plpgsql
as $$
declare
    result jsonb;
    lower_text text;
    patterns text[];
    matches text[];
begin
    if p_text is null or trim(p_text) = '' then
        return jsonb_build_object('detected', false, 'matches', array[]::text[]);
    end if;

    lower_text := lower(p_text);

    -- Normalize common obfuscation patterns
    -- Remove zero-width characters and other obfuscation
    lower_text := regexp_replace(lower_text, '[\u200B-\u200F\u2028-\u202F\u205F\u3000]', '', 'g');
    
    -- Handle leetspeak and common substitutions
    lower_text := regexp_replace(lower_text, '0', 'o', 'g');
    lower_text := regexp_replace(lower_text, '3', 'e', 'g');
    lower_text := regexp_replace(lower_text, '1', 'i', 'g');
    lower_text := regexp_replace(lower_text, '4', 'a', 'g');
    lower_text := regexp_replace(lower_text, '5', 's', 'g');
    lower_text := regexp_replace(lower_text, '7', 't', 'g');

    patterns := array[
        -- Instagram patterns
        'instagr[ae]m',
        'instagram\.com',
        '@[a-z0-9_]{3,30}\s*(?:instagram|insta)',
        
        -- Telegram patterns
        't\.me/',
        'telegram\.com',
        '@[a-z0-9_]{3,30}\s*(?:telegram|telegramm|tg)',
        
        -- Twitter/X patterns
        'twitter\.com',
        'x\.com/',
        '@[a-z0-9_]{3,30}\s*(?:twitter|twit|x\s*app)',
        
        -- Snapchat
        'snapchat\.com',
        '@[a-z0-9_]{3,30}\s*(?:snapchat|snap)',
        
        -- TikTok
        'tiktok\.com',
        '@[a-z0-9_]{3,30}\s*(?:tiktok|tik\s*tok)',
        
        -- Discord
        'discord\.com',
        'discord\.gg',
        
        -- Generic social contact patterns
        '(?:dm|contact|message)\s*(?:me|on)\s*(?:@|at\s*)',
        '(?:add|follow|friend)\s*(?:me|on)\s*(?:@|at\s*)',
        
        -- URL patterns
        'https?://(?:www\.)?(?:instagram|telegram|snapchat|twitter|x\.com|tiktok|discord)'
    ];

    matches := array[]::text[];
    
    for i in 1..array_length(patterns, 1) loop
        if lower_text ~ patterns[i] then
            matches := array_append(matches, patterns[i]);
        end if;
    end loop;

    if array_length(matches, 1) is not null and array_length(matches, 1) > 0 then
        return jsonb_build_object(
            'detected', true,
            'matches', matches,
            'normalized_text_sample', substring(lower_text from 1 for 100)
        );
    end if;

    return jsonb_build_object('detected', false, 'matches', array[]::text[]);
end;
$$;

-- ============================================================
-- 2. PROFILE BIO VALIDATION TRIGGER
-- ============================================================
create or replace function public.validate_profile_bio()
returns trigger
language plpgsql
as $$
declare
    detection_result jsonb;
    is_social_media boolean;
begin
    -- Only validate non-empty bios
    if new.bio is not null and trim(new.bio) <> '' then
        detection_result := public.detect_social_media_in_text(new.bio);
        is_social_media := (detection_result->>'detected')::boolean;
        
        if is_social_media then
            -- For high-confidence matches, reject the update
            -- For medium-confidence (first offense), we could flag for review
            -- but for launch, we reject to enforce policy
            raise exception 'Profile bio contains external social media identifiers or links. Weekend allows phone contact information but does not allow external social media handles or links in profiles.';
        end if;
    end if;
    
    return new;
end;
$$;

-- Drop existing trigger if it exists
drop trigger if exists validate_profile_bio_trigger on public.profiles;

-- Create the trigger for INSERT and UPDATE
create trigger validate_profile_bio_trigger
    before insert or update of bio on public.profiles
    for each row
    execute function public.validate_profile_bio();

-- ============================================================
-- 3. GRANTS
-- ============================================================
-- Allow authenticated users to call the detection function
-- (for client-side preview/validation)
grant execute on function public.detect_social_media_in_text to authenticated;

-- ============================================================
-- 4. COMMENTS
-- ============================================================
comment on function public.detect_social_media_in_text is
'Analyzes text for social media identifiers (Instagram, Telegram, Twitter/X, Snapchat, TikTok, Discord, etc.). Returns JSON with detection status and matched patterns.';

comment on trigger validate_profile_bio_trigger on public.profiles is
'Blocks profile bio updates containing external social media identifiers. Phone numbers are allowed per Weekend policy.';
