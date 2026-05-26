import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'loginpage.dart' as login_page;
import 'gatepage.dart' as gate_page;
import 'mainpage.dart' as main_page;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

enum AppPage {
  login,
  gate,
  main,
}

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: switch (currentPage) {
        // =========================
        // ログインページ
        // =========================

        AppPage.login => login_page.LoginPage(
            onLoginSuccess: (stores, isAdmin) {
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
            onEnter: (
              store,
              address,
              lat,
              lon,
              actual,
              actualWaste,
            ) {
              setState(() {
                selectedStore = store;

                selectedGateData = {
                  'actual': actual,
                  'actualWaste': actualWaste,
                  'storeAddress': address,
                  'lat': lat,
                  'lon': lon,
                };

                currentPage = AppPage.main;
              });
            },
          ),

        // =========================
        // メインページ
        // =========================

        AppPage.main => main_page.MainPage(
            storeName: selectedStore!,
            gateData: selectedGateData,
          ),
      },
    );
  }
}
