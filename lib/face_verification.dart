// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/to/pubspec-plugin-platforms.

import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'src/services/face_detector.dart';
import 'src/services/storage.dart';
import 'src/services/tflite_embedder.dart';
import 'src/utils/preprocess.dart';
import 'src/services/verification.dart';

/// High-level API for registration and verification.
class FaceVerification {
  static final FaceVerification instance = FaceVerification._internal();

  FaceVerification._internal();

  late TfliteEmbedder _embedder;
  final FaceDetectorService _detector = FaceDetectorService();
  final FaceStore _store = FaceStore();

  bool _initialized = false;

  /// Initialize Hive, open box, and load TFLite embedding model.
  /// - [modelAsset] should point to a 112x112 face embedding model (e.g. facenet.tflite).
  Future<void> init({String modelAsset = 'packages/face_verification/assets/models/facenet.tflite', int numThreads = 4}) async {
    if (_initialized) return;
    await _store.init();

    _embedder = TfliteEmbedder(modelAsset: modelAsset);
    await _embedder.loadModel(numThreads: numThreads);
    if (!_embedder.isLikelyEmbeddingModel()) {
      throw Exception('Loaded model does not look like an embedding model.');
    }
    _initialized = true;
  }

  /// Register a face from an image file path with mandatory user-provided ID.
  /// Returns the provided ID if successful.
  Future<String> registerFromImagePath({required String id, required String imagePath, required String imageId}) async {
    _ensureInitialized();

    // Validate mandatory ID parameter
    if (id.trim().isEmpty) {
      throw ArgumentError('ID cannot be empty or null');
    }

    // Validate image ID parameter
    if (imageId.trim().isEmpty) {
      throw ArgumentError('imageId cannot be empty or null');
    }

    // Check if ID already exists
    final existingRecord = await _store.getById(id);
    if (existingRecord != null) {
      // If imageId is the same, don't allow duplicate registration
      if (existingRecord.imageId == imageId) {
        throw Exception('A face record with ID "$id" and imageId "$imageId" already exists');
      }
      // If imageId is different, we'll proceed to update/re-register
      debugPrint('Re-registering face for ID "$id" with new imageId "$imageId" (previous: "${existingRecord.imageId}")');
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
    await _store.upsert(record);
    return id;
  }

  /// Verify a face image against stored embeddings. Returns best match or null.
  Future<String?> verifyFromImagePath({required String imagePath, double threshold = 0.70, String? staffId}) async {
    _ensureInitialized();
    List<FaceRecord> all = [];
    if (staffId != null && staffId != 'null') {
      final faceRec = await _store.getById(staffId);
      if (faceRec != null) {
        all.add(faceRec);
      }
    } else {
      all = await _store.listAll();
    }
    if (all.isEmpty) return null;

    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _detector.detectFaces(inputImage);
    if (faces.isEmpty) return null;

    final bytes = await File(imagePath).readAsBytes();
    double bestScore = -1.0;
    String? id;

    // final modelInput = await preprocessForModel(rawImageBytes: bytes, face: faces.first, inputSize: _embedder.getModelInputSize());
    // final embedding = await _embedder.runModelOnPreprocessed(modelInput);
    // if (embedding.isEmpty) return null;
    final Map<Face, List<double>> faceEmbeddings = {};
    for (final face in faces) {
      final modelInput = await preprocessForModel(rawImageBytes: bytes, face: face, inputSize: _embedder.getModelInputSize());
      final emb = await _embedder.runModelOnPreprocessed(modelInput);
      if (emb.isNotEmpty) faceEmbeddings[face] = emb;
    }

    for (final record in all) {
      for (final embedding in faceEmbeddings.values) {
        if (record.embedding.length == embedding.length) {
          final score = cosineSimilarity(record.embedding, embedding);
          if (score > bestScore) {
            bestScore = score;
            id = record.id;
          }
        }
      }
    }
    log('Best Score: $bestScore, ID: $id, All:${all.length}');
    if (id != null && bestScore >= threshold) {
      return id;
    }
    return null;
  }

  /// Check if a face is registered by ID
  /// Returns true if face is registered, false otherwise
  Future<bool> isFaceRegistered(String id) async {
    _ensureInitialized();

    if (id.trim().isEmpty) {
      return false;
    }

    final record = await _store.getById(id);
    return record != null;
  }

  /// Check if a face is registered with specific ID and imageId combination
  /// Returns true if exact match found, false otherwise
  Future<bool> isFaceRegisteredWithImageId(String id, String imageId) async {
    _ensureInitialized();

    if (id.trim().isEmpty || imageId.trim().isEmpty) {
      return false;
    }

    log('ID:$id,StaffId:$imageId');

    final record = await _store.getById(id);
    inspect(record);
    return record != null && record.imageId == imageId;
  }

  Future<List<FaceRecord>> listRegisteredAsync() async {
    _ensureInitialized();
    return _store.listAll();
  }

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
