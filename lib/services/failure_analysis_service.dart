import '../models/prediction_log.dart';
import 'prediction_log_service.dart';

// ── 資料模型 ──────────────────────────────────────────────────────

/// 單一策略標籤的統計
class TagStat {
  final String tag;
  final int hits;
  final int misses;

  const TagStat({required this.tag, required this.hits, required this.misses});
  int get total => hits + misses;
  double get hitRate => total > 0 ? hits / total : 0;
}

/// 失敗分析彙整結果
class FailureAnalysisResult {
  const FailureAnalysisResult({
    required this.lotteryTagStats,
    required this.bingoGroupStats,
    required this.sportsStats,
    required this.lotteryInsights,
    required this.bingoInsights,
    required this.sportsInsights,
    required this.totalAnalyzed,
    required this.strategyMultipliers,
  });

  /// 樂透策略標籤命中率 tag→TagStat（已有 ≥3 樣本的標籤才收錄）
  final Map<String, TagStat> lotteryTagStats;

  /// 賓果組別命中率 groupLabel→hitRate
  final Map<String, double> bingoGroupStats;

  /// 體育各類命中率 sport→winRate
  final Map<String, double> sportsStats;

  /// 樂透失敗分析文字摘要
  final List<String> lotteryInsights;

  /// 賓果失敗分析文字摘要
  final List<String> bingoInsights;

  /// 體育失敗分析文字摘要
  final List<String> sportsInsights;

  /// 已分析期數 {lottery/bingo/sports → count}
  final Map<String, int> totalAnalyzed;

  /// 樂透策略加成倍率（正規化後標籤 → multiplier），供 LotteryAnalyzer 使用
  final Map<String, double> strategyMultipliers;

  static FailureAnalysisResult empty() => const FailureAnalysisResult(
    lotteryTagStats: {},
    bingoGroupStats: {},
    sportsStats: {},
    lotteryInsights: [],
    bingoInsights: [],
    sportsInsights: [],
    totalAnalyzed: {},
    strategyMultipliers: {},
  );
}

// ── 服務 ──────────────────────────────────────────────────────────

/// 分析歷史預測失敗原因，並提供改進建議供各預測引擎使用。
class FailureAnalysisService {
  FailureAnalysisService(this._logSvc);
  final PredictionLogService _logSvc;

  // ── 主要入口 ──────────────────────────────────────────────────

  Future<FailureAnalysisResult> analyze() async {
    final lotteryLogs = await _logSvc.loadByType(PredictionType.lottery);
    final bingoLogs   = await _logSvc.loadByType(PredictionType.bingo);
    final sportLogs   = await _logSvc.loadByType(PredictionType.sport);

    final lotteryRes = _analyzeLottery(lotteryLogs);
    final bingoRes   = _analyzeBingo(bingoLogs);
    final sportsRes  = _analyzeSports(sportLogs);

    final mult = _buildMultipliers(lotteryRes.$1);

    return FailureAnalysisResult(
      lotteryTagStats:     lotteryRes.$1,
      bingoGroupStats:     bingoRes.$1,
      sportsStats:         sportsRes.$1,
      lotteryInsights:     lotteryRes.$2,
      bingoInsights:       bingoRes.$2,
      sportsInsights:      sportsRes.$2,
      strategyMultipliers: mult,
      totalAnalyzed: {
        'lottery': lotteryLogs.where((l) => l.outcome != PredictionOutcome.pending).length,
        'bingo':   bingoLogs.where((l) => l.outcome != PredictionOutcome.pending).length,
        'sports':  sportLogs.where((l) => l.outcome != PredictionOutcome.pending).length,
      },
    );
  }

  // ── 樂透分析 ──────────────────────────────────────────────────

  (Map<String, TagStat>, List<String>) _analyzeLottery(List<PredictionLog> logs) {
    final settled = logs.where((l) => l.outcome != PredictionOutcome.pending).toList();
    if (settled.isEmpty) return ({}, []);

    final tagHits   = <String, int>{};
    final tagMisses = <String, int>{};

    for (final log in settled) {
      final pred   = _parseNumbers(log.predictedResult);
      final actual = _parseNumbers(log.actualResult ?? '').toSet();
      final reasons = _parseReasons(log.details['reasons']);

      for (final n in pred) {
        final rawTags = _tagsForNumber(n, reasons);
        // Normalize: strip trailing digits so '遺漏3期' and '遺漏7期' merge into '遺漏'
        final tags = rawTags.map(_normalize).toSet().toList();
        final isHit = actual.contains(n);
        for (final tag in tags) {
          if (isHit) {
            tagHits[tag]   = (tagHits[tag]   ?? 0) + 1;
          } else {
            tagMisses[tag] = (tagMisses[tag] ?? 0) + 1;
          }
        }
      }
    }

    // Collect tags with ≥3 samples
    final tagStats = <String, TagStat>{};
    final allTags = {...tagHits.keys, ...tagMisses.keys};
    for (final tag in allTags) {
      final h = tagHits[tag]   ?? 0;
      final m = tagMisses[tag] ?? 0;
      if (h + m >= 3) tagStats[tag] = TagStat(tag: tag, hits: h, misses: m);
    }

    // Insights
    final insights = <String>[];
    final totalSettled = settled.length;
    final correctCount = settled.where((l) =>
        l.outcome == PredictionOutcome.correct ||
        l.outcome == PredictionOutcome.partial).length;
    insights.add('已分析 $totalSettled 期，命中 $correctCount 期（${totalSettled > 0 ? (correctCount * 100 ~/ totalSettled) : 0}%）');

    if (tagStats.isNotEmpty) {
      final sorted = tagStats.values.toList()
        ..sort((a, b) => b.hitRate.compareTo(a.hitRate));
      final best  = sorted.where((e) => e.hitRate >= 0.45).take(3).toList();
      final worst = sorted.reversed.where((e) => e.hitRate < 0.35).take(3).toList();
      if (best.isNotEmpty) {
        insights.add('高命中策略：${best.map((e) => '${e.tag}(${(e.hitRate * 100).round()}%)').join('、')}');
      }
      if (worst.isNotEmpty) {
        insights.add('低命中策略：${worst.map((e) => '${e.tag}(${(e.hitRate * 100).round()}%)').join('、')}');
      }
    }

    return (tagStats, insights);
  }

  // ── 賓果分析 ──────────────────────────────────────────────────

  (Map<String, double>, List<String>) _analyzeBingo(List<PredictionLog> logs) {
    final settled = logs.where((l) => l.outcome != PredictionOutcome.pending).toList();
    if (settled.isEmpty) return ({}, []);

    final groupCorrect = <String, int>{};
    final groupTotal   = <String, int>{};

    for (final log in settled) {
      final group = (log.details['group'] as String? ?? log.subtitle);
      groupTotal[group]   = (groupTotal[group]   ?? 0) + 1;
      if (log.outcome == PredictionOutcome.correct ||
          log.outcome == PredictionOutcome.partial) {
        groupCorrect[group] = (groupCorrect[group] ?? 0) + 1;
      }
    }

    final stats = <String, double>{
      for (final g in groupTotal.keys)
        g: (groupCorrect[g] ?? 0) / groupTotal[g]!,
    };

    final insights = <String>['已分析 ${settled.length} 筆賓果預測'];
    if (stats.isNotEmpty) {
      final sorted = stats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      insights.add('最佳：${sorted.first.key}（${(sorted.first.value * 100).round()}%）');
      if (sorted.length > 1) {
        insights.add('最弱：${sorted.last.key}（${(sorted.last.value * 100).round()}%）');
      }
    }

    return (stats, insights);
  }

  // ── 體育分析 ──────────────────────────────────────────────────

  (Map<String, double>, List<String>) _analyzeSports(List<PredictionLog> logs) {
    final settled = logs.where((l) => l.outcome != PredictionOutcome.pending).toList();
    if (settled.isEmpty) return ({}, []);

    final sportCorrect = <String, int>{};
    final sportTotal   = <String, int>{};

    for (final log in settled) {
      final sport = (log.details['sport'] as String? ?? 'other');
      sportTotal[sport]   = (sportTotal[sport]   ?? 0) + 1;
      if (log.outcome == PredictionOutcome.correct ||
          log.outcome == PredictionOutcome.partial) {
        sportCorrect[sport] = (sportCorrect[sport] ?? 0) + 1;
      }
    }

    final stats = <String, double>{
      for (final s in sportTotal.keys)
        s: (sportCorrect[s] ?? 0) / sportTotal[s]!,
    };

    const sportNames = {
      'basketball': '籃球',
      'baseball':   '棒球',
      'football':   '足球',
    };

    final insights = <String>['已分析 ${settled.length} 場體育預測'];
    if (stats.isNotEmpty) {
      for (final entry in stats.entries) {
        final name = sportNames[entry.key] ?? entry.key;
        final pct  = (entry.value * 100).round();
        final cnt  = sportTotal[entry.key] ?? 0;
        insights.add('$name：$pct%（$cnt 場）');
      }
      final sorted = stats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.first.value > 0.6) {
        insights.add('💡 ${sportNames[sorted.first.key] ?? sorted.first.key} 預測最佳');
      }
      if (sorted.last.value < 0.35 && sorted.length > 1) {
        insights.add('⚠️ ${sportNames[sorted.last.key] ?? sorted.last.key} 正確率偏低，需調整');
      }
    }

    return (stats, insights);
  }

  // ── 策略倍率建構 ──────────────────────────────────────────────

  /// 根據 tag 命中率構建加成倍率（0.75 ~ 1.30），供 LotteryAnalyzer 使用
  Map<String, double> _buildMultipliers(Map<String, TagStat> tagStats) {
    final result = <String, double>{};
    for (final stat in tagStats.values) {
      final r = stat.hitRate;
      double mult;
      if      (r >= 0.65) { mult = 1.30; }
      else if (r >= 0.50) { mult = 1.12; }
      else if (r <  0.30) { mult = 0.75; }
      else if (r <  0.40) { mult = 0.88; }
      else                 { mult = 1.00; }
      result[stat.tag] = mult;
    }
    return result;
  }

  // ── 賓果組別建議排序 ─────────────────────────────────────────

  /// 依歷史命中率由高到低排列組別標籤（供 BingoService 展示優先序）
  List<String> bingoGroupOrder(Map<String, double> groupStats) {
    if (groupStats.isEmpty) return [];
    return (groupStats.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => e.key)
        .toList();
  }

  // ── 私有工具 ──────────────────────────────────────────────────

  List<int> _parseNumbers(String s) => s
      .split(RegExp(r'[,\s，]+'))
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toList();

  Map<String, String> _parseReasons(dynamic raw) {
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    return {};
  }

  List<String> _tagsForNumber(int n, Map<String, String> reasons) {
    final s = reasons[n.toString()] ?? '';
    if (s.isEmpty) return [];
    return s.split('・').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

  /// 正規化標籤：去掉尾部數字和 ★↑ 符號，保留語意根
  String _normalize(String tag) {
    if (tag.startsWith('遺漏'))  return '遺漏';
    if (tag.startsWith('近熱'))  return '近熱';
    if (tag.startsWith('中熱'))  return '中熱';
    if (tag.startsWith('鄰'))    return '鄰號';
    if (tag.startsWith('同尾'))  return '同尾';
    if (tag.startsWith('日尾'))  return '日期';
    if (tag.startsWith('顛倒'))  return '顛倒';
    // Strip ★ from cross-lottery tags and trailing numbers
    return tag.replaceAll('★', '').replaceAll(RegExp(r'\d+'), '').trim();
  }
}
