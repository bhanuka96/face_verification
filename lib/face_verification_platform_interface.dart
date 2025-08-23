import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'face_verification_method_channel.dart';

abstract class FaceVerificationPlatform extends PlatformInterface {
  /// Constructs a FaceVerificationPlatform.
  FaceVerificationPlatform() : super(token: _token);

  static final Object _token = Object();

  static FaceVerificationPlatform _instance = MethodChannelFaceVerification();

  /// The default instance of [FaceVerificationPlatform] to use.
  ///
  /// Defaults to [MethodChannelFaceVerification].
  static FaceVerificationPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FaceVerificationPlatform] when
  /// they register themselves.
  static set instance(FaceVerificationPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
