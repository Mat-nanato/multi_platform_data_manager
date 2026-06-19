import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'gatepage.dart';
import 'dart:io';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'pdf_analysis_page.dart';
import 'package:file_picker/file_picker.dart';

class PdfListPage extends StatelessWidget {
  final int month;
  final List<File> files;

  const PdfListPage({super.key, required this.month, required this.files});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$month月 PDF一覧')),
      body: ListView.builder(
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];

          return ListTile(
            title: Text(file.path.split('/').last),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      Scaffold(appBar: AppBar(), body: SfPdfViewer.file(file)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

final logger = Logger();

class AiAnalysisPage extends StatefulWidget {
  final String store;

  const AiAnalysisPage({super.key, required this.store});

  @override
  State<AiAnalysisPage> createState() => _AiAnalysisPageState();
}

Future<void> _importPdf(int month) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );

  if (result == null) return;

  final sourcePath = result.files.single.path;

  if (sourcePath == null) return;

  final sourceFile = File(sourcePath);

  final dir = await getApplicationDocumentsDirectory();

  final fileName = sourcePath.split('/').last;

  final saveName =
      '${DateTime.now().year}${month.toString().padLeft(2, '0')}_$fileName';

  await sourceFile.copy('${dir.path}/$saveName');
}

class _AiAnalysisPageState extends State<AiAnalysisPage> {
  String pdfAnalysisResult = '';
  bool pdfLoading = false;
  bool loading = false;
  String result = '';

  Future<void> _showImportPdfMonthDialog() async {
    int selectedMonth = DateTime.now().month;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('保存月を選択'),
              content: DropdownButton<int>(
                value: selectedMonth,
                isExpanded: true,
                items: List.generate(
                  12,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1}月')),
                ),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() {
                      selectedMonth = v;
                    });
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);

                    await _importPdf(selectedMonth);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('daily_data')
        .where('store', isEqualTo: widget.store)
        .get();

    final data = snapshot.docs
        .map((doc) => doc.data())
        .cast<Map<String, dynamic>>()
        .toList();

    data.sort((a, b) {
      final da = DateTime.parse(a['date'].toString());
      final db = DateTime.parse(b['date'].toString());
      return da.compareTo(db);
    });

    return data;
  }

  String _getWeekday(DateTime date) {
    const w = ['月', '火', '水', '木', '金', '土', '日'];
    return w[date.weekday - 1];
  }

  bool _isJapaneseHoliday(DateTime date) {
    final m = date.month;
    final d = date.day;

    if (m == 1 && d == 1) {
      return true;
    }
    if (m == 2 && d == 11) {
      return true;
    }
    if (m == 2 && d == 23) {
      return true;
    }
    if (m == 4 && d == 29) {
      return true;
    }
    if (m == 5 && d == 3) {
      return true;
    }
    if (m == 5 && d == 4) {
      return true;
    }
    if (m == 5 && d == 5) {
      return true;
    }
    if (m == 8 && d == 11) {
      return true;
    }
    if (m == 11 && d == 3) {
      return true;
    }
    if (m == 11 && d == 23) {
      return true;
    }

    if (m == 1 && date.weekday == DateTime.monday && d >= 8 && d <= 14) {
      return true;
    }
    if (m == 7 && date.weekday == DateTime.monday && d >= 15 && d <= 21) {
      return true;
    }
    if (m == 9 && date.weekday == DateTime.monday && d >= 15 && d <= 21) {
      return true;
    }
    if (m == 10 && date.weekday == DateTime.monday && d >= 8 && d <= 14) {
      return true;
    }

    return false;
  }

  String _getSchoolEvent(DateTime date) {
    if (date.month == 3 && date.day <= 20) {
      return "卒業式";
    }
    if (date.month == 4 && date.day <= 15) {
      return "入学式";
    }
    return "なし";
  }

  List<String> _getTempEvents(double temp) {
    List<String> e = [];

    if (temp <= 5) {
      e.add("ホット飲料");
      e.add("中華まん");
    }
    if (temp >= 20) {
      e.add("クール麺");
    }
    if (temp >= 30) {
      e.add("冷凍飲料");
    }

    return e;
  }

  Future<Map<String, dynamic>> _fetchPastWeather(String date) async {
    const lat = 38.2682;
    const lon = 140.8694;

    final url =
        "https://archive-api.open-meteo.com/v1/archive?latitude=$lat&longitude=$lon&start_date=$date&end_date=$date&daily=temperature_2m_mean,weathercode&timezone=Asia%2FTokyo";

    final res = await http.get(Uri.parse(url));
    final body = utf8.decode(res.bodyBytes);

    if (res.statusCode != 200) {
      throw Exception("天気取得失敗");
    }

    final data = jsonDecode(body);

    return {
      "temp": data["daily"]["temperature_2m_mean"][0],
      "code": data["daily"]["weathercode"][0],
    };
  }

  Future<void> _analyze() async {
    setState(() => loading = true);

    try {
      final history = await _loadHistory();

      final storeInfo = storeInfoMap[widget.store];

      if (storeInfo == null) {
        throw Exception('店舗情報が見つかりません: ${widget.store}');
      }

      final wikiEvents = await _fetchWikiEvents(storeInfo.lat, storeInfo.lon);

      logger.i("店舗=${widget.store}");
      logger.i("住所=${storeInfo.address}");
      logger.i("lat=${storeInfo.lat}");
      logger.i("lon=${storeInfo.lon}");

      logger.i("===== HISTORY =====");
      logger.i(history);

      List<Map<String, dynamic>> enriched = [];

      double? prevTemp;

      for (final d in history) {
        final dateStr = d["date"].toString().substring(0, 10);
        final date = DateTime.parse(dateStr);

        final w = await _fetchPastWeather(dateStr);
        final temp = (w["temp"] as num).toDouble();

        double diff = 0;
        bool big = false;

        if (prevTemp != null) {
          diff = temp - prevTemp; // ← !削除
          if (diff.abs() >= 5) {
            big = true;
          }
        }

        prevTemp = temp;

        enriched.add({
          "date": dateStr,
          "store": d["store"],

          "sales": d["売上"],
          "customers": d["客数"],
          "wasteCost": d["廃棄（原価）"],

          "onigiriOrder": d["おむすび発注金額"],
          "sushiOrder": d["寿司発注金額"],
          "teionBentoOrder": d["定温弁当発注金額"],
          "sandwichOrder": d["サンドイッチ発注金額"],
          "pastaOrder": d["パスタ発注金額"],
          "saladOrder": d["サラダ発注金額"],
          "sweetBreadOrder": d["菓子パン発注金額"],
          "deliBreadOrder": d["惣菜パン発注金額"],
          "breadOrder": d["食パンマルチパン発注金額"],
          "ffOrder": d["FF発注金額"],

          "temperature": temp,
          "weekday": _getWeekday(date),
          "holiday": _isJapaneseHoliday(date),
          "event": _getSchoolEvent(date),
          "temp_events": _getTempEvents(temp),
          "temp_diff": diff,
          "big_change": big,
          "nearby_events": wikiEvents,
        });
      }
      logger.i("===== ENRICHED =====");
      logger.i(jsonEncode(enriched));

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
履歴データには過去の売上・客数・発注金額が含まれる。

必ず過去実績を分析し、

・売上
・客数
・おむすび発注金額
・寿司発注金額
・定温弁当発注金額
・チルド弁当発注金額
・サンドイッチ発注金額
・パスタ発注金額
・サラダ発注金額
・菓子パン発注金額
・惣菜パン発注金額
・食パンマルチパン発注金額
・FF発注金額

などの推移を参考に発注数を決定すること。

気温だけで判断してはならない。
過去実績を最優先で分析すること。

履歴データには以下の補足情報が含まれる。

holiday
- true = 祝日
- false = 平日

weekday
- 月 火 水 木 金 土 日

event
- 卒業式 → 昼食需要増加の可能性
- 入学式 → 新規客増加の可能性
- なし → 特殊イベントなし

temp_events
- ホット飲料 → 温かい商品の需要増
- 中華まん → 中華まん需要増
- クール麺 → 冷し麺需要増
- 冷凍飲料 → 冷たい飲料需要増

temperature
- 当日の平均気温

temp_diff
- 前日との気温差

big_change
- true = 前日比5℃以上の大幅変化
- false = 通常変動

temp_diffは重要指標である。

temp_diff >= 5
→ 冷し麺、サラダ、寿司を増やす

temp_diff <= -5
→ おにぎり、定温弁当、チルド弁当、FFを増やす

big_change=true の場合は
temperature単独より優先して判断すること。

発注理由には、
売上推移・客数推移・曜日・祝日・event・temp_events・temperature・temp_diff・big_change
を反映すること。

{
  "store": "店舗名",
  "date": "YYYY-MM-DD",
  "orders": [
    {
      "item": "商品名",
      "quantity": 0,
      "reason": "発注理由"
    }
  ]
}

ルール:
- storeは店舗名
- dateは対象日
- ordersは配列
- itemは必ず日本語の商品名
- quantityは整数
- reasonは日本語
- drink、bread、snackなど英語カテゴリは禁止
- orderというキーは禁止
- orders以外の構造は禁止
- 配列で囲まない
- JSON以外の文章は禁止
- Markdown禁止
- ```json 禁止

発注対象商品は必ず以下を全て出力すること。

- おにぎり
- 寿司
- 定温弁当
- チルド弁当
- サンドイッチ
- パスタ
- サラダ
- 菓子パン
- 惣菜パン
- 食パンマルチパン
- FF

上記11カテゴリを省略せず全件出力すること。

発注理由は気温・曜日・祝日・イベント・過去実績を考慮して記載してください。
""",
            },
            {"role": "user", "content": jsonEncode(enriched)},
          ],
        }),
      );

      final decoded = utf8.decode(res.bodyBytes);
      logger.i("RAW RESPONSE");
      logger.i(decoded);

      if (res.statusCode != 200) {
        setState(() {
          result = "HTTP ${res.statusCode}\n$decoded";
          loading = false;
        });
        return;
      }

      final data = jsonDecode(decoded);
      final content = data['choices']?[0]?['message']?['content'];

      logger.i("CONTENT TYPE");
      logger.i(content.runtimeType);

      logger.i("CONTENT VALUE");
      logger.i(content);

      try {
        String cleaned = content
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final orderJson = jsonDecode(cleaned) as Map<String, dynamic>;

        logger.i("TYPE");
        logger.i(orderJson.runtimeType);

        logger.i("JSON");
        logger.i(orderJson);

        String formatted = "";

        formatted += "【${orderJson["store"]}】\n";
        formatted += "${orderJson["date"]}\n\n";

        final orders = orderJson["orders"] as List<dynamic>;

        for (final item in orders) {
          formatted += "- ${item["item"]}：${item["quantity"]}円\n";

          if (item["reason"] != null) {
            formatted += "  理由：${item["reason"]}\n";
          }

          formatted += "\n";
        }

        setState(() {
          result = formatted;
          loading = false;
        });
      } catch (e, st) {
        logger.e("JSON PARSE ERROR", error: e, stackTrace: st);

        setState(() {
          result =
              "JSON解析失敗\n\n"
              "エラー: $e\n\n"
              "----- AI返答 -----\n"
              "$content";
          loading = false;
        });
      }
    } catch (e, st) {
      logger.e("UPLOAD ERROR", error: e, stackTrace: st);
      setState(() {
        result = "アップロード失敗\n$e";
      });
    }
  }

  Future<void> _showPdfMonthDialog() async {
    int selectedMonth = DateTime.now().month;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('月を選択'),
              content: DropdownButton<int>(
                value: selectedMonth,
                isExpanded: true,
                items: List.generate(
                  12,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1}月')),
                ),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => selectedMonth = v);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),

                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);

                    final dir = await getApplicationDocumentsDirectory();

                    final all = dir.listSync();

                    final storeCode = getStoreCode(widget.store);

                    final files = all
                        .where((e) {
                          final name = e.path.split('/').last;

                          final targetMonth =
                              '${DateTime.now().year}${selectedMonth.toString().padLeft(2, '0')}';

                          return name.endsWith('.pdf') &&
                              name.contains(storeCode) &&
                              name.contains(targetMonth);
                        })
                        .map((e) => File(e.path))
                        .toList();

                    if (!context.mounted) return;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PdfListPage(month: selectedMonth, files: files),
                      ),
                    );
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('発注AI')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _analyze,
                child: const Text('発注生成'),
              ),
            ),

            const SizedBox(height: 20),

            if (loading) const CircularProgressIndicator(),

            if (!loading)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            await launchUrl(
                              Uri.parse(
                                'https://procenter-global.com/procenter/jsp/index.jsp',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          child: const Text('損益書'),
                        ),
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _showImportPdfMonthDialog,
                          child: const Text('PDF取込'),
                        ),
                      ),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _showPdfMonthDialog,
                          child: const Text('PDF月別一覧'),
                        ),
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PdfAnalysisPage(store: widget.store),
                              ),
                            );
                          },
                          child: const Text('PDF分析'),
                        ),
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        '分析結果は間違えることがあります',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),

                      const SizedBox(height: 10),

                      if (pdfLoading)
                        const CircularProgressIndicator()
                      else
                        Text(pdfAnalysisResult),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<List<Map<String, dynamic>>> _fetchWikiEvents(
  double lat,
  double lon,
) async {
  const endpoint = "https://query.wikidata.org/sparql";

  final query =
      """
PREFIX geo: <http://www.opengis.net/ont/geosparql#>

SELECT ?event ?eventLabel WHERE {
  ?event wdt:P31/wdt:P279* wd:Q1190554.
  ?event wdt:P625 ?coord.

  SERVICE wikibase:around {
    ?location wdt:P625 ?coord.
    bd:serviceParam wikibase:center "Point($lon $lat)"^^geo:wktLiteral.
    bd:serviceParam wikibase:radius "10".
  }

  SERVICE wikibase:label {
    bd:serviceParam wikibase:language "ja,en".
  }
}
LIMIT 10
""";

  final res = await http.post(
    Uri.parse(endpoint),
    headers: {
      "Content-Type": "application/sparql-query",
      "Accept": "application/sparql-results+json",
      "User-Agent": "FlutterApp",
    },
    body: query,
  );

  if (res.statusCode != 200) {
    return [];
  }

  final body = utf8.decode(res.bodyBytes);

  if (!res.headers['content-type'].toString().contains('json')) {
    return [];
  }

  final data = jsonDecode(body);

  final results = data["results"]["bindings"] as List;

  return results.map((e) {
    return {"name": e["eventLabel"]?["value"] ?? ""};
  }).toList();
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
