import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

final formatter = NumberFormat('#,###');

class TenpoDataPage extends StatefulWidget {
  final String actual;
  final String actualWaste;
  final String storeAddress;

  final double lat;
  final double lon;

  final String storeName;

  const TenpoDataPage({
    super.key,
    required this.storeName,
    required this.lat,
    required this.lon,
    this.actual = '',
    this.actualWaste = '',
    this.storeAddress = '',
  });

  @override
  State<TenpoDataPage> createState() => _TenpoDataPageState();
}

class _TenpoDataPageState extends State<TenpoDataPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<String, dynamic> _weatherMap = {};

  int _calculateBaseDailyTarget(DateTime day) {
    int monthlyTarget = _parse(_monthlyTargetController.text);
    int daysInMonth = DateTime(day.year, day.month + 1, 0).day;
    if (daysInMonth == 0) return 0;
    return (monthlyTarget / daysInMonth).round();
  }

  // 売上の累計
  Future<int> _getMonthlyTotalUntilSelected() async {
    int total = 0;

    DateTime start = DateTime(_selectedDay.year, _selectedDay.month, 1);

    for (int i = 0; i <= _selectedDay.day - 1; i++) {
      DateTime day = start.add(Duration(days: i));

      final doc = await FirebaseFirestore.instance
          .collection('daily_data')
          .doc('${widget.storeName}_${DateFormat('yyyyMMdd').format(day)}')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        total += _parse(data['売上'] ?? '0');
      }
    }

    return total;
  }

  // 累計廃棄
  Future<int> _getMonthlyWasteTotalUntilSelected() async {
    int total = 0;

    DateTime start = DateTime(_selectedDay.year, _selectedDay.month, 1);

    for (int i = 0; i <= _selectedDay.day - 1; i++) {
      DateTime day = start.add(Duration(days: i));

      final doc = await FirebaseFirestore.instance
          .collection('daily_data')
          .doc('${widget.storeName}_${DateFormat('yyyyMMdd').format(day)}')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        total += _parse(data['廃棄（原価）'] ?? '0');
      }
    }

    return total;
  }

  Future<int> _calculateMonthlyAchievementRate() async {
    int monthlyTarget = _parse(_monthlyTargetController.text);
    if (monthlyTarget == 0) return 0;

    int total = await _getMonthlyTotalUntilSelected();

    return ((total / monthlyTarget) * 100).round();
  }

  Future<int> _calculateMonthlyWasteRate() async {
    int monthlyWasteTarget = _parse(_monthlyWasteController.text);
    if (monthlyWasteTarget == 0) return 0;

    int totalWaste = await _getMonthlyWasteTotalUntilSelected();

    return ((totalWaste / monthlyWasteTarget) * 100).round();
  }

  final TextEditingController _monthlyTargetController =
      TextEditingController();
  final TextEditingController _monthlyWasteController = TextEditingController();
  final TextEditingController _weekdayController = TextEditingController();
  final TextEditingController _saturdayController = TextEditingController();
  final TextEditingController _sundayController = TextEditingController();
  final TextEditingController _holidayController = TextEditingController();
  final TextEditingController _actualController = TextEditingController();
  final TextEditingController _actualWasteController = TextEditingController();
  final TextEditingController _weekdayWasteController = TextEditingController();
  final TextEditingController _dayHolidayWasteController =
      TextEditingController();

  String _weekday = '', _saturday = '', _sunday = '', _holiday = '';
  String _weekdayWaste = '', _dayHolidayWaste = '';

  final Set<DateTime> _holidays = {
    DateTime(2026, 1, 1),
    DateTime(2026, 2, 11),
    DateTime(2026, 4, 29),
  };

  bool isHoliday(DateTime day) {
    return _holidays.any(
      (d) => d.year == day.year && d.month == day.month && d.day == day.day,
    );
  }

  @override
  void initState() {
    super.initState();

    _addCommaFormat(_monthlyTargetController);
    _addCommaFormat(_monthlyWasteController);
    _addCommaFormat(_actualController);
    _addCommaFormat(_actualWasteController);

    _loadData().then((_) {
      if (widget.actual.isNotEmpty) {
        _actualController.text = widget.actual;
      }

      if (widget.actualWaste.isNotEmpty) {
        _actualWasteController.text = widget.actualWaste;
      }
    });
    debugPrint('storeAddress = ${widget.storeAddress}');
    _loadWeather();
  }

  void _addCommaFormat(TextEditingController controller) {
    controller.addListener(() {
      final text = controller.text.replaceAll(',', '');
      if (text.isEmpty) return;
      final value = int.tryParse(text);
      if (value == null) return;

      final newText = formatter.format(value);
      if (newText != controller.text) {
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }

      // ここで日割りを再計算
      setState(() {});
    });
  }

  int _parse(String text) => int.tryParse(text.replaceAll(',', '')) ?? 0;

  Future<void> _saveAll() async {
    await FirebaseFirestore.instance
        .collection('tenpo_setting')
        .doc(widget.storeName)
        .set({
          'monthlyTarget': _monthlyTargetController.text,
          'monthlyWaste': _monthlyWasteController.text,

          'weekday': _weekday,
          'saturday': _saturday,
          'sunday': _sunday,
          'holiday': _holiday,

          'weekdayWaste': _weekdayWaste,
          'dayHolidayWaste': _dayHolidayWaste,
        });

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('保存しました')));
  }

  Future<void> _loadData() async {
    // 売上目標などはFirestore
    final doc = await FirebaseFirestore.instance
        .collection('tenpo_setting')
        .doc(widget.storeName)
        .get();

    final dailyDoc = await FirebaseFirestore.instance
        .collection('daily_data')
        .doc(
          '${widget.storeName}_${DateFormat('yyyyMMdd').format(_selectedDay)}',
        )
        .get();

    if (dailyDoc.exists) {
      final daily = dailyDoc.data()!;

      _actualController.text = daily['売上'] ?? '';
      _actualWasteController.text = daily['廃棄（原価）'] ?? '';
    }

    setState(() {
      if (doc.exists) {
        final data = doc.data()!;

        _monthlyTargetController.text = data['monthlyTarget'] ?? '';

        _monthlyWasteController.text = data['monthlyWaste'] ?? '';

        _weekday = data['weekday'] ?? '';
        _saturday = data['saturday'] ?? '';
        _sunday = data['sunday'] ?? '';
        _holiday = data['holiday'] ?? '';

        _weekdayWaste = data['weekdayWaste'] ?? '';
        _dayHolidayWaste = data['dayHolidayWaste'] ?? '';
      }

      _weekdayController.text = _weekday;
      _saturdayController.text = _saturday;
      _sundayController.text = _sunday;
      _holidayController.text = _holiday;

      _weekdayWasteController.text = _weekdayWaste;
      _dayHolidayWasteController.text = _dayHolidayWaste;
    });
  }

  @override
  void dispose() {
    _monthlyTargetController.dispose();
    _monthlyWasteController.dispose();
    _weekdayController.dispose();
    _saturdayController.dispose();
    _sundayController.dispose();
    _holidayController.dispose();
    _actualController.dispose();
    _actualWasteController.dispose(); // ← ★ここ追加
    _weekdayWasteController.dispose();
    _dayHolidayWasteController.dispose();
    super.dispose();
  }

  String _dayLabel(DateTime day) {
    if (isHoliday(day)) return '祝日';
    switch (day.weekday) {
      case DateTime.saturday:
        return '土曜';
      case DateTime.sunday:
        return '日曜';
      default:
        return '平日';
    }
  }

  int _calculateDailyTarget(DateTime day) {
    int monthlyTarget = _parse(_monthlyTargetController.text);
    int days = DateTime(day.year, day.month + 1, 0).day;

    double ratio = 0;
    switch (_dayLabel(day)) {
      case '平日':
        ratio = double.tryParse(_weekday) ?? 0;
        break;
      case '土曜':
        ratio = double.tryParse(_saturday) ?? 0;
        break;
      case '日曜':
        ratio = double.tryParse(_sunday) ?? 0;
        break;
      case '祝日':
        ratio = double.tryParse(_holiday) ?? 0;
        break;
    }

    return ((monthlyTarget / days) * (ratio / 100)).round();
  }

  int _calculateDailyWasteTarget(DateTime day) {
    int monthlyWaste = _parse(_monthlyWasteController.text);
    int days = DateTime(day.year, day.month + 1, 0).day;

    double ratio = (_dayLabel(day) == '平日')
        ? double.tryParse(_weekdayWaste) ?? 0
        : double.tryParse(_dayHolidayWaste) ?? 0;

    return ((monthlyWaste / days) * (ratio / 100)).round();
  }

  int _calculateAchievementRate(int dailyTarget) {
    int actual = _parse(_actualController.text);
    if (dailyTarget == 0) return 0;
    return ((actual / dailyTarget) * 100).round();
  }

  int _calculateWasteRate(int dailyWaste) {
    int actualWaste = _parse(_actualWasteController.text);
    if (dailyWaste == 0) return 0;
    if (actualWaste == 0) return 100; // 廃棄ゼロ＝満点扱い
    return ((dailyWaste / actualWaste) * 100).round();
  }

  Widget _buildRatioCard(String label, TextEditingController controller) {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.all(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                ),
              ),
              const Text('%'),
              IconButton(
                icon: const Icon(Icons.save, size: 16),
                onPressed: () {
                  setState(() {
                    switch (label) {
                      case '平日売上':
                        _weekday = controller.text;
                        break;
                      case '土曜':
                        _saturday = controller.text;
                        break;
                      case '日曜':
                        _sunday = controller.text;
                        break;
                      case '祝日':
                        _holiday = controller.text;
                        break;
                      case '平日廃棄':
                        _weekdayWaste = controller.text;
                        break;
                      case '日祝廃棄':
                        _dayHolidayWaste = controller.text;
                        break;
                    }
                  });
                  _saveAll();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadWeather() async {
    debugPrint('lat=${widget.lat}');
    debugPrint('lon=${widget.lon}');

    final weatherUrl =
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${widget.lat}'
        '&longitude=${widget.lon}'
        '&daily=temperature_2m_max,temperature_2m_min'
        '&timezone=Asia%2FTokyo';

    debugPrint(weatherUrl);

    final weatherRes = await http.get(Uri.parse(weatherUrl));

    if (weatherRes.statusCode != 200) {
      debugPrint('weather error');
      return;
    }

    final data = jsonDecode(weatherRes.body);

    final dates = data['daily']['time'];
    final maxTemps = data['daily']['temperature_2m_max'];
    final minTemps = data['daily']['temperature_2m_min'];

    Map<String, dynamic> tempMap = {};

    for (int i = 0; i < dates.length; i++) {
      tempMap[dates[i]] = {'max': maxTemps[i], 'min': minTemps[i]};
    }

    for (int i = 1; i < dates.length; i++) {
      double diff = maxTemps[i] - maxTemps[i - 1];
      tempMap[dates[i]]['diff'] = diff;
    }

    debugPrint(tempMap.toString());

    setState(() {
      _weatherMap = tempMap;
    });
  }

  String _formattedDay(DateTime d) =>
      '${d.year}/${d.month}/${d.day}（${_dayLabel(d)}）';

  @override
  Widget build(BuildContext context) {
    int dailyTarget = _calculateDailyTarget(_selectedDay);
    int dailyWaste = _calculateDailyWasteTarget(_selectedDay);
    int achievement = _calculateAchievementRate(dailyTarget);

    int wasteRate = _calculateWasteRate(dailyWaste);

    return Scaffold(
      appBar: AppBar(title: const Text('店舗データ詳細')),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('月間売上目標'),
                  Expanded(
                    child: TextField(
                      controller: _monthlyTargetController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Text('円'),
                  IconButton(icon: const Icon(Icons.save), onPressed: _saveAll),
                ],
              ),
              Row(
                children: [
                  const Text('月間廃棄目標'),
                  Expanded(
                    child: TextField(
                      controller: _monthlyWasteController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Text('円'),
                  IconButton(icon: const Icon(Icons.save), onPressed: _saveAll),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                color: Colors.blue[50],
                child: TableCalendar(
                  rowHeight: 80,
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                  availableGestures: AvailableGestures.all,
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) {
                      String key = DateFormat('yyyy-MM-dd').format(day);

                      debugPrint('calendar=$key weather=${_weatherMap[key]}');

                      final weather = _weatherMap[key];

                      return Container(
                        margin: const EdgeInsets.all(2),
                        padding: const EdgeInsets.all(2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${day.day}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (weather != null) ...[
                              Text(
                                '↑${weather['max'].round()}°',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.red,
                                ),
                              ),
                              Text(
                                '↓${weather['min'].round()}°',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.blue,
                                ),
                              ),
                              if (weather['diff'] != null)
                                Text(
                                  '${weather['diff'] >= 0 ? '+' : ''}${weather['diff'].round()}°',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: weather['diff'] >= 0
                                        ? Colors.orange
                                        : Colors.cyan,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  onDaySelected: (s, f) async {
                    final dailyDoc = await FirebaseFirestore.instance
                        .collection('daily_data')
                        .doc(
                          '${widget.storeName}_${DateFormat('yyyyMMdd').format(s)}',
                        )
                        .get();

                    setState(() {
                      _selectedDay = s;
                      _focusedDay = f;

                      if (dailyDoc.exists) {
                        final daily = dailyDoc.data()!;

                        _actualController.text = daily['売上'] ?? '';
                        _actualWasteController.text = daily['廃棄（原価）'] ?? '';
                      } else {
                        _actualController.clear();
                        _actualWasteController.clear();
                      }
                    });
                  },
                ),
              ),
              // ← ここに基準日時売上カードを追加
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '基準日割り売上（単純割）　${formatter.format(_calculateBaseDailyTarget(_selectedDay))} 円',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // 既存の比率カード
              Row(
                children: [
                  _buildRatioCard('平日売上', _weekdayController),
                  _buildRatioCard('土曜', _saturdayController),
                ],
              ),
              Row(
                children: [
                  _buildRatioCard('日曜', _sundayController),
                  _buildRatioCard('祝日', _holidayController),
                ],
              ),
              Row(
                children: [
                  _buildRatioCard('平日廃棄', _weekdayWasteController),
                  _buildRatioCard('日祝廃棄', _dayHolidayWasteController),
                ],
              ),
              // 日販目標
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${_formattedDay(_selectedDay)} 日販目標（税込）　${formatter.format(dailyTarget)} 円',
                  ),
                ),
              ),

              // 累計達成率カード
              FutureBuilder<int>(
                future: _calculateMonthlyAchievementRate(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  return Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '現在までの累計達成率　${snapshot.data}%'
                        '（累計売上 ÷ 月間目標）',
                      ),
                    ),
                  );
                },
              ),

              // 日割り廃棄目標
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${_formattedDay(_selectedDay)} 日割廃棄目標（税込）　${formatter.format(dailyWaste)} 円',
                  ),
                ),
              ),

              // 累計廃棄使用率カード
              FutureBuilder<int>(
                future: _calculateMonthlyWasteRate(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  return Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '現在までの累計廃棄使用率　${snapshot.data}%'
                        '（累計廃棄 ÷ 月間廃棄目標）',
                      ),
                    ),
                  );
                },
              ),
              Card(
                child: Row(
                  children: [
                    const Text('売上'),
                    Expanded(
                      child: TextField(
                        controller: _actualController,
                        readOnly: true, // 手入力禁止
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Text('円'),
                    Text('達成率 $achievement%'),
                  ],
                ),
              ),
              Card(
                child: Row(
                  children: [
                    const Text('廃棄'),
                    Expanded(
                      child: TextField(
                        controller: _actualWasteController,
                        readOnly: true, // 手入力禁止
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Text('円'),
                    Text('達成率 $wasteRate%'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
