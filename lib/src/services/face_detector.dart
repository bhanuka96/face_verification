// lib/src/services/face_detector.dart
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorService {
  final FaceDetector _detector = FaceDetector(options: FaceDetectorOptions(enableLandmarks: true, enableContours: true, performanceMode: FaceDetectorMode.accurate));

  Future<List<Face>> detectFaces(InputImage inputImage) async {
    return await _detector.processImage(inputImage);
  }

  void close() => _detector.close();
}
