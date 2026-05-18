# 體育賽事預測應用 - 集成真實數據指南

## 📋 概述

本應用已整合多個國際數據源，支持以下功能：

- ⚽ **足球**: 歐洲主流聯賽 + 日職等
- 🏀 **籃球**: NBA 等
- ⚾ **棒球**: MLB、中華職棒等
- 💰 **國際賭盤賠率**: 實時賠率數據

## 🔧 配置步驟

### 1. 設置 TheOddsAPI (推薦用於賭盤數據)

#### 獲取 API Key
1. 訪問 https://www.theoddsapi.com/
2. 點擊「Sign Up」免費註冊
3. 確認郵箱
4. 在控制面板複製你的 API Key

#### 更新應用配置
編輯 `lib/config/app_config.dart`:
```dart
static const String oddsApiKey = 'YOUR_ACTUAL_API_KEY'; // 替換為你的 key
```

#### API 功能及限制
- **免費方案**: 500 次/月
- **付費方案**: 聯繫他們獲取企業級額度
- **支持聯賽**:
  ```
  足球: soccer_epl, soccer_fifa_world_cup, soccer_europe_champions
  籃球: basketball_nba
  棒球: baseball_mlb
  美式足球: americanfootball_nfl
  ```

#### 示例 API 調用
```
GET https://api.the-odds-api.com/v4/sports/soccer_epl/events?apiKey=YOUR_KEY
GET https://api.the-odds-api.com/v4/sports/basketball_nba/events?apiKey=YOUR_KEY
```

### 2. ESPN API (免費，無需認證)

已在應用中自動使用，無需額外配置。

**支持的端點**:
- NBA 賽事: `https://site.api.espn.com/v2/site/en/sports/basketball/nba/events`
- MLB 賽事: `https://site.api.espn.com/v2/site/en/sports/baseball/mlb/events`
- 足球賽事: `https://site.api.espn.com/v2/site/en/sports/soccer/events`

### 3. 可選: RapidAPI 集成 (高級功能)

對於更多功能，可整合 RapidAPI 中的各種體育 API:

1. 訪問 https://rapidapi.com/
2. 搜索「football」或「sports」
3. 選擇所需 API 並訂閱
4. 複製 API Key 到 `app_config.dart`:

```dart
static const String rapidApiKey = 'YOUR_RAPIDAPI_KEY';
static const String rapidApiHost = 'api-football-v1.p.rapidapi.com';
```

## 📱 使用應用

### 切換數據源

編輯 `lib/config/app_config.dart`:
```dart
// 使用真實數據 (需要有效 API keys)
static const bool useRealDataByDefault = true;

// 使用模擬數據進行測試
static const bool useRealDataByDefault = false;
```

### 更新應用以使用新服務

在 `lib/screens/home_screen.dart` 中，替換數據服務初始化:

```dart
// 原來:
final fixtures = MockDataService().getTodaysFixtures();

// 改為:
final dataManager = DataServiceManager(useRealData: true);
final fixtures = await dataManager.getTodaysFixtures();
```

### 使用增強型預測引擎

在預測調用處替換為：

```dart
// 原來:
final prediction = PredictionEngine().predictScore(fixture);

// 改為:
final prediction = EnhancedPredictionEngine().predictMatch(fixture);
```

## 🎯 支持的聯賽清單

### 足球 (Football)
- 英超 (EPL)
- 西甲 (La Liga)
- 意甲 (Serie A)
- 德甲 (Bundesliga)
- 法甲 (Ligue 1)
- 日職 (J1 League)
- 世界盃 (FIFA World Cup)
- 冠軍聯賽 (Champions League)

### 籃球 (Basketball)
- NBA (美職籃)
- EuroLeague (歐洲聯賽)

### 棒球 (Baseball)
- MLB (美職棒)
- CPBL (中華職棒)
- NPB (日職棒)

## 📊 預測模型特性

### 新增功能
1. **市場隱含概率**: 直接從賠率計算
2. **多因子分析**:
   - 球隊進攻/防守評級
   - 近期動能 (Momentum Score)
   - 傷停影響
   - 市場趨勢

3. **運動特異性**:
   - 足球: 考慮平局、控球率
   - 籃球: 處理總分範圍
   - 棒球: 打線分析

4. **信心度量化**: 50-92% 的可信度評分

## 🐛 常見問題

### API Key 不工作？
1. 確認 key 已複製完整 (無空格)
2. 確認 API 限額未超過
3. 檢查網路連接

### 為什麼還在顯示模擬數據？
1. 檢查 `useRealDataByDefault` 是否為 `true`
2. 確認 API keys 已正確配置
3. 查看應用日誌中的錯誤信息

### 如何添加新的運動？

編輯 `lib/services/real_data_service.dart`:
```dart
Future<List<MatchFixture>> getNewSportMatches() async {
  try {
    final url = Uri.parse('your_api_endpoint');
    final response = await http.get(url).timeout(...);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return _parseNewSportResponse(data);
    }
    return [];
  } catch (e) {
    print('Error: $e');
    return [];
  }
}
```

## 🚀 部署建議

### 環境變數 (推薦)
為了安全起見，不要在代碼中硬編碼 API keys。使用環境變數：

```dart
// 使用 flutter_dotenv 包
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apiKey = dotenv.env['ODDS_API_KEY']!;
```

### 生產部署檢查清單
- [ ] API keys 已配置
- [ ] 數據快取機制已啟用 (30 分鐘)
- [ ] 錯誤處理已完善
- [ ] 已在真實環境測試
- [ ] 監控 API 調用配額

## 📈 未來增強

計畫中的功能：
- [ ] 歷史賠率數據集成
- [ ] 機器學習預測模型
- [ ] 用戶投注紀錄追蹤
- [ ] 推播通知系統
- [ ] 多語言支持

## 📞 技術支持

遇到問題？檢查以下資源：

1. **TheOddsAPI 文檔**: https://the-odds-api.com/
2. **ESPN API 文檔**: https://www.espn.com/apis/site/v2
3. **Flutter 文檔**: https://flutter.dev/docs
4. **應用日誌**: 查看 VS Code 調試終端輸出

---

最後更新: 2026 年 4 月

享受預測！ ⚽🎯
