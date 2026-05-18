import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// ════════════════════════════════════════════════════════════════
/// 宾果(Bingo) 高级预测引擎
///
/// 20个号码每期开出，分析：
/// 1. 号码热度 - 频率最高的号码
/// 2. 配对关系 - 常一起出现的号码
/// 3. 周期性 - 号码开出周期
/// 4. 覆盖率 - 号码组合的完整性
/// ════════════════════════════════════════════════════════════════

class BingoDraw {
  final int drawNo; // 期数
  final String drawDate; // YYYY-MM-DD
  final List<int> numbers; // 20个号码，1-80
  final String superNum; // 超级奖号

  BingoDraw({
    required this.drawNo,
    required this.drawDate,
    required this.numbers,
    this.superNum = '',
  });

  factory BingoDraw.fromJson(Map<String, dynamic> json) {
    return BingoDraw(
      drawNo: json['drawNo'] as int,
      drawDate: json['drawDate'] as String,
      numbers: List<int>.from(json['numbers'] as List),
      superNum: json['superNum'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'drawNo': drawNo,
    'drawDate': drawDate,
    'numbers': numbers,
    'superNum': superNum,
  };
}

class BingoNumberStat {
  final int number;
  final int frequency; // 出现次数
  final int lastDrawNo; // 最后一次开出的期数
  final int gapSinceLast; // 距上次开出已多少期
  final double heatScore; // 0.0-1.0
  final List<int> frequentPairs; // 经常搭配的号码
  final int avgGapBetweenDraws; // 平均间隔期数
  
  BingoNumberStat({
    required this.number,
    required this.frequency,
    required this.lastDrawNo,
    required this.gapSinceLast,
    required this.heatScore,
    required this.frequentPairs,
    required this.avgGapBetweenDraws,
  });

  String get label => number.toString().padLeft(2, '0');
  
  String get temperatureLabel {
    if (heatScore >= 0.8) return '🔥超热';
    if (heatScore >= 0.65) return '♨热号';
    if (heatScore >= 0.5) return '✓温号';
    if (heatScore >= 0.35) return '➖冷号';
    return '❄️超冷';
  }

  factory BingoNumberStat.fromJson(Map<String, dynamic> json) {
    return BingoNumberStat(
      number: json['number'] as int,
      frequency: json['frequency'] as int,
      lastDrawNo: json['lastDrawNo'] as int,
      gapSinceLast: json['gapSinceLast'] as int,
      heatScore: (json['heatScore'] as num).toDouble(),
      frequentPairs: List<int>.from(json['frequentPairs'] as List),
      avgGapBetweenDraws: json['avgGapBetweenDraws'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'frequency': frequency,
    'lastDrawNo': lastDrawNo,
    'gapSinceLast': gapSinceLast,
    'heatScore': heatScore,
    'frequentPairs': frequentPairs,
    'avgGapBetweenDraws': avgGapBetweenDraws,
  };
}

class BingoPrediction {
  final List<int> recommendedNumbers; // 推荐的号码 (通常 5-10 个)
  final String strategy;
  final String detailedAnalysis;
  final List<BingoNumberStat> allStats;
  final int confidenceScore; // 0-100
  final Map<String, dynamic> signals;
  final DateTime generatedAt;

  BingoPrediction({
    required this.recommendedNumbers,
    required this.strategy,
    required this.detailedAnalysis,
    required this.allStats,
    required this.confidenceScore,
    required this.signals,
    required this.generatedAt,
  });

  factory BingoPrediction.fromError(String message) {
    return BingoPrediction(
      recommendedNumbers: [],
      strategy: '分析失败',
      detailedAnalysis: message,
      allStats: [],
      confidenceScore: 0,
      signals: {},
      generatedAt: DateTime.now(),
    );
  }

  factory BingoPrediction.fromJson(Map<String, dynamic> json) {
    return BingoPrediction(
      recommendedNumbers: List<int>.from(json['recommendedNumbers'] as List),
      strategy: json['strategy'] as String,
      detailedAnalysis: json['detailedAnalysis'] as String,
      allStats: (json['allStats'] as List)
          .map((e) => BingoNumberStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      confidenceScore: json['confidenceScore'] as int,
      signals: json['signals'] as Map<String, dynamic>,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'recommendedNumbers': recommendedNumbers,
    'strategy': strategy,
    'detailedAnalysis': detailedAnalysis,
    'allStats': allStats.map((s) => s.toJson()).toList(),
    'confidenceScore': confidenceScore,
    'signals': signals,
    'generatedAt': generatedAt.toIso8601String(),
  };
}

class BingoAnalyzer {
  static const _cacheKey = 'bingo_prediction_v2';
  static const int BINGO_MAX_NUMBER = 80;
  static const int NUMBERS_PER_DRAW = 20;

  final List<BingoDraw> allDraws;
  final DateTime analysisDate;

  BingoAnalyzer({
    required this.allDraws,
    required this.analysisDate,
  });

  /// 主分析函数
  BingoPrediction analyze({
    int lookbackDraws = 100,
    int recommendCount = 8,
  }) {
    try {
      if (allDraws.isEmpty) {
        return BingoPrediction.fromError('没有可用的开奖数据');
      }

      // 1. 计算号码统计
      final stats = _calculateNumberStats(lookbackDraws);

      // 2. 识别热冷号
      final (hotNumbers, coldNumbers, warmNumbers) = _identifyTemperatures(stats);

      // 3. 分析配对关系
      final pairingMatrix = _analyzePairings(lookbackDraws);

      // 4. 计算周期性
      final cycles = _analyzeCycles();

      // 5. 生成推荐
      final recommended = _generateRecommendations(
        stats,
        hotNumbers,
        coldNumbers,
        warmNumbers,
        pairingMatrix,
        recommendCount,
      );

      // 6. 计算信心度
      final confidence = _calculateConfidence(stats, cycles, pairingMatrix);

      // 7. 生成文案
      final (strategy, analysis) = _generateAnalysisText(
        stats,
        hotNumbers,
        coldNumbers,
        warmNumbers,
        recommended,
        confidence,
      );

      final signals = {
        'hot_numbers': hotNumbers,
        'cold_numbers': coldNumbers,
        'warm_numbers': warmNumbers,
        'total_draws_analyzed': min(lookbackDraws, allDraws.length),
        'analysis_date': analysisDate.toIso8601String(),
      };

      return BingoPrediction(
        recommendedNumbers: recommended,
        strategy: strategy,
        detailedAnalysis: analysis,
        allStats: stats,
        confidenceScore: confidence,
        signals: signals,
        generatedAt: DateTime.now(),
      );
    } catch (e) {
      return BingoPrediction.fromError('分析异常: $e');
    }
  }

  /// 计算每个号码的详细统计
  List<BingoNumberStat> _calculateNumberStats(int lookbackDraws) {
    final stats = <int, BingoNumberStat>{};
    final recentDraws = allDraws.take(lookbackDraws).toList();

    if (recentDraws.isEmpty) return [];

    // 初始化所有号码
    for (int i = 1; i <= BINGO_MAX_NUMBER; i++) {
      stats[i] = BingoNumberStat(
        number: i,
        frequency: 0,
        lastDrawNo: 0,
        gapSinceLast: lookbackDraws + 1,
        heatScore: 0.0,
        frequentPairs: [],
        avgGapBetweenDraws: 0,
      );
    }

    // 统计频率和最后出现
    final appearances = <int, List<int>>{};
    for (int i = 1; i <= BINGO_MAX_NUMBER; i++) {
      appearances[i] = [];
    }

    for (int idx = 0; idx < recentDraws.length; idx++) {
      final draw = recentDraws[idx];
      for (final num in draw.numbers) {
        if (stats[num] != null) {
          final old = stats[num]!;
          stats[num] = BingoNumberStat(
            number: num,
            frequency: old.frequency + 1,
            lastDrawNo: draw.drawNo,
            gapSinceLast: old.gapSinceLast,
            heatScore: old.heatScore,
            frequentPairs: old.frequentPairs,
            avgGapBetweenDraws: old.avgGapBetweenDraws,
          );
          appearances[num]!.add(idx);
        }
      }
    }

    // 计算间隔和热度
    for (int i = 1; i <= BINGO_MAX_NUMBER; i++) {
      final stat = stats[i]!;
      final idxList = appearances[i]!;

      // 距离最后一次开出的期数
      int gap = lookbackDraws + 1;
      if (idxList.isNotEmpty) {
        gap = recentDraws.length - 1 - idxList.last;
      }

      // 平均间隔
      int avgGap = 0;
      if (idxList.length >= 2) {
        int totalGap = 0;
        for (int j = 1; j < idxList.length; j++) {
          totalGap += idxList[j] - idxList[j - 1];
        }
        avgGap = totalGap ~/ (idxList.length - 1);
      }

      // 热度计算：60% 频率 + 40% 最近性
      final freqScore = (stat.frequency / (recentDraws.length / NUMBERS_PER_DRAW * 1.5)).clamp(0.0, 1.0);
      final recencyScore = 1.0 - (gap.toDouble() / lookbackDraws).clamp(0.0, 1.0);
      final heatScore = freqScore * 0.6 + recencyScore * 0.4;

      stats[i] = BingoNumberStat(
        number: i,
        frequency: stat.frequency,
        lastDrawNo: stat.lastDrawNo,
        gapSinceLast: gap,
        heatScore: heatScore,
        frequentPairs: stat.frequentPairs,
        avgGapBetweenDraws: avgGap,
      );
    }

    return stats.values.toList()..sort((a, b) => b.heatScore.compareTo(a.heatScore));
  }

  /// 识别热号、温号、冷号
  (List<int>, List<int>, List<int>) _identifyTemperatures(List<BingoNumberStat> stats) {
    stats.sort((a, b) => b.heatScore.compareTo(a.heatScore));

    final hot = stats
        .where((s) => s.heatScore >= 0.65)
        .map((s) => s.number)
        .toList();

    final warm = stats
        .where((s) => s.heatScore >= 0.4 && s.heatScore < 0.65)
        .map((s) => s.number)
        .toList();

    final cold = stats
        .where((s) => s.heatScore < 0.35)
        .map((s) => s.number)
        .toList();

    return (hot, cold, warm);
  }

  /// 分析号码配对矩阵
  Map<String, int> _analyzePairings(int lookbackDraws) {
    final pairings = <String, int>{};
    final recentDraws = allDraws.take(lookbackDraws).toList();

    for (final draw in recentDraws) {
      for (int i = 0; i < draw.numbers.length - 1; i++) {
        for (int j = i + 1; j < draw.numbers.length; j++) {
          final a = draw.numbers[i];
          final b = draw.numbers[j];
          final key = '${min(a, b)}-${max(a, b)}';
          pairings[key] = (pairings[key] ?? 0) + 1;
        }
      }
    }

    return pairings;
  }

  /// 分析周期性
  Map<String, dynamic> _analyzeCycles() {
    final cycles = <String, dynamic>{};
    
    // 计算等差数列出现频率（如 1,11,21,31 等）
    for (int start = 1; start <= 10; start++) {
      for (int diff = 1; diff <= 10; diff++) {
        final arithmetic = <int>[];
        for (int i = 0; i < 8; i++) {
          final num = start + i * diff;
          if (num <= BINGO_MAX_NUMBER) {
            arithmetic.add(num);
          }
        }

        if (arithmetic.isEmpty) continue;

        // 统计这个等差数列在历史中出现的频率
        int count = 0;
        for (final draw in allDraws) {
          int matched = 0;
          for (final num in arithmetic) {
            if (draw.numbers.contains(num)) matched++;
          }
          if (matched >= 3) count++; // 至少 3 个匹配算一次
        }

        if (count > 0) {
          cycles['arithmetic_${start}_${diff}'] = {
            'sequence': arithmetic,
            'hit_count': count,
            'hit_rate': count / allDraws.length,
          };
        }
      }
    }

    return cycles;
  }

  /// 生成推荐号码
  List<int> _generateRecommendations(
    List<BingoNumberStat> stats,
    List<int> hotNumbers,
    List<int> coldNumbers,
    List<int> warmNumbers,
    Map<String, int> pairingMatrix,
    int count,
  ) {
    final recommended = <int>{};

    // 策略1: 热号 (50%)
    recommended.addAll(hotNumbers.take((count * 0.5).ceil()));

    // 策略2: 温号 (30%)
    recommended.addAll(warmNumbers.take((count * 0.3).ceil()));

    // 策略3: 冷号回暖 (20%)
    final coldWithPotential = coldNumbers.where((num) {
      final stat = stats.firstWhere((s) => s.number == num);
      return stat.gapSinceLast >= stat.avgGapBetweenDraws && stat.avgGapBetweenDraws > 0;
    }).toList();
    recommended.addAll(coldWithPotential.take((count * 0.2).ceil()));

    // 补充高配对号码
    if (recommended.length < count) {
      final topPairs = pairingMatrix.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

      for (final pair in topPairs) {
        if (recommended.length >= count) break;
        final nums = pair.key.split('-').map(int.parse).toList();
        for (final num in nums) {
          if (recommended.length < count && !recommended.contains(num)) {
            recommended.add(num);
          }
        }
      }
    }

    return recommended.toList().take(count).toList()..sort();
  }

  /// 计算信心度
  int _calculateConfidence(
    List<BingoNumberStat> stats,
    Map<String, dynamic> cycles,
    Map<String, int> pairingMatrix,
  ) {
    int score = 50;

    // 加分: 热号集中
    final hotCount = stats.where((s) => s.heatScore >= 0.7).length;
    score += min(20, hotCount ~/ 2);

    // 加分: 配对关系明显
    if (pairingMatrix.isNotEmpty) {
      final maxPairFreq = pairingMatrix.values.reduce((a, b) => max(a, b));
      score += min(15, maxPairFreq ~/ 3);
    }

    // 加分: 周期性规律
    score += min(10, cycles.length);

    // 减分: 样本不足
    if (allDraws.length < 30) {
      score -= 15;
    }

    return score.clamp(20, 95);
  }

  /// 生成分析文案
  (String, String) _generateAnalysisText(
    List<BingoNumberStat> stats,
    List<int> hotNumbers,
    List<int> coldNumbers,
    List<int> warmNumbers,
    List<int> recommended,
    int confidence,
  ) {
    final strategy = '''
🔥 热号策略: 优先选择频率高 + 最近出现的号码
❄️ 冷号策略: 关注长期未出现的号码回暖信号
🤝 配对策略: 选择常一起出现的号码组合
📈 周期策略: 识别等差数列规律
'''.trim();

    final sb = StringBuffer();
    sb.writeln('═══ 宾果(Bingo) 分析报告 ═══\n');

    sb.writeln('🔥 热号分析 (${hotNumbers.length}个)');
    for (final num in hotNumbers.take(8)) {
      final stat = stats.firstWhere((s) => s.number == num);
      sb.writeln('  • ${stat.label} 频率${stat.frequency}次 ${stat.temperatureLabel}');
    }
    sb.writeln();

    sb.writeln('❄️ 冷号分析 (${coldNumbers.length}个)');
    for (final num in coldNumbers.take(5)) {
      final stat = stats.firstWhere((s) => s.number == num);
      final daysOverdue = stat.gapSinceLast > (stat.avgGapBetweenDraws * 1.5) ? '⚠️超期' : '';
      sb.writeln('  • ${stat.label} 已${stat.gapSinceLast}期未出 $daysOverdue');
    }
    sb.writeln();

    sb.writeln('♨ 温号分析 (${warmNumbers.length}个)');
    for (final num in warmNumbers.take(5)) {
      final stat = stats.firstWhere((s) => s.number == num);
      sb.writeln('  • ${stat.label} 稳定出现');
    }
    sb.writeln();

    sb.writeln('🎯 推荐号码: ${recommended.map((n) => n.toString().padLeft(2, '0')).join(' ')}');
    sb.writeln('📊 信心度: ${confidence}%\n');

    return (strategy, sb.toString());
  }

  /// 保存到缓存
  Future<void> saveToCache(BingoPrediction prediction) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(prediction.toJson()));
    } catch (e) {
      print('宾果缓存保存失败: $e');
    }
  }

  /// 从缓存读取
  static Future<BingoPrediction?> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached == null) return null;
      return BingoPrediction.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
