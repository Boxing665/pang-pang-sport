class MatchPrediction {
  const MatchPrediction({
    required this.predictedHomeScore,
    required this.predictedAwayScore,
    required this.confidence,
    required this.impliedHomeStrength,
    required this.impliedAwayStrength,
    required this.summary,
    required this.keyFactors,
    this.upsetAlert = false,
    this.injuryWarning,
    this.monteCarloHomeWinPct = 0.0,
    this.monteCarloDrawPct = 0.0,
    this.monteCarloAwayWinPct = 0.0,
    this.kellyHome = 0.0,
    this.kellyAway = 0.0,
    this.mcModeHomeScore,
    this.mcModeAwayScore,
    this.poissonModeHomeScore,
    this.poissonModeAwayScore,
    this.ensembleHomeWinPct = 0.0,
    this.ensembleDrawPct = 0.0,
    this.ensembleAwayWinPct = 0.0,
    this.poissonHomeWinPct = 0.0,
    this.poissonDrawPct = 0.0,
    this.poissonAwayWinPct = 0.0,
    this.marketMovement = 0.0,
    this.overround = 0.0,
    this.bayesianHomeWinPct = 0.0,
    this.bayesianDrawPct = 0.0,
    this.bayesianAwayWinPct = 0.0,
    this.homeValueEdge = 0.0,
    this.awayValueEdge = 0.0,
    this.hasValueBetSignal = false,
    this.marketHomeExp = 0.0,
    this.marketAwayExp = 0.0,
    this.marketVolumePressure = 0.0,
    this.isDefensiveSwitchLikely = false,
    this.topScores = const [],
    this.aiTotalExpected = 0.0,
    this.predictedMargin = 0.0,
  });

  final int predictedHomeScore;
  final int predictedAwayScore;
  final double confidence;
  final double impliedHomeStrength;
  final double impliedAwayStrength;
  final String summary;
  final List<String> keyFactors;

  /// 防爆冷警示：當市場看好隊伍有顯著傷兵時為 true
  final bool upsetAlert;

  /// 傷兵影響說明文字，無傷兵時為 null
  final String? injuryWarning;

  /// 蒙地卡羅模擬（N=500）各結果出現機率
  final double monteCarloHomeWinPct;
  final double monteCarloDrawPct;
  final double monteCarloAwayWinPct;

  /// 凱利公式建議值 f* = (b×p − q) / b
  /// > 0 = 對應方向有正期望值；< 0 = 不建議
  final double kellyHome;
  final double kellyAway;

  /// 蒙地卡羅模擬最高頻比分（500次中出現最多的比分）
  final int? mcModeHomeScore;
  final int? mcModeAwayScore;

  /// 泊松機率矩陣眾數比分：argmax P(i,j) = Poisson(λH,i)×Poisson(λA,j)
  final int? poissonModeHomeScore;
  final int? poissonModeAwayScore;

  /// 多模型融合結果（蒙地卡羅 × 泊松精確分佈 加權平均）
  final double ensembleHomeWinPct;
  final double ensembleDrawPct;
  final double ensembleAwayWinPct;

  /// 泊松精確分佈模型結果
  final double poissonHomeWinPct;
  final double poissonDrawPct;
  final double poissonAwayWinPct;

  /// 特徵工程：盤口變動方向（正=主勝方向，負=客勝方向）
  final double marketMovement;

  /// 特徵工程：博彩公司抽水百分比
  final double overround;

  /// Bayesian 後驗機率（先驗盤口 + 新證據）
  final double bayesianHomeWinPct;
  final double bayesianDrawPct;
  final double bayesianAwayWinPct;

  /// 模型機率與隱含機率的差值（正值=模型看得更高）
  final double homeValueEdge;
  final double awayValueEdge;

  /// 是否達到「顯著高於隱含機率」的出手條件
  final bool hasValueBetSignal;

  /// 莊家預期比分 (由盤口退算)
  final double marketHomeExp;
  final double marketAwayExp;

  /// 市場資金壓力指標 (0.0 ~ 1.0)
  final double marketVolumePressure;

  /// 是否可能觸發「領先後轉防守」模式
  final bool isDefensiveSwitchLikely;

  /// 泊松分佈機率最高前 3 組比分（蒙地卡羅模擬結果）
  final List<({int h, int a, double prob})> topScores;

  /// AI 模型（未經市場錨定）預測總得分，用於與盤口大小分做比較
  final double aiTotalExpected;

  /// 預測勝分差（正值 = 主隊領先）：棒球/籃球用勝率差 × 比例係數推算
  final double predictedMargin;
}