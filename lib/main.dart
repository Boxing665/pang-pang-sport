import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/main_navigation_screen.dart';
import 'services/pang_pang_sports_service.dart';

void main() async {
  // 確保 Flutter 引擎已初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化 Firebase (若專案已設定則啟用，這對 Remote Config ML 權重很重要)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('⚠️ Firebase 初始化跳過：$e');
  }

  // 初始化體育預測單例服務，觸發背景緩存預熱與歷史偏差載入
  // 這能確保使用者「開起 APP」時，數據分析已經在後台運作
  PangPangSportsService();

  runApp(const PangPangApp());
}

class PangPangApp extends StatelessWidget {
  const PangPangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '胖胖體育',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        // 採用 APP 統一配色：薄荷綠 (數據感) + 財神金 (樂透感)
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3DDC97),
          brightness: Brightness.dark,
          primary: const Color(0xFF3DDC97),
          secondary: const Color(0xFFFFD700),
        ),
        scaffoldBackgroundColor: const Color(0xFF050E24),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          indicatorColor: Color(0xFF3DDC97),
          labelColor: Color(0xFF3DDC97),
          unselectedLabelColor: Colors.white54,
          labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      // 設定初始進入頁面為具備導覽功能的主分頁，找回以前的感覺
      home: const MainNavigationScreen(),
    );
  }
}

