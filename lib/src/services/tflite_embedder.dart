// lib/src/services/tflite_embedder.dart
import 'dart:math' as math;
// ignore: unnecessary_import
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteEmbedder {
  Interpreter? _interpreter;
  final String modelAsset;
  final int inputSize;
  final int embSize;

  TfliteEmbedder({required this.modelAsset, this.inputSize = 112, this.embSize = 512});

  Future<void> loadModel({int numThreads = 4}) async {
    try {
      final opts = InterpreterOptions()..threads = numThreads;
      _interpreter = await Interpreter.fromAsset(modelAsset, options: opts);
      debugPrint('Model loaded successfully');

      // Print input/output tensor info for debugging
      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      debugPrint('Input shape: ${inputTensor.shape}');
      debugPrint('Output shape: ${outputTensor.shape}');
      debugPrint('Input type: ${inputTensor.type}');
      debugPrint('Output type: ${outputTensor.type}');
    } catch (e) {
      debugPrint('Error loading model: $e');
      rethrow;
    }
  }

  // inside TfliteEmbedder class in tflite_embedder.dart
  Future<List<double>> runModelOnPreprocessed(Float32List imageData, {double mean = 127.5, double std = 128.0}) async {
    if (_interpreter == null) {
      throw Exception('Interpreter not loaded. Call loadModel() first.');
    }

    try {
      final interpreter = _interpreter!;
      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);
      final inputShape = inputTensor.shape; // e.g., [1,112,112,3] or [1,3,112,112]
      final outputShape = outputTensor.shape;
      final outputType = outputTensor.type;
      final inputType = inputTensor.type;

      debugPrint('Input shape: $inputShape, type: $inputType');
      debugPrint('Output shape: $outputShape, type: $outputType');
      debugPrint('Preprocessed data length: ${imageData.length}');

      final expectedInputLength = inputShape.reduce((a, b) => a * b);
      if (imageData.length != expectedInputLength && !(inputShape.length == 4 && inputShape[0] == 1 && imageData.length == inputShape[1] * inputShape[2] * inputShape[3])) {
        // For NCHW shape this check below accounts accordingly
        // But prefer to continue and reshape carefully below
        debugPrint('Warning: provided imageData length ${imageData.length} does not match inputTensor total $expectedInputLength');
      }

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
      final shapedInput = _reshapeInput(dataToFeed, inputShape, inputType);

      // Prepare output buffer
      final output = _createOutputBuffer(outputShape, outputType);

      // run
      interpreter.run(shapedInput, output);

      // flatten output as in your original code (supports [1,emb], or [emb])
      List<double> flatOutput = [];
      if (outputShape.length == 2) {
        if (outputShape[0] == 1) {
          final firstRow = (output as List<List<dynamic>>)[0];
          flatOutput = firstRow.map((e) => (e as num).toDouble()).toList();
        } else if (outputShape[1] == 1) {
          flatOutput = (output as List<List<dynamic>>).map((row) => (row[0] as num).toDouble()).toList();
        } else {
          throw Exception('Model output shape $outputShape looks like detection model. Use embedding model.');
        }
      } else if (outputShape.length == 1) {
        flatOutput = (output as List<dynamic>).map((e) => (e as num).toDouble()).toList();
      } else {
        throw Exception('Unsupported output shape: $outputShape');
      }

      return _normalizeEmbedding(flatOutput);
    } catch (e) {
      debugPrint('Error during model inference: $e');
      rethrow;
    }
  }

  /// data can be Float32List or Uint8List. This returns nested List matching input shape.
  /// Supports NHWC ([1,H,W,3] or [H,W,3]) and NCHW ([1,3,H,W] or [3,H,W]).
  dynamic _reshapeInput(dynamic data, List<int> shape, TensorType inputType) {
    // Flattened length check
    // final totalLen = shape.reduce((a, b) => a * b);
    // data length might be totalLen or (totalLen / batch) if batch=1 etc
    final isFloat = inputType == TensorType.float32 || inputType == TensorType.float16;

    // Handle common 4D shapes:
    if (shape.length == 4) {
      final batch = shape[0];
      final dim1 = shape[1];
      final dim2 = shape[2];
      final dim3 = shape[3];

      // NHWC: [1, H, W, C] when last dim == 3
      if (dim3 == 3) {
        // build List(batch)[ List(height)[ List(width)[ List(ch) ] ] ]
        return List.generate(batch, (b) {
          return List.generate(dim1, (h) {
            return List.generate(dim2, (w) {
              return List.generate(dim3, (c) {
                final idx = ((b * dim1 + h) * dim2 + w) * dim3 + c;
                final val = (idx < (data.length) ? data[idx] : 0);
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
                // index mapping: ((b * c + ch) * h + yy) * w + xx
                final idx = ((b * c + ch) * h + yy) * w + xx;
                final val = (idx < (data.length) ? data[idx] : 0);
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
              final val = (idx < (data.length) ? data[idx] : 0);
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
              final val = (idx < (data.length) ? data[idx] : 0);
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

  /// Returns the model's expected square input size (height), falling back to
  /// the configured inputSize if the interpreter is not yet available.
  int getModelInputSize() {
    if (_interpreter == null) return inputSize;
    final shape = _interpreter!.getInputTensor(0).shape;
    if (shape.length == 4) {
      // [batch, height, width, channels]
      return shape[1];
    } else if (shape.length == 3) {
      // [height, width, channels]
      return shape[0];
    }
    return inputSize;
  }

  /// Returns the current model's output shape.
  List<int> getModelOutputShape() {
    if (_interpreter == null) return [embSize];
    return _interpreter!.getOutputTensor(0).shape;
  }

  /// Quick heuristic to check if the loaded model looks like an embedding model.
  /// Accepts 1D [emb] or 2D [1, emb] where emb is in allowed sizes.
  bool isLikelyEmbeddingModel({List<int> allowedEmbSizes = const [512, 256, 192, 128, 64]}) {
    if (_interpreter == null) return true; // assume OK before load
    final shape = getModelOutputShape();
    if (shape.length == 1) {
      return allowedEmbSizes.contains(shape[0]);
    }
    if (shape.length == 2 && shape[0] == 1) {
      return allowedEmbSizes.contains(shape[1]);
    }
    return false;
  }

  /// Create an output buffer matching the tensor's shape and numeric type
  dynamic _createOutputBuffer(List<int> shape, TensorType type) {
    const zeroDouble = 0.0;
    const zeroInt = 0;

    bool isFloatType = type == TensorType.float32 || type == TensorType.float16;

    if (shape.length == 2) {
      return List.generate(shape[0], (_) => List.filled(shape[1], isFloatType ? zeroDouble : zeroInt));
    } else if (shape.length == 1) {
      return List.filled(shape[0], isFloatType ? zeroDouble : zeroInt);
    } else {
      // Fallback for unexpected ranks
      throw Exception('Unsupported output shape: $shape');
    }
  }

  /// L2 normalize the embedding vector
  List<double> _normalizeEmbedding(List<double> embedding) {
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

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}
