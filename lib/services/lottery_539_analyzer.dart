import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lottery_model.dart';

/// ════════════════════════════════════════════════════════════════
/// 539 彩票高级分析引擎
/// 
/// 逻辑：
/// 1. 热号分析 - 出现频率最高的号码
/// 2. 冷号分析 - 长期未出现的号码
/// 3. 配对关系 - 经常一起出现的号码对
/// 4. 周期性 - 号码间隔周期
/// 5. 差值模式 - 相邻号码间的差值规律
/// ════════════════════════════════════════════════════════════════

class Number539Stats {
  final int number;
  final int frequency; // 出现次数
  final int lastDrawDaysAgo; // 距最近一次开出已多少天
  final double heatScore; // 0.0-1.0 热度评分
  final int avgGap; // 平均间隔天数
  final List<int> pairedWith; // 经常搭配的号码
  
  Number539Stats({
    required this.number,
    required this.frequency,
    required this.lastDrawDaysAgo,
    required this.heatScore,
    required this.avgGap,
    required this.pairedWith,
  });

  factory Number539Stats.fromJson(Map<String, dynamic> json) {
    return Number539Stats(
      number: json['number'] as int,
      frequency: json['frequency'] as int,
      lastDrawDaysAgo: json['lastDrawDaysAgo'] as int,
      heatScore: (json['heatScore'] as num).toDouble(),
      avgGap: json['avgGap'] as int,
      pairedWith: List<int>.from(json['pairedWith'] as List),
    );
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'frequency': frequency,
    'lastDrawDaysAgo': lastDrawDaysAgo,
    'heatScore': heatScore,
    'avgGap': avgGap,
    'pairedWith': pairedWith,
  };

  String get label => number.toString().padLeft(2, '0');
  String get heatLabel {
    if (heatScore >= 0.8) return '🔥热号';
    if (heatScore >= 0.6) return '♨温号';
    if (heatScore >= 0.4) return '✓常见';
    return '❄️冷号';
  }
}

class Lottery539Prediction {
  final List<int> recommendedNumbers; // 5个推荐号码
  final String strategy; // 策略说明
  final String analysis; // 详细分析
  final List<Number539Stats> numberStats; // 所有号码的统计
  final double confidence; // 预测信心度 0-100
  final Map<String, dynamic> signals; // 各种信号数据
  
  Lottery539Prediction({
    required this.recommendedNumbers,
    required this.strategy,
    required this.analysis,
    required this.numberStats,
    required this.confidence,
    required this.signals,
  });

  factory Lottery539Prediction.fromError(String msg) {
    return Lottery539Prediction(
      recommendedNumbers: [],
      strategy: '分析失败',
      analysis: msg,
      numberStats: [],
      confidence: 0,
      signals: {},
    );
  }
}

class Lottery539Analyzer {
  static const _cacheKey = 'lottery_539_analysis_v3';
  
  // 不再使用硬編碼數據：歷史記錄由 allHistoricalRecords 直接傳入
  static const _recentDraws = <Map<String, dynamic>>[];

  final List<DrawRecord> allHistoricalRecords;
  final DateTime analysisDate;

  Lottery539Analyzer({
    required this.allHistoricalRecords,
    required this.analysisDate,
  });

  /// 添加最新数据
  void addRecentDraws() {
    for (final draw in _recentDraws) {
      final existingIndex = allHistoricalRecords.indexWhere(
        (r) => r.date == draw['date'],
      );
      if (existingIndex == -1) {
        allHistoricalRecords.add(DrawRecord(
          date: draw['date'] as String,
          numbers: List<int>.from(draw['numbers'] as List),
        ));
      }
    }
  }

  /// 主分析函数
  Lottery539Prediction analyze({
    int lookbackDays = 180,
    int recommendCount = 5,
  }) {
    try {
      addRecentDraws();

      // 1. 收集号码频率
      final stats = _calculateNumberStats(lookbackDays);
      
      // 2. 识别特征号码
      final (hotNumbers, coldNumbers) = _identifyHotCold(stats);
      
      // 3. 分析配对关系
      final pairings = _analyzePairings(lookbackDays);
      
      // 4. 计算周期性
      final cycles = _analyzeCycles();
      
      // 5. 生成推荐
      final recommended = _generateRecommendation(
        stats,
        hotNumbers,
        coldNumbers,
        pairings,
        recommendCount,
      );

      // 6. 计算信心度
      final confidence = _calculateConfidence(stats, cycles, pairings);

      // 7. 生成分析文案
      final (strategy, analysis) = _generateAnalysisText(
        hotNumbers,
        coldNumbers,
        pairings,
        cycles,
        recommended,
        stats,
      );

      final topPairsForSignals = pairings.entries.toList();
      topPairsForSignals.sort((a, b) => b.value.compareTo(a.value));

      final signals = {
        'hot_numbers': hotNumbers,
        'cold_numbers': coldNumbers,
        'top_pairs': topPairsForSignals
            .take(5)
            .map((e) => {'pair': e.key, 'frequency': e.value})
            .toList(),
        'cycles': cycles,
      };

      return Lottery539Prediction(
        recommendedNumbers: recommended,
        strategy: strategy,
        analysis: analysis,
        numberStats: stats,
        confidence: confidence,
        signals: signals,
      );
    } catch (e) {
      return Lottery539Prediction.fromError('分析失败: $e');
    }
  }

  /// 计算每个号码的统计数据
  List<Number539Stats> _calculateNumberStats(int lookbackDays) {
    final stats = <int, Number539Stats>{};
    final now = analysisDate;
    final cutoffDate = now.subtract(Duration(days: lookbackDays));

    // 初始化所有号码
    for (int i = 1; i <= 39; i++) {
      stats[i] = Number539Stats(
        number: i,
        frequency: 0,
        lastDrawDaysAgo: lookbackDays + 1,
        heatScore: 0.0,
        avgGap: 0,
        pairedWith: [],
      );
    }

    // 收集期间内的所有开奖
    final drawsInRange = allHistoricalRecords.where((draw) {
      try {
        final drawDate = DateTime.parse(draw.date);
        return drawDate.isAfter(cutoffDate) && drawDate.isBefore(now);
      } catch (_) {
        return false;
      }
    }).toList();

    if (drawsInRange.isEmpty) return stats.values.toList();

    // 计算频率
    final intervals = <int, List<int>>{};
    for (int i = 1; i <= 39; i++) {
      intervals[i] = [];
    }

    for (final draw in drawsInRange) {
      for (final num in draw.numbers) {
        if (stats[num] != null) {
          final oldStat = stats[num]!;
          stats[num] = Number539Stats(
            number: num,
            frequency: oldStat.frequency + 1,
            lastDrawDaysAgo: oldStat.lastDrawDaysAgo,
            heatScore: oldStat.heatScore,
            avgGap: oldStat.avgGap,
            pairedWith: oldStat.pairedWith,
          );
          intervals[num]!.add(drawsInRange.length);
        }
      }
    }

    // 计算最后出现的距离和平均间隔
    for (int i = 1; i <= 39; i++) {
      int lastDrawAgo = lookbackDays + 1;

      for (int j = 0; j < drawsInRange.length; j++) {
        if (drawsInRange[j].numbers.contains(i)) {
          lastDrawAgo = drawsInRange.length - 1 - j;
          break;
        }
      }

      final gapList = intervals[i]!;
      int avgGap = gapList.isEmpty ? 0 : (gapList.reduce((a, b) => a + b) ~/ gapList.length);

      // 计算热度分数
      final freq = stats[i]!.frequency.toDouble();
      final maxFreq = drawsInRange.length / 5; // 539每期5個號碼，理論最高頻率
      final freqScore = (freq / maxFreq).clamp(0.0, 1.0);
      final recencyScore = 1.0 - (lastDrawAgo / lookbackDays).clamp(0.0, 1.0);
      final heatScore = freqScore * 0.6 + recencyScore * 0.4;

      stats[i] = Number539Stats(
        number: i,
        frequency: stats[i]!.frequency,
        lastDrawDaysAgo: lastDrawAgo,
        heatScore: heatScore,
        avgGap: avgGap,
        pairedWith: [],
      );
    }

    return stats.values.toList()..sort((a, b) => b.frequency.compareTo(a.frequency));
  }

  /// 识别热号和冷号
  (List<int>, List<int>) _identifyHotCold(List<Number539Stats> stats) {
    stats.sort((a, b) => b.heatScore.compareTo(a.heatScore));
    
    final hot = stats
        .where((s) => s.heatScore >= 0.6)
        .map((s) => s.number)
        .toList()
        .take(10)
        .toList();
    
    final cold = stats
        .where((s) => s.heatScore < 0.3)
        .map((s) => s.number)
        .toList()
        .take(10)
        .toList();

    return (hot, cold);
  }

  /// 分析号码配对关系
  Map<String, int> _analyzePairings(int lookbackDays) {
    final pairings = <String, int>{};
    final cutoffDate = analysisDate.subtract(Duration(days: lookbackDays));

    final drawsInRange = allHistoricalRecords.where((draw) {
      try {
        final drawDate = DateTime.parse(draw.date);
        return drawDate.isAfter(cutoffDate) && drawDate.isBefore(analysisDate);
      } catch (_) {
        return false;
      }
    }).toList();

    for (final draw in drawsInRange) {
      final nums = draw.numbers.toList()..sort();
      for (int i = 0; i < nums.length - 1; i++) {
        for (int j = i + 1; j < nums.length; j++) {
          final key = '${nums[i]}-${nums[j]}';
          pairings[key] = (pairings[key] ?? 0) + 1;
        }
      }
    }

    return pairings;
  }

  /// 分析周期性规律
  Map<String, dynamic> _analyzeCycles() {
    if (allHistoricalRecords.isEmpty) return {};

    final cycles = <String, int>{};
    
    // 分析号码出现的间隔周期
    for (int num = 1; num <= 39; num++) {
      final appearances = allHistoricalRecords
          .asMap()
          .entries
          .where((e) => e.value.numbers.contains(num))
          .map((e) => e.key)
          .toList();

      if (appearances.length >= 2) {
        final gaps = <int>[];
        for (int i = 1; i < appearances.length; i++) {
          gaps.add(appearances[i] - appearances[i - 1]);
        }
        
        if (gaps.isNotEmpty) {
          final avgGap = gaps.reduce((a, b) => a + b) ~/ gaps.length;
          cycles['num_$num'] = avgGap;
        }
      }
    }

    return cycles;
  }

  /// 生成推荐号码
  List<int> _generateRecommendation(
    List<Number539Stats> stats,
    List<int> hotNumbers,
    List<int> coldNumbers,
    Map<String, int> pairings,
    int count,
  ) {
    // 綜合評分：熱度 × 60% + 間隔到期 × 40%（避免純熱號導致號碼扎堆）
    final scored = stats.map((s) {
      final overdueBonus = s.avgGap > 0 && s.lastDrawDaysAgo > s.avgGap
          ? (s.lastDrawDaysAgo - s.avgGap).clamp(0, 15) * 0.04
          : 0.0;
      return MapEntry(s.number, s.heatScore * 0.60 + overdueBonus);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 區間多樣性：確保 5 顆號碼來自至少 3 個十位區間（1-10, 11-20, 21-30, 31-39）
    final recommended = <int>{};
    final zoneUsed = <int, int>{}; // zone → count
    int zone(int n) => (n - 1) ~/ 10;

    // 先按分數加入，但每個區間最多先取 2 顆
    for (final e in scored) {
      if (recommended.length >= count) break;
      final z = zone(e.key);
      if ((zoneUsed[z] ?? 0) < 2) {
        recommended.add(e.key);
        zoneUsed[z] = (zoneUsed[z] ?? 0) + 1;
      }
    }

    // 若仍不足，再依分數補滿（放鬆區間限制）
    for (final e in scored) {
      if (recommended.length >= count) break;
      recommended.add(e.key);
    }

    // 加入最強配對中未入選的號碼（若仍有空位）
    if (recommended.length < count) {
      final topPairs = pairings.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final pair in topPairs) {
        if (recommended.length >= count) break;
        final nums = pair.key.split('-').map(int.parse).toList();
        for (final n in nums) {
          if (!recommended.contains(n)) {
            recommended.add(n);
            break;
          }
        }
      }
    }

    return recommended.toList().take(count).toList()..sort();
  }

  /// 计算预测信心度
  double _calculateConfidence(
    List<Number539Stats> stats,
    Map<String, dynamic> cycles,
    Map<String, int> pairings,
  ) {
    double score = 50.0; // 基础分

    // 加分: 热号集中度
    final hotCount = stats.where((s) => s.heatScore >= 0.7).length;
    score += min(20.0, hotCount * 2.0);

    // 加分: 配对关系明显
    final topPairFreq = pairings.isEmpty
        ? 0
        : pairings.values.reduce((a, b) => max(a, b));
    score += min(15.0, topPairFreq * 1.5);

    // 减分: 样本较少
    if (stats.length < 20) {
      score -= 10.0;
    }

    return score.clamp(20.0, 95.0);
  }

  /// 生成分析文案
  (String, String) _generateAnalysisText(
    List<int> hotNumbers,
    List<int> coldNumbers,
    Map<String, int> pairings,
    Map<String, dynamic> cycles,
    List<int> recommended,
    List<Number539Stats> stats,
  ) {
    final strategy = '''
🔥 热号策略: 优先选择频率高 + 最近出现的号码
❄️ 冷号策略: 关注长期未出现的号码，可能回暖
🤝 配对策略: 选择常一起出现的号码组合
📊 数据驱动: 基于最近180天开奖记录分析
'''.trim();

    final sb = StringBuffer();
    sb.writeln('═══ 539 彩票分析报告 ═══\n');
    
    sb.writeln('📈 热号分析 (${hotNumbers.length}个)');
    for (final num in hotNumbers.take(5)) {
      final stat = stats.firstWhere((s) => s.number == num);
      sb.writeln('  • ${stat.label} 出现${stat.frequency}次 ${stat.heatLabel}');
    }
    sb.writeln();

    sb.writeln('❄️ 冷号分析 (${coldNumbers.length}个)');
    for (final num in coldNumbers.take(5)) {
      final stat = stats.firstWhere((s) => s.number == num);
      sb.writeln('  • ${stat.label} 已${stat.lastDrawDaysAgo}天未出');
    }
    sb.writeln();

    sb.writeln('🎯 推荐号码: ${recommended.map((n) => n.toString().padLeft(2, '0')).join(' ')}');
    
    return (strategy, sb.toString());
  }

  /// 保存分析结果到缓存
  Future<void> saveToCache(Lottery539Prediction prediction) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'timestamp': DateTime.now().toIso8601String(),
        'recommended': prediction.recommendedNumbers,
        'strategy': prediction.strategy,
        'analysis': prediction.analysis,
        'confidence': prediction.confidence,
        'signals': prediction.signals,
      };
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (e) {
      print('缓存保存失败: $e');
    }
  }

  /// 从缓存读取
  static Future<Lottery539Prediction?> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached == null) return null;
      
      final data = jsonDecode(cached) as Map<String, dynamic>;
      return Lottery539Prediction(
        recommendedNumbers: List<int>.from(data['recommended'] as List),
        strategy: data['strategy'] as String,
        analysis: data['analysis'] as String,
        numberStats: [],
        confidence: (data['confidence'] as num).toDouble(),
        signals: data['signals'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
