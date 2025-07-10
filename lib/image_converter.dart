import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

int _deviceOrientationToDegrees(DeviceOrientation orientation) {
  switch (orientation) {
    case DeviceOrientation.portraitUp:
      return 0;
    case DeviceOrientation.landscapeLeft:
      return 90;
    case DeviceOrientation.portraitDown:
      return 180;
    case DeviceOrientation.landscapeRight:
      return 270;
  }
}

Uint8List _convertYUV420toNV21(CameraImage image) {
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yBuffer = yPlane.bytes;
  final uBuffer = uPlane.bytes;
  final vBuffer = vPlane.bytes;

  final ySize = yBuffer.lengthInBytes;
  final uSize = uBuffer.lengthInBytes;

  final nv21Bytes = Uint8List(ySize + uSize * 2);

  // Copy Y plane
  nv21Bytes.setRange(0, ySize, yBuffer);

  // Interleave V and U planes
  for (int i = 0; i < uSize; i++) {
    nv21Bytes[ySize + 2 * i] = vBuffer[i];
    nv21Bytes[ySize + 2 * i + 1] = uBuffer[i];
  }

  return nv21Bytes;
}

InputImage? inputImageFromCameraImage(
    CameraImage image,
    CameraController? controller,
    List<CameraDescription> cameras,
    int cameraIndex) {
  if (controller == null) return null;

  final camera = cameras[cameraIndex];
  final sensorOrientation = camera.sensorOrientation;
  InputImageRotation? rotation;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    var rotationCompensation =
        _deviceOrientationToDegrees(controller.value.deviceOrientation);
    if (camera.lensDirection == CameraLensDirection.front) {
      // front-facing
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      // back-facing
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
  }

  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);

  // iOSの場合はbgra8888のみを許可し、それ以外はnullを返す
  if (defaultTargetPlatform == TargetPlatform.iOS &&
      format != InputImageFormat.bgra8888) {
    return null;
  }

  // Androidの場合のフォーマット処理
  Uint8List bytes;
  InputImageFormat inputFormat;
  int bytesPerRow;

  if (defaultTargetPlatform == TargetPlatform.android) {
    if (format == InputImageFormat.yuv_420_888) {
      bytes = _convertYUV420toNV21(image);
      inputFormat = InputImageFormat.nv21;
      bytesPerRow = image.planes[0].bytesPerRow;
    } else if (format == InputImageFormat.nv21) {
      final allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      bytes = allBytes.done().buffer.asUint8List();
      inputFormat = InputImageFormat.nv21;
      bytesPerRow = image.planes[0].bytesPerRow;
    } else {
      // Androidでサポートされていないフォーマットの場合
      return null;
    }
  } else { // iOSの場合
    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    bytes = allBytes.done().buffer.asUint8List();
    inputFormat = format!; // iOSではbgra8888が保証されている
    bytesPerRow = image.planes[0].bytesPerRow; // iOSのbgra8888は1プレーン
  }

  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: inputFormat,
      bytesPerRow: bytesPerRow,
    ),
  );
}
