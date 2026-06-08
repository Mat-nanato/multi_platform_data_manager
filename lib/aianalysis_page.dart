import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

final logger = Logger();

class AiAnalysisPage extends StatefulWidget {
  final String store;

  const AiAnalysisPage({super.key, required this.store});

  @override
  State<AiAnalysisPage> createState() => _AiAnalysisPageState();
}

class _AiAnalysisPageState extends State<AiAnalysisPage> {
  bool loading = false;
  String result = '';

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('history') ?? [];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
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
          "temperature": temp,
          "weekday": _getWeekday(date),
          "holiday": _isJapaneseHoliday(date),
          "event": _getSchoolEvent(date),
          "temp_events": _getTempEvents(temp),
          "temp_diff": diff,
          "big_change": big,
        });
      }

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
あなたはコンビニ発注AIです。
JSONのみで返答してください。
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
        final orderJson = jsonDecode(content);

        logger.i("TYPE");
        logger.i(orderJson.runtimeType);

        logger.i("JSON");
        logger.i(orderJson);

        String formatted = "";

        for (final o in orderJson) {
          formatted += "【${o["store"]}】\n";

          final order = o["order"] as Map<String, dynamic>;

          order.forEach((name, qty) {
            formatted += "- $name：$qty\n";
          });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('発注AI')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(onPressed: _analyze, child: const Text('発注生成')),

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

                      ElevatedButton(
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
