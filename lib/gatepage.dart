import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multi_platform_data_manager/soneki.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class GatePage extends StatefulWidget {
  final List<String> allowedStores;
  final void Function(
    String store,
    String address,
    double lat,
    double lon,
    String actual,
    String actualWaste,
  )
  onEnter;

  const GatePage({
    super.key,
    required this.allowedStores,
    required this.onEnter,
  });

  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  DateTime? selectedDate;
  String? selectedStore;
  List<String> availableStores = [];

  final NumberFormat formatter = NumberFormat('#,###');

  final Map<String, TextEditingController> controllers = {
    '売上': TextEditingController(),
    '客数': TextEditingController(),
    '廃棄（原価）': TextEditingController(),
    'おむすび発注金額': TextEditingController(),
    '寿司発注金額': TextEditingController(),
    '定温弁当発注金額': TextEditingController(),
    'チルド弁当発注金額': TextEditingController(),
    'サンドイッチ発注金額': TextEditingController(),
    'パスタ発注金額': TextEditingController(),
    'サラダ発注金額': TextEditingController(),
    '菓子パン発注金額': TextEditingController(),
    '惣菜パン発注金額': TextEditingController(),
    '食パンマルチパン発注金額': TextEditingController(),
    'FF発注金額': TextEditingController(),
  };

  final List<String> stores = [
    '事業部',
    '東勝山二丁目店',
    '上杉一丁目店',
    '仙台木町通一丁目店',
    '安養寺二丁目店',
    '利府青山店',
    '電力ビル店',
    '中山台店',
  ];

  @override
  void initState() {
    super.initState();

    if (widget.allowedStores.contains('全店舗')) {
      availableStores = List.from(stores);
    } else {
      availableStores = widget.allowedStores;
    }

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('history') ?? [];

    if (history.isNotEmpty) {
      final latest = jsonDecode(history.last);
      setState(() {
        selectedDate = latest['date'] != null
            ? DateTime.parse(latest['date'])
            : DateTime.now();
        selectedStore = latest['store'];
      });

      if (selectedDate != null && selectedStore != null) {
        _loadDataFor(selectedDate!, selectedStore!);
      }
    } else {
      setState(() {
        selectedDate = DateTime.now();
      });
    }
  }

  void _formatNumber(TextEditingController controller, String value) {
    final numeric = value.replaceAll(',', '');
    if (numeric.isEmpty) return;

    final number = int.tryParse(numeric);
    if (number == null) return;

    final newText = formatter.format(number);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  String _cleanNumber(String value) {
    return value.replaceAll(',', '');
  }

  Future<void> _saveData() async {
    if (selectedDate == null || selectedStore == null) return;

    final prefs = await SharedPreferences.getInstance();

    final String actualKey =
        'actual-${DateFormat('yyyyMMdd').format(selectedDate!)}';
    final String actualWasteKey =
        'actualWaste-${DateFormat('yyyyMMdd').format(selectedDate!)}';

    await prefs.setString(actualKey, _cleanNumber(controllers['売上']!.text));
    await prefs.setString(
      actualWasteKey,
      _cleanNumber(controllers['廃棄（原価）']!.text),
    );

    final record = {
      "date": selectedDate!.toIso8601String(),
      "store": selectedStore,
      ...controllers.map((k, v) => MapEntry(k, _cleanNumber(v.text))),
    };
    debugPrint("SAVE RECORD");
    debugPrint(jsonEncode(record));

    try {
      await FirebaseFirestore.instance
          .collection('daily_data')
          .doc(
            '${selectedStore}_${DateFormat('yyyyMMdd').format(selectedDate!)}',
          )
          .set(record);

      debugPrint('Firestore保存完了');
    } catch (e, st) {
      debugPrint('Firestore保存失敗');
      debugPrint(e.toString());
      debugPrint(st.toString());
    }
  }

  Future<void> _loadDataFor(DateTime date, String store) async {
    final doc = await FirebaseFirestore.instance
        .collection('daily_data')
        .doc('${store}_${DateFormat('yyyyMMdd').format(date)}')
        .get();

    if (!mounted) return;

    if (!doc.exists) {
      setState(() {
        for (final entry in controllers.entries) {
          entry.value.text = '';
        }
      });
      return;
    }

    final data = doc.data()!;

    setState(() {
      for (final entry in controllers.entries) {
        final value = data[entry.key]?.toString() ?? '';

        entry.value.text = value.isNotEmpty
            ? formatter.format(int.tryParse(value) ?? 0)
            : '';
      }
    });
  }

  Widget _buildInput(String label) {
    final controller = controllers[label]!;
    final unit = label == '客数' ? '人' : '円';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixText: unit,
        ),
        onChanged: (value) {
          _formatNumber(controller, value);
          _saveData();
        },
      ),
    );
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CalendarDatePicker(
              initialDate: selectedDate ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
              onDateChanged: (date) {
                setState(() {
                  selectedDate = date;
                });
                if (selectedStore != null) {
                  _loadDataFor(date, selectedStore!);
                }
              },
            ),
            const SizedBox(height: 20),
            if (availableStores.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: selectedStore, // ← value → initialValue
                hint: const Text('店舗を選択'),
                items: availableStores.map((store) {
                  return DropdownMenuItem<String>(
                    value: store,
                    child: Text(store),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedStore = value;
                  });
                  if (selectedDate != null && value != null) {
                    _loadDataFor(selectedDate!, value);
                  }
                },
              ),
            const SizedBox(height: 20),
            if (selectedStore != null) ...[
              if (selectedStore != '事業部')
                ...controllers.keys.map((label) => _buildInput(label)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  debugPrint('【次へ】押下');

                  if (selectedStore == null) {
                    debugPrint('selectedStore == null');
                    return;
                  }

                  debugPrint('selectedStore = $selectedStore');

                  // 事業部なら別ページへ
                  if (selectedStore == '事業部') {
                    debugPrint('SonEkiPageへ遷移');

                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SonEkiPage()),
                    );

                    debugPrint('SonEkiPageから復帰');
                    return;
                  }

                  try {
                    final actual = _cleanNumber(controllers['売上']!.text);
                    final actualWaste = _cleanNumber(
                      controllers['廃棄（原価）']!.text,
                    );

                    debugPrint('actual = $actual');
                    debugPrint('actualWaste = $actualWaste');

                    final storeInfo = storeInfoMap[selectedStore!];

                    if (storeInfo == null) {
                      debugPrint('storeInfo == null');
                      return;
                    }

                    debugPrint(
                      'storeInfo: '
                      '${storeInfo.address}, '
                      '${storeInfo.lat}, '
                      '${storeInfo.lon}',
                    );

                    debugPrint('onEnter開始');

                    widget.onEnter(
                      selectedStore!,
                      storeInfo.address,
                      storeInfo.lat,
                      storeInfo.lon,
                      actual,
                      actualWaste,
                    );

                    debugPrint('onEnter終了');

                    await _saveData();

                    debugPrint('_saveData終了');
                  } catch (e, st) {
                    debugPrint('【エラー】$e');
                    debugPrint(st.toString());
                  }
                },
                child: const Text('次へ'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const Map<String, StoreInfo> storeInfoMap = {
  '事業部': StoreInfo(address: '事業部', lat: 0, lon: 0),
  '東勝山二丁目店': StoreInfo(address: '仙台市青葉区東勝山二丁目', lat: 38.2876, lon: 140.8713),
  '上杉一丁目店': StoreInfo(address: '仙台市青葉区上杉一丁目', lat: 38.2689, lon: 140.8721),
  '仙台木町通一丁目店': StoreInfo(address: '仙台市青葉区木町通一丁目', lat: 38.2680, lon: 140.8605),
  '安養寺二丁目店': StoreInfo(address: '仙台市宮城野区安養寺二丁目', lat: 38.2879, lon: 140.9108),
  '利府青山店': StoreInfo(address: '宮城郡利府町青山', lat: 38.3366, lon: 140.9990),
  '電力ビル店': StoreInfo(address: '仙台市青葉区一番町', lat: 38.2595, lon: 140.8698),
  '中山台店': StoreInfo(address: '仙台市青葉区中山台', lat: 38.3047, lon: 140.8422),
};

class StoreInfo {
  final String address;
  final double lat;
  final double lon;

  const StoreInfo({
    required this.address,
    required this.lat,
    required this.lon,
  });
}
