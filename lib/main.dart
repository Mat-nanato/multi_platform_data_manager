import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'gatepage.dart' as gate_page;
import 'mainpage.dart' as main_page;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool showGate = true;

  String? selectedStore;

  Map<String, dynamic>? selectedGateData;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: showGate
          ? gate_page.GatePage(
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

                  showGate = false;
                });
              },
            )
          : main_page.MainPage(
              storeName: selectedStore!,
              gateData: selectedGateData,
              onBackToGate: () {
                setState(() {
                  showGate = true;
                });
              },
            ),
    );
  }
}
