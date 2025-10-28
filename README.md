# Face Verification — Advanced On-Device Face Recognition for Flutter

**On-device, privacy-first face recognition for production-ready apps.**
This plugin provides advanced face verification capabilities (powered by a FaceNet model) so you can register multiple face samples per user, verify identities reliably, and keep all processing offline.

Ideal for attendance systems, secure login, access control, KYC workflows, and other production scenarios where accuracy and privacy matter.

---

## 🔥 What's new (v0.1.0)

* ✅ **Server-side embeddings**: NEW `registerFromEmbedding()` and `registerFromEmbeddingsBatch()` for registering pre-computed embeddings from server.
* ✅ **Performance optimization**: Offload embedding generation to server for batch registration (20-50+ faces per user).
* ✅ **Group photo identification**: NEW `identifyAllUsersFromImagePath()` method identifies ALL users in a single photo with multiple faces.
* ✅ **Multi-face detection**: Automatically detects and processes every face in the image.
* ✅ **Batch identification**: Returns a list of all matched user IDs in one call.
* ✅ **tflite_flutter 0.12.0**: Updated dependency for better compatibility.
* ✅ **Real-world use cases**: Perfect for group attendance, event check-in, family photo tagging, and multi-person scenarios.
* ✅ **Backward compatible**: All existing methods work unchanged.
* ✅ **Package bumped**: `0.1.0`

---

## 🧠 Model (FaceNet)

This plugin uses a FaceNet embedding model by default:
`models/facenet.tflite` — included with the package and used to compute face embeddings on-device.

If you want to use a different model, the plugin supports loading a custom TFLite model via `init(modelAsset: ...)` (see **Custom Model** below). The default FaceNet model is tuned for high-quality embeddings suitable for verification workflows.

---

## 🚀 Capabilities

* Register multiple labeled face images per person (e.g., `profile_pic`, `work_id`, `passport_photo`)
* **NEW: Register from server-side embeddings** - batch register 20-50+ faces efficiently
* Replace a particular face image for a person (via `replace` flag)
* Verify a photo against a single person (all their faces) or against everyone
* **NEW: Identify ALL users in a group photo** - detect and recognize multiple people at once
* List, count, and delete face entries per user
* All processing runs on-device (no internet), preserving privacy

---

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  face_verification: ^0.1.0
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
  id: 'jane_smith',
  imagePath: '/path/to/jane_work_id.jpg',
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

// 4. NEW: Identify ALL users in a group photo
final identifiedUsers = await FaceVerification.instance.identifyAllUsersFromImagePath(
  imagePath: '/path/to/group_photo.jpg',
  threshold: 0.70,
);

print('Found ${identifiedUsers.length} users: $identifiedUsers');
// Output: Found 2 users: [john_doe, jane_smith]
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

### Group Photo Identification (NEW in v0.1.0)

Identify **all users** in a single photo containing multiple faces:

```dart
final identifiedUsers = await FaceVerification.instance.identifyAllUsersFromImagePath(
  imagePath: '/path/to/group_photo.jpg',
  threshold: 0.70,
);

// Returns List<String> of all matched user IDs
// Example: ['alice', 'bob', 'charlie']
// Empty list if no matches found
```

**Use cases:**
* Group attendance marking
* Event check-in (identify all attendees at once)
* Family photo tagging
* Multi-person access control
* Classroom or workplace monitoring

### Server-Side Embedding Registration (NEW in v0.1.0)

Register pre-computed embeddings from your server for better performance with large datasets:

**Single embedding:**
```dart
final result = await FaceVerification.instance.registerFromEmbedding(
  id: '123',
  imageId: 'staffs/123/photo/profile.jpg',
  embedding: [0.123, -0.456, ...], // 512 floats from your API
);

if (result['success']) {
  print('Registered: ${result['id']}');
} else {
  print('Failed: ${result['message']}');
}
```

**Batch registration (20-50+ faces):**
```dart
// Direct from API response
final apiResponse = await http.post(yourApiUrl);
final jsonData = jsonDecode(apiResponse.body);

final results = await FaceVerification.instance.registerFromEmbeddingsBatch(
  embeddingsData: List<Map<String, dynamic>>.from(jsonData['data']),
);

// Check results
final successCount = results.where((r) => r['success'] == true).length;
print('Registered $successCount/${results.length} faces');
```

**Use cases:**
* Batch onboarding (register 20-50 employee photos at once)
* Server-side preprocessing for performance
* Sync embeddings from cloud storage
* Reduce mobile device processing load

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