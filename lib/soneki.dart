import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  int depreciationCount = 1;
  int managerCount = 0;
  int storeManagerCount = 0;
  int employeeManageCount = 0;
  int welfareCount = 0;
  int retirementCount = 1;
  int transportCount = 0;

  int _bExpenseTotal() {
    return depreciationCount * 100000 +
        managerCount * 400000 +
        storeManagerCount * 250000 +
        employeeManageCount * 80000 +
        welfareCount * 88888 +
        retirementCount * 10000 +
        transportCount * 50000;
  }

  final List<int> years = List.generate(6, (i) => DateTime.now().year - 3 + i);

  String selectedStore = '東勝山二丁目店';
  int selectedYear = DateTime.now().year;

  Map<String, String> pdfMap = {};

  bool isAnalyzing = false;
  String analysisResult = '';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    _loadPdfData();
    _loadAnalysisResult();
    _loadBExpenseSetting();
  }

  /// =========================
  /// PDFデータ読み込み
  /// =========================
  Future<void> _loadPdfData() async {
    final dir = await getApplicationDocumentsDirectory();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList();

    for (final file in files) {
      final name = file.path.split('/').last;

      final reg = RegExp(r'_(\d{6})_');

      final match = reg.firstMatch(name);

      if (match == null) continue;

      final ym = match.group(1)!;

      final year = int.parse(ym.substring(0, 4));

      final month = int.parse(ym.substring(4, 6));

      // 店舗コードから店舗名取得
      for (final store in stores) {
        final code = getStoreCode(store);

        if (name.contains(code)) {
          pdfMap['${store}_${year}_$month'] = file.path;
        }
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

  Future<void> _saveBExpenseSetting() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt("depreciationCount", depreciationCount);
    await prefs.setInt("managerCount", managerCount);
    await prefs.setInt("storeManagerCount", storeManagerCount);
    await prefs.setInt("employeeManageCount", employeeManageCount);
    await prefs.setInt("welfareCount", welfareCount);
    await prefs.setInt("retirementCount", retirementCount);
    await prefs.setInt("transportCount", transportCount);
  }

  Future<void> _loadBExpenseSetting() async {
    final prefs = await SharedPreferences.getInstance();

    depreciationCount = prefs.getInt("depreciationCount") ?? 1;
    managerCount = prefs.getInt("managerCount") ?? 0;
    storeManagerCount = prefs.getInt("storeManagerCount") ?? 0;
    employeeManageCount = prefs.getInt("employeeManageCount") ?? 0;
    welfareCount = prefs.getInt("welfareCount") ?? 0;
    retirementCount = prefs.getInt("retirementCount") ?? 1;
    transportCount = prefs.getInt("transportCount") ?? 0;

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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null) return;

    final path = result.files.single.path;

    if (path == null) return;

    // PDF文字抽出
    final pdfText = await _extractPdfText(path);

    final summary = parseProfitLoss(pdfText);

    // Firestoreへ保存
    await _firestore
        .collection("profit_summary")
        .doc("${selectedStore}_${selectedYear}_$month")
        .set({
          "store": selectedStore,
          "year": selectedYear,
          "month": month,
          ...summary,
          "updatedAt": FieldValue.serverTimestamp(),
        });

    debugPrint(pdfText);
    if (!mounted) return;
    // PDF表示画面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('PDF表示')),
          body: SfPdfViewer.file(File(path)),
        ),
      ),
    );

    final key = '${selectedStore}_${selectedYear}_$month';

    final file = File(path);

    final storageRef = _storage.ref().child(
      'soneki_pdf/$selectedStore/$selectedYear/$month.pdf',
    );

    await storageRef.putFile(file);

    final downloadUrl = await storageRef.getDownloadURL();

    pdfMap[key] = downloadUrl;

    await _savePdfData();

    setState(() {});
  }

  Map<String, dynamic> parseProfitLoss(String text) {
    return {
      "salesTotal": _findValueByLine(text, "売上高合計"),
      "operatingProfit": _findValueByLine(text, "営業利益"),
      "grossProfit": _findValueByLine(text, "営業総利益"),
      "totalIncome": _findValueByLine(text, "総収入"),
      "employeeSalary": _findValueByLine(text, "従業員給与"),
    };
  }

  int _findValueByLine(String text, String keyword) {
    final lines = text.split('\n');

    for (final line in lines) {
      final normalized = line.replaceAll(' ', '').replaceAll('　', '');

      if (normalized.contains(keyword)) {
        final match = RegExp(r'[\d,]+').firstMatch(line);

        if (match != null) {
          return int.parse(match.group(0)!.replaceAll(',', ''));
        }
      }
    }

    return 0;
  }

  /// =========================
  /// OpenAI分析
  /// =========================
  Future<void> _analyzeData() async {
    setState(() {
      isAnalyzing = true;
    });

    try {
      // 登録済みPDFから最新2か月を取得
      final months = pdfMap.keys
          .where((e) => e.startsWith('${selectedStore}_${selectedYear}_'))
          .map((e) => int.parse(e.split('_').last))
          .toList();

      months.sort();

      if (months.length < 2) {
        setState(() {
          analysisResult = "比較するPDFが2か月分以上登録されていません";
          isAnalyzing = false;
        });
        return;
      }

      final currentMonth = months.last;
      final previousMonth = months[months.length - 2];

      final currentSnapshot = await _firestore
          .collection("profit_summary")
          .where("year", isEqualTo: selectedYear)
          .where("month", isEqualTo: currentMonth)
          .get();

      final previousSnapshot = await _firestore
          .collection("profit_summary")
          .where("year", isEqualTo: selectedYear)
          .where("month", isEqualTo: previousMonth)
          .get();

      if (currentSnapshot.docs.isEmpty || previousSnapshot.docs.isEmpty) {
        setState(() {
          analysisResult = "$currentMonth月または$previousMonth月の損益データがありません";
          isAnalyzing = false;
        });
        return;
      }

      int currentSales = 0;
      int currentProfit = 0;

      int previousSales = 0;
      int previousProfit = 0;

      final List<Map<String, dynamic>> stores = [];

      for (final doc in currentSnapshot.docs) {
        final data = doc.data();

        currentSales += (data["salesTotal"] ?? 0) as int;
        currentProfit += (data["operatingProfit"] ?? 0) as int;

        stores.add({
          "store": data["store"],
          "sales": data["salesTotal"],
          "profit": data["operatingProfit"],
        });
      }

      for (final doc in previousSnapshot.docs) {
        final data = doc.data();

        previousSales += (data["salesTotal"] ?? 0) as int;
        previousProfit += (data["operatingProfit"] ?? 0) as int;
      }

      final bExpense = _bExpenseTotal();

      final payload = {
        "currentMonth": {
          "year": selectedYear,
          "month": currentMonth,
          "salesTotal": currentSales,
          "profitTotal": currentProfit,
        },
        "previousMonth": {
          "year": selectedYear,
          "month": previousMonth,
          "salesTotal": previousSales,
          "profitTotal": previousProfit,
        },
        "bExpenseTotal": bExpense,
        "stores": stores,
      };

      final result = await analyzePdfData(payload);

      await _saveAnalysisResult(result);

      setState(() {
        analysisResult = result;
        isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        analysisResult = "分析エラー: $e";
        isAnalyzing = false;
      });
    }
  }

  /// =========================
  /// 月カード
  /// =========================
  Widget _buildMonthCard(int month) {
    final key = '${selectedStore}_${selectedYear}_$month';

    final pdfUrl = pdfMap[key];

    final exists = pdfUrl != null;

    return Card(
      child: ListTile(
        title: Text('$month 月'),
        subtitle: Text(exists ? 'PDF登録済み' : 'PDF未登録'),
        trailing: ElevatedButton(
          onPressed: () async {
            final path = pdfMap[key];

            if (path != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('$month月PDF')),
                    body: SfPdfViewer.file(File(path)),
                  ),
                ),
              );
            } else {
              await _pickPdf(month);
            }
          },
          child: Text(exists ? '変更' : '追加'),
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
      appBar: AppBar(title: const Text('損益書+分析結果')),
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
                    return DropdownMenuItem(value: store, child: Text(store));
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
                    return DropdownMenuItem(value: year, child: Text('$year年'));
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
                  ...List.generate(12, (index) => _buildMonthCard(index + 1)),

                  const SizedBox(height: 20),

                  /// B勘定管理費入力
                  _buildBExpenseRow('減価償却', '店舗', 100000, depreciationCount, (
                    v,
                  ) {
                    setState(() {
                      depreciationCount = v;
                    });

                    _saveBExpenseSetting();
                  }),

                  _buildBExpenseRow('管理者数', '名', 400000, managerCount, (v) {
                    setState(() {
                      managerCount = v;
                    });

                    _saveBExpenseSetting();
                  }),

                  _buildBExpenseRow('店長数', '名', 250000, storeManagerCount, (v) {
                    setState(() {
                      storeManagerCount = v;
                    });
                    _saveBExpenseSetting();
                  }),

                  _buildBExpenseRow('社員管理費', '名', 80000, employeeManageCount, (
                    v,
                  ) {
                    setState(() {
                      employeeManageCount = v;
                    });
                    _saveBExpenseSetting();
                  }),

                  _buildBExpenseRow('法定福利・社会保険料', '名', 88888, welfareCount, (
                    v,
                  ) {
                    setState(() {
                      welfareCount = v;
                    });
                    _saveBExpenseSetting();
                  }),

                  _buildBExpenseRow('退職金積立金', '店舗', 10000, retirementCount, (
                    v,
                  ) {
                    setState(() {
                      retirementCount = v;
                    });
                    _saveBExpenseSetting();
                  }),

                  _buildBExpenseRow('移動交通費', '名', 50000, transportCount, (v) {
                    setState(() {
                      transportCount = v;
                    });
                    _saveBExpenseSetting();
                  }),

                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text(
                        'B勘定管理費合計 ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),

                      Text(
                        '${NumberFormat("#,###").format(_bExpenseTotal())}円',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  /// 分析ボタン
                  ElevatedButton(
                    onPressed: isAnalyzing ? null : _analyzeData,
                    child: Text(isAnalyzing ? '分析中...' : '分析結果'),
                  ),

                  const SizedBox(height: 20),

                  /// AI分析結果
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
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

  Widget _buildBExpenseRow(
    String title,
    String unit,
    int price,
    int count,
    Function(int) onChanged,
  ) {
    final total = count * price;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),

      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              DropdownButton<int>(
                value: count,

                items: List.generate(20, (index) {
                  return DropdownMenuItem(
                    value: index,
                    child: Text('$index$unit'),
                  );
                }),

                onChanged: (value) {
                  if (value == null) return;

                  onChanged(value);
                },
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text('× ¥${NumberFormat("#,###").format(price)}'),
              ),
            ],
          ),

          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '= ${NumberFormat("#,###").format(total)}円',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> analyzePdfData(Map<String, dynamic> payload) async {
    final prompt =
        '''
以下は全店舗の損益集計データです。

【今月】
${jsonEncode(payload["currentMonth"])}

【前月】
${jsonEncode(payload["previousMonth"])}

【店舗別】
${jsonEncode(payload["stores"])}

【B勘定管理費合計】
${payload["bExpenseTotal"]}円

以下の内容を分析してください。

・全店舗売上の前月比較
・営業利益の前月比較
・B勘定管理費合計を差し引いた営業利益額を計算
・差し引き後の利益が黒字か赤字かを評価
・売上・利益の増減率
・店舗別の好調・不調
・改善すべき店舗
・全体としての課題
・今後の改善提案

日本語で経営者向けに分かりやすく回答してください。
''';

    final response = await http.post(
      Uri.parse('https://sales-ai-worker.app-lab-nanato.workers.dev'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"type": "profit_analysis", "prompt": prompt}),
    );

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }

    final json = jsonDecode(response.body);

    return json["analysis"];
  }
}

Future<String> _extractPdfText(String path) async {
  try {
    final bytes = await File(path).readAsBytes();

    final document = PdfDocument(inputBytes: bytes);

    final text = PdfTextExtractor(document).extractText();

    document.dispose();

    return text;
  } catch (e) {
    return 'PDF解析失敗: $e';
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
