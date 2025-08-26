# face_verification

Face verification for Flutter: detect a face in an image, generate an on-device embedding with a bundled TFLite model, store embeddings locally, and verify new images against the stored records using cosine similarity.

## Features

- On-device face registration and verification
- Bundled face embedding model (TFLite) — works offline
- Simple high-level API (init, register, verify, list, delete)
- Robust preprocessing and cosine-similarity matching
- Local persistence using `sqflite`

## Installation

Add the dependency in your app’s `pubspec.yaml`:

```yaml
dependencies:
  face_verification: ^0.0.1
```

Then run:

```bash
flutter pub get
```

The model asset is bundled with this plugin; no extra asset setup is required for default usage.

## Requirements

### iOS

- Minimum iOS Deployment Target: 15.5
- Xcode 15.3.0 or newer
- Swift 5
- 64-bit architectures only (x86_64, arm64). Exclude 32-bit (i386, armv7).

Exclude armv7 in Xcode:

- Project > Runner > Build Settings > Excluded Architectures > Any SDK > add `armv7`

Update your `ios/Podfile` to set the deployment target and exclude 32-bit:

```ruby
platform :ios, '15.5'

$iOSVersion = '15.5'

post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings["EXCLUDED_ARCHS[sdk=*"] = "armv7"
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = $iOSVersion
  end

  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    target.build_configurations.each do |config|
      if Gem::Version.new($iOSVersion) > Gem::Version.new(config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'])
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = $iOSVersion
      end
    end
  end
end
```

Note: You may set a newer deployment target, but not older than 15.5.

### Android

- `minSdkVersion`: 21
- `targetSdkVersion`: 35
- `compileSdkVersion`: 35

Ensure your Android project `build.gradle`/`build.gradle.kts` matches these values.

### Additional runtime setup (when applicable)

These notes help ensure the on-device ML runtime loads correctly across platforms:

#### Mobile (iOS and Android)

- Build and install on a physical device for best results.
- iOS Simulator may not support certain ML runtimes reliably; prefer a physical device.
- Android devices should be on recent API levels. If you encounter native library load issues, test on a device with API level ≥ 26.
- Creating an iOS release archive (IPA) can strip symbols and cause a "Failed to lookup symbol" error. In Xcode:
  - Target Runner > Build Settings > Strip Style → set to "Non-Global Symbols".

#### Desktop (optional)

If you target desktop platforms, you may need to bundle a platform-specific dynamic library for the ML runtime.

- macOS: Build a `.dylib` for your architecture(s) and add it to your Xcode project.
  - For universal builds, combine arm64/x86_64 with `lipo`.
- Linux: Build a `.so`, place it in a `blobs/` directory, and reference it from `linux/CMakeLists.txt`:

```cmake
# get ml runtime binaries
install(
  FILES ${PROJECT_BUILD_DIR}/../blobs/libtensorflowlite_c-linux.so
  DESTINATION ${INSTALL_BUNDLE_DATA_DIR}/../blobs/
)
```

- Windows: Build a `.dll`, place it in `blobs/`, and reference it from `windows/CMakeLists.txt`:

```cmake
# get ml runtime binaries
install(
  FILES ${PROJECT_BUILD_DIR}/../blobs/libtensorflowlite_c-win.dll 
  DESTINATION ${INSTALL_BUNDLE_DATA_DIR}/../blobs/
)
```

## Quick start

```dart
import 'package:face_verification/face_verification.dart';

Future<void> run() async {
  // Initialize once (bundled model is used by default)
  await FaceVerification.instance.init();

  // Register a face
  final id = await FaceVerification.instance.registerFromImagePath(
    id: 'user_123',
    imagePath: '/path/to/face.jpg',
    imageId: 'img_001',
  );
  print('Registered: $id');

  // Verify a new image
  final matchId = await FaceVerification.instance.verifyFromImagePath(
    imagePath: '/path/to/another_face.jpg',
    threshold: 0.70, // adjust as needed
  );
  print('Best match: $matchId');

  // List all registered faces
  final records = await FaceVerification.instance.listRegisteredAsync();
  print('Registered count: ${records.length}');

  // Optional: delete a record
  await FaceVerification.instance.deleteRecord('user_123');

  // Dispose when done
  await FaceVerification.instance.dispose();
}
```

### Using a custom model (optional)

If you want to provide your own compatible embedding model, pass its asset path on init:

```dart
await FaceVerification.instance.init(
  modelAsset: 'assets/models/your_model.tflite',
  numThreads: 4,
);
```

Make sure the custom model path is included under your app’s `flutter/assets`.

## Example app

See the example in `example/` for a minimal working setup and UI. Run it with:

```bash
cd example
flutter run
```

## Troubleshooting

- No face detected / Multiple faces detected
  - Ensure the input image has a clear, front-facing face. The API throws when zero or multiple faces are found during registration.

- Model not found
  - If you override `modelAsset`, ensure it is correctly listed under your app’s assets and the path is correct.

- iOS build fails for armv7
  - Confirm armv7 is excluded as described in Requirements.

- Matching quality
  - Tune `threshold` (default 0.70). Higher threshold = stricter match.

## Reporting issues

Please open an issue in this repository with the following details:
- Platform and versions (iOS/Android, OS, Flutter, plugin version)
- Device model and architecture
- Steps to reproduce and minimal code snippet
- Relevant logs and, if possible, a test image (redact personal data)

## Contributing

Contributions are welcome. For non-trivial changes, consider opening an issue first to discuss the approach. Please include tests or example changes when appropriate.

## License

This project is licensed under the MIT License. See `LICENSE` for details.

## Changelog

See `CHANGELOG.md` for release notes.
