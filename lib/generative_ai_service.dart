import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

class GenerativeAiService {
  // TODO: ここにあなたのGemini APIキーを設定してください
  static const String _apiKey = "Your_API_KEY";

  final GenerativeModel _model;

  GenerativeAiService()
    : _model = GenerativeModel(
        model: 'gemini-1.5-flash', // 画像を扱える新しいモデルを指定
        apiKey: _apiKey,
      );

  Future<String> askAboutPoses(List<Uint8List> images, String question) async {
    try {
      // AIへの指示（プロンプト）を作成
      final prompt = <Content>[
        Content.multi([
          TextPart(
            'あなたはプロのパーソナルトレーナーです。'
            '提供された4枚のポーズ画像（上、右、下、左の順）を見て、'
            'それぞれのポーズの良い点や改善点を分析し、以下の質問に答えてください。',
          ),
          // 画像データを添付
          DataPart('image/png', images[0]),
          DataPart('image/png', images[1]),
          DataPart('image/png', images[2]),
          DataPart('image/png', images[3]),
          // ユーザーからの質問
          TextPart('質問: $question'),
        ]),
      ];

      final response = await _model.generateContent(prompt);
      return response.text ?? '回答を取得できませんでした。';
    } catch (e) {
      print('Error communicating with Generative AI: $e');
      return 'エラーが発生しました: $e';
    }
  }
}
