# GitHub User Journey

**Purpose:** Map the path a search visitor takes from landing on the repository page to downloading and trying Weekend, identifying friction points along the way.

## Visitor persona

A person searching for "free dating app", "free dating app for Android", or
"dating app to meet people nearby" lands on the Weekend GitHub page. They are
not looking to read code — they want to understand the product and try it.

## The journey map

```text
SEARCH
  ↓
GITHUB PAGE (README.md)
  ↓
HERO — "Weekend — Free Dating App for Android · Open Source"
  ↓
SCREENSHOTS — real app captures + labelled brand artwork
  ↓
WHY WEEKEND? — benefit comparison table
  ↓
HOW IT WORKS — 5-step onboarding flow
  ↓
FEATURES — location-based discovery, matching, chat, plans, safety, etc.
  ↓
FREE DATING — no paywall, how it's funded
  ↓
DOWNLOAD — APK link, version, checksum, install instructions
  ↓
FAQ — answers common questions
  ↓
INSTALL APK → OPEN APP → SIGN UP
```

## Friction points identified

| Step | Friction | Resolution |
|------|----------|------------|
| Hero | Visitor may not immediately see it's free or Android-only | H1 reads "Free Dating App for Android"; badges reinforce platform |
| Screenshots | Some images are brand artwork, not app captures | Honesty note explicitly labels real captures vs. artwork; roadmap item for full screenshots |
| Free positioning | "Free" could mean freemium | "Free dating on Weekend" section explicitly states no subscription, no paid likes, explains ad funding |
| Download | Visitor needs APK + checksum verification | Direct download links + SHA-256 checksum + step-by-step install instructions |
| After install | Visitor needs a Supabase backend for full features | Offline demo mode explained; clear "backend not configured" messaging |
| Technical docs | Developer content should not overwhelm end users | Developer documentation is below the fold in the README |
| Known limitations | Honesty about gaps builds trust | Known limitations section is transparent about passkeys, voice intros, FCM, etc. |

## Key design decisions

1. **User-first content first.** The README lead is a human-readable product description, not technical boilerplate.
2. **Honest screenshots.** Real captures are labelled as such; artwork is clearly marked. No fake app screenshots.
3. **Clear CTAs.** Download and source links are prominent in the hero and table of contents.
4. **Truthful free model.** The "Free dating on Weekend" table explains exactly what is free and how the app is funded.
5. **Transparent limitations.** Known limitations and roadmap are upfront — nothing is overstated.
6. **Mobile-friendly.** The README uses responsive image layouts and scannable sections.

## Success criteria

- A visitor searching "free dating app" understands Weekend within 5 seconds.
- The download CTA is visible above the fold.
- Screenshots provide visual proof of the product.
- The FAQ answers real questions a searcher would have.
- The page does not contain fake statistics, testimonials, or unsupported claims.
- No competitor names are used as SEO bait.