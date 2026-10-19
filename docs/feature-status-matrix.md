# Weekend v2.7.0 — Feature Status Matrix (25-feature consolidated spec)

Verification bases:
- **A** = verified in code + automated tests (`flutter analyze` clean, 310/310 tests pass, migrations parse/contract-tested against `test/database_contract_test.dart`)
- **B** = verified in code but NOT verified against the live Supabase project (migrations 030–033 unapplied; no access token available at time of release)
- **C** = shipped as honest placeholder / deliberately held back

| # | Feature | Server | Client | Status | Note |
|---|---------|--------|--------|--------|------|
| 1 | Server-authoritative entitlements (`user_entitlements`, `system_free`) | 031 [B] | mirror + UI gates [A] | Implemented-B | All features free; no billing provider — entitlement integration is an abstraction layer only |
| 2 | Priority likes (server-computed weight) | 031/032 [B] | likes screen [A] | Implemented-B | weight computed in `record_like`; never accepted from client |
| 3 | Like notes / compliments (140 chars) | 032 [B] | note sheet [A] | Implemented-B | server validates length + social-media policy |
| 4 | 24 h match initiation windows | 032 [B] | banners/countdown [A] | Implemented-B | first message settles window server-side |
| 5 | Women-led initiation (hetero matching) | 032 [B] | UI chips [A] | Implemented-B | initiator rule in `check_mutual_like` + `enforce_message_rules` |
| 6 | Extend match (+24 h, once per participant, idempotent) | 032 [B] | Extend button [A] | Implemented-B | deadline returned by server call only |
| 7 | Rematch (once per 7 days, expired+messageless) | 032 [B] | Rematch button [A] | Implemented-B | fresh `record_like`; partner's like must be outstanding |
| 8 | Match list status chips | 032 (RPC output) [B] | MatchCard chips [A] | Implemented-B | derived only from server fields |
| 9 | Incognito mode | 031 privacy_mode [B] | privacy dialog [A] | Implemented-B | discovery suppression server-side |
| 10 | Snooze (with duration choice) | 031 [B] | privacy dialog [A] | Implemented-B | |
| 11 | Away status + away note | 031 [B] | chat banner + dialog [A] | Implemented-B | shown to connections only, while window active |
| 12 | Travel mode | 031 [B] | dialog + on-device geocoding [A] | Implemented-B | server rejects null coords; client requires lat/lon |
| 13 | Online-now consent toggle | 031 [B] | privacy dialog [A] | Implemented-B | |
| 14 | Spotlight activation window | 031 [B] | visibility dialog [A] | Implemented-B | server reasons + cooldowns, never client-decided |
| 15 | Photo impressions recording | 032 record_photo_impressions [B] | deck top card [A] | Implemented-B | once per photo per session, real impressions only |
| 16 | Photo insights (30 d) | 031 RPC [B] | visibility dialog [A] | Implemented-B | `sufficient_data=false` renders "Not enough data yet" |
| 17 | Surge (city activity surge) | 031 RPC [B] | home banner [A] | Implemented-B | server-aggregated state only |
| 18 | Opening moves (3 slots, 160 chars) | 032 table+RLS [B] | dialog editor [A] | Implemented-B | photo-linked prompts validated server-side |
| 19 | Selfie verification | existing EF + 031 status [B] | verification dialog [A] | Implemented-B | submits to `photo-verification` Edge Function |
| 20 | In-app support tickets | 033 [B] | support dialog [A] | Implemented-B | status transitions service-role only; 5/day limit |
| 21 | Explainable message risk flags | 033 trigger [B] | chat chips [A] | Implemented-B | message delivered regardless; no auto-ban |
| 22 | Unified discovery surface (`get_nearby_profiles` + `primary_photo_id`) | 031 [B] | discovery repository [A] | Implemented-B | 8-arg overload replaced (repo uses 9-arg latest) |
| 23 | Migration 029 hold-back | `migrations-held/` [A] | n/a | Held back (C) | deliberate; documented, never applied blindly |
| 24 | Documentation honesty pass | n/a | README/store-listing [A] | Complete-verified | artwork removed, signing identity + limits documented |
| 25 | Release signing identity | n/a | build.gradle key wiring [A] | Complete-verified | dedicated RSA-4096 keystore valid to 2054; fingerprint documented; CI builds are dev-key verification builds only |

## Honest bottom line
- Every feature is **implemented and enforced server-side in code** with contract tests, and the Flutter client gates all UI on confirmed server state — nothing in the UI fakes success.
- **Nothing in rows 1–22 has been exercised against the live Supabase database yet** (no access token at release time). Until `supabase db push` applies 030–033, the live backend continues serving the pre-033 surface; the 2.7.0 client degrades honestly to neutral states it was designed for (verified by the model-default tests).
- No live database, no transaction execution of 031–033, and no authenticated end-to-end run (signup/probe) was possible in this environment (no access token; Docker unavailable). These remain the next steps.
