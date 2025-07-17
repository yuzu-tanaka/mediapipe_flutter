import 'dart:async';
import 'dart:io'; // Fileクラスのために追加

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 日付フォーマットのために追加
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

/// 録画の状態を管理するためのenum
enum RecordingState {
  idle, // アイドル状態
  waiting, // 録画開始待機中
  recording, // 録画中
}

/// 録画機能を提供するサービスクラス
class VideoRecorderService {
  final CameraController _cameraController;
  final VoidCallback onRecordingStart;
  final VoidCallback onRecordingComplete;

  // UIに状態を通知するためのValueNotifier
  final ValueNotifier<RecordingState> state = ValueNotifier(
    RecordingState.idle,
  );
  final ValueNotifier<int> countdown = ValueNotifier(0);

  Timer? _waitTimer;
  Timer? _recordTimer;
  Timer? _countdownTimer;

  VideoRecorderService(
    this._cameraController, {
    required this.onRecordingStart,
    required this.onRecordingComplete,
  });

  /// 録画シーケンスを開始する（30秒待機 -> 30秒録画）
  Future<void> startRecordingSequence() async {
    if (state.value != RecordingState.idle) return;

    // 1. 待機状態に移行
    state.value = RecordingState.waiting;
    countdown.value = 30;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      countdown.value--;
      if (countdown.value <= 0) {
        timer.cancel();
      }
    });

    // 2. 30秒後に録画を開始
    _waitTimer = Timer(const Duration(seconds: 30), () async {
      _countdownTimer?.cancel();
      try {
        onRecordingStart(); // 録画開始を通知
        await _cameraController.startVideoRecording();
        state.value = RecordingState.recording;

        // 3. 30秒後に録画を停止
        _recordTimer = Timer(const Duration(seconds: 30), stopRecording);
      } catch (e) {
        print("Error starting video recording: $e");
        _resetState();
        onRecordingComplete(); // エラー時も完了を通知
      }
    });
  }

  /// 録画を停止し、ファイルを保存する
  Future<void> stopRecording() async {
    if (state.value != RecordingState.recording) return;

    try {
      final file = await _cameraController.stopVideoRecording();
      final oldPath = file.path;

      // 新しいファイルパスを生成 (.temp を .mp4 に変更)
      final newPath = oldPath.replaceAll('.temp', '.mp4');

      // ファイルをリネーム
      final renamedFile = await File(oldPath).rename(newPath);

      // 現在の日時を取得し、指定されたフォーマットに変換
      final String timestamp = DateFormat(
        'yyyyMMddHHmmss',
      ).format(DateTime.now());
      final String fileName = 'pose_video_$timestamp.mp4';

      // ギャラリーに保存
      await ImageGallerySaverPlus.saveFile(
        renamedFile.path, // リネーム後のパスを使用
        name: fileName,
        isReturnPathOfIOS: true,
      );
      print("Video saved as $fileName"); // ユーザーへの通知として残す
    } catch (e) {
      print("Error stopping or saving video: $e");
    } finally {
      _resetState();
      onRecordingComplete(); // 録画完了を通知
    }
  }

  /// 状態をリセットする
  void _resetState() {
    _waitTimer?.cancel();
    _recordTimer?.cancel();
    _countdownTimer?.cancel();
    state.value = RecordingState.idle;
    countdown.value = 0;
  }

  /// サービスを破棄する（メモリリーク防止）
  void dispose() {
    _resetState();
    state.dispose();
    countdown.dispose();
  }
}
