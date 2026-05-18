import '../models/match_prediction.dart';

// ════════════════════════════════════════════════════════════════
// 凱利公式投注管理服務
// ════════════════════════════════════════════════════════════════

/// 凱利公式投注建議（Kelly Criterion for Sports Betting）
/// 
/// 原理：
///   f* = (bp - q) / b
///   其中：
///     f* = 建議投注佔銀行資金的比例
///     b  = 賠率（如 -110 → 1.909 倍）
///     p  = 我們對該結果的預測概率
///     q  = 1 - p（反面發生概率）
class KellyCriterionService {
  /// 標準凱利投注倍數（過激進可能破產，通常用 1/4 ~ 1/2 凱利）
  static const standardKelly = 1.0;
  /// 保守凱利投注倍數（降低破產風險）
  static const quarterKelly = 0.25;
  /// 中等凱利投注倍數
  static const halfKelly = 0.50;

  /// 從十進位賠率轉換為美式賠率（如 2.0 → -100）
  /// 
  /// 十進位賠率計算方式：
  ///   - 賠率 >= 2.0：美式賠率 = (賠率 - 1) × 100
  ///   - 賠率 < 2.0：美式賠率 = -100 / (賠率 - 1)
  static int _decimalToAmericanOdds(double decimalOdds) {
    if (decimalOdds < 0.1 || decimalOdds.isInfinite) return 0;
    if (decimalOdds >= 2.0) {
      return ((decimalOdds - 1.0) * 100).round();
    } else {
      return (-100.0 / (decimalOdds - 1.0)).round();
    }
  }

  /// 從美式賠率計算 b 值（凱利公式中的倍數）
  /// 
  /// 計算方式：
  ///   - 正數（如 +150）：b = odds / 100
  ///   - 負數（如 -110）：b = 100 / abs(odds)
  static double _americanOddsToBValue(int americanOdds) {
    if (americanOdds > 0) {
      return americanOdds / 100.0;
    } else if (americanOdds < 0) {
      return 100.0 / americanOdds.abs();
    }
    return 1.0; // 預設
  }

  /// 計算凱利公式推薦投注比例
  /// 
  /// 參數：
  ///   - predictedProb: 我們對該結果的預測概率（0.0 ~ 1.0）
  ///   - decimalOdds: 十進位賠率（如 1.90、2.50）
  ///   - kellyMultiplier: 凱利倍數（預設 0.25 = 1/4 凱利）
  /// 
  /// 返回值：
  ///   建議投注佔銀行資金的比例（0.0 ~ 1.0）
  ///   - 返回值 <= 0：不建議投注（預期值為負）
  ///   - 返回值 > 0：建議投注該比例的銀行資金
  static double calculateKellyBet(
    double predictedProb,
    double decimalOdds, {
    double kellyMultiplier = quarterKelly,
  }) {
    if (decimalOdds <= 1.0 || decimalOdds.isInfinite) return 0.0;
    if (predictedProb <= 0.0 || predictedProb >= 1.0) return 0.0;

    // 轉換賠率為 b 值
    final americanOdds = _decimalToAmericanOdds(decimalOdds);
    final b = _americanOddsToBValue(americanOdds);

    // 凱利公式：f* = (b*p - q) / b
    final p = predictedProb;
    final q = 1.0 - p;
    final kellyFraction = (b * p - q) / b;

    // 應用凱利倍數（降低激進度）
    final adjustedKelly = (kellyFraction * kellyMultiplier).clamp(0.0, 0.25);

    // 負值表示反面有利可圖，但我們只考慮正向投注
    return adjustedKelly.clamp(0.0, 1.0);
  }

  /// 計算投注期望值（Expected Value, EV）
  /// 
  /// 期望值 = (獲勝概率 × 利潤) - (失敗概率 × 投注額)
  /// 
  /// 返回值：
  ///   - EV > 0：正期望值，適合投注
  ///   - EV < 0：負期望值，不適合投注
  static double calculateExpectedValue(
    double predictedProb,
    double decimalOdds,
    double betAmount,
  ) {
    if (decimalOdds <= 1.0) return 0.0;

    final winProfit = (decimalOdds - 1.0) * betAmount;
    final lossPenalty = betAmount;
    final expectedValue =
        (predictedProb * winProfit) - ((1.0 - predictedProb) * lossPenalty);

    return expectedValue;
  }

  /// 計算投注的勝率期望（Return on Investment）
  /// 
  /// ROI = EV / 投注額
  static double calculateROI(
    double predictedProb,
    double decimalOdds,
  ) {
    if (decimalOdds <= 1.0 || predictedProb <= 0.0) return 0.0;

    // 凱利公式：f* = (b*p - q) / b
    final americanOdds = _decimalToAmericanOdds(decimalOdds);
    final b = _americanOddsToBValue(americanOdds);
    final p = predictedProb;
    final q = 1.0 - p;

    // ROI = (b*p - q) / b
    return ((b * p - q) / b).clamp(0.0, 5.0);
  }

  /// 凱利投注建議物件
  static KellyBetSuggestion generateBetSuggestion(
    String matchId,
    String league,
    String homeTeam,
    String awayTeam,
    double bankroll,
    MatchPrediction prediction, {
    double kellyMultiplier = quarterKelly,
  }) {
    // 提取預測概率（主勝 / 平 / 客勝）- 使用 Ensemble 融合模型
    final homeWinProb = prediction.ensembleHomeWinPct;
    final drawProb = prediction.ensembleDrawPct;
    final awayWinProb = prediction.ensembleAwayWinPct;

    // 使用預測分數轉換為假設賠率（簡易模型）
    // 若需真實賠率，應從外部賠率 API 獲取
    final homeOdds = 2.0; // 預設主勝賠率
    final drawOdds = 3.0; // 預設平手賠率
    final awayOdds = 2.5; // 預設客勝賠率

    // 計算各選項的凱利投注比例
    final homeKelly = calculateKellyBet(homeWinProb, homeOdds,
        kellyMultiplier: kellyMultiplier);
    final drawKelly = calculateKellyBet(drawProb, drawOdds,
        kellyMultiplier: kellyMultiplier);
    final awayKelly = calculateKellyBet(awayWinProb, awayOdds,
        kellyMultiplier: kellyMultiplier);

    // 推薦投注金額
    final homeBetAmount = homeKelly * bankroll;
    final drawBetAmount = drawKelly * bankroll;
    final awayBetAmount = awayKelly * bankroll;

    // 計算期望值和 ROI
    final homeEV = calculateExpectedValue(homeWinProb, homeOdds, homeBetAmount);
    final awayEV =
        calculateExpectedValue(awayWinProb, awayOdds, awayBetAmount);

    // 選擇最佳投注機會
    final allOptions = [
      BetOption('主勝', homeTeam, homeOdds, homeWinProb, homeBetAmount, homeEV,
          calculateROI(homeWinProb, homeOdds)),
      if (drawOdds > 1.0)
        BetOption('平手', '平手', drawOdds, drawProb, drawBetAmount,
            calculateExpectedValue(drawProb, drawOdds, drawBetAmount),
            calculateROI(drawProb, drawOdds)),
      BetOption('客勝', awayTeam, awayOdds, awayWinProb, awayBetAmount, awayEV,
          calculateROI(awayWinProb, awayOdds)),
    ];

    final bestOption = allOptions.reduce(
      (a, b) => a.expectedValue > b.expectedValue ? a : b,
    );

    return KellyBetSuggestion(
      matchId: matchId,
      league: league,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      recommendedOption: bestOption.outcome,
      recommendedOdds: bestOption.odds,
      recommendedProbability: bestOption.probability,
      recommendedBetAmount: bestOption.betAmount,
      expectedValue: bestOption.expectedValue,
      roi: bestOption.roi,
      kellyFraction: allOptions
          .map((o) => o.probability > 0 ? o.betAmount / bankroll : 0.0)
          .reduce((a, b) => a + b)
          .clamp(0.0, 1.0),
      allOptions: allOptions,
      riskLevel: _assessRiskLevel(bestOption.expectedValue, bankroll),
      timestamp: DateTime.now(),
    );
  }

  /// 風險評估（基於期望值和銀行資金）
  static String _assessRiskLevel(double expectedValue, double bankroll) {
    if (expectedValue < 0) return '❌ 負期望值 - 不投注';
    final roi = expectedValue / bankroll;
    if (roi < 0.02) return '🟡 低風險';
    if (roi < 0.05) return '🟠 中等風險';
    if (roi < 0.10) return '🔴 高風險';
    return '⚫ 極高風險';
  }

  /// 多場投注組合凱利優化
  /// 
  /// 當投注多場比賽時，根據凱利公式計算最優投注分配
  static BankrollAllocationResult optimizeBankroll(
    double bankroll,
    List<KellyBetSuggestion> suggestions, {
    double kellyMultiplier = quarterKelly,
  }) {
    if (suggestions.isEmpty) {
      return BankrollAllocationResult(
        totalBankroll: bankroll,
        allocations: [],
        totalAllocated: 0.0,
        remainingBankroll: bankroll,
        portfolioExpectedValue: 0.0,
      );
    }

    // 按期望值降序排序
    final sorted = List<KellyBetSuggestion>.from(suggestions)
      ..sort((a, b) => b.expectedValue.compareTo(a.expectedValue));

    // 保留至少 50% 的銀行資金（避免過度投注）
    final maxAllocationPercentage = 0.50 * kellyMultiplier;
    double totalAllocated = 0.0;
    final allocations = <BankrollAllocation>[];

    for (final suggestion in sorted) {
      final remainingBankroll = bankroll - totalAllocated;
      final maxAllocation = remainingBankroll * maxAllocationPercentage;
      final allocation = (suggestion.recommendedBetAmount).clamp(0.0, maxAllocation);

      if (allocation > 0.01 * bankroll) {
        // 最小投注額為銀行資金的 1%
        allocations.add(BankrollAllocation(
          matchId: suggestion.matchId,
          league: suggestion.league,
          matchup: '${suggestion.homeTeam} vs ${suggestion.awayTeam}',
          recommendedOutcome: suggestion.recommendedOption,
          allocatedAmount: allocation,
          odds: suggestion.recommendedOdds,
          expectedValue: suggestion.expectedValue,
          roi: suggestion.roi,
        ));
        totalAllocated += allocation;
      }
    }

    // 計算投資組合期望值
    final portfolioEV =
        allocations.fold<double>(0.0, (sum, a) => sum + a.expectedValue);

    return BankrollAllocationResult(
      totalBankroll: bankroll,
      allocations: allocations,
      totalAllocated: totalAllocated,
      remainingBankroll: (bankroll - totalAllocated).clamp(0.0, bankroll),
      portfolioExpectedValue: portfolioEV,
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 資料模型
// ════════════════════════════════════════════════════════════════

/// 單個投注選項
class BetOption {
  final String outcome;
  final String team;
  final double odds;
  final double probability;
  final double betAmount;
  final double expectedValue;
  final double roi;

  const BetOption(
    this.outcome,
    this.team,
    this.odds,
    this.probability,
    this.betAmount,
    this.expectedValue,
    this.roi,
  );
}

/// 凱利投注建議
class KellyBetSuggestion {
  final String matchId;
  final String league;
  final String homeTeam;
  final String awayTeam;
  final String recommendedOption; // "主勝" / "平手" / "客勝"
  final double recommendedOdds;
  final double recommendedProbability;
  final double recommendedBetAmount;
  final double expectedValue; // EV = (prob × profit) - ((1-prob) × bet)
  final double roi; // 投報率
  final double kellyFraction; // 凱利比例（0.0 ~ 1.0）
  final List<BetOption> allOptions; // 所有投注選項
  final String riskLevel; // 風險等級
  final DateTime timestamp;

  const KellyBetSuggestion({
    required this.matchId,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.recommendedOption,
    required this.recommendedOdds,
    required this.recommendedProbability,
    required this.recommendedBetAmount,
    required this.expectedValue,
    required this.roi,
    required this.kellyFraction,
    required this.allOptions,
    required this.riskLevel,
    required this.timestamp,
  });

  /// 投注建議是否值得考慮（正期望值）
  bool get isWorthwhile => expectedValue > 0.0;

  /// 投報率百分比
  String get roiPercentage => '${(roi * 100).toStringAsFixed(2)}%';
}

/// 銀行資金分配結果
class BankrollAllocationResult {
  final double totalBankroll;
  final List<BankrollAllocation> allocations;
  final double totalAllocated;
  final double remainingBankroll;
  final double portfolioExpectedValue;

  const BankrollAllocationResult({
    required this.totalBankroll,
    required this.allocations,
    required this.totalAllocated,
    required this.remainingBankroll,
    required this.portfolioExpectedValue,
  });

  /// 投資組合期望值百分比
  double get portfolioROI =>
      totalBankroll > 0 ? portfolioExpectedValue / totalBankroll : 0.0;

  /// 已分配銀行資金的百分比
  double get allocationPercentage =>
      totalBankroll > 0 ? totalAllocated / totalBankroll : 0.0;
}

/// 單個投注分配
class BankrollAllocation {
  final String matchId;
  final String league;
  final String matchup;
  final String recommendedOutcome;
  final double allocatedAmount;
  final double odds;
  final double expectedValue;
  final double roi;

  const BankrollAllocation({
    required this.matchId,
    required this.league,
    required this.matchup,
    required this.recommendedOutcome,
    required this.allocatedAmount,
    required this.odds,
    required this.expectedValue,
    required this.roi,
  });

  /// 潛在利潤（如果投注成功）
  double get potentialProfit => allocatedAmount * (odds - 1.0);

  /// 最大損失（如果投注失敗）
  double get maxLoss => allocatedAmount;
}
