// ============================================================
// 🔥 Firebase 配置文件
// 
// ⚠️  此文件需要用 FlutterFire CLI 自動生成
//     執行步驟：
//     1. 安裝 FlutterFire CLI：
//        dart pub global activate flutterfire_cli
//     2. 登入 Firebase：
//        firebase login
//     3. 在專案根目錄執行：
//        flutterfire configure
//     4. 選擇你的 Firebase 專案（或建立新的）
//     5. 選擇 android / ios 兩個平台
//     6. 指令完成後，此文件會自動被正確覆蓋
//
//  在完成上述步驟前，此佔位符文件可讓專案編譯通過。
// ============================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        '此 App 尚未配置 Web 平台的 Firebase。\n'
        '請執行 flutterfire configure 並選擇 web 平台。',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          '此平台尚未配置 Firebase。請執行 flutterfire configure。',
        );
    }
  }

  // ⚠️  以下為佔位符數值，必須執行 flutterfire configure 才能正確填入
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosClientId: 'YOUR_IOS_CLIENT_ID',
    iosBundleId: 'com.example.flutterApplication1',
  );
}
