# Weekend UI/UX Design Research

**Date:** 2026-11-01
**Project:** Weekend (Flutter 3.41.9 / Dart 3.11.5, Supabase backend)

## 1. Research Method

Studied interface patterns of leading modern mobile applications (Tinder, Bumble, Hinge,
Instagram, Snapchat, Airbnb, Spotify, Pinterest, and other high-quality dating/lifestyle
apps) for layout, visual hierarchy, navigation, typography, card design, animation,
spacing, and interaction. Findings distilled into an original Weekend design language — no
proprietary assets, branding, or exact screens copied.

## 2. Key Patterns Adopted

### Navigation
- Single bottom navigation bar with primary destinations (Discover, Matches/Explore,
  Chat, Plans, Profile). Selected state uses filled icon + brand colour; unselected uses
  outline icons + muted colour.
- Back navigation always available on Android (system back + app bar back arrow).
- Frosted/glass navigation plate for depth without heavy shadows.

### Discovery / Swipe Cards
- Full-bleed profile photo card with bottom gradient scrim holding name, age, distance.
- Action row: Pass (x), Super-like (star), Like (heart) with circular, colour-coded buttons.
- Swipe thresholds with snap-back, depth stack of upcoming cards, NOPE/LIKE overlays.
- Rounded card radius (20-26 px), subtle border, no hard drop shadows.

### Profile Detail
- Hero photo gallery with pager dots and pinch-to-zoom.
- Sectioned content: bio, interests (chips), lifestyle, location, verification badge.
- Sticky bottom action bar (Like / Pass / Message).

### Chat / Messaging
- Rounded message bubbles: sent (brand gradient), received (surface variant).
- Timestamps grouped, read receipts where supported, typing indicator.
- Floating input bar with rounded text field and circular send button.
- Empty conversation state with prompt to start.

### Lists (Matches, Notifications, Settings)
- Rounded list containers (18-24 px) with hairline borders.
- Section headers with small caps / uppercase labels.
- Icon + title + chevron rows; destructive actions in error colour.

### Forms (Auth, Profile Edit)
- Rounded input fields (14-18 px), inline validation, helper text.
- Primary button full-width, 54 px height, 16-20 px radius, loading spinner in place.
- Disabled state clearly de-emphasised.

### Empty / Loading / Error States
- Centred icon-in-glass tile, title, subtitle, optional action button.
- Skeleton/shimmer placeholders for lists; never blank screens.
- Honest error states with retry.

### Premium / Monetisation
- Weekend is free; no fake subscription prices or purchase confirmations. Any premium
  surfaces must be backed by the real billing provider.

## 3. Weekend Design Direction

- Sleek, minimal, premium, elegant, clean, smooth.
- Restrained palette centred on the coral to violet ribbon mark.
- Glass/frosted surfaces for depth; atmospheric gradient backdrop.
- Consistent corner radii, spacing scale, motion tokens.
- Light + Dark mode, both fully themed, persisted via theme provider.
- Accessibility: 44-48 dp touch targets, semantic labels, contrast-safe text.

## 4. Anti-Patterns Avoided

- No sharp rectangular buttons.
- No excessive gradients/shadows/borders.
- No fake data, fake online status, fake read receipts.
- No decorative non-functional buttons.
- No cluttered screens; generous whitespace.

## 5. Inspiration Sources (not copied)

Tinder (swipe deck), Bumble (profile detail + verification), Hinge (prompts/interests),
Instagram (image gallery + chat), Snapchat (camera-first, badges), Airbnb (cards + filters),
Spotify (dark surfaces, typography), Pinterest (masonry grids, empty states).
