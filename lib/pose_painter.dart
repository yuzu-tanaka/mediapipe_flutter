import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// ポーズの骨格を描画するためのCustomPainter
class PosePainter extends CustomPainter {
  final List<Pose> poses; // 描画するポーズのリスト
  final Size? imageSize; // 元のカメラ画像のサイズ
  final int sensorOrientation; // センサーの向き

  PosePainter(this.poses, this.imageSize, this.sensorOrientation);

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null) return; // 画像サイズがなければ何もしない

    // 描画ペイントの設定（赤色、太さ5.0）
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 5.0;

    // 各ポーズをループして描画
    for (final pose in poses) {
      // 各ランドマーク（関節）を点で描画
      for (final landmark in pose.landmarks.values) {
        // ランドマークの座標を画面サイズに合わせて変換
        final dx = landmark.x * size.width / imageSize!.width;
        final dy = landmark.y * size.height / imageSize!.height;
        canvas.drawCircle(Offset(dx, dy), 2, paint); // 点を描画
      }

      // 2つのランドマーク間を線で結ぶヘルパー関数
      void drawLine(PoseLandmarkType type1, PoseLandmarkType type2) {
        final landmark1 = pose.landmarks[type1];
        final landmark2 = pose.landmarks[type2];
        if (landmark1 != null && landmark2 != null) {
          // ランドマークの座標を画面サイズに合わせて変換
          final dx1 = landmark1.x * size.width / imageSize!.width;
          final dy1 = landmark1.y * size.height / imageSize!.height;
          final dx2 = landmark2.x * size.width / imageSize!.width;
          final dy2 = landmark2.y * size.height / imageSize!.height;
          canvas.drawLine(Offset(dx1, dy1), Offset(dx2, dy2), paint); // 線を描画
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
    return true; // 常に再描画
  }
}
