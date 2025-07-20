import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import 'best_pose_analyzer.dart';
import 'image_converter.dart';
import 'pose_painter.dart';
import 'pose_smoother.dart';
import 'inquiry_screen.dart';

// アプリケーションの状態を管理するenum
enum AppState {
  idle, // 初期状態
  waiting, // 30秒待機中
  collecting, // 30秒データ収集中
  analyzing, // ベストポーズ分析中
  showingResults, // 結果表示中
}

// 収集したフレームのデータを保持するクラス
class PoseFrameData {
  final Uint8List imageBytes;
  final Pose pose;
  PoseFrameData({required this.imageBytes, required this.pose});
}

/// ポーズ検出画面のStatefulWidget
class PoseDetectionScreen extends StatefulWidget {
  const PoseDetectionScreen({Key? key}) : super(key: key);

  @override
  _PoseDetectionScreenState createState() => _PoseDetectionScreenState();
}

class _PoseDetectionScreenState extends State<PoseDetectionScreen> {
  // 状態管理
  AppState _appState = AppState.idle;
  final _boundaryKey = GlobalKey();

  // カメラ関連
  CameraController? _cameraController;
  CameraDescription? _camera;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  Size? _imageSize;

  // ポーズ推定関連
  late PoseDetector _poseDetector;
  late PoseSmoother _poseSmoother;
  List<Pose> _poses = [];

  // データ収集関連
  final List<PoseFrameData> _frameData = [];
  Timer? _waitTimer;
  Timer? _collectTimer;
  int _countdown = 0;

  // 結果表示関連
  List<Uint8List> _bestPoseImages = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _collectTimer?.cancel();
    _cameraController?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (await _requestPermissions()) {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        if (_cameraIndex == -1) _cameraIndex = 0;
        _camera = _cameras[_cameraIndex];
        _poseDetector = PoseDetector(options: PoseDetectorOptions());
        _poseSmoother = PoseSmoother();
        _initializeCamera();
      }
    }
  }

  Future<bool> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();
    return cameraStatus.isGranted && microphoneStatus.isGranted;
  }

  void _initializeCamera() {
    if (_camera == null) return;
    _cameraController = CameraController(
      _camera!,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
      _cameraController!.startImageStream((image) {
        if (_isProcessing) return;
        _isProcessing = true;
        _processCameraImage(image);
      });
    }).catchError((e) {
      print("Error initializing camera: $e");
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final inputImage = inputImageFromCameraImage(image, _cameraController, _cameras, _cameraIndex);
    if (inputImage == null) {
      _isProcessing = false;
      return;
    }

    try {
      final poses = await _poseDetector.processImage(inputImage);
      final smoothedPoses = poses.map((pose) => _poseSmoother.smooth(pose)).toList();

      if (_appState == AppState.collecting && smoothedPoses.isNotEmpty) {
        await _captureFrame(smoothedPoses.first);
      }

      if (mounted) {
        setState(() {
          _poses = smoothedPoses;
          _imageSize = inputImage.metadata?.size;
        });
      }
    } catch (e) {
      print("Error processing image: $e");
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _captureFrame(Pose pose) async {
    try {
      RenderRepaintBoundary boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData != null) {
        _frameData.add(PoseFrameData(imageBytes: byteData.buffer.asUint8List(), pose: pose));
      }
    } catch (e) {
      print("Error capturing frame: $e");
    }
  }

  void _startSequence() {
    if (_appState != AppState.idle) return;

    setState(() {
      _appState = AppState.waiting;
      _countdown = 30;
    });

    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _startCollecting();
      }
    });
  }

  void _startCollecting() {
    _frameData.clear();
    setState(() {
      _appState = AppState.collecting;
      _countdown = 30;
    });

    _collectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _analyzePoses();
      }
    });
  }

  void _analyzePoses() {
    setState(() => _appState = AppState.analyzing);
    _cameraController?.stopImageStream();

    final analyzer = BestPoseAnalyzer(_frameData);
    final results = analyzer.analyze();

    _bestPoseImages = [
      results['top'] ?? Uint8List(0),
      results['right'] ?? Uint8List(0),
      results['bottom'] ?? Uint8List(0),
      results['left'] ?? Uint8List(0),
    ];

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _appState = AppState.showingResults);
      }
    });
  }

  void _reset() {
    _waitTimer?.cancel();
    _collectTimer?.cancel();
    _frameData.clear();
    _bestPoseImages.clear();
    _cameraController?.startImageStream((image) {
      if (_isProcessing) return;
      _isProcessing = true;
      _processCameraImage(image);
    });
    setState(() => _appState = AppState.idle);
  }

  void _switchCamera() {
    if (_cameras.length > 1) {
      // 現在のカメラを停止し、新しいカメラを初期化する
      _cameraController?.dispose();
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      _camera = _cameras[_cameraIndex];
      _initializeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_appState) {
      case AppState.showingResults:
        return _buildResultsView();
      default:
        return _buildCameraView();
    }
  }

  Widget _buildCameraView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          key: _boundaryKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_cameraController!),
              CustomPaint(
                painter: PosePainter(
                  _poses,
                  _imageSize,
                  _cameraController!.description.sensorOrientation,
                  _cameraController!.value.deviceOrientation,
                  _camera!.lensDirection,
                ),
              ),
            ],
          ),
        ),
        if (_appState == AppState.waiting || _appState == AppState.collecting)
          _buildCountdownOverlay(),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(child: _buildActionButton()),
        ),
        Positioned(
          top: 40,
          right: 20,
          child: IconButton(
            icon: const Icon(Icons.switch_camera, color: Colors.white),
            onPressed: _appState == AppState.idle ? _switchCamera : null,
          ),
        ),
      ],
    );
  }

  Widget _buildResultsView() {
    final List<Map<String, dynamic>> displayOrder = [
      {'label': 'ベストポーズ(上)', 'image': _bestPoseImages[0]},
      {'label': 'ベストポーズ(右)', 'image': _bestPoseImages[1]},
      {'label': 'ベストポーズ(下)', 'image': _bestPoseImages[2]},
      {'label': 'ベストポーズ(左)', 'image': _bestPoseImages[3]},
    ];

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
                final item = displayOrder[index];
                final imageBytes = item['image'] as Uint8List;
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.black,
                      child: Text(
                        item['label'] as String,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          image: imageBytes.isNotEmpty
                              ? DecorationImage(
                                  image: MemoryImage(imageBytes),
                                  fit: BoxFit.contain,
                                )
                              : null,
                        ),
                        child: imageBytes.isEmpty
                            ? const Center(child: Text('No Image'))
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: _reset, child: const Text('再撮影')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => InquiryScreen(poseImages: _bestPoseImages),
                      ),
                    );
                  },
                  child: const Text('問い合わせ'),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (_appState == AppState.idle) {
      return ElevatedButton(
        onPressed: _startSequence,
        child: const Text('撮影開始'),
        style: ElevatedButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(24)),
      );
    }
    return const SizedBox.shrink(); // 他の状態ではボタンを非表示
  }

  Widget _buildCountdownOverlay() {
    final String message = _appState == AppState.waiting ? '撮影開始まで' : 'データ収集中';
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: Colors.white, fontSize: 24)),
            Text('$_countdown', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
