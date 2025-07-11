
// lib/main.dart
// このファイルは、Flutterアプリケーションのエントリポイントです。

import 'package:flutter/material.dart'; // FlutterのUIコンポーネントのためにインポート
import 'pose_detection_screen.dart'; // ポーズ検出画面をインポート

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
