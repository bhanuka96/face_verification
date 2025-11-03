// lib/src/utils/tflite_utils.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Shared TFLite utilities that can be used in both main and background isolates.
/// These functions were extracted from TfliteEmbedder to avoid duplication.

/// Run TFLite model on preprocessed image data.
/// This is the EXACT same logic as TfliteEmbedder.runModelOnPreprocessed()
/// but accepts an interpreter parameter so it can be used in isolates.
Future<List<double>> runModelOnPreprocessedData(
  Interpreter interpreter,
  Float32List imageData, {
  double mean = 127.5,
  double std = 128.0,
}) async {
  try {
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputShape = inputTensor.shape;
    final outputShape = outputTensor.shape;
    final outputType = outputTensor.type;
    final inputType = inputTensor.type;

    debugPrint('Input shape: $inputShape, type: $inputType');
    debugPrint('Output shape: $outputShape, type: $outputType');
    debugPrint('Preprocessed data length: ${imageData.length}');

    // If model expects uint8, convert normalized floats back to 0..255 ints
    dynamic dataToFeed;
    if (inputType == TensorType.uint8) {
      // reverse normalization: value = (floatVal * std + mean), clamp 0..255
      final uint8 = Uint8List(imageData.length);
      for (int i = 0; i < imageData.length; i++) {
        final v = (imageData[i] * std + mean).round();
        uint8[i] = v.clamp(0, 255);
      }
      dataToFeed = uint8;
    } else if (inputType == TensorType.float32 || inputType == TensorType.float16) {
      // already Float32List normalized => feed as-is
      dataToFeed = imageData;
    } else {
      throw Exception('Unsupported input tensor type: $inputType');
    }

    // Reshape dataToFeed into nested List matching interpreter expected layout
    final shapedInput = reshapeInput(dataToFeed, inputShape, inputType);

    // Prepare output buffer
    final output = createOutputBuffer(outputShape, outputType);

    // run
    interpreter.run(shapedInput, output);

    // flatten output as in your original code (supports [1,emb], or [emb])
    List<double> flatOutput = [];
    if (outputShape.length == 2) {
      if (outputShape[0] == 1) {
        final firstRow = (output as List<List<dynamic>>)[0];
        flatOutput = firstRow.map((e) => (e as num).toDouble()).toList();
      } else if (outputShape[1] == 1) {
        flatOutput = (output as List<List<dynamic>>)
            .map((row) => (row[0] as num).toDouble())
            .toList();
      } else {
        throw Exception(
            'Model output shape $outputShape looks like detection model. Use embedding model.');
      }
    } else if (outputShape.length == 1) {
      flatOutput = (output as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    } else {
      throw Exception('Unsupported output shape: $outputShape');
    }

    return normalizeEmbedding(flatOutput);
  } catch (e) {
    debugPrint('Error during model inference: $e');
    rethrow;
  }
}

/// Reshape flat input data to match tensor shape.
/// Supports NHWC ([1,H,W,3] or [H,W,3]) and NCHW ([1,3,H,W] or [3,H,W]).
/// data can be Float32List or Uint8List. This returns nested List matching input shape.
dynamic reshapeInput(dynamic data, List<int> shape, TensorType inputType) {
  final isFloat = inputType == TensorType.float32 || inputType == TensorType.float16;
  // Handle common 4D shapes:
  if (shape.length == 4) {
    final batch = shape[0];
    final dim1 = shape[1];
    final dim2 = shape[2];
    final dim3 = shape[3];

    // NHWC: [1, H, W, C] when last dim == 3
    if (dim3 == 3) {
      return List.generate(batch, (b) {
        return List.generate(dim1, (h) {
          return List.generate(dim2, (w) {
            return List.generate(dim3, (c) {
              final idx = ((b * dim1 + h) * dim2 + w) * dim3 + c;
              final val = (idx < data.length ? data[idx] : 0);
              return val is num ? (isFloat ? (val as double) : (val as int)) : val;
            });
          });
        });
      });
    }

    // NCHW: [1, C, H, W] when shape[1] == 3
    if (dim1 == 3) {
      final c = dim1;
      final h = dim2;
      final w = dim3;
      return List.generate(batch, (b) {
        return List.generate(c, (ch) {
          return List.generate(h, (yy) {
            return List.generate(w, (xx) {
              final idx = ((b * c + ch) * h + yy) * w + xx;
              final val = (idx < data.length ? data[idx] : 0);
              return val is num ? (isFloat ? (val as double) : (val as int)) : val;
            });
          });
        });
      });
    }
  }

  // 3D: [H,W,C] or [C,H,W]
  if (shape.length == 3) {
    if (shape[2] == 3) {
      final h = shape[0], w = shape[1], c = shape[2];
      return List.generate(h, (yy) {
        return List.generate(w, (xx) {
          return List.generate(c, (ch) {
            final idx = (yy * w + xx) * c + ch;
            final val = (idx < data.length ? data[idx] : 0);
            return val is num ? (isFloat ? (val as double) : (val as int)) : val;
          });
        });
      });
    } else if (shape[0] == 3) {
      // [C,H,W]
      final c = shape[0], h = shape[1], w = shape[2];
      return List.generate(c, (ch) {
        return List.generate(h, (yy) {
          return List.generate(w, (xx) {
            final idx = ((ch * h) + yy) * w + xx;
            final val = (idx < data.length ? data[idx] : 0);
            return val is num ? (isFloat ? (val as double) : (val as int)) : val;
          });
        });
      });
    }
  }

  // fallback: flatten to 1D list
  if (shape.length == 1) {
    return List.generate(shape[0], (i) => (i < data.length ? data[i] : 0));
  }

  throw Exception('Unsupported input shape: $shape');
}

/// Create output buffer matching the tensor's shape and numeric type
dynamic createOutputBuffer(List<int> shape, TensorType type) {
  const zeroDouble = 0.0;
  const zeroInt = 0;

  bool isFloatType = type == TensorType.float32 || type == TensorType.float16;

  if (shape.length == 2) {
    return List.generate(
      shape[0],
      (_) => List.filled(shape[1], isFloatType ? zeroDouble : zeroInt),
    );
  } else if (shape.length == 1) {
    return List.filled(shape[0], isFloatType ? zeroDouble : zeroInt);
  } else {
    throw Exception('Unsupported output shape: $shape');
  }
}

/// L2 normalize the embedding vector
List<double> normalizeEmbedding(List<double> embedding) {
  double norm = 0.0;
  for (double val in embedding) {
    norm += val * val;
  }
  norm = math.sqrt(norm);

  if (norm == 0.0) {
    return embedding; // Avoid division by zero
  }

  return embedding.map((val) => val / norm).toList();
}
