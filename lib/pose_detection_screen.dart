import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import 'image_converter.dart';
import 'pose_painter.dart';
import 'pose_smoother.dart';
import 'video_recorder_service.dart';

/// ポーズ検出画面のStatefulWidget
class PoseDetectionScreen extends StatefulWidget {
  const PoseDetectionScreen({Key? key}) : super(key: key);

  @override
  _PoseDetectionScreenState createState() => _PoseDetectionScreenState();
}

/// PoseDetectionScreenのState
class _PoseDetectionScreenState extends State<PoseDetectionScreen> {
  CameraController? _cameraController; // カメラを制御するためのコントローラー
  late PoseDetector _poseDetector; // ポーズ検出器のインスタンス
  late PoseSmoother _poseSmoother; // ポーズを滑らかにするためのクラス
  late VideoRecorderService _recorderService; // 録画サービス
  List<Pose> _poses = []; // 検出されたポーズのリスト
  Size? _imageSize; // 処理中のカメラ画像のサイズ
  bool _isCameraInitialized = false; // カメラが初期化されたかどうかのフラグ
  bool _isProcessing = false; // 画像処理が進行中かどうかのフラグ
  CameraDescription? _camera; // 選択されたカメラの記述
  List<CameraDescription> _cameras = []; // 利用可能なカメラのリスト
  int _cameraIndex = 0; // 選択されたカメラのインデックス

  @override
  void initState() {
    super.initState();
    _initialize(); // 初期化処理を開始
  }

  /// アプリケーションの初期化処理
  Future<void> _initialize() async {
    // カメラのパーミッションを要求
    if (await _requestPermissions()) {
      // 利用可能なカメラのリストを取得し、背面カメラを優先して選択
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraIndex = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (_cameraIndex == -1) {
          _cameraIndex = 0;
        }
        _camera = _cameras[_cameraIndex];
        // ポーズ検出器とスムーザーを初期化
        _poseDetector = PoseDetector(options: PoseDetectorOptions());
        _poseSmoother = PoseSmoother();
        // カメラの初期化を開始
        _initializeCamera();
      }
    }
  }

  /// カメラのパーミッションを要求する
  Future<bool> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();
    final storageStatus = await Permission.storage.request(); // Android用
    final photosStatus = await Permission.photos.request(); // iOS用

    return cameraStatus.isGranted &&
        microphoneStatus.isGranted &&
        (storageStatus.isGranted || photosStatus.isGranted);
  }

  /// カメラの初期化と映像ストリームの開始
  void _initializeCamera() async {
    if (_camera == null) return; // カメラが選択されていなければ何もしない

    // UIツリーが完全に構築された後にカメラの初期化を遅延させる
    // これにより、Androidでのディスプレイ関連のクラッシュを回避できる可能性がある
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _cameraController = CameraController(
        _camera!, // 選択されたカメラ
        ResolutionPreset.high, // 解像度1280x720で映像を取得
        enableAudio: false, // 音声は不要
        // プラットフォームに応じた画像フォーマットグループを設定
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup
                  .nv21 // AndroidではNV21
            : ImageFormatGroup.bgra8888, // iOSではBGRA8888
      );

      try {
        // カメラコントローラーを初期化
        await _cameraController!.initialize();
        if (!mounted) return; // ウィジェットが破棄されていたら何もしない

        // 録画サービスを初期化
        _recorderService = VideoRecorderService(
          _cameraController!,
          onRecordingStart: () {
            // 録画開始時にイメージストリームを停止
            _cameraController?.stopImageStream();
          },
          onRecordingComplete: () {
            // 録画完了時にイメージストリームを再開
            _cameraController?.startImageStream((image) {
              if (_isProcessing) return;
              _isProcessing = true;
              _processCameraImage(image);
            });
          },
        );

        setState(() {
          _isCameraInitialized = true; // カメラ初期化済みフラグを立てる
        });

        // カメラ映像ストリームを開始し、フレームごとに処理
        _cameraController!.startImageStream((image) {
          if (_isProcessing) return; // 処理中であればスキップ
          _isProcessing = true; // 処理中フラグを立てる
          // カメラ画像を非同期で処理
          _processCameraImage(image);
        });
      } catch (e) {
        // カメラ初期化中のエラーを捕捉し、ログに出力
        print("Error initializing camera: $e");
        // エラーハンドリング（例: ユーザーにアラートを表示）
      }
    });
  }

  /// カメラを切り替える
  void _switchCamera() async {
    if (_cameras.length > 1) {
      // 現在のカメラを停止
      await _cameraController?.dispose();

      // 次のカメラを選択
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      _camera = _cameras[_cameraIndex];

      // 新しいカメラを初期化
      _initializeCamera();
    }
  }

  /// カメラ画像を受け取り、ポーズ検出のために処理
  Future<void> _processCameraImage(CameraImage image) async {
    // CameraImageをInputImageに変換
    final inputImage = inputImageFromCameraImage(
      image,
      _cameraController,
      _cameras,
      _cameraIndex,
    );
    if (inputImage == null) {
      _isProcessing = false;
      return;
    }
    await _processImage(inputImage); // ポーズ検出処理を実行
  }

  /// InputImageを使用してポーズ検出を実行し、結果を更新
  Future<void> _processImage(InputImage inputImage) async {
    try {
      // ポーズ検出器で画像を処理
      final poses = await _poseDetector.processImage(inputImage);

      // 検出されたポーズを滑らかにする
      final smoothedPoses = poses
          .map((pose) => _poseSmoother.smooth(pose))
          .toList();

      // ウィジェットがマウントされていればUIを更新
      if (mounted) {
        setState(() {
          _poses = smoothedPoses; // スムージングされたポーズでリストを更新
          _imageSize = inputImage.metadata?.size; // 画像サイズを更新
        });
      }
    } catch (e) {
      // 画像処理中のエラーを捕捉し、ログに出力
      print("Error processing image: $e");
    } finally {
      _isProcessing = false; // 処理中フラグをリセット
    }
  }

  @override
  void dispose() {
    _isProcessing = false; // 処理中フラグをリセット
    _recorderService.dispose(); // 録画サービスを破棄
    _cameraController?.dispose(); // カメラコントローラーを破棄
    _poseDetector.close(); // ポーズ検出器を閉じる
    super.dispose(); // 親クラスのdisposeを呼び出す
  }

  @override
  Widget build(BuildContext context) {
    // カメラが初期化されていなければローディングインジケーターを表示
    if (!_isCameraInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // カメラが初期化されていればカメラプレビューと骨格描画を表示
    return Scaffold(
      body: Stack(
        fit: StackFit.expand, // Stackの子ウィジェットを親いっぱいに広げる
        children: [
          // カメラプレビューを表示
          CameraPreview(_cameraController!),
          // 骨格を描画するCustomPaintウィジェット
          CustomPaint(
            painter: PosePainter(
              _poses, // 検出されたポーズ
              _imageSize, // 処理した画像のサイズを使用
              _cameraController!.description.sensorOrientation, // センサーの向き
              _cameraController!.value.deviceOrientation, // デバイスの向き
              _camera!.lensDirection,
            ), // カメラの向き
            // sizeは指定せず、StackFit.expandによって親と同じサイズになる
          ),
          // カメラ切り替えボタン
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.switch_camera, color: Colors.white),
              onPressed: _switchCamera,
            ),
          ),
          // 録画ボタン
          Positioned(
            bottom: 40,
            left: 20,
            child: ValueListenableBuilder(
              valueListenable: _recorderService.state,
              builder: (context, RecordingState state, child) {
                return _buildRecordButton(state);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 録画ボタンの状態に応じてウィジェットを構築する
  Widget _buildRecordButton(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        // アイドル状態：録画開始ボタン
        return IconButton(
          icon: const Icon(Icons.circle, color: Colors.red, size: 48),
          onPressed: _recorderService.startRecordingSequence,
        );
      case RecordingState.waiting:
        // 待機中：カウントダウン表示
        return ValueListenableBuilder(
          valueListenable: _recorderService.countdown,
          builder: (context, int countdown, child) {
            return Column(
              children: [
                const Icon(Icons.hourglass_top, color: Colors.white, size: 48),
                Text(
                  countdown.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
              ],
            );
          },
        );
      case RecordingState.recording:
        // 録画中：停止ボタン
        return IconButton(
          icon: const Icon(Icons.stop, color: Colors.red, size: 48),
          onPressed: _recorderService.stopRecording,
        );
    }
  }
}
