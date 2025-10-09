import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'src/services/face_detector.dart';
import 'src/services/storage.dart';
import 'src/services/tflite_embedder.dart';
import 'src/utils/preprocess.dart';
import 'src/services/verification.dart';

/// High-level API for registration and verification with multiple faces per user.
class FaceVerification {
  static final FaceVerification instance = FaceVerification._internal();

  FaceVerification._internal();

  late TfliteEmbedder _embedder;
  final FaceDetectorService _detector = FaceDetectorService();
  final FaceStore _store = FaceStore();

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
      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing FaceVerification: $e');
      rethrow;
    }
  }

  /// Register a face from an image file path with mandatory user-provided ID.
  /// Now supports multiple faces per user.
  /// Returns the provided ID if successful.
  Future<String> registerFromImagePath({required String id, required String imagePath, required String imageId, bool replace = true}) async {
    _ensureInitialized();

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

    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _detector.detectFaces(inputImage);
    if (faces.isEmpty) {
      throw Exception('No face detected');
    }
    if (faces.length > 1) {
      throw Exception('Multiple faces detected');
    }

    final bytes = await File(imagePath).readAsBytes();
    final modelInput = await preprocessForModel(rawImageBytes: bytes, face: faces.first, inputSize: _embedder.getModelInputSize());
    final embedding = await _embedder.runModelOnPreprocessed(modelInput);
    if (embedding.isEmpty) throw Exception('Failed to generate embedding');

    final record = FaceRecord(id, imageId, embedding);
    await _store.upsert(record, replace: replace);

    final totalFaces = await _store.getFaceCountForUser(id);
    final action = existingRecord != null ? "Replaced" : "Registered";
    debugPrint('$action face for user "$id" with imageId "$imageId". Total faces for user: $totalFaces');

    return id;
  }

  /// Verify a face image against all stored embeddings for the user.
  /// If staffId is provided, only compares against that user's faces.
  /// If staffId is null, compares against all users' faces.
  Future<String?> verifyFromImagePath({required String imagePath, double threshold = 0.70, String? staffId}) async {
    _ensureInitialized();

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
    _initialized = false;
  }
}
