
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 指数移動平均（EMA）を使ってポーズのランドマークを滑らかにするクラス
class PoseSmoother {
  // スムージングの度合いを調整する係数（0.0に近いほど滑らかになるが遅延が大きくなる）
  final double alpha;

  // 前のフレームでスムージングされたランドマークの位置を保持する
  Map<PoseLandmarkType, PoseLandmark> _smoothedLandmarks = {};

  PoseSmoother({this.alpha = 0.3}); // この値を0.1にするとより滑らかに、0.5でより追従性が良くなる。

  /// 新しいポーズを受け取り、滑らかにしたポーズを返す
  Pose smooth(Pose pose) {
    final newSmoothedLandmarks = <PoseLandmarkType, PoseLandmark>{};

    for (final entry in pose.landmarks.entries) {
      final type = entry.key;
      final newLandmark = entry.value;
      final oldLandmark = _smoothedLandmarks[type];

      if (oldLandmark != null) {
        // EMA計算式: new_value * alpha + old_value * (1 - alpha)
        final smoothedX = alpha * newLandmark.x + (1 - alpha) * oldLandmark.x;
        final smoothedY = alpha * newLandmark.y + (1 - alpha) * oldLandmark.y;
        final smoothedZ = alpha * newLandmark.z + (1 - alpha) * oldLandmark.z;

        newSmoothedLandmarks[type] = PoseLandmark(
          type: type,
          x: smoothedX,
          y: smoothedY,
          z: smoothedZ,
          likelihood: newLandmark.likelihood, // 信頼度は最新のものをそのまま使用
        );
      } else {
        // 最初のフレームでは、そのままの値を使用
        newSmoothedLandmarks[type] = newLandmark;
      }
    }

    // 次のフレームのために、今回計算した値を保持する
    _smoothedLandmarks = newSmoothedLandmarks;
    return Pose(landmarks: newSmoothedLandmarks);
  }
}
