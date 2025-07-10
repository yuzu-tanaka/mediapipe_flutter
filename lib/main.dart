// lib/main.dart
// このファイルは、Flutterアプリケーションのエントリポイントであり、
// カメラ映像からのリアルタイムポーズ検出と骨格描画を実装しています。

import 'dart:io'; // プラットフォーム判定のためにインポート

import 'package:camera/camera.dart'; // カメラ機能のためにインポート
import 'package:flutter/foundation.dart'; // プラットフォーム判定のためにインポート
import 'package:flutter/material.dart'; // FlutterのUIコンポーネントのためにインポート
import 'package:flutter/services.dart'; // DeviceOrientationのためにインポート
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'; // MediaPipe Pose Detectionのためにインポート
import 'package:permission_handler/permission_handler.dart'; // パーミッション管理のためにインポート

/// アプリケーションのエントリポイント
void main() {
  runApp(const MyApp());
}

/// アプリケーションのルートウィジェット
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      // デバッグバナーを非表示にする
      debugShowCheckedModeBanner: false,
      // アプリケーションのホーム画面を設定
      home: PoseDetectionScreen(),
    );
  }
}

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
      _camera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first);
      _cameraIndex = _cameras.indexOf(_camera!);
      // ポーズ検出器を初期化
      _poseDetector = PoseDetector(options: PoseDetectorOptions());
      // カメラの初期化を開始
      _initializeCamera();
    }
  }

  /// カメラのパーミッションを要求する
  Future<bool> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    return cameraStatus.isGranted; // 許可されたかどうかを返す
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
            ? ImageFormatGroup.nv21 // AndroidではNV21
            : ImageFormatGroup.bgra8888, // iOSではBGRA8888
      );

      try {
        // カメラコントローラーを初期化
        await _cameraController!.initialize();
        if (!mounted) return; // ウィジェットが破棄されていたら何もしない

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

  /// カメラ画像を受け取り、ポーズ検出のために処理
  Future<void> _processCameraImage(CameraImage image) async {
    // バグ取り用プリント文
    print('processCameraImageを実行');
    // CameraImageをInputImageに変換
    final inputImage = _inputImageFromCameraImage(
      image,
      _cameraController,
      _cameras,
      _cameraIndex,
    );
    if (inputImage == null) {
      _isProcessing = false;
      // バグ取り用プリント文
      print('inputImageがnullだった(T T)/---');
      return;
    }
    // バグ取り用プリント文
    print('inputImageがnullじゃなかった');
    await _processImage(inputImage); // ポーズ検出処理を実行
  }

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

  InputImage? _inputImageFromCameraImage(
      CameraImage image,
      CameraController? controller,
      List<CameraDescription> cameras,
      int _cameraIndex) {
    if (controller == null) return null;

    final camera = cameras[_cameraIndex];
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
    if (defaultTargetPlatform == TargetPlatform.iOS && format != InputImageFormat.bgra8888) {
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

  /// InputImageを使用してポーズ検出を実行し、結果を更新
  Future<void> _processImage(InputImage inputImage) async {
    try {
      // ポーズ検出器で画像を処理
      final poses = await _poseDetector.processImage(inputImage);
      // 検出されたポーズの数をログに出力
      print('Poses found: ${poses.length}');
      // 各ポーズのランドマーク情報をログに出力
      for (final pose in poses) {
        print('  Pose ID: ${pose.landmarks.values.first.x}'); // 例: 最初のランドマークのX座標
        for (final landmark in pose.landmarks.values) {
          print('    ${landmark.type}: (${landmark.x}, ${landmark.y}, ${landmark.z})');
        }
      }
      // ウィジェットがマウントされていればUIを更新
      if (mounted) {
        setState(() {
          _poses = poses; // 検出されたポーズでリストを更新
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
    _cameraController?.dispose(); // カメラコントローラーを破棄
    _poseDetector.close(); // ポーズ検出器を閉じる
    super.dispose(); // 親クラスのdisposeを呼び出す
  }

  @override
  Widget build(BuildContext context) {
    // カメラが初期化されていなければローディングインジケーターを表示
    if (!_isCameraInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    // カメラが初期化されていればカメラプレビューと骨格描画を表示
    return Scaffold(
      body: Stack(
        children: [
          // カメラプレビューを表示
          CameraPreview(_cameraController!),
          // 骨格を描画するCustomPaintウィジェット
          CustomPaint(
            painter: PosePainter(
                _poses, // 検出されたポーズ
                _imageSize, // 処理した画像のサイズを使用
                _cameraController!.description.sensorOrientation), // センサーの向き
            size: MediaQuery.of(context).size, // 画面全体のサイズを使用
          ),
        ],
      ),
    );
  }
}

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
