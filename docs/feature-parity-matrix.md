# Feature parity matrix

Status of every functional area against a mature swipe-based dating product.

- **Audit date:** 2026-09-30
- **Baseline:** commit `c4ca548` (v2.6.0+11), plus in-flight passkey/email-confirmation work
- **Status legend:** `COMPLETE` · `PARTIAL` · `MISSING` · `BROKEN` (wrote the client code, but the backend it calls cannot work) · `NEEDS REFACTOR` · `BLOCKED` (cannot be verified here)

This document was produced by reading every Dart source file, all 25 existing migrations and all 9 edge functions. It is the input to the work in migration `026_dating_platform_completion.sql` and the accompanying Dart changes; the second half records what those changes moved.

---

## 1. Summary table

| Area | Before | After | Action taken |
| --- | --- | --- | --- |
| Authentication | PARTIAL | PARTIAL | Improved — 2 unsafe edge functions disabled, deletion now re-authenticates |
| Profile | PARTIAL | PARTIAL | Improved — interests save bug fixed; large file left alone |
| Discovery | PARTIAL | PARTIAL | Preserved — existing hard-filter logic untouched |
| Likes | **BROKEN** | **COMPLETE** | `record_like` RPC; card rollback added |
| Passes | **BROKEN** | **COMPLETE** | `record_pass` RPC |
| Received likes | **MISSING** | **COMPLETE** | `get_received_likes` + `/likes` screen + tab |
| Matching | COMPLETE | COMPLETE | Preserved — `check_mutual_like` untouched |
| Matches list | **BROKEN** | **COMPLETE** | `get_matches_for_user` repaired |
| Unmatch | **MISSING** | **COMPLETE** | `unmatch_match` RPC |
| Chat | PARTIAL | PARTIAL | `conversations` INSERT policy added; leak not fixed |
| Notifications | **MISSING** | **COMPLETE** | Centre + 3 RPCs + badge + deep links |
| Push delivery | **MISSING** | **MISSING** | Not attempted — needs a push provider |
| Settings | PARTIAL | PARTIAL | Appearance + push toggles now real; still a dialog |
| Theme | **BROKEN** | **COMPLETE** | Persisted Light/Dark/System |
| Safety | PARTIAL | PARTIAL | Report categories + re-auth improved |
| Blocking | **BROKEN** | **COMPLETE** | Both directions + unwind on block |
| Verification | **BROKEN** | PARTIAL | TDZ crash fixed; moderation still auto-approves |
| Premium | N/A | N/A | Does not exist in this product — not invented |
| Analytics | MISSING | MISSING | No analytics in the app today |
| Ads | **BROKEN** | **COMPLETE** | `service_role` grants added |

---

## 2. Detailed findings

### BROKEN — the client was written against a backend that could not work

These are the expensive ones: the code exists, compiles, and passes tests, but every call raises and the error is swallowed.

**`get_matches_for_user` could not execute.**
Migration `022_advanced_search.sql:160` selected `m.conversation_id` (no such column — the link runs the other way, via `conversations.match_id`) and `mm.content` (the column is `text`). Postgres does not validate column names inside a `plpgsql` body at `CREATE` time, so the function was created happily. At runtime it raised; `MatchRepository.fetchMatches` caught and returned `[]`. **Every user saw "No Matches Yet" permanently, with no error logged anywhere.**
It also returned 12 columns while `MatchRepository` read 17 — `interests`, `shared_interests`, `matched_at`, `unread_count`, `distance_km` had no source and silently defaulted.
*Fixed:* rewritten in migration 026 with the exact 18-column contract the client reads, plus the join it should have had.

**Ads never served.** `serve-ad/index.ts` builds a service-role client, then calls `get_ad_for_user` and `record_ad_event` — both of which raise on `auth.uid() is null`. Migration 009 fixed exactly this for `delete_user_account` and never applied it to the ad RPCs.
*Fixed:* `grant execute ... to service_role` on both.

**Sending the first message could fail.** `MessageRepository.sendMessage` inserts a `conversations` row when it cannot find one, but `conversations` had SELECT-only RLS and `check_mutual_like` already creates the conversation. The insert always hit a permission error.
*Fixed:* scoped INSERT policy for match participants.

**Interests could not be saved.** `client.from('interests').upsert({'name': ...})` cannot conflict on the primary key (no `id` supplied), so the second user to pick the same interest hit the unique violation on `name` and the whole interests block was reported as unsaved.

**The discovery radius never persisted.** `saveLocationPreferences` upserted `user_settings` with no conflict target. The table's PK is `id`, so PostgREST targeted the PK, turning the write into a plain INSERT that hit `user_settings_user_id_key` (23505). The slider silently reset on every launch.

### MISSING — capability that was never built

| Capability | State |
| --- | --- |
| Notification centre | Table written by the database since migration 001; `NotificationRepository` called from nowhere; `subscribeToNotifications` attached a listener it never stored or cancelled, with an empty body |
| "People who liked you" | No query anywhere selected `liked_id = me`. `likes` is directional and the data was simply never read |
| Unmatch | `matches` had SELECT-only RLS and no client call site anywhere |
| `is_stand_out` read path | Written by the client, never read back by anything |
| `profile_completion` | Write-protected, and no function computed it — permanently 0, yet `search_profiles` weighted it at 10 ranking points |
| Theme persistence | `ThemeMode.system` hardcoded; the settings switch flipped a local field nothing read |
| Notification deep links | `_onNotificationTap` was a `debugPrint` |
| `new_like` notification type | Allowed by the CHECK constraint, never produced |
| Push delivery | No device-token table, no FCM/APNs, no `pg_net`/`pg_cron`. Notifications only appeared while the app was foregrounded |

### SECURITY

| Severity | Finding |
| --- | --- |
| **Critical** | `passkey-authenticate/index.ts` defined `authenticate()` and never called it, then built a service-role client and returned `access_token` + `refresh_token`. Unauthenticated endpoint whose stated purpose was minting a session. |
| **Critical** | `account-deletion/index.ts` destructured `password` from the request body and never verified it. A live — and routinely cached — session token was sufficient to irreversibly destroy an account. |
| **High** | Block enforcement was one-directional. `enforce_message_rules` raised only when the *recipient* had blocked the sender, so if you blocked someone they could still message you. |
| **High** | Blocking never unwound anything: the match, conversation and full history survived. |
| **High** | `interests` UPDATE policy was `using (auth.uid() is not null)` — any signed-in user could rewrite any shared interest, changing the chip on every profile using it. |
| **Medium** | `verification_requests` INSERT checked only `user_id`, and `status` accepts `'approved'` with no column protection — a client could self-approve its own verification. |
| **Medium** | `ad_campaigns` SELECT was `auth.uid() is not null`, exposing `budget_cents`, `spent_cents` and `cpm_cents` for every campaign to every signed-in user. |
| **Medium** | `photo-verification/index.ts` assigned `riskLevel` and pushed to `suspicionReasons` before their `let`/`const` declarations — a `ReferenceError` on exactly the uploads matching a social-media filename. |
| **Medium** | SECURITY DEFINER functions added by 022/023/025 pinned `search_path = public` without `pg_temp`, which Postgres still searches first. Migration 024 fixed the earlier ones; the later ones were left weaker. |
| **Medium** | No rate limit on likes, passes or reports. 200 likes/hour could be scripted to inflate match and referral counters; reports were unbounded. |
| **Low** | Duplicate `check_mutual_like` trigger — 003's `on_like_insert` was never dropped when 010 added `on_like_created`. Wasteful, not corrupting. |

### Explicitly not built (and why)

- **Premium / subscriptions / IAP.** No subscription table, no entitlement column, no billing provider anywhere in `supabase/`. `plans_screen.dart` is *Weekend Plans* (community events), not billing. Inventing a paywall would have been fabricating a business model.
- **Swipe undo.** No undo buffer, no prior-state persistence. `record_like` is now idempotent so a like can be retracted by re-reading, but the undo *gesture* is not built.
- **Analytics.** No analytics SDK in the app. Adding one with invented event names would create fake instrumentation.
- **Rate-limited "who viewed you".** No such data is collected.

---

## 3. What migration 026 changed

| Kind | Change |
| --- | --- |
| Table constraint | `notifications.type` gains `new_like`; `reports.report_type` gains `spam`, `underage`, `unsafe_behavior`, `other` |
| Index | 9 new indexes for the interaction rate limiter, received likes, notifications, matches and messages |
| Realtime | `conversation_members`, `likes`, `matches` added to `supabase_realtime` |
| Trigger | `enforce_message_rules` (both directions) · `enforce_block_unwind` · `enforce_interaction_rate_limit` on likes + passes · `notify_on_like` · `sync_profile_completion` · `guard_interest_name_change` · `protect_verification_verdict` |
| RPC | `record_like` · `record_pass` · `unmatch_match` · `get_received_likes` · `get_notifications` · `mark_all_notifications_read` · `notification_unread_count` · `submit_report` · `ensure_interest` · `get_matches_for_user` (repaired) |
| Policy | interests UPDATE dropped + revoked · `ad_campaigns` SELECT scoped to the advertiser · `conversations` INSERT for match participants · ad event tables UPDATE/DELETE revoked |
| Grant | `get_ad_for_user`, `record_ad_event` to `service_role` |
| Security | `pg_temp` sweep over every SECURITY DEFINER function |

Matching remains owned by the `check_mutual_like` trigger, untouched. Discovery filtering remains owned by `get_nearby_profiles` and `search_profiles`, untouched. No recommendation or ranking logic was introduced.

## 4. Edge functions

| Function | Change |
| --- | --- |
| `passkey-authenticate` | Replaced with a hard 410. Unauthenticated, unreachable-by-design, no caller. |
| `passkey-register` | Replaced with a hard 410. Called the wrong MFA API for a service-role client; no caller. |
| `account-deletion` | Now verifies the account password against a throwaway anon client and confirms the returned session belongs to the caller. |
| `photo-verification` | Moved the `riskLevel` / `suspicionReasons` declarations above their first use. |

## 5. Verification status

| Check | Result |
| --- | --- |
| `flutter analyze` | **No issues found** |
| `flutter test` | **287 passed**, 0 failed (231 before this change, +56) |
| `pytest` (security, passkey, structure) | **44 passed** |
| Migration 026 against a live database | **NOT RUN** — no Docker or `psql` in this environment. `supabase db start` and `db push` were not attempted; deploying to the linked project is a production action. |
| Edge functions type-check / `deno lint` | **NOT RUN** — no Deno toolchain in this environment |
| Emulator / device walkthrough | **NOT RUN** — no attached Android device or running emulator |
| `flutter build apk --release` | **NOT RUN** — needs live `--dart-define` credentials, which are correctly absent from source control |

The contract tests in `test/database_contract_test.dart` are written to catch the *class* of defect that produced the `get_matches_for_user` breakage (client/RPC column drift), but they are static checks: they cannot prove the SQL executes.