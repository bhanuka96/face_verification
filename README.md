# Face Verification — Advanced On-Device Face Recognition for Flutter

**On-device, privacy-first face recognition for production-ready apps.**
This plugin provides advanced face verification capabilities (powered by a FaceNet model) so you can register multiple face samples per user, verify identities reliably, and keep all processing offline.

Ideal for attendance systems, secure login, access control, KYC workflows, and other production scenarios where accuracy and privacy matter.

---

## 🔥 What's new (v0.0.7)

* ✅ **Multiple faces per user**: a single user ID can now have many face records (each with its own `imageId`).
* ✅ **Optional `replace` flag on registration**: register with `replace: true` to replace an existing `id + imageId` entry.
* ✅ **Verification checks all faces**: verification will compare against *all* faces for a given user (if `staffId` supplied) or against *all users*.
* ✅ **List / count / delete per-user faces**: new management methods to enumerate and maintain user face samples.
* ✅ **DB migration**: schema migrated to a composite primary key `(id, imageId)` and includes `createdAt` timestamp for each face record.
* ✅ **Package bumped**: `0.0.7`

---

## 🧠 Model (FaceNet)

This plugin uses a FaceNet embedding model by default:
`models/facenet.tflite` — included with the package and used to compute face embeddings on-device.

If you want to use a different model, the plugin supports loading a custom TFLite model via `init(modelAsset: ...)` (see **Custom Model** below). The default FaceNet model is tuned for high-quality embeddings suitable for verification workflows.

---

## 🚀 Capabilities

* Register multiple labeled face images per person (e.g., `profile_pic`, `work_id`, `passport_photo`)
* Replace a particular face image for a person (via `replace` flag)
* Verify a photo against a single person (all their faces) or against everyone
* List, count, and delete face entries per user
* All processing runs on-device (no internet), preserving privacy

---

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  face_verification: ^0.0.7
```

Run:

```bash
flutter pub get
```

---

## 📱 Quick Demo (updated)

```dart
// 1. Initialize (do this once when your app starts)
await FaceVerification.instance.init(); // uses models/facenet.tflite by default

// 2. Register multiple faces for one user
await FaceVerification.instance.registerFromImagePath(
  id: 'john_doe',
  imagePath: '/path/to/john_profile.jpg',
  imageId: 'profile_pic',
);

await FaceVerification.instance.registerFromImagePath(
  id: 'john_doe',
  imagePath: '/path/to/john_work_id.jpg',
  imageId: 'work_id',
);

// Replace an existing face image
await FaceVerification.instance.registerFromImagePath(
  id: 'john_doe',
  imagePath: '/path/to/john_new_profile.jpg',
  imageId: 'profile_pic',
  replace: true,
);

// 3. Verify a new photo against everyone (returns matched user ID or null)
final matchId = await FaceVerification.instance.verifyFromImagePath(
  imagePath: '/path/to/new_photo.jpg',
  threshold: 0.70,
);

if (matchId == 'john_doe') {
  print('Welcome back, John!');
} else {
  print('Face not recognized');
}

// 4. Verify against a single user (checks all their registered faces)
final matchForUser = await FaceVerification.instance.verifyFromImagePath(
  imagePath: '/path/to/new_photo.jpg',
  threshold: 0.70,
  staffId: 'john_doe',
);
```

---

## 🎯 Full Usage & Management

### Initialize

Call once when your app starts:

```dart
await FaceVerification.instance.init(
  // optional: modelAsset: 'assets/models/my_custom_facenet.tflite',
  // optional: numThreads: 4
);
```

### Register a face (multiple per user)

```dart
await FaceVerification.instance.registerFromImagePath(
  id: 'employee_123',
  imagePath: '/path/to/photo.jpg',
  imageId: 'passport',     // unique per user
  replace: false,          // optional
);
```

### Verify

* Without `staffId`: checks against *all users* and all their faces.
* With `staffId`: checks only that user's registered faces.

```dart
final matchId = await FaceVerification.instance.verifyFromImagePath(
  imagePath: photoPath,
  threshold: 0.70,
  staffId: null, // or specific id
);
```

### Management API (examples)

```dart
final faces = await FaceVerification.instance.getFacesForUser('employee_123');
final count = await FaceVerification.instance.getFacesCountForUser('employee_123');
final isRegistered = await FaceVerification.instance.isFaceRegistered('employee_123');
final hasSpecific = await FaceVerification.instance.isFaceRegisteredWithImageId('employee_123', 'passport');
await FaceVerification.instance.deleteFace('employee_123', 'passport'); // delete one sample
await FaceVerification.instance.deleteRecord('employee_123'); // delete all samples for user
```

---

## ⚙️ Database migration notes

* The plugin now stores multiple face rows per user using a composite primary key `(id, imageId)` and a `createdAt` timestamp for each record.
* On upgrade to v0.0.7 the plugin runs a migration to preserve existing records where possible. If you rely on embedded data, test the upgrade process and back up data before updating in critical environments.

---

## 📸 Tips for Best Results

Good photos:

* Clear, front-facing face
* Even lighting (avoid harsh shadows)
* No sunglasses or masks
* Single person in frame

Avoid:

* Blurry or low-resolution images
* Multiple people in one registration image
* Extreme angles

---

## 🚨 Troubleshooting (common cases)

**"ID already exists"**

* With multi-face support this only happens for the same `(id, imageId)`. Use a different `imageId` or `replace: true`.

**"Multiple faces detected"**

* Supply an image with only the target person or crop the photo.

**Low accuracy**

* Use higher-quality photos, adjust `threshold`, or add more samples per user.

---

## 🎨 Custom Model (Advanced)

You can load your own TFLite model instead of the default `models/facenet.tflite`:

```dart
await FaceVerification.instance.init(
  modelAsset: 'assets/models/my_custom_model.tflite',
  numThreads: 4,
);
```

Add the model to your `pubspec.yaml` assets.

---

## 📱 Example App

See the `example/` folder for a complete app demonstrating registration, verification, and management:

```bash
cd example
flutter run
```

---

## 🆘 Need Help?

Please [open an issue](https://github.com/bhanuka96/face_verification/issues) with:

* Platform (iOS/Android) & versions
* Device model
* Error messages & stack traces
* Minimal reproducible example

---

## 📄 License

MIT License — see [LICENSE](LICENSE).

---

**⭐ Found this helpful? Please star the repo and leave a review on pub.dev!**