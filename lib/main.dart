import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'loginpage.dart' as login_page;
import 'gatepage.dart' as gate_page;
import 'mainpage.dart' as main_page;
import 'package:firebase_storage/firebase_storage.dart';

import 'package:logger/logger.dart';

final logger = Logger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  logger.i("BUCKET=${FirebaseStorage.instance.bucket}");

  runApp(const MyApp());
}

enum AppPage { login, gate, main }

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppPage currentPage = AppPage.login;

  String? selectedStore;

  Map<String, dynamic>? selectedGateData;

  List<String> allowedStores = [];

  @override
  Widget build(BuildContext context) {
    debugPrint('BUILD: $currentPage');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: switch (currentPage) {
        // =========================
        // ログインページ
        // =========================
        AppPage.login => login_page.LoginPage(
          onLoginSuccess: (stores, isAdmin) {
            debugPrint('LOGIN SUCCESS');
            setState(() {
              allowedStores = stores;

              // 管理者
              if (isAdmin) {
                currentPage = AppPage.gate;
              }
              // 一般
              else {
                selectedStore = stores.first;

                selectedGateData = null;

                currentPage = AppPage.main;
              }
            });
          },
        ),

        // =========================
        // ゲートページ
        // =========================
        AppPage.gate => gate_page.GatePage(
          allowedStores: allowedStores,
          onEnter: (store, address, lat, lon, actual, actualWaste) {
            debugPrint('ENTER');
            setState(() {
              selectedStore = store;

              selectedGateData = {
                'store': store,
                'actual': actual,
                'actualWaste': actualWaste,
                'storeAddress': address,
                'lat': lat,
                'lon': lon,
              };

              currentPage = AppPage.main;
              debugPrint('currentPage -> $currentPage');
            });
          },
        ),

        // =========================
        // メインページ
        // =========================
        AppPage.main => main_page.MainPage(
          storeName: selectedStore!,
          gateData: selectedGateData,
          onBack: () {
            setState(() {
              currentPage = AppPage.login;

              // 必要なら状態も初期化
              selectedStore = null;
              selectedGateData = null;
              allowedStores = [];
            });
          },
        ),
      },
    );
  }
}
