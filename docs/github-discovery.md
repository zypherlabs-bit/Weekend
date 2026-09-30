# GitHub Discovery

**Purpose:** Document the GitHub repository discovery strategy — description, topics, and SEO settings that make Weekend discoverable to the right audience.

## Repository description

**Recommended:**

> Weekend — free, open-source dating app for Android. Location-based discovery, real-time chat, weekend plans. Flutter + Supabase (MIT).

This communicates:
- **Free** — addresses "free dating app" search intent
- **Open source** — addresses "open source dating app" search intent
- **Android** — addresses "dating app for Android" search intent
- **Location-based discovery** — addresses "location-based dating app" search intent
- **Real-time chat** — addresses "real time dating chat" search intent
- **Flutter + Supabase** — addresses developer/contributor search intent
- **MIT** — clarifies license

## GitHub topics

**Recommended topic set:**

```text
dating-app
dating-app-android
free-dating-app
location-based
open-source
android
android-app
flutter
dart
supabase
supabase-edge-functions
postgis
realtime-chat
social-discovery
matchmaking
privacy
passkey
mobile-app
```

### Rules followed

- Only topics genuinely relevant to the repository are used.
- No competitor names (Tinder, Bumble, Hinge, etc.) are included as topics.
- No misleading or clickbait tags.
- Topics cover: product category (dating-app), platform (android), pricing (free), tech stack (flutter, dart, supabase, postgis), features (location-based, realtime-chat), and values (open-source, privacy).

## Search intent coverage

| Search query | How the page addresses it |
|---|---|
| "free dating app" | H1, FAQ, "Free dating on Weekend" section |
| "free dating app for Android" | H1, badges, download section |
| "dating app for Android" | H1, badges, download section |
| "location-based dating" | Dedicated discovery section, SEO keywords |
| "location-based dating app" | Dedicated discovery section, SEO keywords |
| "meet people nearby" | "Why Weekend?" benefits, discovery section |
| "nearby dating app" | Discovery section, FAQ |
| "local dating app" | Discovery section, FAQ |
| "open source dating app" | H1, "Open source" section, SEO keywords |
| "privacy focused dating app" | "Privacy & Safety" section, FAQ |
| "social discovery app" | Discovery section, tagline |
| "real time dating chat" | Messaging section, FAQ |

## Social preview

**Recommended social preview image:** `docs/assets/weekend-logo.jpg`

A clean image showing the Weekend logo and tagline for link unfurls on social media.

## Social links

- **Repository:** https://github.com/zypherlabs-bit/Weekend
- **Releases:** https://github.com/zypherlabs-bit/Weekend/releases
- **Issues:** https://github.com/zypherlabs-bit/Weekend/issues
- **Analytics dashboard:** https://zypherlabs-bit.github.io/Weekend/analytics/

## SEO enforcement

The `tool/seo_audit.py` script validates:
- Single H1 containing key product terms
- Required sections in correct order
- Keyword presence (free dating app, location-based, open source, etc.)
- Keyword stuffing thresholds
- FAQ question count (>= 10)
- Download version match with pubspec.yaml
- Internal link resolution
- Image existence, alt text, and size limits
- Duplicate image detection
- `docs/SEO.md` documentation existence

Run before every release PR:

```bash
python tool/seo_audit.py            # static checks
python tool/seo_audit.py --online   # + verify GitHub latest release matches pubspec
```