import 'package:flutter_test/flutter_test.dart';
import 'package:face_verification/face_verification_platform_interface.dart';
import 'package:face_verification/face_verification_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFaceVerificationPlatform
    with MockPlatformInterfaceMixin
    implements FaceVerificationPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FaceVerificationPlatform initialPlatform = FaceVerificationPlatform.instance;

  test('$MethodChannelFaceVerification is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFaceVerification>());
  });

  test('getPlatformVersion', () async {
    // FaceVerification faceVerificationPlugin = FaceVerification();
    // MockFaceVerificationPlatform fakePlatform = MockFaceVerificationPlatform();
    // FaceVerificationPlatform.instance = fakePlatform;

    // expect(await faceVerificationPlugin.getPlatformVersion(), '42');
  });
}
