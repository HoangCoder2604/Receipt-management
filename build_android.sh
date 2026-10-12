#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo 'Install Flutter SDK and Android SDK first'; exit 1; }
flutter create --platforms=android --org com.vku --project-name receiptly .
if [[ -f android/app/build.gradle.kts ]]; then
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/g' android/app/build.gradle.kts
elif [[ -f android/app/build.gradle ]]; then
  sed -i 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/g' android/app/build.gradle
fi
sed -i 's/android:label="receiptly"/android:label="Receiptly"/' android/app/src/main/AndroidManifest.xml
flutter pub get
flutter build apk --release
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/Receiptly-v1.0.0.apk
echo "APK: dist/Receiptly-v1.0.0.apk"
