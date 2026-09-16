## Description

Please include a summary of the change and which issue is fixed. Please also include relevant motivation and context.

Fixes # (issue)

## Type of Change

Please delete options that are not relevant.

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring

## How Has This Been Tested?

Please describe the tests that you ran to verify your changes. Provide instructions so we can reproduce.

- [ ] `flutter analyze` (no new issues)
- [ ] `flutter test` (all suites pass)
- [ ] Manual testing on device/emulator
- [ ] `supabase/test/rls_test.sql` case added/updated (schema or policy changes only)

**Test Configuration:**
- Flutter version (e.g. 3.41.9):
- Android version:
- Device:
- Supabase configured? (yes / offline demo mode):

## Screenshots (if applicable)

Add screenshots to help explain your changes.

## Checklist:

- [ ] My code follows the style guidelines of this project
- [ ] I have performed a self-review of my own code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation (`README.md`, `docs/`, `CHANGELOG.md`)
- [ ] Documentation describes only behaviour that actually ships in this change
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing tests pass locally with my changes
- [ ] Any dependent changes have been merged and published

## Security Considerations

- [ ] No secrets, `.env` files, keystores, API keys or personal data are included in this change
- [ ] New data access is enforced server-side (RLS policies / `security definer` RPCs), not in the client
- [ ] New tables have RLS enabled with policies added in the same change
- [ ] Client-provided user ids are not trusted (`assert_self(auth.uid())` used instead)
- [ ] This change has been reviewed for security implications

## Breaking Changes

Does this change break existing functionality? If yes, please describe the impact and migration path.