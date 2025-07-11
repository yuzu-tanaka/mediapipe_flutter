import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart'; // applyBoxFitのためにインポート
import 'package:flutter/services.dart'; // DeviceOrientationのためにインポート
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// image_converter.dartから持ってきたヘルパー関数
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

/// ポーズの骨格を描画するためのCustomPainter
class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size? imageSize;
  final int sensorOrientation;
  final DeviceOrientation deviceOrientation;
  final CameraLensDirection lensDirection;

  PosePainter(this.poses, this.imageSize, this.sensorOrientation,
      this.deviceOrientation, this.lensDirection);

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null) return;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 5.0;

    // ML Kitに渡される画像の向きを計算し、処理される画像のサイズを特定する
    var rotationCompensation = _deviceOrientationToDegrees(deviceOrientation);
    if (lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      // back-facing
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    final bool isRotated = rotationCompensation == 90 || rotationCompensation == 270;
    final Size inputImageSize =
        isRotated ? Size(imageSize!.height, imageSize!.width) : imageSize!;

    // 画面に表示するために画像をどのようにフィットさせるかを計算
    final FittedSizes fittedSizes =
        applyBoxFit(BoxFit.cover, inputImageSize, size);

    // Alignment.center.inscribe を使って、中央に配置された source と destination の Rect を計算する
    // これにより、CameraPreview の表示と描画の座標系が一致する
    final Rect sourceRect = Alignment.center.inscribe(fittedSizes.source, Offset.zero & inputImageSize);
    final Rect destRect = Alignment.center.inscribe(fittedSizes.destination, Offset.zero & size);

    // 座標変換のためのスケールを計算
    final double scaleX = destRect.width / sourceRect.width;
    final double scaleY = destRect.height / sourceRect.height;

    for (final pose in poses) {
      for (final landmark in pose.landmarks.values) {
        // ランドマークの座標を画面座標に変換
        // 1. 元画像での座標から、表示される部分(source)の左上を原点にする
        // 2. 画面サイズに合わせてスケーリングする
        // 3. 描画先の左上オフセット(destination)を足す
        double dx = (landmark.x - sourceRect.left) * scaleX + destRect.left;
        double dy = (landmark.y - sourceRect.top) * scaleY + destRect.top;

        // インカメラの場合は左右反転
        if (lensDirection == CameraLensDirection.front) {
          dx = size.width - dx;
        }
        canvas.drawCircle(Offset(dx, dy), 2, paint);
      }

      void drawLine(PoseLandmarkType type1, PoseLandmarkType type2) {
        final landmark1 = pose.landmarks[type1];
        final landmark2 = pose.landmarks[type2];
        if (landmark1 != null && landmark2 != null) {
          double dx1 = (landmark1.x - sourceRect.left) * scaleX + destRect.left;
          double dy1 = (landmark1.y - sourceRect.top) * scaleY + destRect.top;
          double dx2 = (landmark2.x - sourceRect.left) * scaleX + destRect.left;
          double dy2 = (landmark2.y - sourceRect.top) * scaleY + destRect.top;

          if (lensDirection == CameraLensDirection.front) {
            dx1 = size.width - dx1;
            dx2 = size.width - dx2;
          }
          canvas.drawLine(Offset(dx1, dy1), Offset(dx2, dy2), paint);
        }
      }

      // 胴体部分の描画
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);

      // 腕部分の描画
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);

      // 脚部分の描画
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      drawLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      drawLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      drawLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}