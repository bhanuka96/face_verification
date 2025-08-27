# Face Verification — Simple Face Recognition for Flutter

**Add secure face recognition to your Flutter app in minutes.** This plugin lets you register users' faces and verify their identity later — all processing happens on-device for privacy and works offline.

Perfect for attendance systems, secure login, user verification, and access control apps.

## 🚀 What You Can Do

- **Register faces**: Take a photo and save someone's face profile
- **Verify identity**: Check if a new photo matches any registered person
- **Works offline**: No internet required, all processing on-device
- **Privacy-first**: Face data never leaves the device
- **Simple API**: Just 3 main functions to get started

## 📱 Quick Demo

```dart
// 1. Initialize (do this once when your app starts)
await FaceVerification.instance.init();

// 2. Register someone's face
await FaceVerification.instance.registerFromImagePath(
  id: 'john_doe',
  imagePath: '/path/to/johns_photo.jpg',
  imageId: 'profile_pic',
);

// 3. Later, verify if a new photo matches John
final matchId = await FaceVerification.instance.verifyFromImagePath(
  imagePath: '/path/to/new_photo.jpg',
  threshold: 0.70, // How strict the match should be (0-1)
);

if (matchId == 'john_doe') {
  print('Welcome back, John!');
} else {
  print('Face not recognized');
}
```

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  face_verification: ^0.0.4
```

Run:
```bash
flutter pub get
```

That's it! The face recognition model is included automatically.

## 🛠️ Platform Setup

### iOS Requirements
- iOS 15.5 or newer
- Xcode 15.3.0+

Add this to your `ios/Podfile`:
```ruby
platform :ios, '15.5'

post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings["EXCLUDED_ARCHS[sdk=*"] = "armv7"
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
  end
  
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
    end
  end
end
```

### Android Requirements
Update your `android/app/build.gradle`:
```gradle
android {
    compileSdkVersion 35
    
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 35
    }
}
```

## 🎯 Complete Usage Guide

### Step 1: Initialize the Plugin
Do this once when your app starts, typically in `main()` or your first screen:

```dart
import 'package:face_verification/face_verification.dart';

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initializeFaceVerification();
  }
  
  Future<void> _initializeFaceVerification() async {
    try {
      await FaceVerification.instance.init();
      print('Face verification ready!');
    } catch (e) {
      print('Failed to initialize: $e');
    }
  }
}
```

### Step 2: Register a Person's Face
When someone needs to register (like employee onboarding or user signup):

```dart
Future<void> registerNewPerson(String personId, String photoPath) async {
  try {
    final result = await FaceVerification.instance.registerFromImagePath(
      id: personId,           // Unique ID like 'employee_123' or 'user_john'
      imagePath: photoPath,   // Path to their photo
      imageId: 'main_photo',  // Optional: label for this photo
    );
    
    print('✅ Successfully registered: $result');
    // Show success message to user
    
  } catch (e) {
    print('❌ Registration failed: $e');
    // Handle errors (no face detected, multiple faces, etc.)
  }
}
```

### Step 3: Verify Someone's Identity
When someone tries to log in or access something:

```dart
Future<void> verifyPerson(String photoPath) async {
  try {
    final matchId = await FaceVerification.instance.verifyFromImagePath(
      imagePath: photoPath,
      threshold: 0.70,  // 0.70 = good balance, 0.80 = stricter, 0.60 = more lenient
    );
    
    if (matchId != null) {
      print('✅ Welcome back, $matchId!');
      // Grant access or log them in
    } else {
      print('❌ Face not recognized');
      // Show error or fallback to password
    }
    
  } catch (e) {
    print('❌ Verification failed: $e');
  }
}
```

### Step 4: Check Specific Person (Optional)
If you want to verify against one specific person instead of everyone:

```dart
Future<void> verifySpecificPerson(String photoPath, String expectedPersonId) async {
  final matchId = await FaceVerification.instance.verifyFromImagePath(
    imagePath: photoPath,
    threshold: 0.70,
    staffId: expectedPersonId,  // Only check against this person
  );
  
  if (matchId == expectedPersonId) {
    print('✅ Identity confirmed for $expectedPersonId');
  } else {
    print('❌ Not a match for $expectedPersonId');
  }
}
```

## 🔧 Useful Management Functions

```dart
// List all registered people
final records = await FaceVerification.instance.listRegisteredAsync();
print('${records.length} people registered');

// Remove someone's registration
await FaceVerification.instance.deleteRecord('employee_123');

// Clean up when app closes (optional)
await FaceVerification.instance.dispose();
```

## ⚙️ Understanding the Threshold

The `threshold` parameter controls how strict face matching is:

- **0.60**: More lenient (might accept similar-looking people)
- **0.70**: Balanced (recommended for most apps)
- **0.80**: Strict (reduces false positives, might reject valid matches)
- **0.90**: Very strict (use for high-security applications)

## 📸 Tips for Best Results

**Good photos:**
- Clear, front-facing face
- Good lighting
- No sunglasses or masks
- Single person in frame

**Avoid:**
- Blurry images
- Multiple faces
- Very dark photos
- Extreme angles

## 🚨 Common Issues & Solutions

**"No face detected"**
- Make sure photo has a clear, visible face
- Check lighting and image quality

**"Multiple faces detected"**
- Crop photo to show only one person
- Use photos with single subjects

**iOS build errors**
- Make sure you excluded armv7 architecture as shown above
- Test on physical device, not simulator

**Low accuracy**
- Adjust threshold value
- Use higher quality photos
- Re-register with better photos

## 🎨 Custom Model (Advanced)

Want to use your own face recognition model? 

```dart
await FaceVerification.instance.init(
  modelAsset: 'assets/models/my_custom_model.tflite',
  numThreads: 4,
);
```

Add the model to your `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/models/my_custom_model.tflite
```

## 📱 Example App

Check out the complete working example in the `example/` folder:

```bash
cd example
flutter run
```

## 🆘 Need Help?

Having issues? Please [open an issue](https://github.com/your-repo/issues) with:

- Your platform (iOS/Android) and versions
- Device model
- Error messages
- Sample code that isn't working

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**⭐ Found this helpful? Please star the repo and leave a review on pub.dev!**