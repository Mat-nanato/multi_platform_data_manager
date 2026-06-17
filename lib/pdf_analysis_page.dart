import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class PdfAnalysisPage extends StatefulWidget {
  final String store;

  const PdfAnalysisPage({super.key, required this.store});

  @override
  State<PdfAnalysisPage> createState() => _PdfAnalysisPageState();
}

class _PdfAnalysisPageState extends State<PdfAnalysisPage> {
  bool pdfLoading = false;
  String pdfAnalysisResult = '';

  // =========================
  // PDFボタン押下メイン処理
  // =========================
  Future<void> _analyzePdf() async {
    setState(() {
      pdfLoading = true;
      pdfAnalysisResult = '';
    });

    try {
      final now = DateTime.now();

      final thisMonth = await _loadMonthlyData(now.month);
      final lastMonth = await _loadMonthlyData(now.month - 1);

      final payload = {
        "store": widget.store,
        "thisMonth": thisMonth,
        "lastMonth": lastMonth,
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

特に営業利益の変化を最重要視すること。
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
  // Firestore 月次集計
  // =========================
  Future<Map<String, dynamic>> _loadMonthlyData(int month) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('daily_data')
        .where('store', isEqualTo: widget.store)
        .get();

    double sales = 0;
    double cost = 0;
    double profit = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();

      try {
        final date = DateTime.parse(data['date']);

        if (date.month != month) continue;

        sales += (data['売上'] ?? 0).toDouble();
        cost += (data['原価'] ?? 0).toDouble();
        profit += (data['営業利益'] ?? 0).toDouble();
      } catch (_) {
        continue;
      }
    }

    return {"売上高合計": sales, "売上原価合計": cost, "営業利益": profit};
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
