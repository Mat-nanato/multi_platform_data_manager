import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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

  String selectedStore = '東勝山二丁目店';

  Map<String, String> pdfMap = {};

  @override
  void initState() {
    super.initState();
    _loadPdfData();
  }

  Future<void> _loadPdfData() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString('soneki_pdf_data');

    if (data != null) {
      pdfMap = Map<String, String>.from(jsonDecode(data));
    }

    setState(() {});
  }

  Future<void> _savePdfData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'soneki_pdf_data',
      jsonEncode(pdfMap),
    );
  }

  Future<void> _pickPdf(int month) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null) return;

    final path = result.files.single.path;

    if (path == null) return;

    final key = '${selectedStore}_$month';

    pdfMap[key] = path;

    await _savePdfData();

    setState(() {});
  }

  Widget _buildMonthCard(int month) {
    final key = '${selectedStore}_$month';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('損益書格納庫'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedStore,
              decoration: const InputDecoration(
                labelText: '店舗選択',
                border: OutlineInputBorder(),
              ),
              items: stores.map((store) {
                return DropdownMenuItem(
                  value: store,
                  child: Text(store),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  selectedStore = value;
                });
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: 12,
                itemBuilder: (context, index) {
                  return _buildMonthCard(index + 1);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
