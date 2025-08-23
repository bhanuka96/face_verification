import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'face_verification_platform_interface.dart';

/// An implementation of [FaceVerificationPlatform] that uses method channels.
class MethodChannelFaceVerification extends FaceVerificationPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('face_verification');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
