# Google Play Store Readiness Audit Suite

## Overview

This directory contains a Python-based automated audit suite for verifying
the Weekend dating app's readiness for Google Play Store testing and release.

The suite uses `pytest` and standard Python libraries to validate:

- Release artifact format and validity
- Android configuration (SDK levels, package ID, versioning)
- Signing configuration and debug-detection
- Permission declarations and necessity
- Supabase backend configuration safety
- Secrets and privacy checks
- Data Safety form reconciliation
- Play Store policy compliance

## Directory Structure

```
tools/play_store_audit/
├── requirements.txt    # Python dependencies
├── test_artifact.py    # APK/AAB format and basic validity
├── test_android_config.py  # SDK, package, permission checks
├── test_signing.py   # Signing configuration and debug-detection
├── test_permissions.py   # Manifest permission declarations
├── test_privacy_and_policy.py  # Privacy policy and in-app disclosures
├── test_release_metadata.py  # Version code/name consistency
├── test_supabase_config.py   # Supabase configuration safety
├── test_dependencies.py    # flutter pub get, analyze, test
├── test_play_store_readiness.py  # High-level readiness checks
├── conftest.py     # Shared test fixtures and configuration
└── README.md       # This file
```

## Requirements

```bash
pip install -r requirements.txt
```

See `requirements.txt` for pinned dependency versions.

## Running the Suite

```bash
# From the repository root
pytest tools/play_store_audit/ -v

# Or run a specific test file
pytest tools/play_store_audit/test_android_config.py -v
```

## Interpreting Results

- **PASS**: Verified by actual evidence
- **FAIL**: A confirmed defect or unmet requirement
- **BLOCKED**: Verification or remediation needs external access,
  a credential, or an action not available to the agent
- **NOT VERIFIED**: Insufficient evidence
- **NOT APPLICABLE**: Documented reason the requirement does not apply

## Adding New Tests

New test files should follow the same pattern:

1. Create a file named `test_*.py` in the `tools/play_store_audit/` directory
2. Use `pytest` conventions (functions starting with `test_`)
3. Import `ROOT` from the module or define `Path(ROOT_DIR)` appropriately
4. Use `_read(path)` helper for reading text files
5. Report findings via `print()` or pytest assertions

## Limitations

- Tests are static checks; they verify configuration, not Play Console
  acceptance
- Some checks require Android SDK tools (aapt2, apksigner, bundletool)
  which may not be installed in the environment
- Live backend verification (Supabase) requires credentials that are
  not committed to the repository
- Physical device testing and closed testing track validation cannot be
  automated from this environment