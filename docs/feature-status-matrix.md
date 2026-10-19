# Weekend v2.8.1 — Feature Status Matrix (25-feature consolidated spec)

Verification bases:

- **A** = verified in code + automated tests (`flutter analyze` clean, 312/312
  tests pass, migrations parse- and contract-tested against
  `test/database_contract_test.dart`).
- **L** = additionally exercised against the **live** Supabase project
  (`ocypgybqfushqfzisnvs`) on 2026-10-19: the client's exact RPC call was made
  as an authenticated user and the server answered. Raw responses are in
  `tool/_auth_probe_results.json`; the run is described in
  [live-backend-audit-2026-10-19.md](live-backend-audit-2026-10-19.md).
- **S** = the server object exists on the live project (migration applied; table
  / function / policy present and RLS enabled, confirmed by
  `tool/live_schema_verify.py`) but that feature's behaviour was **not** driven
  end to end.
- **C** = shipped as an honest placeholder / deliberately held back.

Allowed statuses: `Implemented-Live`, `Implemented-Live (partial)`,
`Implemented-Live (schema)`, `Implemented-B`, `Complete-verified`,
`Held back (C)`, `NOT VERIFIED`.

- `Implemented-Live` — server **and** client behaviour observed live.
- `Implemented-Live (partial)` — the live call was exercised but only a
  guard / empty-result path was observed; the full behaviour remains `S`.
- `Implemented-Live (schema)` — present and RLS-enabled live; behaviour not
  exercised.

| # | Feature | Server | Client | Status | Note |
|---|---------|--------|--------|--------|------|
| 1 | Server-authoritative entitlements (`user_entitlements`, `system_free`) | 031 [L] | mirror + UI gates [A] | Implemented-Live | signup trigger wrote 14 entitlements/account with `source='system_free'`; 280 rows backfilled live. All features free; no billing provider — entitlement integration is an abstraction layer only |
| 2 | Priority likes (server-computed weight) | 031/032 [L] | likes screen [A] | Implemented-Live (partial) | `record_like` ran live but returned its adult guard (`HTTP 400`, "Only verified adults can use Weekend matching."); the computed weight value was not observed. Weight is never accepted from the client |
| 3 | Like notes / compliments (140 chars) | 032 [S] | note sheet [A] | Implemented-Live (schema) | validated inside `record_like` + the social-media trigger; no real note was sent |
| 4 | 24 h match initiation windows | 032 [L] | banners/countdown [A] | Implemented-Live (partial) | `get_matches_for_user` answered live (0 rows for the fresh probe account); window settling was not driven |
| 5 | Women-led initiation (hetero matching) | 032 [S] | UI chips [A] | Implemented-Live (schema) | initiator rule in `check_mutual_like` + `enforce_message_rules`; not exercised with a real pair |
| 6 | Extend match (+24 h, once per participant, idempotent) | 032 [L] | Extend button [A] | Implemented-Live (partial) | live guard path only (`"Match not found"`) |
| 7 | Rematch (once per 7 days, expired+messageless) | 032 [S] | Rematch button [A] | Implemented-Live (schema) | needs an expired, messageless match plus an outstanding partner like |
| 8 | Match list status chips | 032 (RPC output) [L] | MatchCard chips [A] | Implemented-Live (partial) | `get_matches_for_user` live; chips derive only from server fields |
| 9 | Incognito mode | 031 privacy_mode [L] | privacy dialog [A] | Implemented-Live | `set_privacy_mode` live; suppression proved separately by `tool/privacy_bypass_probe.py` against **both** `search_profiles` overloads — the incognito account drops out of each. The advanced-search overload ignored the privacy filters until migration **035** made it delegate to the hardened one |
| 10 | Snooze (with duration choice) | 031 [L] | privacy dialog [A] | Implemented-Live (partial) | same live RPC as incognito; a snooze duration was not set |
| 11 | Away status + away note | 031 [L] | chat banner + dialog [A] | Implemented-Live (partial) | `set_away_status` + `get_conversation_away_note` answered live; no live conversation existed to render the banner |
| 12 | Travel mode | 031 [L] | dialog + on-device geocoding [A] | Implemented-Live (partial) | `set_travel_location` live and it correctly refused null coordinates; a real travel city was not set |
| 13 | Online-now consent toggle | 031 [S] | privacy dialog [A] | Implemented-Live (schema) | `user_settings.show_online_now` owner-row upsert; not toggled live |
| 14 | Spotlight activation window | 031 [L] | visibility dialog [A] | Implemented-Live | `activate_spotlight` + `get_my_spotlight` returned a real server window (`ends_at`, `activations_last_30_days`) and the dialog rendered "Spotlight is LIVE until …" |
| 15 | Photo impressions recording | 032 [L] | deck top card [A] | Implemented-Live (partial) | `record_photo_impressions` live (`{"recorded":0}` — nothing to record, no impressions yet) |
| 16 | Photo insights (30 d) | 031 [L] | visibility dialog [A] | Implemented-Live | `get_my_photo_insights` live with `window_days=30`, `minimum_required_impressions=30`; `sufficient_data=false` renders "Not enough data yet" |
| 17 | Surge (city activity surge) | 031 [L] | home banner [A] | Implemented-Live | `get_surge_state` live and honest about its own limits (`reason: "no_city"`) |
| 18 | Opening moves (3 slots, 160 chars) | 032 [L] | dialog editor [A] | Implemented-Live | **defect found and fixed during this run** — the client omitted the NOT NULL `user_id`, so the RLS insert policy rejected every save (42501). After the fix the prompt was saved on-device, confirmed in Postgres and reloaded by the editor |
| 19 | Selfie verification | existing EF + 031 status [L] | verification dialog [A] | Implemented-Live (partial) | the dialog ran live and reported the true state ("Your profile is not verified yet."); the `photo-verification` Edge Function was not driven (no selfie submitted) |
| 20 | In-app support tickets | 033 [S] | support dialog [A] | Implemented-Live (schema) | `support_tickets` present and RLS-enabled; no ticket was filed live. Status transitions service-role only; 5/day limit |
| 21 | Explainable message risk flags | 033 [S] | chat chips [A] | Implemented-Live (schema) | the `033` trigger is live; no message was sent to trip it. Message is delivered regardless; no auto-ban |
| 22 | Unified discovery surface (`get_nearby_profiles` + `primary_photo_id`) | 031 [L] | discovery repository [A] | Implemented-Live | `get_nearby_profiles` answered live (rows=1); schema check confirms the 8-arg overload is gone and the current one is granted to `authenticated` |
| 23 | Migration 029 hold-back | `migrations-held/` [A] | n/a | Held back (C) | deliberate; documented and confirmed still **absent** from the live project |
| 24 | Documentation honesty pass | n/a | README/store-listing [A] | Complete-verified | artwork removed, signing identity + limits documented |
| 25 | Release signing identity | n/a | build.gradle key wiring [A] | Complete-verified | dedicated RSA-4096 keystore valid to 2054; fingerprint documented. `v2.8.1` is built with the same key and carries the baked `SUPABASE_URL`/`SUPABASE_ANON_KEY`. The superseded `v2.8.0` asset carries neither and cannot sign in — see the audit document |

## Live verification run — 2026-10-19

Migrations **031** `unified_discovery_entitlements_and_modes`, **032**
`like_priority_and_match_lifecycle`, **033** `support_and_message_risk`, the
corrective **034** `fix_spotlight_lateral_alias`, and the two hardening
migrations **035** `search_profiles_legacy_overload_privacy_wrapper` and **036**
`harden_helper_function_grants` were applied to the live project and each
verified. Remote state is `001`–`028` + `030`–`036`; `029` remains correctly
absent. Schema grew 38 → 44 tables and 295 → 352 columns, with RLS enabled on
every new table.

The authenticated probe called all 35 client RPCs with client-accurate
parameters: **28 LIVE / 5 GUARDED / 1 DENIED / 0 ABSENT**, unchanged after 036.

Three server defects and one client defect were found and fixed rather than
worked around:

1. `031` — `search_profiles` failed with `42P13 cannot change return type`
   (missing `drop` of the superseded 21-arg overload).
2. `032` — `get_received_likes` failed with `42P13` (13 → 15 columns).
3. `031` Spotlight lateral used `select 1 as mid` while the outer query read
   `sw.id`, so the hardened discovery feed answered `HTTP 400 42703` on every
   call — fixed by migration `034` (OUT row type unchanged).
4. `lib/repositories/engagement_repository.dart` — Opening Moves never saved
   (missing `user_id`); fixed and covered by two new contract tests.

Two further findings from the same run are now also closed:

5. **F1** — the legacy 13-arg `search_profiles` overload ignored incognito,
   snooze and online-consent, so a user who switched incognito on stayed
   discoverable through the advanced-search screen. Migration **035** makes it a
   wrapper that delegates to the hardened 21-arg function; re-proved with
   fixtures afterwards (`no bypass observed`).
6. **F2** — `get_user_interests`, `approved_photo_count`,
   `has_feature_entitlement` and `mfa_recovery_code_hash` carried
   `EXECUTE TO PUBLIC`, i.e. they were callable with the anon key that ships in
   the APK. Migration **036** revokes anon/PUBLIC (and, for the three internal
   helpers, `authenticated`) and drops the stray `tmp_probe_dollar()`; verified
   live with the public key (`401 42501`) and re-checked that the client-facing
   paths still work.

Not verified here (stated, not hidden): the `v2.8.1` APK has been driven on an
emulator only, not on physical Android hardware; 57 project functions still carry
`EXECUTE TO PUBLIC` (trigger functions and `assert_self`-guarded RPCs), which is
a deliberate follow-up rather than an oversight.

## Honest bottom line

- Every feature is **implemented and enforced server-side**, and the Flutter
  client gates its UI on confirmed server state — nothing in the UI fakes
  success.
- Rows 1–22 are now **present and running on the live backend**. The distinction
  that matters is between `Implemented-Live` (the behaviour was actually
  driven) and `Implemented-Live (partial)` / `(schema)` (the object is live and
  answers, but the full behaviour has not been exercised). No row claims more
  evidence than it has.
- `Implemented-Live (partial)` and `(schema)` are **not** failures; they are
  places where the next live test should push harder. They are called out per
  row rather than hidden behind a single "verified" label.
