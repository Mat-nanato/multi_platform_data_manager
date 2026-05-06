import 'package:flutter/material.dart';
import 'gatepage.dart' as gate_page; // 名前空間追加
import 'mainpage.dart' as main_page; // 名前空間追加

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool showGate = true;
  String? selectedStore; // 選択された店舗名を保存
  Map<String, String>? selectedGateData; // 売上・廃棄まとめて保存

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: showGate
          ? gate_page.GatePage(
              // GatePage側で渡している store, actual, actualWaste を Map で受け取る
              onEnter: (store, actual, actualWaste) {
                setState(() {
                  selectedStore = store;
                  selectedGateData = {
                    'actual': actual,
                    'actualWaste': actualWaste,
                  };
                  showGate = false; // GatePage を閉じる
                });
              },
            )
          : main_page.MainPage(
              storeName: selectedStore!, // 選択された店舗名を渡す
              gateData: selectedGateData, // 売上・廃棄まとめて渡す
              onBackToGate: () {
                setState(() {
                  showGate = true; // 再度 GatePage を表示
                });
              },
            ),
    );
  }
}
