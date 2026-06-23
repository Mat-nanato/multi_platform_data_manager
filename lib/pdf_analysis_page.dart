import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfAnalysisPage extends StatefulWidget {
  final String store;

  const PdfAnalysisPage({super.key, required this.store});

  @override
  State<PdfAnalysisPage> createState() => _PdfAnalysisPageState();
}

class _PdfAnalysisPageState extends State<PdfAnalysisPage> {
  bool pdfLoading = false;
  String pdfAnalysisResult = '';

  Future<List<File>> _getStorePdfFiles() async {
    final dir = await getApplicationDocumentsDirectory();

    final storeCode = getStoreCode(widget.store);

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf') && f.path.contains(storeCode))
        .toList();

    files.sort((a, b) {
      final reg = RegExp(r'_(\d{6})_');

      final aMatch = reg.firstMatch(a.path);
      final bMatch = reg.firstMatch(b.path);

      final aYm = int.tryParse(aMatch?.group(1) ?? '0') ?? 0;
      final bYm = int.tryParse(bMatch?.group(1) ?? '0') ?? 0;

      return bYm.compareTo(aYm);
    });

    return files;
  }

  // =========================
  // PDFボタン押下メイン処理
  // =========================
  Future<void> _analyzePdf() async {
    setState(() {
      pdfLoading = true;
      pdfAnalysisResult = '';
    });

    try {
      final files = await _getStorePdfFiles();

      if (files.length < 2) {
        throw Exception('比較用PDFが不足しています');
      }

      final latestPdf = files[0];
      final previousPdf = files[1];

      final latestDoc = PdfDocument(inputBytes: latestPdf.readAsBytesSync());

      final previousDoc = PdfDocument(
        inputBytes: previousPdf.readAsBytesSync(),
      );

      final thisMonthText = PdfTextExtractor(latestDoc).extractText();

      final lastMonthText = PdfTextExtractor(previousDoc).extractText();

      latestDoc.dispose();
      previousDoc.dispose();

      final payload = {
        "store": widget.store,
        "thisMonthPdf": thisMonthText,
        "lastMonthPdf": lastMonthText,
      };

      const url = "https://sales-ai-worker.app-lab-nanato.workers.dev";

      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "type": "chat",
          "messages": [
            {
              "role": "system",
              "content": """
あなたはコンビニ経営のプロ経営コンサルタントです。

以下の月次データをもとに、
経営状況を「経営者向けレポート」として文章で説明してください。

## 必須ルール
- 数値の羅列は禁止
- 表形式禁止
- JSON再出力禁止
- 箇条書きは最小限（使っても良いが説明中心）
- 必ず「なぜそうなったか」を推測して説明する

## 分析対象
- 売上高合計
- 売上原価合計
- 本部フィー
- 奨励金・助成金・支援金
- 販売奨励金
- 総収入
- 従業員給与
- 廃棄ロス
- 用度品代
- 棚卸
- 水道光熱費
- 清掃費
- 営業雑費
- 現金過不足
- 営業利益

## 分析観点
- 売上の増減理由
- 利益の増減理由
- コスト構造の変化
- 異常値の特定
- 改善提案

特に売上高合計と従業員給与と廃棄ロスと営業利益の先月との差異金額及び％表示で必ず回答する事。
""",
            },
            {"role": "user", "content": jsonEncode(payload)},
          ],
        }),
      );

      final decoded = utf8.decode(res.bodyBytes);

      if (res.statusCode != 200) {
        setState(() {
          pdfAnalysisResult = "HTTPエラー\n$decoded";
          pdfLoading = false;
        });
        return;
      }

      final data = jsonDecode(decoded);
      final content = data['choices'][0]['message']['content'];

      setState(() {
        pdfAnalysisResult = content;
        pdfLoading = false;
      });
    } catch (e) {
      setState(() {
        pdfAnalysisResult = "例外エラー: $e";
        pdfLoading = false;
      });
    }
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('月次経営分析')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _analyzePdf,
              child: const Text('PDF分析（経営レポート生成）'),
            ),

            const SizedBox(height: 20),

            if (pdfLoading) const CircularProgressIndicator(),

            const SizedBox(height: 20),

            const Text(
              '分析結果',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    pdfAnalysisResult.isEmpty ? '未分析' : pdfAnalysisResult,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String getStoreCode(String storeName) {
  switch (storeName) {
    case '東勝山二丁目店':
      return '61685';
    case '上杉一丁目店':
      return '61780';
    case '仙台木町通一丁目店':
      return '25658';
    case '安養寺二丁目店':
      return '61987';
    case '利府青山店':
      return '62012';
    case '電力ビル店':
      return '62060';
    case '中山台店':
      return '62219';
    default:
      return '';
  }
}
