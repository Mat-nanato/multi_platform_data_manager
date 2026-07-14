import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PdfAnalysisPage extends StatefulWidget {
  final String store;

  const PdfAnalysisPage({super.key, required this.store});

  @override
  State<PdfAnalysisPage> createState() => _PdfAnalysisPageState();
}

class _PdfAnalysisPageState extends State<PdfAnalysisPage> {
  bool pdfLoading = false;
  String pdfAnalysisResult = '';

  Future<void> _saveAnalysis(String text) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('pdfAnalysis_${widget.store}', text);
  }

  Future<void> _loadAnalysis() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      pdfAnalysisResult = prefs.getString('pdfAnalysis_${widget.store}') ?? '';
    });
  }

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

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

  Future<String> _pdfToBase64(File file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  Future<int> _getCustomerTotal(DateTime targetMonth) async {
    final firstDay = DateTime(targetMonth.year, targetMonth.month, 1);

    final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0);

    int total = 0;

    for (
      DateTime day = firstDay;
      !day.isAfter(lastDay);
      day = day.add(const Duration(days: 1))
    ) {
      final doc = await FirebaseFirestore.instance
          .collection('daily_data')
          .doc('${widget.store}_${DateFormat('yyyyMMdd').format(day)}')
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        total += int.tryParse(data['客数']?.toString() ?? '0') ?? 0;
      }
    }

    return total;
  }

  // =========================
  // PDFボタン押下メイン処理
  // =========================
  Future<void> _analyzePdf() async {
    setState(() {
      pdfLoading = true;
    });

    try {
      final files = await _getStorePdfFiles();

      if (files.length < 2) {
        throw Exception('比較用PDFが不足しています');
      }

      final latestPdf = files[0];
      final previousPdf = files[1];

      final latestBase64 = await _pdfToBase64(latestPdf);
      final previousBase64 = await _pdfToBase64(previousPdf);

      // PDFファイル名の年月を取得
      final reg = RegExp(r'_(\d{6})_');

      final latestMatch = reg.firstMatch(latestPdf.path);
      final previousMatch = reg.firstMatch(previousPdf.path);

      if (latestMatch == null || previousMatch == null) {
        throw Exception('PDF年月が取得できません');
      }

      final latestYm = latestMatch.group(1)!;
      final previousYm = previousMatch.group(1)!;

      // yyyyMM → DateTime
      final latestMonth = DateTime(
        int.parse(latestYm.substring(0, 4)),
        int.parse(latestYm.substring(4, 6)),
      );

      final previousMonth = DateTime(
        int.parse(previousYm.substring(0, 4)),
        int.parse(previousYm.substring(4, 6)),
      );

      // PDF年月で客数取得
      final lastMonthCustomers = await _getCustomerTotal(latestMonth);

      final previousMonthCustomers = await _getCustomerTotal(previousMonth);

      const url = "https://sales-ai-worker.app-lab-nanato.workers.dev";

      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "type": "pdf_analysis",
          "store": widget.store,

          "latestPdf": latestBase64,
          "previousPdf": previousBase64,

          "lastMonthCustomers": lastMonthCustomers,
          "previousMonthCustomers": previousMonthCustomers,
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

      String content;

      if (data['choices'] != null) {
        content = data['choices'][0]['message']['content'];
      } else if (data['result'] != null) {
        content = data['result'];
      } else if (data['analysis'] != null) {
        content = data['analysis'];
      } else {
        content = "解析結果が取得できません\n\n$decoded";
      }

      setState(() {
        pdfAnalysisResult = content;
        pdfLoading = false;
      });

      await _saveAnalysis(content);

      await _saveAnalysis(content);
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
