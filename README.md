# Face Verification : Advanced On-Device Face Recognition for Flutter

**On-device, privacy-first face recognition for production-ready apps.**
This plugin provides advanced face verification capabilities (powered by a FaceNet model) so you can register multiple face samples per user, verify identities reliably, and keep all processing offline.

Ideal for attendance systems, secure login, access control, KYC workflows, and other production scenarios where accuracy and privacy matter.

---

## What's new

* **Background isolate verification**: NEW `verifyFromImagePathIsolate()` keeps UI responsive during verification (v0.3.0).
* **Parallel batch processing**: NEW `identifyUsersFromImagePaths()` processes 10 images in ~5-7 seconds (vs 50s sequential).
* **Multi-image identification**: Identify users across multiple images with configurable parallel processing.
* **Annotated group output**: NEW `identifyAllUsersFromImagePathWithBoundingBoxes()` returns an image with green face boundaries.
* **Crash prevention**: Pool-based concurrency control (max 3 concurrent operations) prevents thread exhaustion.
* **Type-safe results**: New `ImageIdentificationResult` class for per-image results.
* **Database safety**: Automatic recovery from closed connections, isolate-safe database access.
* **Backward compatible**: All existing methods work unchanged including server-side embeddings from v0.2.0.

---

## Model (FaceNet)

This plugin uses a FaceNet embedding model by default:
`models/facenet.tflite` included with the package and used to compute face embeddings on-device.

If you want to use a different model, the plugin supports loading a custom TFLite model via `init(modelAsset: ...)` (see **Custom Model** below). The default FaceNet model is tuned for high-quality embeddings suitable for verification workflows.

---

## Capabilities

* Register multiple labeled face images per person (e.g., `profile_pic`, `work_id`, `passport_photo`)
* **NEW: Register from server-side embeddings** - batch register 20-50+ faces efficiently
* Replace a particular face image for a person by deleting and re-registering
* Verify a photo against a single person (all their faces) or against everyone
* **NEW: Identify ALL users in a group photo** - detect and recognize multiple people at once
* **NEW: Export group photo with green face boxes** - visualize all detected faces
* List, count, and delete face entries per user
* All processing runs on-device (no internet), preserving privacy

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  face_verification: ^0.3.3
```

Run:

```bash
flutter pub get
```

---

## Quick Demo

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

// Replace an existing face image: delete then register again
await FaceVerification.instance.deleteFaceRecord('john_doe', 'profile_pic');
await FaceVerification.instance.registerFromImagePath(
  id: 'john_doe',
  imagePath: '/path/to/john_new_profile.jpg',
  imageId: 'profile_pic',
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

// 4. Verify with background isolate (UI stays responsive)
final matchId = await FaceVerification.instance.verifyFromImagePathIsolate(
  imagePath: '/path/to/new_photo.jpg',
  threshold: 0.70,
);

// 5. Identify users across multiple images (parallel processing)
final results = await FaceVerification.instance.identifyUsersFromImagePaths(
  imagePaths: ['/img1.jpg', '/img2.jpg', '/img3.jpg'],
  threshold: 0.60,
  batchSize: 3, // Process 3 images in parallel
);

for (var result in results) {
  print('${result.imagePath}: ${result.userIds}');
}
// Output:
// /img1.jpg: [john_doe]
// /img2.jpg: [jane_smith]
// /img3.jpg: []

// 6. Identify ALL users in a single group photo
final identifiedUsers = await FaceVerification.instance.identifyAllUsersFromImagePath(
  imagePath: '/path/to/group_photo.jpg',
  threshold: 0.60,
);

print('Found ${identifiedUsers.length} users: $identifiedUsers');
// Output: Found 2 users: [john_doe, jane_smith]

// 7. Identify + get annotated image with green face boundaries
final annotated = await FaceVerification.instance.identifyAllUsersFromImagePathWithBoundingBoxes(
  imagePath: '/path/to/group_photo.jpg',
  threshold: 0.60,
);
print('Annotated image: ${annotated.annotatedImagePath}');
print('Detected faces: ${annotated.detectedFaceCount}');
```

---

## Full Usage & Management

### Current Public API (`FaceVerification`)

```dart
Future<void> init({
  String modelAsset = 'packages/face_verification/assets/models/facenet.tflite',
  int numThreads = 4,
});

Future<String> registerFromImagePath({
  required String id,
  required String imagePath,
  required String imageId,
  bool replace = true,
});

Future<String?> verifyFromImagePath({
  required String imagePath,
  double threshold = 0.70,
  String? staffId,
});

Future<String?> verifyFromImagePathIsolate({
  required String imagePath,
  double threshold = 0.70,
  String? staffId,
});

Future<List<String?>> verifyFromImagePathsBatch({
  required List<String> imagePaths,
  double threshold = 0.70,
  String? staffId,
});

Future<List<ImageIdentificationResult>> identifyUsersFromImagePaths({
  required List<String> imagePaths,
  double threshold = 0.60,
  int batchSize = 3,
});

Future<List<String>> identifyAllUsersFromImagePath({
  required String imagePath,
  double threshold = 0.60,
});

Future<AnnotatedImageIdentificationResult> identifyAllUsersFromImagePathWithBoundingBoxes({
  required String imagePath,
  double threshold = 0.60,
  String? outputPath,
  int lineThickness = 3,
});

Future<Map<String, dynamic>> registerFromEmbedding({
  required String id,
  required String imageId,
  required List<double> embedding,
});

Future<List<Map<String, dynamic>>> registerFromEmbeddingsBatch({
  required List<Map<String, dynamic>> embeddingsData,
});

Future<bool> isFaceRegistered(String id);
Future<bool> isFaceRegisteredWithImageId(String id, String imageId);
Future<List<FaceRecord>> getFacesForUser(String userId);
Future<int> getFaceCountForUser(String userId);
Future<List<String>> getAllRegisteredUsers();
Future<List<FaceRecord>> listRegisteredAsync();
Future<void> deleteFaceRecord(String userId, String imageId);
Future<void> deleteUserFaces(String userId);
Future<void> deleteRecord(String id); // legacy alias
Future<void> dispose();
```

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

If the same `(id, imageId)` already exists, registration throws an error.
To replace a face sample, call `deleteFaceRecord(userId, imageId)` first, then register again.

### Verify

**Standard Verification (Main Thread):**

```dart
final matchId = await FaceVerification.instance.verifyFromImagePath(
  imagePath: photoPath,
  threshold: 0.70,
  staffId: null, // null = check all users, or specific user ID
);
```

**Background Isolate Verification (NEW in v0.3.0):**

Keeps UI responsive during verification with many registered users:

```dart
final matchId = await FaceVerification.instance.verifyFromImagePathIsolate(
  imagePath: photoPath,
  threshold: 0.70,
  staffId: null,
);

// UI stays responsive, no freezing
// Pool-protected: max 3 concurrent operations to prevent crashes
```

**Batch Verification (NEW in v0.3.0):**

Process multiple images and return one result per image:

```dart
final results = await FaceVerification.instance.verifyFromImagePathsBatch(
  imagePaths: ['/img1.jpg', '/img2.jpg', '/img3.jpg'],
  threshold: 0.70,
);

// Returns List<String?> - one result per image, in input order
// Example: ['john_doe', null, 'jane_smith']
```

### Multi-Image Identification (NEW in v0.3.0)

Identify users across multiple images with parallel processing:

```dart
final results = await FaceVerification.instance.identifyUsersFromImagePaths(
  imagePaths: ['/img1.jpg', '/img2.jpg', '/img3.jpg'],
  threshold: 0.60,
  batchSize: 3, // Process 3 images in parallel (default: 3, max recommended: 10)
);

// Returns List<ImageIdentificationResult>
for (var result in results) {
  print('Image: ${result.imagePath}');
  print('Found users: ${result.userIds}');
}

// Performance: 10 images in ~5-7 seconds (vs 50s sequential)
```

**Use cases:**
* Batch attendance processing (process 10-50 photos at once)
* High-throughput verification systems
* Parallel identity checks for event entry
* Mass photo analysis

**Performance tuning:**
* `batchSize: 3` - Safe, ~17s for 10 images (recommended)
* `batchSize: 5` - Faster, ~10s for 10 images (test on device)
* `batchSize: 10` - Fastest, ~5-7s for 10 images (may crash on old phones, test first)

### Group Photo Identification (added in v0.1.0)

Identify **all users** in a single photo containing multiple faces:

```dart
final identifiedUsers = await FaceVerification.instance.identifyAllUsersFromImagePath(
  imagePath: '/path/to/group_photo.jpg',
  threshold: 0.60,
);

// Returns List<String> of all matched user IDs
// Example: ['alice', 'bob', 'charlie']
// Empty list if no matches found
```

### Group Photo + Green Face Boundaries

Identify users and generate an annotated image with green boxes for all detected faces:

```dart
final result = await FaceVerification.instance.identifyAllUsersFromImagePathWithBoundingBoxes(
  imagePath: '/path/to/group_photo.jpg',
  threshold: 0.60,
  // optional: outputPath: '/custom/path/group_annotated.jpg',
  // optional: lineThickness: 3,
);

print('Users: ${result.userIds}');
print('Faces detected: ${result.detectedFaceCount}');
print('Annotated path: ${result.annotatedImagePath}');
// result.annotatedImageBytes also available
```

**Use cases:**
* Group attendance marking
* Event check-in (identify all attendees at once)
* Family photo tagging
* Multi-person access control
* Classroom or workplace monitoring

### Server-Side Embedding Registration (NEW in v0.2.0)

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
final count = await FaceVerification.instance.getFaceCountForUser('employee_123');
final isRegistered = await FaceVerification.instance.isFaceRegistered('employee_123');
final hasSpecific = await FaceVerification.instance.isFaceRegisteredWithImageId('employee_123', 'passport');
final users = await FaceVerification.instance.getAllRegisteredUsers();
final allRecords = await FaceVerification.instance.listRegisteredAsync();
await FaceVerification.instance.deleteFaceRecord('employee_123', 'passport'); // delete one sample
await FaceVerification.instance.deleteUserFaces('employee_123'); // delete all samples for user
await FaceVerification.instance.deleteRecord('employee_123'); // legacy alias
```

---

## Database migration notes

* The plugin now stores multiple face rows per user using a composite primary key `(id, imageId)` and a `createdAt` timestamp for each record.
* On upgrade to v0.0.7 the plugin runs a migration to preserve existing records where possible. If you rely on embedded data, test the upgrade process and back up data before updating in critical environments.

---

## Tips for Best Results

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

## Troubleshooting (common cases)

**"ID already exists"**

* With multi-face support this only happens for the same `(id, imageId)`. Use a different `imageId`, or delete first with `deleteFaceRecord(id, imageId)` and register again.

**"Multiple faces detected"**

* Supply an image with only the target person or crop the photo.

**Low accuracy**

* Use higher-quality photos, adjust `threshold`, or add more samples per user.

---

## Custom Model (Advanced)

You can load your own TFLite model instead of the default `models/facenet.tflite`:

```dart
await FaceVerification.instance.init(
  modelAsset: 'assets/models/my_custom_model.tflite',
  numThreads: 4,
);
```

Add the model to your `pubspec.yaml` assets.

---

## Example App

See the `example/` folder for a complete app demonstrating registration, verification, and management:

```bash
cd example
flutter run
```

---

## Need Help?

Please [open an issue](https://github.com/bhanuka96/face_verification/issues) with:

* Platform (iOS/Android) & versions
* Device model
* Error messages & stack traces
* Minimal reproducible example

---

## License

MIT License [LICENSE](LICENSE).

---

**⭐ Found this helpful? Please star the repo and leave a review on pub.dev!**
