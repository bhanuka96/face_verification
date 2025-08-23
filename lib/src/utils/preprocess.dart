// lib/src/utils/preprocess.dart
import 'dart:typed_data';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Preprocess image bytes + ML Kit Face => Float32List ready for model.
/// NOTE: this returns Float32List normalized by (r-mean)/std as before.
/// We avoid rotating the whole image here because ML Kit boundingBox coords
/// are from original image; rotating would require transforming those coords.
Future<Float32List> preprocessForModel({
  required Uint8List rawImageBytes,
  required Face face,
  required int inputSize, // e.g., 112
  double mean = 127.5,
  double std = 128.0,
}) async {
  img.Image? image = img.decodeImage(rawImageBytes);
  if (image == null) throw Exception('Could not decode image bytes');

  // Use bounding box with margin; do NOT rotate the image here.
  final rect = face.boundingBox;
  final cx = (rect.left + rect.right) / 2.0;
  final cy = (rect.top + rect.bottom) / 2.0;
  final boxSize = max(rect.width, rect.height) * 1.4;

  int left = (cx - boxSize / 2).round();
  int top = (cy - boxSize / 2).round();
  int width = boxSize.round();
  int height = boxSize.round();

  // clamp to image boundaries
  if (left < 0) left = 0;
  if (top < 0) top = 0;
  if (left + width > image.width) width = image.width - left;
  if (top + height > image.height) height = image.height - top;
  if (width <= 0 || height <= 0) {
    // fallback to full image
    left = 0;
    top = 0;
    width = image.width;
    height = image.height;
  }

  final cropped = img.copyCrop(image, x: left, y: top, width: width, height: height);

  // Resize/crop to square inputSize
  final resized = img.copyResizeCropSquare(cropped, size: inputSize);

  // Build Float32List in RGB order normalized (mean/std)
  final w = resized.width;
  final h = resized.height;
  final out = Float32List(w * h * 3);
  int idx = 0;
  for (int yy = 0; yy < h; yy++) {
    for (int xx = 0; xx < w; xx++) {
      final img.Pixel pixel = resized.getPixel(xx, yy);
      final int r = pixel.r.toInt();
      final int g = pixel.g.toInt();
      final int b = pixel.b.toInt();

      out[idx++] = (r - mean) / std;
      out[idx++] = (g - mean) / std;
      out[idx++] = (b - mean) / std;
    }
  }
  return out;
}
