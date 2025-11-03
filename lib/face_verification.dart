import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pool/pool.dart';

import 'src/services/face_detector.dart';
import 'src/services/storage.dart';
import 'src/services/tflite_embedder.dart';
import 'src/utils/preprocess.dart';
import 'src/services/verification.dart';
import 'src/services/isolate_verification_worker.dart';

/// Result of identifying users in a single image.
class ImageIdentificationResult {
  /// Path to the image that was processed
  final String imagePath;

  /// List of user IDs found in this image (empty if no matches)
  final List<String> userIds;

  ImageIdentificationResult({required this.imagePath, required this.userIds});

  @override
  String toString() => 'ImageIdentificationResult(imagePath: $imagePath, userIds: $userIds)';
}

/// Internal helper class to store face detection data for an image.
class _ImageFaceData {
  final String imagePath;
  final List<Face> faces;
  final Uint8List bytes;

  _ImageFaceData({required this.imagePath, required this.faces, required this.bytes});
}

/// Helper function to split a list into chunks of specified size.
List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
  final chunks = <List<T>>[];
  for (int i = 0; i < list.length; i += chunkSize) {
    final end = (i + chunkSize < list.length) ? i + chunkSize : list.length;
    chunks.add(list.sublist(i, end));
  }
  return chunks;
}

/// High-level API for registration and verification with multiple faces per user.
class FaceVerification {
  static final FaceVerification instance = FaceVerification._internal();

  FaceVerification._internal();

  late TfliteEmbedder _embedder;
  final FaceDetectorService _detector = FaceDetectorService();
  final FaceStore _store = FaceStore();
  late final Pool _verificationPool;

  bool _initialized = false;

  /// Initialize database and load TFLite embedding model.
  Future<void> init({String modelAsset = 'packages/face_verification/assets/models/facenet.tflite', int numThreads = 4}) async {
    if (_initialized) return;
    try {
      await _store.init();

      _embedder = TfliteEmbedder(modelAsset: modelAsset);
      await _embedder.loadModel(numThreads: numThreads);
      if (!_embedder.isLikelyEmbeddingModel()) {
        throw Exception('Loaded model does not look like an embedding model.');
      }

      // Initialize verification pool with concurrency limit of 3
      _verificationPool = Pool(3);
      log('Verification pool initialized with max concurrency: 3');

      _initialized = true;
    } catch (e) {
      log('Error initializing FaceVerification: $e');
      rethrow;
    }
  }

  /// Register a face from an image file path with mandatory user-provided ID.
  /// Now supports multiple faces per user.
  /// Returns the provided ID if successful.
  Future<String> registerFromImagePath({required String id, required String imagePath, required String imageId, bool replace = true}) async {
    _ensureInitialized();

    // Ensure database is open (might have been closed by an isolate)
    await _store.ensureOpen();

    // Validate mandatory parameters
    if (id.trim().isEmpty) {
      throw ArgumentError('ID cannot be empty or null');
    }
    if (imageId.trim().isEmpty) {
      throw ArgumentError('imageId cannot be empty or null');
    }

    // Check if this specific face (id + imageId) already exists
    final existingRecord = await _store.getByUserIdAndImageId(id, imageId);
    if (existingRecord != null) {
      throw Exception('A face record with ID "$id" and imageId "$imageId" already exists.');
    }

    final tempDir = await getTemporaryDirectory();
    final isAlreadyInTemp = imagePath.startsWith(tempDir.path);

    File? tempFile;
    Uint8List? bytes;
    
    try {
      if (isAlreadyInTemp) {
        // Use existing file, read bytes only once
        tempFile = File(imagePath);
        bytes = await tempFile.readAsBytes();
      } else {
        // Read bytes, create temp file
        bytes = await File(imagePath).readAsBytes();
        tempFile = File('${tempDir.path}/temp_face_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(bytes);
      }

      final inputImage = InputImage.fromFile(tempFile);
      final faces = await _detector.detectFaces(inputImage);
      if (faces.isEmpty) {
        throw Exception('No face detected');
      }
      if (faces.length > 1) {
        throw Exception('Multiple faces detected');
      }

      // final bytes = await File(imagePath).readAsBytes();
      final modelInput = await preprocessForModel(rawImageBytes: bytes, face: faces.first, inputSize: _embedder.getModelInputSize());
      final embedding = await _embedder.runModelOnPreprocessed(modelInput);
      if (embedding.isEmpty) throw Exception('Failed to generate embedding');

      final record = FaceRecord(id, imageId, embedding);
      await _store.upsert(record, replace: replace);

      final totalFaces = await _store.getFaceCountForUser(id);
      final action = existingRecord != null ? "Replaced" : "Registered";
      log('$action face for user "$id" with imageId "$imageId". Total faces for user: $totalFaces');

      return id;
    } finally {
      // Only delete temp files we created
      if (!isAlreadyInTemp && tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Verify a face image against all stored embeddings for the user.
  /// If staffId is provided, only compares against that user's faces.
  /// If staffId is null, compares against all users' faces.
  Future<String?> verifyFromImagePath({required String imagePath, double threshold = 0.70, String? staffId}) async {
    _ensureInitialized();

    // Ensure database is open (might have been closed by an isolate)
    await _store.ensureOpen();

    List<FaceRecord> candidateRecords = [];
    if (staffId != null && staffId != 'null') {
      candidateRecords = await _store.getAllByUserId(staffId);
    } else {
      candidateRecords = await _store.listAll();
    }

    if (candidateRecords.isEmpty) return null;

    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _detector.detectFaces(inputImage);
    if (faces.isEmpty) return null;

    final bytes = await File(imagePath).readAsBytes();
    double bestScore = -1.0;
    String? bestMatchId;

    // Generate embeddings for all detected faces in the input image
    final Map<Face, List<double>> faceEmbeddings = {};
    for (final face in faces) {
      final modelInput = await preprocessForModel(rawImageBytes: bytes, face: face, inputSize: _embedder.getModelInputSize());
      final emb = await _embedder.runModelOnPreprocessed(modelInput);
      if (emb.isNotEmpty) faceEmbeddings[face] = emb;
    }

    // Compare against all stored face records
    for (final record in candidateRecords) {
      for (final inputEmbedding in faceEmbeddings.values) {
        if (record.embedding.length == inputEmbedding.length) {
          final score = cosineSimilarity(record.embedding, inputEmbedding);
          if (score > bestScore) {
            bestScore = score;
            bestMatchId = record.id;
          }
        }
      }
    }

    log('Best Score: $bestScore, ID: $bestMatchId, Candidate records: ${candidateRecords.length}');

    if (bestMatchId != null && bestScore >= threshold) {
      return bestMatchId;
    }
    return null;
  }

  /// Verify a face image using a background isolate.
  ///
  /// This method runs the entire verification pipeline in a background isolate:
  /// - Face detection (ML Kit)
  /// - TFLite embedding generation
  /// - Database query and comparison
  ///
  /// This keeps the UI responsive during verification, especially when comparing
  /// against many registered users (10-50+).
  ///
  /// **Concurrency Control**: This method is protected by a pool that limits
  /// concurrent verifications to 3. Additional requests will automatically queue.
  /// This prevents crashes from excessive parallel native operations.
  ///
  /// If staffId is provided, only compares against that user's faces.
  /// If staffId is null, compares against all users' faces.
  ///
  /// Returns the matched user ID if found, or null if no match.
  Future<String?> verifyFromImagePathIsolate({required String imagePath, double threshold = 0.70, String? staffId}) async {
    _ensureInitialized();

    // Request a resource from the pool (limits concurrent verifications to 3)
    final poolResource = await _verificationPool.request();
    log('[POOL] Acquired verification slot');

    try {
      // Get database path on main isolate (path_provider uses method channels)
      final dbPath = await FaceStore.getDatabasePath();

      // Get RootIsolateToken for BackgroundIsolateBinaryMessenger
      final rootIsolateToken = ServicesBinding.rootIsolateToken;
      if (rootIsolateToken == null) {
        throw Exception('RootIsolateToken is null. Make sure to call this from the main isolate.');
      }

      // Load TFLite model bytes on main isolate (asset loading requires ServicesBinding)
      log('[MAIN] Loading TFLite model bytes for isolate...');
      final modelBytes = await rootBundle.load(_embedder.modelAsset);
      final modelBytesList = modelBytes.buffer.asUint8List();
      log('[MAIN] Model bytes loaded: ${modelBytesList.length} bytes');

      // Get model input size from embedder
      final modelInputSize = _embedder.getModelInputSize();
      log('[MAIN] Model input size: $modelInputSize');

      // Run entire verification in background isolate
      final result = await compute(isolateVerificationWorker, {
        'imagePath': imagePath,
        'dbPath': dbPath,
        'threshold': threshold,
        'staffId': staffId,
        'modelBytes': modelBytesList,
        'rootIsolateToken': rootIsolateToken,
        'modelInputSize': modelInputSize,
      });

      // Extract and return only the matched ID
      if (result['success'] == true) {
        final matchId = result['matchId'] as String?;
        final bestScore = result['bestScore'] as double;
        log('Best Score: $bestScore, ID: $matchId');
        return matchId;
      } else {
        final error = result['error'];
        log('Verification in isolate failed: $error');
        return null;
      }
    } catch (e, stackTrace) {
      log('Error in verifyFromImagePathIsolate: $e');
      log('Stack trace: $stackTrace');
      return null;
    } finally {
      // Always release the pool resource
      poolResource.release();
      log('[POOL] Released verification slot');
    }
  }

  /// Verify multiple face images using background isolates with automatic queuing.
  ///
  /// This method processes a list of image paths, calling [verifyFromImagePathIsolate]
  /// for each one. The underlying pool ensures only 3 verifications run concurrently,
  /// with additional requests queuing automatically. This prevents crashes from
  /// excessive parallel operations while still maintaining good throughput.
  ///
  /// Returns a list of matched user IDs (String?) in the same order as input paths.
  /// Null values indicate no match or verification failure.
  ///
  /// Example:
  /// ```dart
  /// final results = await FaceVerification.instance.verifyFromImagePathsBatch(
  ///   imagePaths: ['/path1.jpg', '/path2.jpg', '/path3.jpg'],
  ///   threshold: 0.70,
  /// );
  /// // results might be: ['user123', null, 'user456']
  /// ```
  Future<List<String?>> verifyFromImagePathsBatch({required List<String> imagePaths, double threshold = 0.70, String? staffId}) async {
    _ensureInitialized();

    if (imagePaths.isEmpty) return [];

    log('[BATCH] Starting batch verification for ${imagePaths.length} images');
    final stopwatch = Stopwatch()..start();

    final results = <String?>[];
    int successCount = 0;
    int failureCount = 0;

    for (int i = 0; i < imagePaths.length; i++) {
      final imagePath = imagePaths[i];
      log('[BATCH] Processing ${i + 1}/${imagePaths.length}: $imagePath');

      try {
        final result = await verifyFromImagePathIsolate(imagePath: imagePath, threshold: threshold, staffId: staffId);
        results.add(result);

        if (result != null) {
          successCount++;
          log('[BATCH] ✓ Matched: $result');
        } else {
          failureCount++;
          log('[BATCH] ✗ No match');
        }
      } catch (e) {
        log('[BATCH] Error verifying $imagePath: $e');
        results.add(null);
        failureCount++;
      }
    }

    stopwatch.stop();
    log('[BATCH] Completed: ${results.length} total, $successCount matched, $failureCount no match/failed in ${stopwatch.elapsedMilliseconds}ms');

    return results;
  }

  /// Identify users from multiple images with parallel processing.
  ///
  /// Processes multiple images and returns identification results for each image.
  /// This method is designed for scenarios where you need to verify multiple images
  /// in a single API call (e.g., batch attendance, group verification).
  ///
  /// **Processing:** Parallel batched processing in main isolate.
  /// Images are processed in batches (default: 3 at a time) using Future.wait().
  /// This provides significant speedup while controlling resource usage.
  ///
  /// **Performance:** ~5-7 seconds for 10 images (vs 50 seconds sequential).
  ///
  /// **Safety:** Controlled parallelism prevents crashes from thread exhaustion.
  /// Trade-off: UI may freeze during processing. Increase [batchSize] for speed
  /// but test on target devices first to avoid crashes.
  ///
  /// Returns a list of [ImageIdentificationResult] in the same order as input images.
  /// Each result contains the image path and list of matched user IDs for that image.
  ///
  /// Example:
  /// ```dart
  /// final results = await FaceVerification.instance.identifyUsersFromImagePaths(
  ///   imagePaths: ['/img1.jpg', '/img2.jpg', '/img3.jpg'],
  ///   threshold: 0.70,
  ///   batchSize: 3, // Process 3 images in parallel
  /// );
  /// for (var result in results) {
  ///   print('${result.imagePath}: ${result.userIds}');
  /// }
  /// // Output:
  /// // /img1.jpg: [user123, user456]
  /// // /img2.jpg: []
  /// // /img3.jpg: [user789]
  /// ```
  Future<List<ImageIdentificationResult>> identifyUsersFromImagePaths({required List<String> imagePaths, double threshold = 0.70, int batchSize = 3}) async {
    _ensureInitialized();

    if (imagePaths.isEmpty) return [];

    log('[MULTI-ID] Starting identification for ${imagePaths.length} images');
    final totalStopwatch = Stopwatch()..start();

    // Load all candidate records once (optimization)
    final candidateRecords = await _store.listAll();
    if (candidateRecords.isEmpty) {
      log('[MULTI-ID] No registered faces in database');
      return [];
    }

    log('[MULTI-ID] Loaded ${candidateRecords.length} face records from database');

    // ========== PHASE 1: DETECT FACES FROM ALL IMAGES (PARALLEL) ==========
    log('[MULTI-ID] ========== Phase 1: Detecting faces from all images ==========');
    log('[MULTI-ID] Using parallel processing with batch size: $batchSize');
    final phase1Stopwatch = Stopwatch()..start();

    final List<_ImageFaceData> allImageFaces = [];
    int totalFacesDetected = 0;

    // Split images into batches for parallel processing
    final batches = _chunkList(imagePaths, batchSize);
    log('[MULTI-ID] Processing ${imagePaths.length} images in ${batches.length} batch(es)');

    int processedCount = 0;

    for (int batchIdx = 0; batchIdx < batches.length; batchIdx++) {
      final batch = batches[batchIdx];
      log('[MULTI-ID] Batch ${batchIdx + 1}/${batches.length}: Processing ${batch.length} images in parallel...');

      // Process batch in parallel using Future.wait
      final batchResults = await Future.wait(
        batch.map((imagePath) async {
          try {
            final inputImage = InputImage.fromFilePath(imagePath);
            final faces = await _detector.detectFaces(inputImage);
            final bytes = await File(imagePath).readAsBytes();

            log('[MULTI-ID]   → ${imagePath.split('/').last}: ${faces.length} face(s)');

            return _ImageFaceData(imagePath: imagePath, faces: faces, bytes: bytes);
          } catch (e) {
            log('[MULTI-ID]   → ${imagePath.split('/').last}: Error - $e');
            return _ImageFaceData(imagePath: imagePath, faces: [], bytes: Uint8List(0));
          }
        }),
      );

      // Add batch results to main list
      allImageFaces.addAll(batchResults);
      totalFacesDetected += batchResults.fold<int>(0, (sum, data) => sum + data.faces.length);
      processedCount += batch.length;

      log('[MULTI-ID] Batch ${batchIdx + 1} complete: $processedCount/${imagePaths.length} images processed');
    }

    phase1Stopwatch.stop();
    log('[MULTI-ID] Phase 1 complete: Detected $totalFacesDetected total faces in ${phase1Stopwatch.elapsedMilliseconds}ms');

    // ========== PHASE 2: PROCESS ALL DETECTED FACES ==========
    log('[MULTI-ID] ========== Phase 2: Processing all detected faces ==========');
    final phase2Stopwatch = Stopwatch()..start();

    final List<ImageIdentificationResult> results = [];
    int successfulImages = 0;
    int failedImages = 0;

    for (int i = 0; i < allImageFaces.length; i++) {
      final imageData = allImageFaces[i];
      final imagePath = imageData.imagePath;
      log('[MULTI-ID] Processing image ${i + 1}/${allImageFaces.length}: $imagePath');

      try {
        // Track matched user IDs for THIS image only
        final Set<String> imageUserIds = {};

        if (imageData.faces.isEmpty) {
          log('[MULTI-ID]   → No faces to process');
          results.add(ImageIdentificationResult(imagePath: imagePath, userIds: []));
          continue;
        }

        // Generate embeddings for all faces in this image (in parallel)
        log('[MULTI-ID]   → Generating ${imageData.faces.length} embedding(s) in parallel...');

        final faceEmbeddingResults = await Future.wait(
          imageData.faces.asMap().entries.map((entry) async {
            final faceIdx = entry.key;
            final face = entry.value;
            try {
              final modelInput = await preprocessForModel(rawImageBytes: imageData.bytes, face: face, inputSize: _embedder.getModelInputSize());
              final emb = await _embedder.runModelOnPreprocessed(modelInput);
              if (emb.isNotEmpty) {
                return emb;
              }
            } catch (e) {
              log('[MULTI-ID]   → Error generating embedding for face ${faceIdx + 1}: $e');
            }
            return <double>[];
          }),
        );

        // Filter out empty embeddings
        final List<List<double>> faceEmbeddings = faceEmbeddingResults.where((emb) => emb.isNotEmpty).toList();

        log('[MULTI-ID]   → Successfully generated ${faceEmbeddings.length}/${imageData.faces.length} embedding(s)');

        // Compare each detected face against all stored records
        for (final inputEmbedding in faceEmbeddings) {
          double bestScore = -1.0;
          String? bestMatchId;

          for (final record in candidateRecords) {
            if (record.embedding.length == inputEmbedding.length) {
              final score = cosineSimilarity(record.embedding, inputEmbedding);
              if (score > bestScore) {
                bestScore = score;
                bestMatchId = record.id;
              }
            }
          }

          if (bestMatchId != null && bestScore >= threshold) {
            if (!imageUserIds.contains(bestMatchId)) {
              log('[MULTI-ID]   ✓ Match found: $bestMatchId (score: ${bestScore.toStringAsFixed(3)})');
              imageUserIds.add(bestMatchId);
            }
          }
        }

        // Add result for this image
        results.add(ImageIdentificationResult(imagePath: imagePath, userIds: imageUserIds.toList()));

        successfulImages++;
        log('[MULTI-ID]   → Completed - Found ${imageUserIds.length} user(s)');
      } catch (e) {
        log('[MULTI-ID]   → Error processing: $e');
        failedImages++;
        // Add result with empty user list for failed images
        results.add(ImageIdentificationResult(imagePath: imagePath, userIds: []));
      }
    }

    phase2Stopwatch.stop();
    log('[MULTI-ID] Phase 2 complete: Processed all faces in ${phase2Stopwatch.elapsedMilliseconds}ms');

    totalStopwatch.stop();

    log('[MULTI-ID] ========================================');
    log('[MULTI-ID] Identification complete!');
    log('[MULTI-ID] Total images: ${imagePaths.length}');
    log('[MULTI-ID] Successful: $successfulImages');
    log('[MULTI-ID] Failed: $failedImages');
    log('[MULTI-ID] Total faces detected: $totalFacesDetected');
    log('[MULTI-ID] Phase 1 time: ${phase1Stopwatch.elapsedMilliseconds}ms (face detection)');
    log('[MULTI-ID] Phase 2 time: ${phase2Stopwatch.elapsedMilliseconds}ms (processing)');
    log('[MULTI-ID] Total time: ${totalStopwatch.elapsedMilliseconds}ms');
    log('[MULTI-ID] ========================================');

    return results;
  }

  /// Identify all users from a single photo containing multiple faces.
  /// Returns a list of unique user IDs that match faces in the image.
  /// Each detected face is compared against all stored embeddings.
  Future<List<String>> identifyAllUsersFromImagePath({required String imagePath, double threshold = 0.70}) async {
    _ensureInitialized();

    final candidateRecords = await _store.listAll();
    if (candidateRecords.isEmpty) return [];

    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _detector.detectFaces(inputImage);
    if (faces.isEmpty) return [];

    final bytes = await File(imagePath).readAsBytes();
    final Set<String> matchedUserIds = {};

    // Generate embeddings for all detected faces in the input image
    final List<List<double>> faceEmbeddings = [];
    for (final face in faces) {
      final modelInput = await preprocessForModel(rawImageBytes: bytes, face: face, inputSize: _embedder.getModelInputSize());
      final emb = await _embedder.runModelOnPreprocessed(modelInput);
      if (emb.isNotEmpty) faceEmbeddings.add(emb);
    }

    // For each detected face, find the best matching user
    for (final inputEmbedding in faceEmbeddings) {
      double bestScore = -1.0;
      String? bestMatchId;

      for (final record in candidateRecords) {
        if (record.embedding.length == inputEmbedding.length) {
          final score = cosineSimilarity(record.embedding, inputEmbedding);
          if (score > bestScore) {
            bestScore = score;
            bestMatchId = record.id;
          }
        }
      }

      if (bestMatchId != null && bestScore >= threshold) {
        matchedUserIds.add(bestMatchId);
      }
    }

    log('Detected ${faces.length} faces, identified ${matchedUserIds.length} users: $matchedUserIds');

    return matchedUserIds.toList();
  }

  /// Register a face from a pre-computed embedding (e.g., from server).
  /// Skips if the face record (id + imageId) already exists.
  ///
  /// Returns a map with:
  /// - 'success': bool
  /// - 'message': String (description of what happened)
  /// - 'id': String? (user ID if successful)
  /// - 'imageId': String? (image ID if successful)
  Future<Map<String, dynamic>> registerFromEmbedding({required String id, required String imageId, required List<double> embedding}) async {
    _ensureInitialized();

    // Validate parameters
    if (id.trim().isEmpty) {
      return {'success': false, 'message': 'ID cannot be empty', 'id': null, 'imageId': null};
    }

    if (imageId.trim().isEmpty) {
      return {'success': false, 'message': 'imageId cannot be empty', 'id': null, 'imageId': null};
    }

    // Validate embedding size
    if (embedding.length != 512) {
      return {'success': false, 'message': 'Invalid embedding size: ${embedding.length} (expected 512)', 'id': null, 'imageId': null};
    }

    // Check if already exists
    final existing = await _store.getByUserIdAndImageId(id, imageId);
    if (existing != null) {
      return {'success': false, 'message': 'Face record already exists (skipped)', 'id': id, 'imageId': imageId};
    }

    // Create and insert record
    final record = FaceRecord(id, imageId, embedding);
    await _store.upsert(record, replace: false);

    final totalFaces = await _store.getFaceCountForUser(id);
    log('✓ Registered embedding for user "$id" with imageId "$imageId". Total faces: $totalFaces');

    return {'success': true, 'message': 'Successfully registered', 'id': id, 'imageId': imageId};
  }

  /// Register multiple faces from pre-computed embeddings (batch operation).
  /// Each item in embeddingsData should contain:
  /// - 'staff_id': int or String (user ID)
  /// - 's3_key': String (image identifier)
  /// - 'embedding': List<dynamic> (512 floats)
  ///
  /// Returns a list of results for each embedding with:
  /// - 'success': bool
  /// - 'message': String
  /// - 'id': String?
  /// - 'imageId': String?
  Future<List<Map<String, dynamic>>> registerFromEmbeddingsBatch({required List<Map<String, dynamic>> embeddingsData}) async {
    _ensureInitialized();

    final results = <Map<String, dynamic>>[];

    for (final item in embeddingsData) {
      try {
        // Extract and convert data
        final staffId = item['staff_id']?.toString() ?? '';
        final s3Key = item['s3_key']?.toString() ?? '';
        final embeddingRaw = item['embedding'] as List?;

        if (embeddingRaw == null) {
          results.add({'success': false, 'message': 'Missing embedding data', 'id': staffId.isEmpty ? null : staffId, 'imageId': s3Key.isEmpty ? null : s3Key});
          continue;
        }

        // Convert to List<double>
        final embedding = embeddingRaw.map((e) => (e as num).toDouble()).toList();

        // Register single embedding
        final result = await registerFromEmbedding(id: staffId, imageId: s3Key, embedding: embedding);

        results.add(result);
      } catch (e) {
        results.add({'success': false, 'message': 'Error: ${e.toString()}', 'id': item['staff_id']?.toString(), 'imageId': item['s3_key']?.toString()});
      }
    }

    final successCount = results.where((r) => r['success'] == true).length;
    log('✅ Batch registration complete: $successCount/${results.length} successful');

    return results;
  }

  /// Check if a user has any registered faces
  Future<bool> isFaceRegistered(String id) async {
    _ensureInitialized();
    if (id.trim().isEmpty) return false;

    final faceCount = await _store.getFaceCountForUser(id);
    return faceCount > 0;
  }

  /// Check if a specific face (user ID + image ID combination) is registered
  Future<bool> isFaceRegisteredWithImageId(String id, String imageId) async {
    _ensureInitialized();
    if (id.trim().isEmpty || imageId.trim().isEmpty) return false;

    final record = await _store.getByUserIdAndImageId(id, imageId);
    return record != null;
  }

  /// Get all registered faces for a specific user
  Future<List<FaceRecord>> getFacesForUser(String userId) async {
    _ensureInitialized();
    return _store.getAllByUserId(userId);
  }

  /// Get count of registered faces for a user
  Future<int> getFaceCountForUser(String userId) async {
    _ensureInitialized();
    return _store.getFaceCountForUser(userId);
  }

  /// Get all users who have registered faces
  Future<List<String>> getAllRegisteredUsers() async {
    _ensureInitialized();
    return _store.getAllUserIds();
  }

  /// Legacy method for backward compatibility
  Future<List<FaceRecord>> listRegisteredAsync() async {
    _ensureInitialized();
    return _store.listAll();
  }

  /// Delete a specific face record
  Future<void> deleteFaceRecord(String userId, String imageId) async {
    _ensureInitialized();
    await _store.deleteByUserIdAndImageId(userId, imageId);
  }

  /// Delete all faces for a user
  Future<void> deleteUserFaces(String userId) async {
    _ensureInitialized();
    await _store.deleteAllByUserId(userId);
  }

  /// Legacy delete method for backward compatibility
  Future<void> deleteRecord(String id) async {
    _ensureInitialized();
    await _store.delete(id);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw Exception('FaceVerification not initialized. Call init() first.');
    }
  }

  Future<void> dispose() async {
    _detector.close();
    _embedder.close();
    await _store.close();
    await _verificationPool.close();
    _initialized = false;
  }
}
