import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

Uint8List cropFace(Uint8List imageBytes, Face face) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return imageBytes;

  final box = face.boundingBox;

  final cropped = img.copyCrop(
    decoded,
    x: box.left.toInt().clamp(0, decoded.width - 1),
    y: box.top.toInt().clamp(0, decoded.height - 1),
    width: box.width.toInt().clamp(1, decoded.width),
    height: box.height.toInt().clamp(1, decoded.height),
  );

  return Uint8List.fromList(img.encodeJpg(cropped));
}
