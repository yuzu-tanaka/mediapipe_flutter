import 'dart:math';
import 'dart:typed_data';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'pose_detection_screen.dart'; // PoseFrameDataのため

class BestPoseAnalyzer {
  final List<PoseFrameData> frameData;

  BestPoseAnalyzer(this.frameData);

  Map<String, Uint8List> analyze() {
    if (frameData.isEmpty) return {};

    final bestTop = _findBestPoseBy(compare: (a, b) => a.y.compareTo(b.y), selectHighest: false);
    final bestBottom = _findBestPoseBy(compare: (a, b) => a.y.compareTo(b.y), selectHighest: true);
    final bestLeft = _findBestPoseBy(compare: (a, b) => a.x.compareTo(b.x), selectHighest: false);
    final bestRight = _findBestPoseBy(compare: (a, b) => a.x.compareTo(b.x), selectHighest: true);

    return {
      'top': bestTop,
      'right': bestRight,
      'bottom': bestBottom,
      'left': bestLeft,
    };
  }

  Uint8List _findBestPoseBy({
    required int Function(Point<double>, Point<double>) compare,
    required bool selectHighest,
  }) {
    if (frameData.isEmpty) return Uint8List(0);

    // 足首のランドマークのみを抽出（左右両方）
    List<MapEntry<int, Point<double>>> allAnkles = [];
    for (int i = 0; i < frameData.length; i++) {
      final pose = frameData[i].pose;
      final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
      final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
      if (leftAnkle != null) {
        allAnkles.add(MapEntry(i, Point(leftAnkle.x, leftAnkle.y)));
      }
      if (rightAnkle != null) {
        allAnkles.add(MapEntry(i, Point(rightAnkle.x, rightAnkle.y)));
      }
    }

    if (allAnkles.isEmpty) return Uint8List(0);

    // 座標でソート
    allAnkles.sort((a, b) => compare(a.value, b.value));

    // 上位/下位30件を抽出
    final targetAnkles = selectHighest
        ? allAnkles.sublist(max(0, allAnkles.length - 30))
        : allAnkles.sublist(0, min(30, allAnkles.length));

    if (targetAnkles.isEmpty) return Uint8List(0);

    // 中央値を計算
    final medianX = _calculateMedian(targetAnkles.map((e) => e.value.x).toList());
    final medianY = _calculateMedian(targetAnkles.map((e) => e.value.y).toList());
    final medianPoint = Point(medianX, medianY);

    // 中央値に最も近いフレームを見つける
    MapEntry<int, Point<double>>? bestEntry;
    double minDistance = double.infinity;

    for (final entry in targetAnkles) {
      final distance = _calculateDistance(entry.value, medianPoint);
      if (distance < minDistance) {
        minDistance = distance;
        bestEntry = entry;
      }
    }

    return frameData[bestEntry!.key].imageBytes;
  }

  double _calculateMedian(List<double> numbers) {
    if (numbers.isEmpty) return 0.0;
    numbers.sort();
    int middle = numbers.length ~/ 2;
    if (numbers.length % 2 == 1) {
      return numbers[middle];
    } else {
      return (numbers[middle - 1] + numbers[middle]) / 2.0;
    }
  }

  double _calculateDistance(Point<double> p1, Point<double> p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
  }
}
