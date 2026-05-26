import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  final Function(List<String> stores, bool isAdmin) onLoginSuccess;

  const LoginPage({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController adminIdController = TextEditingController();

  final Map<String, List<String>> passwordMap = {
    "100927": ["全店舗"],
    "061685": ["東勝山二丁目店"],
    "061780": ["上杉一丁目店"],
    "025658": ["仙台木町通一丁目店"],
    "061987": ["安養寺二丁目店"],
    "062012": ["利府青山店"],
    "062060": ["電力ビル店"],
    "062219": ["中山台店"],
  };

  final List<String> guestStores = [
    "東勝山二丁目店",
    "上杉一丁目店",
    "仙台木町通一丁目店",
    "安養寺二丁目店",
    "利府青山店",
    "電力ビル店",
    "中山台店",
  ];

  String? selectedGuestStore;
  bool showGuestDropdown = false;

  String? errorText;

  @override
  void dispose() {
    adminIdController.dispose();
    super.dispose();
  }

  // =========================
  // 管理者ログイン
  // =========================

  void login() {
    final input = adminIdController.text.trim();

    if (passwordMap.containsKey(input)) {
      widget.onLoginSuccess(passwordMap[input]!, true);
    } else {
      setState(() {
        errorText = '管理者IDが違います';
      });
    }
  }

  // =========================
  // 一般ログイン
  // =========================

  void guestNext() {
    setState(() {
      showGuestDropdown = true;
    });
  }

  void guestLogin() {
    if (selectedGuestStore == null) return;

    widget.onLoginSuccess(
      [selectedGuestStore!],
      false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.blueGrey,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // =========================
                    // 一般UI
                    // =========================

                    const Text(
                      '一般',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 次へボタン
                    if (!showGuestDropdown)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: guestNext,
                          child: const Text(
                            '次へ',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),

                    // プルダウン表示
                    if (showGuestDropdown) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedGuestStore,
                        decoration: const InputDecoration(
                          labelText: '店舗を選択',
                          border: OutlineInputBorder(),
                        ),
                        items: guestStores.map((store) {
                          return DropdownMenuItem<String>(
                            value: store,
                            child: Text(store),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedGuestStore = value;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed:
                              selectedGuestStore == null ? null : guestLogin,
                          child: const Text(
                            '決定',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),

                    const Divider(),

                    const SizedBox(height: 40),

                    // =========================
                    // 管理者UI
                    // =========================

                    const Text(
                      '管理者ログイン',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 24),

                    TextField(
                      controller: adminIdController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '管理者ID',
                        border: const OutlineInputBorder(),
                        errorText: errorText,
                      ),
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: login,
                        child: const Text(
                          '次へ',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
