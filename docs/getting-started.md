# Getting Started

Get a working Weekend development environment in about ten minutes.

Weekend is a Flutter app for Android with a Supabase backend. You can start it
**without any backend** (offline demo mode) to look at the UI, or connect it to
your own Supabase project for the full feature set.

---

## 1. Prerequisites

| Tool | Version used by Weekend | Notes |
|------|------------------------|-------|
| Flutter SDK | **3.41.9** (stable) | Bundles Dart 3.11.5 |
| Dart SDK | **3.11.5** | Installed with Flutter |
| JDK | **17** | Required by the Android Gradle build |
| Android SDK | API 36 platform + build tools | Installed via Android Studio |
| Supabase CLI | latest | Only needed to push migrations / deploy functions |
| Git | any recent | |

```bash
flutter --version
flutter doctor        # fix anything it reports before continuing
```

---

## 2. Clone and install dependencies

```bash
git clone https://github.com/zypherlabs-bit/Weekend.git
cd Weekend
flutter pub get
```

---

## 3. Choose a run mode

### A. Offline demo mode (no backend)

Just run the app. When `SUPABASE_URL` / `SUPABASE_ANON_KEY` are absent the app
uses bundled sample data, so you can review every screen without provisioning
anything:

```bash
flutter run            # Android device or emulator
flutter run -d chrome  # or in a browser during development
```

### B. Production mode (your own Supabase project)

1. Create a project at [supabase.com](https://supabase.com/).
2. Apply migrations and deploy Edge Functions (see [supabase.md](supabase.md)).
3. Copy your **Project URL** and **anon/public key** from
   **Supabase Dashboard → Project Settings → API**:

   ```properties
   SUPABASE_URL=https://your-project-ref.supabase.co   # <-- YOUR project URL
   SUPABASE_ANON_KEY=your-real-anon-key-here            # <-- YOUR anon key
   ```

   **⚠️ Critical:** The placeholder values shown here are **not valid
   credentials**. If you use them, the app runs in offline demo mode
   instead of connecting to the backend. You **must** replace them with
   real values from your Supabase dashboard.

4. Build/run with your real credentials via `--dart-define`:

   ```bash
   flutter run \
     --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=your-real-anon-key-here
   ```

   **To build a release APK:**

   ```bash
   flutter build apk --release \
     --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=your-real-anon-key-here
   ```

5. Apply the database schema:

   ```bash
   supabase link --project-ref <your-project-ref>
   supabase db push
   ```

6. Deploy the Edge Functions you need (see [supabase.md](supabase.md)):

   ```bash
   supabase functions deploy serve-ad
   supabase functions deploy photo-verification
   supabase functions deploy account-deletion
   supabase secrets set GEMINI_API_KEY=...   # server-side only
   ```

---

## 4. Verify your setup

```bash
flutter analyze       # must report no issues
flutter test          # unit + widget tests
```

Then walk the app: onboarding → sign-up → profile → discovery → like/pass →
match → chat → plans.

If sign-up fails, confirm that `SUPABASE_URL` and `SUPABASE_ANON_KEY` were
actually passed (a typo or a placeholder value puts the app back into offline
demo mode).

---

## 5. Build a release APK

Replace the placeholder values with your real Supabase credentials before building.
Using placeholder values will produce an APK that runs in offline demo mode.

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-real-anon-key-here
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

For a signed release build, create `android/key.properties` from
`android/key.properties.example`. Without it, the build uses debug signing.

---

## 6. Where to go next

- [architecture.md](architecture.md) — how the code is layered
- [supabase.md](supabase.md) — schema, RLS, storage, realtime, Edge Functions
- [location-discovery.md](location-discovery.md) — the location/privacy design
- [qr-invitations.md](qr-invitations.md) — invitations and referrals
- [testing.md](testing.md) — test commands and conventions
- [contributing.md](contributing.md) — how to get a change merged

---

## Common problems

| Problem | Cause | Fix |
|---------|-------|-----|
| Lists are empty / no people shown | Supabase credentials missing or placeholder | Re-run with `--dart-define` values |
| `flutter analyze` fails on a CI-only warning | Missing asset directory in a fresh clone | Ensure `assets/images/` is tracked (it contains `placeholder_avatar.png`) |
| Sign-up works but no email arrives | Email confirmation enabled in Supabase Auth | Confirm emails from the inbox, or relax the setting for development |
| Nearby discovery empty | Location permission/services/radius | Grant permission, enable location, widen the radius |
| Realtime chat not updating | Realtime replication not enabled | Enable replication for `messages` and `notifications` in Supabase |
| Edge Function returns 401 | Function expects an authenticated JWT | Sign in first; function calls use the user session |