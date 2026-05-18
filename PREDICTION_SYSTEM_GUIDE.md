# 🎰 综合体育彩票预测系统 - 完整指南

## 📦 已交付功能

### 1. 539彩票分析引擎 (`lottery_539_analyzer.dart`)
**核心功能：**
- 🔥 **热号分析** - 识别频率最高、最近出现的号码
- ❄️ **冷号分析** - 识别长期未出现、可能回暖的号码
- 🤝 **配对分析** - 发现经常一起出现的号码组合
- 📈 **周期性分析** - 检测号码出现的规律
- 🎯 **智能推荐** - 基于多种策略生成5个推荐号码

**已集成最新开奖数据 (2026年5月18-23日)：**
```
- 5/18: 05 10 38
- 5/19: 16 29 32
- 5/20: 09 17 21
- 5/21: 09 31 35
- 5/22: 05 10 32
- 5/23: 20 23 32
```

**使用示例：**
```dart
final analyzer = Lottery539Analyzer(
  allHistoricalRecords: records,
  analysisDate: DateTime.now(),
);
final prediction = analyzer.analyze(
  lookbackDays: 180,
  recommendCount: 5,
);
// prediction.recommendedNumbers → [推荐的5个号码]
// prediction.confidence → 0-100 信心度
```

---

### 2. 宾果(Bingo)预测引擎 (`bingo_analyzer.dart`)
**核心功能：**
- 20个号码每期开出的统计分析
- 🔥 **热号识别** - 温度评分系统 (超热/热号/温号/冷号/超冷)
- 🤝 **配对关系** - 常搭配的号码组合
- 📊 **等差数列规律** - 检测算术序列模式
- 🎯 **8个号码推荐** - 综合策略生成

**关键特性：**
- 80个号码的完整跟踪
- 间隔周期计算
- 冷号回暖预测信号

**使用示例：**
```dart
final bingoAnalyzer = BingoAnalyzer(
  allDraws: draws,
  analysisDate: DateTime.now(),
);
final prediction = bingoAnalyzer.analyze(
  lookbackDraws: 100,
  recommendCount: 8,
);
```

---

### 3. 足球勝分差分析引擎 (`football_spread_analyzer.dart`)
**核心逻辑：**
- 📊 **勝分差规律** - 分析不同联赛的平均分差
- ⚽ **多联赛支持** - MLS、英超、西甲、意甲、法甲
- 🏠 **主场优势** - +0.3-0.5球加成
- 💪 **实力系数** - 调整主客队强度

**已预设数据：**
- MLS 样本数据
- 欧洲联赛数据

**关键发现：**
```
• 大多数足球比赛勝分差在 1-2 球
• 主场优势贡献 0.3-0.5 球
• 强队vs弱队分差可达 3+ 球
```

**使用示例：**
```dart
final predictor = FootballSpreadPredictor();
final result = predictor.predictMatchSpread(
  homeTeam: 'LA Galaxy',
  awayTeam: 'Seattle Sounders',
  league: 'MLS',
  homeStrength: 1.1,
  awayStrength: 0.9,
);
// result['predicted_spread'] → 1.5 (预测分差)
// result['confidence'] → 0.67 (命中率)
```

---

## 🚀 统一预测服务 (`unified_prediction_service.dart`)

**单例服务，集成所有预测引擎：**

### 批量预测
```dart
final service = UnifiedPredictionService();
final allPredictions = await service.generateAllPredictions(
  lottery539Records: records,
  bingoDraws: draws,
  footballMatches: matches,
);
// 返回：{
//   'lottery_539': {...},
//   'bingo': {...},
//   'football': {...}
// }
```

### 流式更新
```dart
// 539预测流
service.lottery539Stream.listen((prediction) {
  print('新的539预测: ${prediction.recommendedNumbers}');
});

// 宾果预测流
service.bingoStream.listen((prediction) {
  print('新的宾果预测: ${prediction.recommendedNumbers}');
});
```

### 缓存管理
```dart
// 清除所有缓存
await service.clearAllCache();

// 查看缓存状态
final status = service.getCacheStatus();
```

---

## 📱 统一预测屏幕 (`unified_prediction_screen.dart`)

**已集成到主导航栏 (第5个标签)：**

### 屏幕功能
- 📊 三个Tab标签页
  1. **539彩票** - 推荐号码、热冷号分析
  2. **宾果(Bingo)** - 20号预测、温度标签
  3. **足球** - 勝分差规律报告

### 显示内容
```
🎯 推荐号码卡片
├── 信心度评分
├── 推荐号码展示
└── 渐变色号码球

💡 策略说明
├── 热号策略
├── 冷号策略
├── 配对策略
└── 数据驱动说明

📊 详细分析
└── 分析文案和统计数据

🔥 热号分析
├── 频率统计
└── 出现次数

❄️ 冷号分析
└── 距上次开出天数
```

---

## 🎯 推荐使用流程

### 1. 初始化
```dart
// main.dart 中
final predictionService = UnifiedPredictionService();

// 或在屏幕中
final service = UnifiedPredictionService();
```

### 2. 生成预测
```dart
// 获取历史数据
final lottery539Records = await LotteryService.loadCached539();
final bingoDraws = await BingoService.fetchDraws();

// 执行预测
final prediction539 = await service.predict539(
  historicalRecords: lottery539Records,
  lookbackDays: 180,
);

final predictionBingo = await service.predictBingo(
  historicalDraws: bingoDraws,
  lookbackDraws: 100,
);
```

### 3. 展示结果
```dart
// 在UI中
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      '539推荐: ${prediction539.recommendedNumbers.join(" ")}',
    ),
  ),
);
```

---

## 📊 数据模型

### Lottery539Prediction
```dart
{
  recommendedNumbers: [5, 10, 15, 20, 35],  // 推荐号码
  strategy: '🔥 热号策略...',              // 策略说明
  analysis: '═══ 539分析报告...',         // 详细分析
  numberStats: [...],                      // 所有号码统计
  confidence: 75,                          // 0-100 信心度
  signals: {                               // 信号数据
    'hot_numbers': [...],
    'cold_numbers': [...],
    'top_pairs': [...],
  }
}
```

### BingoPrediction
```dart
{
  recommendedNumbers: [8, 15, 22, 31, 45, 58, 72, 79],  // 8个号码
  strategy: '🔥 热号策略...',
  detailedAnalysis: '宾果分析报告...',
  allStats: [...],                         // BingoNumberStat 列表
  confidenceScore: 68,                     // 0-100
  signals: {...},
  generatedAt: DateTime.now(),
}
```

### SpreadPattern
```dart
{
  leagueName: 'MLS',
  matchCount: 42,
  observedSpreads: [1, 2, 1, 3, 2, ...],
  spreadFrequency: {1: 20, 2: 15, 3: 7},
  mostCommonSpread: 1.0,
  averageSpread: 1.5,
  accuracyRate: 0.67,
}
```

---

## ⚙️ 配置参数

### 539分析
```dart
analyze({
  int lookbackDays = 180,      // 分析过去多少天
  int recommendCount = 5,       // 推荐几个号码
})
```

### 宾果分析
```dart
analyze({
  int lookbackDraws = 100,      // 分析过去多少期
  int recommendCount = 8,       // 推荐几个号码
})
```

### 足球预测
```dart
predictMatchSpread({
  required String homeTeam,
  required String awayTeam,
  required String league,
  double homeStrength = 1.0,    // 主队实力系数
  double awayStrength = 1.0,    // 客队实力系数
})
```

---

## 🔄 缓存策略

- **有效期**：24小时
- **存储位置**：SharedPreferences
- **自动保存**：每次预测后自动缓存
- **手动清除**：`clearAllCache()`

---

## 📝 关键类文件

| 文件 | 用途 |
|-----|------|
| `lottery_539_analyzer.dart` | 539彩票分析引擎 |
| `bingo_analyzer.dart` | 宾果预测引擎 |
| `football_spread_analyzer.dart` | 足球勝分差引擎 |
| `unified_prediction_service.dart` | 统一预测服务 |
| `unified_prediction_screen.dart` | 预测展示UI |

---

## 🎮 下一步优化建议

1. **连接真实API**
   - 集成539/宾果的实时开奖API
   - 足球数据从Odds API实时获取

2. **机器学习增强**
   - 训练RNN模型预测号码序列
   - 使用XGBoost优化勝分差预测

3. **实时通知**
   - 号码异常信号推送
   - 赔率变化提醒

4. **性能优化**
   - 增量数据更新而非全量重算
   - 预测结果版本管理

---

## ✅ 质量保证

- ✓ 所有编译错误已解决
- ✓ 类型安全检查通过
- ✓ 缓存机制已实现
- ✓ 流式更新已支持
- ✓ 主导航集成完成

---

**祝您使用愉快！如有问题，请查看各模块的详细注释。**
