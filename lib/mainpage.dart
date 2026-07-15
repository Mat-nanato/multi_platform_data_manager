import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'tenpodetapage.dart';
import 'aianalysis_page.dart';

final logger = Logger(printer: PrettyPrinter());

class MainPage extends StatefulWidget {
  final String storeName;
  final dynamic gateData;
  final VoidCallback onBack;

  const MainPage({
    super.key,
    required this.storeName,
    this.gateData,
    required this.onBack,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool showChatInput = false;
  final TextEditingController _controller = TextEditingController();
  String _chatResponse = '';
  Uint8List? _chatImage;
  int _chatCount = 0;
  DateTime? _lockUntil;

  late final WebViewController _webController;

  final String newProductsUrl = 'https://www.family.co.jp/goods/newgoods.html';
  final String campaignsUrl = 'https://www.family.co.jp/campaign.html';
  final String calendarUrl =
      'https://familymart.hisol-shift.net/manager/top-page';

  @override
  void initState() {
    super.initState();
    debugPrint('MainPage initState');

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('about:blank'));

    // 👇 フリーズ対策：描画後に遅延ロード
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _webController.loadRequest(Uri.parse(newProductsUrl));
    });
  }

  @override
  void dispose() {
    debugPrint('MainPage dispose');
    _controller.dispose();
    super.dispose();
  }

  void loadNewProducts() =>
      _webController.loadRequest(Uri.parse(newProductsUrl));
  void loadCampaigns() => _webController.loadRequest(Uri.parse(campaignsUrl));
  void loadCalendar() {
    _webController.loadRequest(
      Uri.parse(calendarUrl),
      headers: {'Accept-Language': 'ja-JP,ja;q=0.9'},
    );
  }

  Future<void> fetchChatOrImage(String prompt) async {
    const workerUrl = 'https://sales-ai-worker.app-lab-nanato.workers.dev';

    try {
      logger.i("==== START REQUEST ====");
      logger.i("INPUT: $prompt");

      if (prompt.contains('画像')) {
        final purePrompt = prompt.substring(3);

        final response = await http.post(
          Uri.parse(workerUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({"type": "image", "prompt": purePrompt}),
        );

        if (response.statusCode == 200 && response.bodyBytes.length > 1000) {
          setState(() {
            _chatResponse = '';
            _chatImage = response.bodyBytes;
          });
        } else {
          final text = utf8.decode(response.bodyBytes, allowMalformed: true);
          setState(() {
            _chatResponse = text;
            _chatImage = null;
          });
        }
      } else {
        final response = await http.post(
          Uri.parse(workerUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "type": "chat",
            "messages": [
              {"role": "user", "content": prompt},
            ],
          }),
        );

        final decoded = utf8.decode(response.bodyBytes);

        if (response.statusCode == 200) {
          final data = jsonDecode(decoded);
          String content = data['choices']?[0]?['message']?['content'] ?? '';

          setState(() {
            _chatResponse = content;
            _chatImage = null;
          });
        } else {
          setState(() => _chatResponse = 'Error: ${response.statusCode}');
        }
      }

      logger.i("==== END REQUEST ====");
    } catch (e) {
      logger.e("EXCEPTION: $e");
      setState(() => _chatResponse = 'Error: $e');
    }
  }

  void _sendChat() async {
    if (_lockUntil != null && DateTime.now().isBefore(_lockUntil!)) {
      final remain = _lockUntil!.difference(DateTime.now());
      setState(() {
        _chatResponse = '送信制限中 ${remain.inHours}時間${remain.inMinutes % 60}分';
      });
      return;
    }

    if (_chatCount >= 10) {
      setState(() {
        _chatResponse = '送信上限（8時間制限）';
        _lockUntil = DateTime.now().add(const Duration(hours: 8));
        _chatCount = 0;
      });
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    await fetchChatOrImage(text);
    _chatCount++;
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MainPage build: ${widget.storeName}');
    return Scaffold(
      body: Row(
        children: [
          /// 左メニュー
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    IconButton(
                      icon: const Text('📅', style: TextStyle(fontSize: 64)),
                      onPressed: loadCalendar,
                    ),
                    const SizedBox(height: 16),
                    IconButton(
                      icon: const Text('🍙', style: TextStyle(fontSize: 64)),
                      onPressed: loadNewProducts,
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Text('🎉', style: TextStyle(fontSize: 64)),
                      onPressed: loadCampaigns,
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Text('🏷️', style: TextStyle(fontSize: 64)),
                      onPressed: () {
                        setState(() => showChatInput = !showChatInput);
                      },
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Text('📊', style: TextStyle(fontSize: 64)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TenpoDataPage(
                              storeName: widget.gateData?['store'] ?? '',
                              actual: widget.gateData?['actual'] ?? '',
                              actualWaste:
                                  widget.gateData?['actualWaste'] ?? '',
                              storeAddress:
                                  widget.gateData?['storeAddress'] ?? '',
                              lat: widget.gateData?['lat'] ?? 38.2682,
                              lon: widget.gateData?['lon'] ?? 140.8694,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Text('🤖', style: TextStyle(fontSize: 64)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AiAnalysisPage(store: widget.storeName),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 40,
                      ),
                      onPressed: widget.onBack,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),

          /// 右画面
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    widget.storeName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: WebViewWidget(controller: _webController),
                    ),
                  ),
                  if (showChatInput)
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: '作成POPイメージ',
                                ),
                                onSubmitted: (_) => _sendChat(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send),
                              onPressed: _sendChat,
                            ),
                          ],
                        ),
                        if (_chatResponse.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            color: Colors.grey[200],
                            child: Text(_chatResponse),
                          ),
                        if (_chatImage != null)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            child: Image.memory(_chatImage!, width: 300),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
