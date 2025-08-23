// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/to/pubspec-plugin-platforms.

import 'dart:io';
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

  /// Register a face from an image file path. Returns stored record id.
  Future<String> registerFromImagePath({required String imagePath, required String displayName}) async {
    _ensureInitialized();
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

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final record = FaceRecord(id, displayName, embedding, imagePath: imagePath);
    await _store.upsert(record);
    return id;
  }

  /// Verify a face image against stored embeddings. Returns best match or null.
  Future<FaceRecord?> verifyFromImagePath({required String imagePath, double threshold = 0.70}) async {
    _ensureInitialized();
    final all = await _store.listAll();
    if (all.isEmpty) return null;

    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _detector.detectFaces(inputImage);
    if (faces.isEmpty) return null;

    final bytes = await File(imagePath).readAsBytes();
    final modelInput = await preprocessForModel(rawImageBytes: bytes, face: faces.first, inputSize: _embedder.getModelInputSize());
    final embedding = await _embedder.runModelOnPreprocessed(modelInput);
    if (embedding.isEmpty) return null;

    double bestScore = -1.0;
    FaceRecord? best;
    for (final record in all) {
      if (record.embedding.length == embedding.length) {
        final score = cosineSimilarity(record.embedding, embedding);
        if (score > bestScore) {
          bestScore = score;
          best = record;
        }
      }
    }
    if (best != null && bestScore >= threshold) {
      return best;
    }
    return null;
  }

  Iterable<FaceRecord> listRegistered() {
    _ensureInitialized();
    // Note: this is now async in SQLite world; providing a sync snapshot is complex.
    // For API stability, we can return an empty list here and recommend using a new async method.
    return const [];
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
