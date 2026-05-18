# 體育預測應用擴展功能文檔

## 🎯 新增聯賽支持

### 新增的體育聯賽

#### 1. 日本職棒 (NPB - Nippon Professional Baseball)
- **聯賽代碼**: NPB
- **球隊數量**: 12隊（太平洋聯盟 6隊 + 中央聯盟 6隊）
- **成立年份**: 1950年
- **官方網站**: https://npb.jp/

**主要球隊**:
- 福岡軟銀鷹隊
- 埼玉西武獅隊
- 北海道日本火腿鬥士隊
- 大阪歐力士野牛隊
- 東北樂天金鷹隊
- 東京讀賣巨人隊
- 中日龍隊
- 大阪阪神虎隊
- 東京養樂多燕子隊
- 橫濱DeNA灣星隊
- 廣島鯉隊

#### 2. 中華職棒 (CPBL - Chinese Professional Baseball League)
- **聯賽代碼**: CPBL
- **球隊數量**: 6隊
- **成立年份**: 1990年
- **官方網站**: https://www.cpbl.com.tw/

**主要球隊**:
- 中信兄弟
- 樂天猴子
- 台泥紅隊
- CTBC蜜蜂隊
- 台中鯨隊
- 高雄鷹隊

#### 3. 歐洲協會聯賽 (UEFA Europa Conference League)
- **聯賽代碼**: UECL
- **球隊數量**: 32隊（小組賽階段）
- **成立年份**: 2021年
- **官方網站**: https://www.uefa.com/uefaconferenceleague/

**特色**:
- 歐足聯第三級別杯賽
- 首屆於2021-22賽季舉辦
- 為小型歐洲足球俱樂部提供國際賽事機會

---

## 🧮 高級預測功能

### 1. 凱利公式投注管理 (`kelly_criterion_service.dart`)

#### 核心功能
- **凱利公式計算**: 根據預測概率和賠率計算最優投注比例
- **投注建議生成**: 為每場比賽生成具體的投注方案
- **銀行資金優化**: 多場比賽的聯合投注組合優化
- **期望值計算**: 計算每次投注的期望盈利

#### 關鍵類別

**KellyCriterionService** - 核心計算引擎
```dart
// 計算凱利投注比例
final kellyBet = KellyCriterionService.calculateKellyBet(
  predictedProb: 0.60,      // 60% 勝率預測
  decimalOdds: 1.90,        // 十進位賠率
  kellyMultiplier: 0.25,    // 1/4 凱利（保守）
);

// 計算期望值
final ev = KellyCriterionService.calculateExpectedValue(
  predictedProb: 0.60,
  decimalOdds: 1.90,
  betAmount: 100,
);

// 生成投注建議
final suggestion = KellyCriterionService.generateBetSuggestion(
  matchId: 'match123',
  league: '英超',
  homeTeam: '曼城',
  awayTeam: '利物浦',
  bankroll: 10000,
  prediction: matchPrediction,
  kellyMultiplier: 0.25,
);

// 優化多場投注
final allocation = KellyCriterionService.optimizeBankroll(
  bankroll: 10000,
  suggestions: betSuggestions,
  kellyMultiplier: 0.25,
);
```

#### 凱利公式原理

```
凱利公式: f* = (b*p - q) / b

其中:
  f* = 建議投注佔銀行資金的比例 (0.0 ~ 1.0)
  b  = 賠率倍數 (如2.0倍賠率 = 1.0)
  p  = 我們對結果的預測概率
  q  = 1 - p (反面發生概率)

理想情況下:
  - EV > 0: 正期望值，適合投注
  - EV < 0: 負期望值，不適合投注
  - ROI = EV / 投注額
```

#### 投注安全機制
- **1/4 凱利** (quarter kelly): 降低破產風險，適合實戰
- **1/2 凱利** (half kelly): 中等風險
- **全凱利** (full kelly): 理論最優但風險高
- **銀行資金保護**: 最少保留50%未投注資金

### 2. 新聯賽專用蒙地卡羅模擬 (`new_leagues_service.dart`)

#### 日職特定因子
```dart
const Map<String, double> npbFactors = {
  'pitcherQualityWeight': 0.35,    // 投手品質權重（日職投手差異大）
  'weatherInfluence': 0.15,        // 天氣影響（日本四季差異明顯）
  'teamConsistency': 0.25,         // 球隊穩定性
  'homeFieldAdvantage': 0.15,      // 主場優勢
  'injuryImpact': 0.10,            // 傷兵影響
};
```

**特色**:
- 投手ERA修正（日職投手強度差異大）
- 考慮天氣影響（四季變化明顯）
- 高精度預測

#### 中華職棒特定因子
```dart
const Map<String, double> cpblFactors = {
  'foreignPlayerImpact': 0.20,     // 外援影響（外援在台灣職棒影響大）
  'pitcherQualityWeight': 0.30,    // 投手品質權重
  'teamConsistency': 0.20,         // 球隊穩定性
  'homeFieldAdvantage': 0.15,      // 主場優勢
  'weather': 0.10,                 // 天氣影響
  'injuryImpact': 0.05,            // 傷兵影響
};
```

**特色**:
- 外援加成評估
- 考慮較高的隨機性（聯賽波動大）
- 適應小規模聯賽特點

#### 歐協聯特定因子
```dart
const Map<String, double> ueclFootballFactors = {
  'competitionNewness': 0.10,       // 聯賽新穎性
  'defensiveStructure': 0.25,       // 防守結構
  'teamFormStability': 0.20,        // 球隊狀態穩定性
  'homeFieldAdvantage': 0.15,       // 主場優勢
  'European_experience': 0.15,      // 歐戰經驗
  'injuryAndSuspension': 0.10,      // 傷兵和禁賽
  'randomness': 0.05,               // 隨機性（第三級別聯賽波動較大）
};
```

**特色**:
- 歐戰經驗加成
- 考慮較高的隨機性（新聯賽，第三級別）
- 歐洲杯賽結構適應

#### 使用示例
```dart
// 日職蒙地卡羅模擬
final npbScores = MonteCarloSimulatorForNewLeagues.simulateNPBMatch(
  homeTeamStrength: 4.2,
  awayTeamStrength: 3.8,
  homeStarterERA: 3.15,
  awayStarterERA: 3.45,
  simulations: 500,
  seed: 12345,
);

// 中華職棒蒙地卡羅模擬
final cpblScores = MonteCarloSimulatorForNewLeagues.simulateCPBLMatch(
  homeTeamStrength: 4.0,
  awayTeamStrength: 3.9,
  homeForeignPlayerBonus: 0.12,  // 主隊外援加成12%
  awayForeignPlayerBonus: 0.08,
  simulations: 500,
  seed: 12345,
);

// 歐協聯蒙地卡羅模擬
final ueclScores = MonteCarloSimulatorForNewLeagues.simulateUECLMatch(
  homeTeamStrength: 1.6,
  awayTeamStrength: 1.4,
  homeEuropeanExperience: 0.85,  // 主隊歐戰經驗85%
  awayEuropeanExperience: 0.60,
  simulations: 500,
  seed: 12345,
);
```

---

## 📊 新增數據模型

### 1. 投注建議模型
- `KellyBetSuggestion`: 單場投注建議
- `BankrollAllocationResult`: 多場投注優化結果
- `BankrollAllocation`: 單場投注分配方案

### 2. 聯賽信息模型
- `BaseballLeagueInfo`: 棒球聯賽信息
- `FootballLeagueInfo`: 足球聯賽信息
- `OddsCalculator`: 賠率計算工具

---

## 🔧 集成方式

### 1. 在主預測服務中集成
```dart
import 'services/kelly_criterion_service.dart';
import 'services/new_leagues_service.dart';

// 生成預測和投注建議
final prediction = PredictionEngine.predictScore(fixture);
final kellyBet = KellyCriterionService.generateBetSuggestion(
  matchId: fixture.id,
  league: fixture.league,
  homeTeam: fixture.homeTeam,
  awayTeam: fixture.awayTeam,
  bankroll: userBankroll,
  prediction: prediction,
  kellyMultiplier: selectedKellyMultiplier,
);
```

### 2. 在UI中顯示投注建議
- 顯示推薦投注金額
- 顯示期望值和ROI
- 顯示風險等級
- 顯示所有投注選項

### 3. 在數據獲取中支持新聯賽
```dart
// 自動支持新聯賽
final matches = await RealDataService.fetchMatchesForDays(days: 5);
// 將包括日職、中華職棒、歐協聯的比賽
```

---

## 💡 最佳實踐

### 投注策略建議

1. **保守策略**: 使用 1/4 凱利公式
   - 破產風險: 低
   - 長期收益: 穩定

2. **平衡策略**: 使用 1/2 凱利公式
   - 破產風險: 中等
   - 長期收益: 中等至高

3. **激進策略**: 使用全凱利公式
   - 破產風險: 高
   - 長期收益: 高

### 多聯賽投注組合

- 不超過銀行資金的 50% 用於投注
- 至少保留 50% 用於應急
- 定期評估預測準確率
- 根據回測結果調整 MC 因子

### 新聯賽注意事項

**日職** 🇯🇵
- 投手差異大，ERA數據很重要
- 考慮天氣和季節因素
- 主客場差異明顯

**中華職棒** 🇹🇼
- 外援是重要變數
- 聯賽波動性較高
- 球隊實力差異大

**歐協聯** 🇪🇺
- 新聯賽，數據相對較少
- 歐戰經驗是重要因素
- 隨機性較高，謹慎投注

---

## 📈 性能優化

- **蒙地卡羅模擬**: 500次迭代（可配置）
- **並行API請求**: 自動批量獲取多聯賽數據
- **緩存機制**: 5分鐘內數據緩存
- **重試機制**: 失敗自動重試（最多2次）

---

## 🚀 未來擴展

- [ ] 添加實時賠率推送
- [ ] 集成更多國際棒球聯賽
- [ ] 添加高級統計分析工具
- [ ] 支持自定義投注策略
- [ ] AI驅動的賠率預測

