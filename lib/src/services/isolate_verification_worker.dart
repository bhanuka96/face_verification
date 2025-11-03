// lib/src/services/isolate_verification_worker.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// Import shared utilities from the main codebase
import '../utils/preprocess.dart';
import '../utils/tflite_utils.dart';
import 'verification.dart';

/// Top-level function for running verification in a background isolate.
///
/// This attempts to run the ENTIRE verification pipeline in an isolate:
/// 1. Face detection (ML Kit) - will test if this works!
/// 2. Image preprocessing
/// 3. TFLite embedding generation
/// 4. Database query
/// 5. Cosine similarity comparison
///
/// Parameters:
/// - imagePath: Path to the image to verify
/// - dbPath: Database path (obtained from main isolate via path_provider)
/// - threshold: Similarity threshold for matching
/// - staffId: Optional user ID to verify against (null = verify against all)
/// - modelBytes: TFLite model bytes (loaded on main isolate)
/// - rootIsolateToken: Token for initializing BackgroundIsolateBinaryMessenger
/// - modelInputSize: Expected input size for the model (e.g., 112 for 112x112)
///
/// Returns a Map with:
/// - success: bool
/// - matchId: String? (matched user ID or null)
/// - bestScore: double
/// - timings: Map<String, int> (breakdown of time spent in each step)
/// - error: String? (error message if failed)
Future<Map<String, dynamic>> isolateVerificationWorker(Map<String, dynamic> params) async {
  final imagePath = params['imagePath'] as String;
  final dbPath = params['dbPath'] as String;
  final threshold = params['threshold'] as double;
  final staffId = params['staffId'] as String?;
  final modelBytes = params['modelBytes'] as Uint8List;
  final rootIsolateToken = params['rootIsolateToken'] as RootIsolateToken;
  final modelInputSize = params['modelInputSize'] as int;

  debugPrint('[ISOLATE] Starting verification worker...');
  debugPrint('[ISOLATE] Image: $imagePath');
  debugPrint('[ISOLATE] DB: $dbPath');
  debugPrint('[ISOLATE] Threshold: $threshold');
  debugPrint('[ISOLATE] Model input size: $modelInputSize');

  final timings = <String, int>{};
  final totalStopwatch = Stopwatch()..start();

  try {
    // Initialize BackgroundIsolateBinaryMessenger for method channel access
    debugPrint('[ISOLATE] Initializing BackgroundIsolateBinaryMessenger...');
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
    debugPrint('[ISOLATE] ✅ BackgroundIsolateBinaryMessenger initialized');

    // Step 1: Face Detection (ML Kit)
    debugPrint('[ISOLATE] Step 1: Face Detection (testing if ML Kit works in isolate...)');
    final faceDetectionStopwatch = Stopwatch()..start();

    final inputImage = InputImage.fromFilePath(imagePath);
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    final faces = await detector.processImage(inputImage);
    faceDetectionStopwatch.stop();
    timings['faceDetection'] = faceDetectionStopwatch.elapsedMilliseconds;

    debugPrint('[ISOLATE] ✅ Face detection WORKS in isolate! Detected ${faces.length} faces in ${faceDetectionStopwatch.elapsedMilliseconds}ms');

    if (faces.isEmpty) {
      detector.close();
      totalStopwatch.stop();
      return {
        'success': true,
        'matchId': null,
        'bestScore': 0.0,
        'timings': {...timings, 'total': totalStopwatch.elapsedMilliseconds},
        'error': null,
        'reason': 'No face detected',
      };
    }

    // Step 2: Preprocessing
    debugPrint('[ISOLATE] Step 2: Preprocessing image...');
    final preprocessStopwatch = Stopwatch()..start();

    final bytes = await File(imagePath).readAsBytes();
    // Use the original preprocessForModel function from preprocess.dart
    final preprocessed = await preprocessForModel(
      rawImageBytes: bytes,
      face: faces.first,
      inputSize: modelInputSize,
    );

    preprocessStopwatch.stop();
    timings['preprocessing'] = preprocessStopwatch.elapsedMilliseconds;

    debugPrint('[ISOLATE] Preprocessing completed in ${preprocessStopwatch.elapsedMilliseconds}ms');

    detector.close();

    // Step 3: TFLite Embedding Generation
    debugPrint('[ISOLATE] Step 3: TFLite embedding generation...');
    final tfliteStopwatch = Stopwatch()..start();

    final opts = InterpreterOptions()..threads = 4;
    final interpreter = Interpreter.fromBuffer(modelBytes, options: opts);

    // Use the EXACT same logic as the production code
    // This ensures identical results between normal and isolate verification
    final embedding = await runModelOnPreprocessedData(interpreter, preprocessed);

    interpreter.close();
    tfliteStopwatch.stop();
    timings['tfliteInference'] = tfliteStopwatch.elapsedMilliseconds;

    debugPrint('[ISOLATE] ✅ TFLite works in isolate! Inference completed in ${tfliteStopwatch.elapsedMilliseconds}ms');

    // Step 4: Database Query
    debugPrint('[ISOLATE] Step 4: Database query...');
    final dbStopwatch = Stopwatch()..start();

    final db = await openDatabase(dbPath);

    List<Map<String, Object?>> rows;
    if (staffId != null && staffId != 'null' && staffId.isNotEmpty) {
      rows = await db.query('faces', where: 'id = ?', whereArgs: [staffId]);
    } else {
      rows = await db.query('faces');
    }

    dbStopwatch.stop();
    timings['dbQuery'] = dbStopwatch.elapsedMilliseconds;

    debugPrint('[ISOLATE] Loaded ${rows.length} records from database in ${dbStopwatch.elapsedMilliseconds}ms');

    if (rows.isEmpty) {
      // Note: Don't close DB here - let it be cleaned up when isolate exits
      // Closing it can interfere with the main isolate's connection
      totalStopwatch.stop();
      return {
        'success': true,
        'matchId': null,
        'bestScore': 0.0,
        'timings': {...timings, 'total': totalStopwatch.elapsedMilliseconds},
        'error': null,
        'reason': 'No registered faces in database',
      };
    }

    // Step 5: Comparison
    debugPrint('[ISOLATE] Step 5: Comparing against ${rows.length} stored embeddings...');
    final comparisonStopwatch = Stopwatch()..start();

    double bestScore = -1.0;
    String? bestMatchId;

    for (final row in rows) {
      final storedEmbedding = (jsonDecode(row['embedding'] as String) as List)
          .map((e) => (e as num).toDouble())
          .toList();

      if (storedEmbedding.length == embedding.length) {
        // Use the original cosineSimilarity function from verification.dart
        final score = cosineSimilarity(embedding, storedEmbedding);

        if (score > bestScore) {
          bestScore = score;
          bestMatchId = row['id'] as String;
        }
      }
    }

    // Note: Don't close DB - let it be cleaned up when isolate exits
    // Closing it explicitly can interfere with the main isolate's connection on some platforms
    comparisonStopwatch.stop();
    timings['comparison'] = comparisonStopwatch.elapsedMilliseconds;

    debugPrint('[ISOLATE] Comparison completed in ${comparisonStopwatch.elapsedMilliseconds}ms');
    debugPrint('[ISOLATE] Best match: $bestMatchId with score $bestScore');

    totalStopwatch.stop();
    timings['total'] = totalStopwatch.elapsedMilliseconds;

    debugPrint('[ISOLATE] ✅ Verification completed successfully in ${totalStopwatch.elapsedMilliseconds}ms');

    return {
      'success': true,
      'matchId': bestScore >= threshold ? bestMatchId : null,
      'bestScore': bestScore,
      'recordsCompared': rows.length,
      'timings': timings,
      'error': null,
    };
  } catch (e, stackTrace) {
    totalStopwatch.stop();
    timings['total'] = totalStopwatch.elapsedMilliseconds;

    debugPrint('[ISOLATE] ❌ Error in verification worker: $e');
    debugPrint('[ISOLATE] Stack trace: $stackTrace');

    return {
      'success': false,
      'matchId': null,
      'bestScore': 0.0,
      'timings': timings,
      'error': e.toString(),
      'stackTrace': stackTrace.toString(),
    };
  }
}
