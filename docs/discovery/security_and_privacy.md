# Security and Privacy

- No exact latitude/longitude returned in discovery RPC result set (only rounded distance).
- Blocked users excluded in both directions server-side.
- Suspended/deleted/rejected/moderated accounts excluded.
- Adult floor (>=18) enforced server-side before caller age range.
- RLS: RPC granted only to authenticated; anon/public revoked.
- Travel mode stores approximate destination in `user_settings`; never overwrites `profiles.latitude/longitude`.
- Location permission denial handled in Flutter; no fabricated default location.
- Private fields (email, phone, auth ids) never selected.
