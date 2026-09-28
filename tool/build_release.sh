APK=${1:-build/app/outputs/flutter-apk/app-release.apk}
if [ ! -f "$APK" ]; then
  echo "No APK at $APK" >&2; exit 1
fi

# Record the local hash so tests/python/test_release.py can compare the built
# artefact against whatever GitHub actually serves.
mkdir -p build/release
sha256sum "$APK" | tee build/release/apk.sha256

VERSION=$(grep -m1 '^version:' pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)
cp "$APK" "Weekend-v${VERSION}-release.apk"
shasum -a 256 "Weekend-v${VERSION}-release.apk" > "Weekend-v${VERSION}-release.apk.sha256" 2>/dev/null \
  || sha256sum "Weekend-v${VERSION}-release.apk" > "Weekend-v${VERSION}-release.apk.sha256"
cat "Weekend-v${VERSION}-release.apk.sha256"