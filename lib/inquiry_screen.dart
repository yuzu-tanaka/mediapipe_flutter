import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'generative_ai_service.dart';

class InquiryScreen extends StatefulWidget {
  final List<Uint8List> poseImages;

  const InquiryScreen({Key? key, required this.poseImages}) : super(key: key);

  @override
  _InquiryScreenState createState() => _InquiryScreenState();
}

class _InquiryScreenState extends State<InquiryScreen> {
  final _questionController = TextEditingController();
  final _aiService = GenerativeAiService();
  String? _answer;
  bool _isLoading = false;

  void _sendQuestion() async {
    if (_questionController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _answer = null;
    });

    final result = await _aiService.askAboutPoses(
      widget.poseImages,
      _questionController.text,
    );

    setState(() {
      _answer = result;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AIに問い合わせ')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // 画像のサムネイル表示
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.poseImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Image.memory(widget.poseImages[index], width: 80, height: 80, fit: BoxFit.contain),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // 質問入力フィールド
            TextField(
              controller: _questionController,
              decoration: const InputDecoration(
                labelText: '質問を入力してください',
                hintText: '例：この中で一番良いポーズはどれですか？改善点はありますか？',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            // 送信ボタン
            ElevatedButton(
              onPressed: _isLoading ? null : _sendQuestion,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('送信'),
            ),
            const SizedBox(height: 20),
            // 回答表示エリア
            if (_answer != null)
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_answer!),
              ),
          ],
        ),
      ),
    );
  }
}
