import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class SonEkiPage extends StatefulWidget {
  const SonEkiPage({super.key});

  @override
  State<SonEkiPage> createState() => _SonEkiPageState();
}

class _SonEkiPageState extends State<SonEkiPage> {
  final List<String> stores = [
    '東勝山二丁目店',
    '上杉一丁目店',
    '仙台木町通一丁目店',
    '安養寺二丁目店',
    '利府青山店',
    '電力ビル店',
    '中山台店',
  ];

  final List<int> years = List.generate(6, (i) => DateTime.now().year - 3 + i);

  String selectedStore = '東勝山二丁目店';
  int selectedYear = DateTime.now().year;

  Map<String, String> pdfMap = {};

  bool isAnalyzing = false;
  String analysisResult = '';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadPdfData();
    _loadAnalysisResult();
  }

  /// =========================
  /// PDFデータ読み込み
  /// =========================
  Future<void> _loadPdfData() async {
    final doc = await _firestore.collection('soneki_pdf').doc('default').get();

    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;
      final raw = data['pdfMap'];

      if (raw != null) {
        pdfMap = Map<String, String>.from(raw);
      }
    }

    setState(() {});
  }

  /// =========================
  /// PDFデータ保存
  /// =========================
  Future<void> _savePdfData() async {
    await _firestore.collection('soneki_pdf').doc('default').set({
      'pdfMap': pdfMap,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// =========================
  /// 分析結果読み込み
  /// =========================
  Future<void> _loadAnalysisResult() async {
    final doc = await _firestore
        .collection('soneki_analysis')
        .doc('${selectedStore}_$selectedYear')
        .get();

    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;

      analysisResult = data['result'] ?? '';
    } else {
      analysisResult = '';
    }

    setState(() {});
  }

  /// =========================
  /// 分析結果保存
  /// =========================
  Future<void> _saveAnalysisResult(String result) async {
    await _firestore
        .collection('soneki_analysis')
        .doc('${selectedStore}_$selectedYear')
        .set({
      'store': selectedStore,
      'year': selectedYear,
      'result': result,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// =========================
  /// PDF選択
  /// =========================
  Future<void> _pickPdf(int month) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null) return;

    final path = result.files.single.path;

    if (path == null) return;

    // PDF文字抽出
    final pdfText = await _extractPdfText(path);

    debugPrint(pdfText);
    if (!mounted) return;
    // PDF表示画面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('PDF表示'),
          ),
          body: SfPdfViewer.file(
            File(path),
          ),
        ),
      ),
    );

    final key = '${selectedStore}_${selectedYear}_$month';

    pdfMap[key] = path;

    await _savePdfData();

    setState(() {});
  }

  /// =========================
  /// OpenAI分析
  /// =========================
  Future<void> _analyzeData() async {
    setState(() {
      isAnalyzing = true;
    });

    try {
      final List<Map<String, dynamic>> yearlyData = [];

      for (int month = 1; month <= 12; month++) {
        final key = '${selectedStore}_${selectedYear}_$month';

        final path = pdfMap[key];

        if (path == null) continue;

        final exists = File(path).existsSync();

        if (!exists) continue;

        yearlyData.add({
          'month': month,
          'pdfPath': path,
        });
      }

      if (yearlyData.isEmpty) {
        setState(() {
          analysisResult = 'PDFが登録されていません';
          isAnalyzing = false;
        });

        return;
      }

      final result = await analyzePdfData(yearlyData);

      /// 保存
      await _saveAnalysisResult(result);

      setState(() {
        analysisResult = result;
        isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        analysisResult = '分析エラー: $e';
        isAnalyzing = false;
      });
    }
  }

  /// =========================
  /// 月カード
  /// =========================
  Widget _buildMonthCard(int month) {
    final key = '${selectedStore}_${selectedYear}_$month';

    final path = pdfMap[key];

    final exists = path != null && File(path).existsSync();

    return Card(
      child: ListTile(
        title: Text('$month 月'),
        subtitle: Text(
          exists ? 'PDF登録済み' : 'PDF未登録',
        ),
        trailing: ElevatedButton(
          onPressed: () => _pickPdf(month),
          child: Text(
            exists ? '変更' : '追加',
          ),
        ),
      ),
    );
  }

  /// =========================
  /// UI
  /// =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('損益書+分析結果'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// 店舗選択
            Row(
              children: [
                const Text('店舗: '),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: selectedStore,
                  items: stores.map((store) {
                    return DropdownMenuItem(
                      value: store,
                      child: Text(store),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value == null) return;

                    selectedStore = value;

                    await _loadAnalysisResult();

                    setState(() {});
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            /// 年選択
            Row(
              children: [
                const Text('年: '),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: selectedYear,
                  items: years.map((year) {
                    return DropdownMenuItem(
                      value: year,
                      child: Text('$year年'),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value == null) return;

                    selectedYear = value;

                    await _loadAnalysisResult();

                    setState(() {});
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView(
                children: [
                  /// 月一覧
                  ...List.generate(
                    12,
                    (index) => _buildMonthCard(index + 1),
                  ),

                  const SizedBox(height: 20),

                  /// 分析ボタン
                  ElevatedButton(
                    onPressed: isAnalyzing ? null : _analyzeData,
                    child: Text(
                      isAnalyzing ? '分析中...' : '分析結果',
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// AI分析結果
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.grey,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      analysisResult.isEmpty
                          ? 'ここにAI分析結果が表示されます'
                          : analysisResult,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> analyzePdfData(
    List<Map<String, dynamic>> pdfData,
  ) async {
    final prompt = '''
以下の損益データ推移を分析してください。

分析内容:
・商品総売上高
・営業収入
・売上高合計
・店舗値下・廃棄ロス原価高
・棚卸増減原価高
・営業総利益
・本部フィー
・分担金・助成金・支援金
・補填金
・販売奨励金
・雑収入
・総収入
・従業員給与
・募集費
・用度品代
・修繕費（含保守料）
・水道光熱費
・清掃費
・営業雑費
・現金過不足
・営業費合計
・営業利益
・引出金
・配分金
・営業利益残高

データ:
${jsonEncode(pdfData)}

日本語で簡潔に出力してください。
''';

    final response = await http.post(
      Uri.parse(
        'https://sales-ai-worker.app-lab-nanato.workers.dev',
      ),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'prompt': prompt,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }

    final json = jsonDecode(response.body);

    return json['choices'][0]['message']['content'];
  }
}

Future<String> _extractPdfText(String path) async {
  try {
    final bytes = await File(path).readAsBytes();

    final document = PdfDocument(
      inputBytes: bytes,
    );

    final text = PdfTextExtractor(
      document,
    ).extractText();

    document.dispose();

    return text;
  } catch (e) {
    return 'PDF解析失敗: $e';
  }
}
