# Firebase 安全設定指南

## 一次性前置作業（只需做一次）

### 步驟 1 — 建立 Firebase 專案

1. 前往 [Firebase Console](https://console.firebase.google.com/)
2. 點擊「新增專案」，輸入名稱（例如 `pang-pang-sports`）
3. 依照引導完成建立

---

### 步驟 2 — 啟用所需的 Firebase 服務

在 Firebase Console 左側選單依序啟用：

| 服務 | 位置 | 設定 |
|------|------|------|
| **Authentication** | 建構 → Authentication → 開始使用 | 啟用「電子郵件/密碼」登入方式 |
| **Firestore** | 建構 → Firestore Database → 建立資料庫 | 選「以正式版模式開始」→ 選擇最近的伺服器位置 |
| **App Check** | 建構 → App Check | 見步驟 4 |

---

### 步驟 3 — 連接 Flutter 專案

在專案根目錄執行以下指令（需先安裝 [Firebase CLI](https://firebase.google.com/docs/cli)）：

```bash
# 安裝 Firebase CLI（如果還沒有）
npm install -g firebase-tools

# 登入 Firebase
firebase login

# 安裝 FlutterFire CLI
dart pub global activate flutterfire_cli

# 自動生成 lib/firebase_options.dart（完成後會覆蓋佔位符文件）
flutterfire configure
# ↑ 按照互動式提示選擇你的專案與 Android / iOS 平台
```

執行完畢後 `lib/firebase_options.dart` 會自動填入正確的 API Key 和 App ID。

---

### 步驟 4 — 設定 App Check

**Android（Play Integrity）：**

1. Firebase Console → App Check → Android App → 「Play Integrity」
2. 在 [Google Play Console](https://play.google.com/console) 確保 App 已完成一次「內部測試」上傳（Play Integrity 需要 App 在 Play 上有記錄）
3. 本機測試時 Debug Provider 會自動啟用（`kDebugMode = true`），不影響正式版

**iOS（App Attest）：**

1. Firebase Console → App Check → iOS App → 「App Attest」
2. 需要 iOS 14+ 的真機才能驗證（模擬器自動降級為 Debug）
3. 同上，本機測試時 Debug Provider 自動啟用

**開啟強制執行：**
- 在 App Check 頁面，對每個 App 點擊「強制執行」
- ⚠️ 強制執行後，沒有 App Check Token 的請求（包括直接 curl、第三方程式）將被 Firebase 完全拒絕

---

### 步驟 5 — 部署 Firestore Security Rules

```bash
# 在專案根目錄執行（使用已建立的 firestore.rules 文件）
firebase deploy --only firestore:rules
```

規則說明：

| 集合 | 誰能讀 | 誰能寫 |
|------|--------|--------|
| `/history` | 所有通過 App Check 的請求 | 僅後端 Admin SDK |
| `/predictions` (tier: public) | 所有通過 App Check 的請求 | 僅後端 Admin SDK |
| `/predictions` (tier: member) | 已登入用戶 | 僅後端 Admin SDK |
| `/predictions` (tier: vip) | isVIP == true 的用戶 | 僅後端 Admin SDK |
| `/users/{uid}` | 本人 | 本人（isVIP 欄位除外） |

---

### 步驟 6 — 安裝套件並測試

```bash
flutter pub get
flutter run
```

---

## VIP 用戶管理

升級用戶為 VIP 需透過 Firebase Admin SDK（後端操作，客戶端無法自行升級）：

```javascript
// Firebase Admin SDK（Node.js 後端範例）
const admin = require('firebase-admin');

await admin.firestore()
  .collection('users')
  .doc(targetUid)
  .update({ isVIP: true });
```

或在 Firebase Console → Firestore → 找到該用戶文件 → 手動將 `isVIP` 改為 `true`。

---

## 安全層次總結

```
用戶請求
   │
   ├─ App Check ──→ 非真實 App？→ 直接拒絕（Google 層）
   │
   ├─ Firebase Auth ──→ 未登入？→ 只能讀 public 預測
   │
   ├─ Security Rules ──→ isVIP 檢查 → 只有 VIP 能讀高勝率預測
   │
   └─ SSL/TLS 加密 ──→ 所有通訊強制 HTTPS，防中間人攻擊
```
