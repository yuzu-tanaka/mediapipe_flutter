import 'dart:async';
import 'dart:io'; // Fileクラスのために追加

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:intl/intl.dart'; // 日付フォーマットのために追加

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

  // AudioPlayerのインスタンスを追加
  final AudioPlayer _audioPlayer = AudioPlayer();

  VideoRecorderService(
    this._cameraController, {
    required this.onRecordingStart,
    required this.onRecordingComplete,
  });

  // 音声再生用のヘルパーメソッド
  Future<void> _playSound(String soundAsset) async {
    try {
      // 以前の再生が完了するのを待たずに新しい音を再生するため、
      // playメソッドの前にstopを呼び出すか、新しいPlayerインスタンスを作成します。
      // ここではシンプルにplayを呼び出します。
      await _audioPlayer.play(AssetSource(soundAsset));
    } catch (e) {
      print("Error playing sound: $e");
    }
  }

  /// 録画シーケンスを開始する（30秒待機 -> 30秒録画）
  Future<void> startRecordingSequence() async {
    if (state.value != RecordingState.idle) return;

    // 1. 待機状態に移行
    state.value = RecordingState.waiting;
    countdown.value = 30; // カウントダウンの初期値を設定

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      countdown.value--;

      // 指定のタイミングでカウントダウン音を再生
      if (countdown.value == 20 ||
          countdown.value == 10 ||
          countdown.value == 5 ||
          countdown.value == 3 ||
          countdown.value == 2 ||
          countdown.value == 1) {
        _playSound('sounds/countdown.mp3');
      }

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
        _playSound('sounds/start.mp3'); // 録画開始音

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
      _playSound('sounds/stop.mp3'); // 録画停止音
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
    _audioPlayer.dispose(); // AudioPlayerを破棄
    state.dispose();
    countdown.dispose();
  }
}
