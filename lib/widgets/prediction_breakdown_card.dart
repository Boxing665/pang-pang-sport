import 'package:flutter/material.dart';

import '../models/match_fixture.dart';
import '../models/match_prediction.dart';
import '../models/sport_type.dart';
import '../theme/app_theme.dart';

/// 顯示賭盤分線：整數不顯示小數（209 → "209"，213.5 → "213.5"）
String _fmtLine(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

class PredictionBreakdownCard extends StatelessWidget {
  const PredictionBreakdownCard({
    super.key,
    required this.fixture,
    required this.prediction,
  });

  final MatchFixture fixture;
  final MatchPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 比分拆解',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E2B4B), Color(0xFF121A30)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: Column(
                children: [
                  Text(
                    '預測比分',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${fixture.homeTeam} ${prediction.predictedHomeScore} : ${prediction.predictedAwayScore} ${fixture.awayTeam}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppTheme.highlight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _MetricChip(
                        label: '信心',
                        value: '${(prediction.confidence * 100).round()}%',
                        color: AppTheme.primaryAccent,
                      ),
                      if (fixture.sport == SportType.football)
                        _MetricChip(
                          label: '總進球',
                          value: '${prediction.predictedHomeScore + prediction.predictedAwayScore}',
                          color: Colors.orangeAccent,
                        ),
                      _MetricChip(
                        label: '主隊強度',
                        value: prediction.impliedHomeStrength.toStringAsFixed(2),
                        color: AppTheme.secondaryAccent,
                      ),
                      _MetricChip(
                        label: '客隊強度',
                        value: prediction.impliedAwayStrength.toStringAsFixed(2),
                        color: AppTheme.highlight,
                      ),
                      if (prediction.marketVolumePressure > 0.1)
                        _MetricChip(
                          label: '資金壓力',
                          value: '${(prediction.marketVolumePressure * 100).round()}%',
                          color: Colors.amber,
                        ),
                      if (prediction.isDefensiveSwitchLikely)
                        const _MetricChip(
                          label: '🛡️ 防守切換',
                          value: '高機率',
                          color: Colors.lightBlueAccent,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (fixture.odds.isFromBookmaker) ...[
              const SizedBox(height: 18),
              _Section(
                title: 'Bet365 賠率',
                child: _BookmakerOddsPanel(fixture: fixture),
              ),
              const SizedBox(height: 18),
              _Section(
                title: '賠率預測分析',
                child: _OddsForecastPanel(fixture: fixture, prediction: prediction),
              ),
              const SizedBox(height: 18),
              _Section(
                title: '莊家盤口走勢分析',
                child: _LineMovementPanel(fixture: fixture),
              ),
            ],
            const SizedBox(height: 18),
            _Section(
              title: '蒙地卡羅 × 凱利',
              child: _MonteCarloKellyPanel(fixture: fixture, prediction: prediction),
            ),
            const SizedBox(height: 18),
            _Section(
              title: '推薦分析',
              child: _RecommendPanel(fixture: fixture, prediction: prediction),
            ),
            const SizedBox(height: 18),
            _Section(
              title: '預測 vs 莊家期望值',
              child: _ComparisonChart(fixture: fixture, prediction: prediction),
            ),
            const SizedBox(height: 18),
            _Section(
              title: '球隊近況',
              child: Column(
                children: [
                  _TeamFormPanel(
                    teamName: fixture.homeTeam,
                    averageScored: fixture.homeForm.averageScored,
                    averageConceded: fixture.homeForm.averageConceded,
                    injuries: fixture.homeForm.injuries,
                    momentumScore: fixture.homeForm.momentumScore,
                    recentResults: fixture.homeForm.lastFiveResults,
                    streakLabel: fixture.homeForm.streakLabel,
                    accentColor: AppTheme.primaryAccent,
                  ),
                  const SizedBox(height: 12),
                  _TeamFormPanel(
                    teamName: fixture.awayTeam,
                    averageScored: fixture.awayForm.averageScored,
                    averageConceded: fixture.awayForm.averageConceded,
                    injuries: fixture.awayForm.injuries,
                    momentumScore: fixture.awayForm.momentumScore,
                    recentResults: fixture.awayForm.lastFiveResults,
                    streakLabel: fixture.awayForm.streakLabel,
                    accentColor: AppTheme.secondaryAccent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _Section(
              title: '關鍵因子',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final factor in prediction.keyFactors) ...[
                    _BulletPoint(text: factor),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    prediction.summary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (fixture.analystNote.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '分析師補充：${fixture.analystNote}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmakerOddsPanel extends StatelessWidget {
  const _BookmakerOddsPanel({required this.fixture});
  final MatchFixture fixture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final odds = fixture.odds;
    final isFootball = fixture.sport.name == 'football';
    final hasSpread = odds.spread != 0.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        children: [
          // ── 標題列 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0x22FFFFFF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.language, size: 15, color: Color(0xFF90CAF9)),
                const SizedBox(width: 6),
                Text(
                  'Bet365',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF90CAF9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x3300E676),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '即時盤口',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF00E676),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── 主勝 / 平局 / 客勝 ──
          _OddsRow(
            label: '獨贏',
            cells: [
              _OddsCell(
                topText: '主場',
                value: odds.homeWin.toStringAsFixed(2),
                color: AppTheme.primaryAccent,
              ),
              if (isFootball)
                _OddsCell(
                  topText: '平局',
                  value: odds.draw.toStringAsFixed(2),
                  color: AppTheme.secondaryAccent,
                ),
              _OddsCell(
                topText: '客場',
                value: odds.awayWin.toStringAsFixed(2),
                color: AppTheme.highlight,
              ),
            ],
          ),
          const Divider(height: 1, color: Color(0x22FFFFFF)),
          // ── 讓分 ──
          if (hasSpread) ...[
            _OddsRow(
              label: '讓分',
              cells: [
                _OddsCell(
                  topText: odds.spread > 0
                      ? '${fixture.homeTeam} +${odds.spread}'
                      : '${fixture.homeTeam} ${odds.spread}',
                  value: odds.homeSpreadOdds.toStringAsFixed(2),
                  color: AppTheme.primaryAccent,
                ),
                _OddsCell(
                  topText: odds.spread > 0
                      ? '${fixture.awayTeam} -${odds.spread}'
                      : '${fixture.awayTeam} +${odds.spread.abs()}',
                  value: odds.awaySpreadOdds.toStringAsFixed(2),
                  color: AppTheme.highlight,
                ),
              ],
            ),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
          ],
          // ── 大小分 ──
          _OddsRow(
            label: '大小分',
            cells: [
              _OddsCell(
                topText: '大 ${_fmtLine(odds.overLine)}',
                value: odds.overOdds.toStringAsFixed(2),
                color: const Color(0xFFEF5350),
              ),
              _OddsCell(
                topText: '小 ${_fmtLine(odds.overLine)}',
                value: odds.underOdds.toStringAsFixed(2),
                color: const Color(0xFF42A5F5),
              ),
            ],
          ),
          // ── 賠率穩定度（僅在有初盤數據時顯示）──
          if (odds.errorMargin > 0) ...[
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            _ErrorMarginRow(errorMargin: odds.errorMargin),
          ],
        ],
      ),
    );
  }
}

class _ComparisonChart extends StatelessWidget {
  const _ComparisonChart({required this.fixture, required this.prediction});
  final MatchFixture fixture;
  final MatchPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final aiHome = prediction.predictedHomeScore.toDouble();
    final aiAway = prediction.predictedAwayScore.toDouble();
    final marketHome = prediction.marketHomeExp;
    final marketAway = prediction.marketAwayExp;
    final maxVal = [aiHome, aiAway, marketHome, marketAway].reduce((a, b) => a > b ? a : b).clamp(1.0, 300.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        children: [
          _chartRow(fixture.homeTeam, aiHome, marketHome, maxVal, AppTheme.primaryAccent),
          const SizedBox(height: 20),
          _chartRow(fixture.awayTeam, aiAway, marketAway, maxVal, AppTheme.highlight),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendIndicator(const Color(0xFF3DDC97), 'AI 預測'),
              const SizedBox(width: 20),
              _legendIndicator(Colors.white38, '莊家期望'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartRow(String team, double ai, double market, double max, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(team, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(height: 12, decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(6))),
                  FractionallySizedBox(
                    widthFactor: (ai / max).clamp(0.05, 1.0),
                    child: Container(
                      height: 12, 
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [color.withAlpha(100), color]),
                        borderRadius: BorderRadius.circular(6)
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 40, child: Text(ai.toStringAsFixed(0), style: TextStyle(color: color, fontWeight: FontWeight.bold))),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(height: 8, decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(4))),
                  FractionallySizedBox(
                    widthFactor: (market / max).clamp(0.05, 1.0),
                    child: Container(
                      height: 8, 
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 40, child: Text(market.toStringAsFixed(1), style: const TextStyle(color: Colors.white38, fontSize: 11))),
          ],
        ),
      ],
    );
  }

  Widget _legendIndicator(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}

class _OddsRow extends StatelessWidget {
  const _OddsRow({required this.label, required this.cells});
  final String label;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: cells,
            ),
          ),
        ],
      ),
    );
  }
}

/// 賠率穩定度（初盤 vs 即時盤）指示列
/// 顯示市場盲目跟風程度，errorMargin > 0.05 時模型已自動修正
class _ErrorMarginRow extends StatelessWidget {
  const _ErrorMarginRow({required this.errorMargin});
  final double errorMargin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color barColor;
    final String label;
    final String desc;
    if (errorMargin < 0.05) {
      barColor = const Color(0xFF00E676);
      label = '盤口穩定';
      desc = '無明顯跟風';
    } else if (errorMargin < 0.15) {
      barColor = const Color(0xFFFFEB3B);
      label = '輕微波動';
      desc = '已微調過濾';
    } else if (errorMargin < 0.30) {
      barColor = const Color(0xFFFF9800);
      label = '顯著波動';
      desc = '跟風資金介入，模型已修正';
    } else {
      barColor = const Color(0xFFEF5350);
      label = '異常波動';
      desc = '強烈跟風噪音，大幅修正';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, size: 13, color: Colors.white54),
              const SizedBox(width: 5),
              Text(
                '賠率穩定度',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white54),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: barColor.withAlpha(36),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$label  ${(errorMargin * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: barColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: errorMargin.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _OddsCell extends StatelessWidget {
  const _OddsCell({
    required this.topText,
    required this.value,
    required this.color,
  });
  final String topText;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          topText,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white54,
                fontSize: 10,
              ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.labelMedium,
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 賠率預測分析面板 ──────────────────────────────────────────────

class _OddsForecastPanel extends StatelessWidget {
  const _OddsForecastPanel({required this.fixture, required this.prediction});
  final MatchFixture fixture;
  final MatchPrediction prediction;

  static const _green   = Color(0xFF3DDC97);
  static const _red     = Color(0xFFFF5252);
  static const _gold    = Color(0xFFFFD700);
  static const _purple  = Color(0xFF9C72FF);
  static const _dim     = Color(0x8AFFFFFF);

  // 公允賠率 = 1 / 機率（無法計算時回傳 null）
  double? _fairOdds(double prob) =>
      prob > 0.01 ? (1 / prob) : null;

  // 優勢率 = (公允賠率 / 盤口賠率 - 1) × 100
  double? _edge(double? fair, double market) =>
      (fair != null && market > 1) ? ((fair / market - 1) * 100) : null;

  @override
  Widget build(BuildContext context) {
    final isFootball = fixture.sport == SportType.football;
    final odds = fixture.odds;

    // 使用 ensemble 機率（最準確）
    final hasEnsemble = prediction.ensembleHomeWinPct > 0 ||
        prediction.ensembleAwayWinPct > 0;
    final pH = hasEnsemble ? prediction.ensembleHomeWinPct
        : (odds.homeWin > 1 ? 1 / odds.homeWin : 0.5);
    final pA = hasEnsemble ? prediction.ensembleAwayWinPct
        : (odds.awayWin > 1 ? 1 / odds.awayWin : 0.5);
    final pD = prediction.ensembleDrawPct;

    final fairH = _fairOdds(pH);
    final fairA = _fairOdds(pA);
    final fairD = isFootball ? _fairOdds(pD) : null;

    final edgeH = _edge(fairH, odds.homeWin);
    final edgeA = _edge(fairA, odds.awayWin);
    final edgeD = isFootball ? _edge(fairD, odds.draw) : null;

    // 最大優勢市場
    final edges = <String, double?>{
      '主隊獨贏': edgeH,
      if (isFootball) '平局': edgeD,
      '客隊獨贏': edgeA,
    };
    final bestEntry = edges.entries
        .where((e) => e.value != null && e.value! > 0)
        .fold<MapEntry<String, double?>?>(null, (best, e) =>
            best == null || e.value! > best.value! ? e : best);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A172F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 說明
          Row(children: [
            const Icon(Icons.insights_rounded, size: 14, color: _purple),
            const SizedBox(width: 6),
            const Text('模型公允賠率 vs Pinnacle 盤口',
                style: TextStyle(color: _dim, fontSize: 11)),
            const Spacer(),
            if (bestEntry != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _green.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _green.withAlpha(80)),
                ),
                child: Text(
                  '推薦 ${bestEntry.key}  +${bestEntry.value!.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: _green, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              )
            else
              const Text('無正期望值市場',
                  style: TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
          const SizedBox(height: 12),

          // 表頭
          _tableHeader(),
          const SizedBox(height: 6),

          // 主隊
          _tableRow(
            label: '主 ${fixture.homeTeam}',
            prob: pH,
            fair: fairH,
            market: odds.homeWin,
            edge: edgeH,
          ),
          const SizedBox(height: 5),

          // 平局（僅足球）
          if (isFootball) ...[
            _tableRow(
              label: '🤝 平局',
              prob: pD,
              fair: fairD,
              market: odds.draw,
              edge: edgeD,
            ),
            const SizedBox(height: 5),
          ],

          // 客隊
          _tableRow(
            label: '客 ${fixture.awayTeam}',
            prob: pA,
            fair: fairA,
            market: odds.awayWin,
            edge: edgeA,
          ),

          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          const Text(
            '公允賠率 = 1 ÷ 模型機率。優勢率 > 0% 代表盤口賠率高於模型公允值，存在正期望值。',
            style: TextStyle(color: _dim, fontSize: 9, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return const Row(
      children: [
        Expanded(flex: 4, child: SizedBox()),
        Expanded(flex: 2, child: Text('機率', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 10))),
        Expanded(flex: 2, child: Text('公允賠率', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 10))),
        Expanded(flex: 2, child: Text('Pinnacle', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 10))),
        Expanded(flex: 2, child: Text('優勢', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 10))),
      ],
    );
  }

  Widget _tableRow({
    required String label,
    required double prob,
    required double? fair,
    required double market,
    required double? edge,
  }) {
    final isPositive = edge != null && edge > 0;
    final edgeColor = isPositive ? _green : (edge != null && edge < -5 ? _red : Colors.white38);
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          flex: 2,
          child: Text('${(prob * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          flex: 2,
          child: Text(fair != null ? fair.toStringAsFixed(2) : '--',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          flex: 2,
          child: Text(market > 1 ? market.toStringAsFixed(2) : '--',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ),
        Expanded(
          flex: 2,
          child: Text(
            edge != null
                ? '${edge >= 0 ? '+' : ''}${edge.toStringAsFixed(1)}%'
                : '--',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: edgeColor, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── 莊家盤口走勢分析面板 ──────────────────────────────────────────

class _LineMovementPanel extends StatelessWidget {
  const _LineMovementPanel({required this.fixture});
  final MatchFixture fixture;

  static const _green  = Color(0xFF3DDC97);
  static const _red    = Color(0xFFFF5252);
  static const _gold   = Color(0xFFFFD700);
  static const _dim    = Color(0x8AFFFFFF);

  @override
  Widget build(BuildContext context) {
    final odds = fixture.odds;
    final hasOpening = odds.openingHomeWin > 0 && odds.openingAwayWin > 0;
    final isFootball  = fixture.sport == SportType.football;
    final movement    = odds.marketMovement;   // positive = 資金往主場
    final margin      = odds.errorMargin;      // 0–1 移動幅度
    final rlm         = odds.hasReverseLineMovement;

    // ── 盤口分析結論 ──────────────────────────────────────────────
    // 聰明錢方向：RLM 表示盤口往大眾偏好反方向移動
    // movement > 0 = 盤口向主場收（初盤開來主場賠率縮短）
    // movement < 0 = 盤口向客場收
    final sharpOnHome = rlm && movement > 0;

    String verdict;
    String suggestion;
    Color verdictColor;
    IconData verdictIcon;

    if (!hasOpening || margin < 0.01) {
      verdict     = '盤口穩定';
      suggestion  = '市場無明顯資金流向，依 AI 模型預測判斷';
      verdictColor = _dim;
      verdictIcon  = Icons.horizontal_rule_rounded;
    } else if (rlm && margin >= 0.05) {
      final side = sharpOnHome ? '主場 ${fixture.homeTeam}' : '客場 ${fixture.awayTeam}';
      verdict     = '⚡ 聰明錢訊號';
      suggestion  = '大眾資金偏向另一邊，但盤口逆向收向 $side\n職業賭客可能正在押 $side，建議跟進';
      verdictColor = _gold;
      verdictIcon  = Icons.bolt_rounded;
    } else if (margin >= 0.10) {
      final side = movement > 0 ? '主場 ${fixture.homeTeam}' : '客場 ${fixture.awayTeam}';
      verdict     = '大量資金湧入';
      suggestion  = '盤口明顯往 $side 收短，可能是大眾跟風盤\n注意：大眾盤莊家利潤高，殺大眾有一定勝算';
      verdictColor = _red;
      verdictIcon  = Icons.warning_amber_rounded;
    } else {
      final side = movement > 0 ? '主場' : '客場';
      verdict     = '小幅資金流入 $side';
      suggestion  = '盤口移動幅度不大，可觀察後續走勢';
      verdictColor = Colors.white60;
      verdictIcon  = Icons.trending_flat_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A172F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 賠率走勢表格 ──
          if (hasOpening) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                children: [
                  _movementHeader(),
                  const SizedBox(height: 6),
                  _movementRow(
                    label: '主場 ${fixture.homeTeam}',
                    open: odds.openingHomeWin,
                    current: odds.homeWin,
                  ),
                  if (isFootball && odds.openingDraw > 0)
                    _movementRow(
                      label: '平局',
                      open: odds.openingDraw,
                      current: odds.draw,
                    ),
                  _movementRow(
                    label: '客場 ${fixture.awayTeam}',
                    open: odds.openingAwayWin,
                    current: odds.awayWin,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
          ],

          // ── 分析結論 ──
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(verdictIcon, size: 16, color: verdictColor),
                    const SizedBox(width: 6),
                    Text(
                      verdict,
                      style: TextStyle(
                        color: verdictColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (hasOpening) ...[
                      const Spacer(),
                      Text(
                        '波動 ${(margin * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  suggestion,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
                if (rlm && margin >= 0.05) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _gold.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _gold.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lightbulb_outline_rounded, size: 13, color: _gold),
                        const SizedBox(width: 6),
                        Text(
                          sharpOnHome
                              ? '建議：主場 ${fixture.homeTeam}'
                              : '建議：客場 ${fixture.awayTeam}',
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _movementHeader() {
    return Row(
      children: const [
        Expanded(flex: 4, child: Text('市場', style: TextStyle(color: Colors.white38, fontSize: 10))),
        Expanded(flex: 2, child: Text('開盤', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 10))),
        Expanded(flex: 2, child: Text('即時', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 10))),
        Expanded(flex: 2, child: Text('變化', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 10))),
      ],
    );
  }

  Widget _movementRow({
    required String label,
    required double open,
    required double current,
  }) {
    final delta = current - open;
    final shortened = delta < -0.01; // 賠率縮短 = 資金流入
    final lengthened = delta > 0.01;  // 賠率拉長 = 資金流出
    final color = shortened ? _green : (lengthened ? _red : _dim);
    final arrow = shortened ? '▼' : (lengthened ? '▲' : '—');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              open.toStringAsFixed(2),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              current.toStringAsFixed(2),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$arrow ${delta.abs().toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 蒙地卡羅 × 凱利 面板 ─────────────────────────────────────────

class _MonteCarloKellyPanel extends StatelessWidget {
  const _MonteCarloKellyPanel({
    required this.fixture,
    required this.prediction,
  });

  final MatchFixture fixture;
  final MatchPrediction prediction;

  static const _green  = Color(0xFF3DDC97);
  static const _red    = Color(0xFFFF5252);
  static const _cyan   = Color(0xFF00E5FF);
  static const _gold   = Color(0xFFFFD700);
  static const _white54 = Color(0x8AFFFFFF);

  @override
  Widget build(BuildContext context) {
    final isFootball = fixture.sport == SportType.football;
    final kHome = prediction.kellyHome;
    final kAway = prediction.kellyAway;
    final modeH = prediction.mcModeHomeScore;
    final modeA = prediction.mcModeAwayScore;

    // 使用最準確的機率來源：ensemble > Monte Carlo
    final ensH = prediction.ensembleHomeWinPct;
    final ensD = prediction.ensembleDrawPct;
    final ensA = prediction.ensembleAwayWinPct;
    final hasEnsemble = ensH > 0 || ensA > 0;
    final dispH = hasEnsemble ? ensH : prediction.monteCarloHomeWinPct;
    final dispD = hasEnsemble ? ensD : prediction.monteCarloDrawPct;
    final dispA = hasEnsemble ? ensA : prediction.monteCarloAwayWinPct;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A172F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 說明列
          Row(children: [
            const Icon(Icons.science_outlined, size: 14, color: _cyan),
            const SizedBox(width: 6),
            const Text('綜合模型預測',
                style: TextStyle(color: _white54, fontSize: 11)),
            const Spacer(),
            if (modeH != null && modeA != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _gold.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _gold.withAlpha(60)),
                ),
                child: Text('最常見比分 $modeH:$modeA',
                    style: const TextStyle(
                        color: _gold, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 12),
          // 勝負機率橫條（單一最準確結果）
          _mcBar(label: '🏠 ${fixture.homeTeam}', pct: dispH, color: _cyan),
          const SizedBox(height: 5),
          if (isFootball) ...[
            _mcBar(label: '🤝 平局', pct: dispD, color: Colors.orange.shade300),
            const SizedBox(height: 5),
          ],
          _mcBar(label: '✈️ ${fixture.awayTeam}', pct: dispA, color: _red),
          const SizedBox(height: 14),
          // 凱利公式
          const Row(children: [
            Icon(Icons.functions_outlined, size: 13, color: _white54),
            SizedBox(width: 4),
            Text('凱利公式 f* = (b×p − q) / b',
                style: TextStyle(color: _white54, fontSize: 10)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _kellyChip(
              label: '主隊凱利',
              kelly: kHome,
              odds: fixture.odds.homeWin,
              modelProb: dispH,
            )),
            const SizedBox(width: 8),
            Expanded(child: _kellyChip(
              label: '客隊凱利',
              kelly: kAway,
              odds: fixture.odds.awayWin,
              modelProb: dispA,
            )),
          ]),
          const SizedBox(height: 8),
          Text(
            '凱利值 > 0 %：模型機率高於賭盤隱含機率，存在正期望值空間；< 0 %：賭盤優勢，不建議參考。',
            style: const TextStyle(color: _white54, fontSize: 10, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _mcBar({required String label, required double pct, required Color color}) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Stack(children: [
            Container(height: 10,
                decoration: BoxDecoration(
                    color: Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.circular(5))),
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                      color: color.withAlpha(180),
                      borderRadius: BorderRadius.circular(5))),
            ),
          ]),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 38,
          child: Text('${(pct * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _kellyChip({
    required String label,
    required double kelly,
    required double odds,
    required double modelProb,
  }) {
    final isPositive = kelly > 0.005;
    final color = isPositive ? _green : (kelly < -0.005 ? _red : Colors.orange);
    final sign = isPositive ? '+' : '';
    final impliedProb = odds > 1 ? 1 / odds : 0.0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 4),
          Text('$sign${(kelly * 100).toStringAsFixed(1)}%',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            '模型 ${(modelProb * 100).round()}%  vs  賭盤 ${(impliedProb * 100).round()}%',
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _TeamFormPanel extends StatelessWidget {
  const _TeamFormPanel({
    required this.teamName,
    required this.averageScored,
    required this.averageConceded,
    required this.injuries,
    required this.momentumScore,
    required this.recentResults,
    required this.accentColor,
    this.streakLabel = '',
  });

  final String teamName;
  final double averageScored;
  final double averageConceded;
  final int injuries;
  final double momentumScore;
  final List<String> recentResults;
  final Color accentColor;
  final String streakLabel;

  String _recentWinRateText() {
    if (recentResults.isEmpty) return '--';
    final wins = recentResults.where((r) => r == '勝').length;
    final pct = (wins / recentResults.length * 100).toStringAsFixed(0);
    return '$pct%';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                teamName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: accentColor,
                    ),
              ),
              if (streakLabel.isNotEmpty) ...
                [
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: streakLabel.contains('🔥')
                          ? const Color(0x33FF6B35)
                          : streakLabel.contains('❄️')
                              ? const Color(0x334FC3F7)
                              : const Color(0x22FFFFFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      streakLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: streakLabel.contains('🔥')
                            ? const Color(0xFFFF6B35)
                            : streakLabel.contains('❄️')
                                ? const Color(0xFF4FC3F7)
                                : Colors.white70,
                      ),
                    ),
                  ),
                ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SmallBadge(
                label: '近${recentResults.length}場',
                value: recentResults.join('-'),
              ),
              _SmallBadge(
                label: '近況勝率',
                value: _recentWinRateText(),
              ),
              _SmallBadge(
                label: '均得分',
                value: averageScored.toStringAsFixed(1),
              ),
              _SmallBadge(
                label: '均失分',
                value: averageConceded.toStringAsFixed(1),
              ),
              _SmallBadge(label: '傷兵', value: '$injuries'),
              _SmallBadge(
                label: '動能',
                value: momentumScore.toStringAsFixed(2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x12000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label：$value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 推薦分析面板（勝分差 + 大小總分），三種運動共用
class _RecommendPanel extends StatelessWidget {
  const _RecommendPanel({
    required this.fixture,
    required this.prediction,
  });
  final MatchFixture fixture;
  final MatchPrediction prediction;

  // 勝分差建議：籃球優先用讓分盤，避免極端比分導致不合理分差顯示
  int _recommendedMargin({required bool hasSpread, required double spreadAbs}) {
    final raw =
        (prediction.predictedHomeScore - prediction.predictedAwayScore).abs();
    switch (fixture.sport) {
      case SportType.basketball:
        if (hasSpread && spreadAbs > 0) {
          return spreadAbs.round().clamp(3, 28);
        }
        return raw.clamp(3, 32);
      case SportType.baseball:
        if (hasSpread && spreadAbs > 0) return spreadAbs.round().clamp(1, 10);
        return raw.clamp(1, 10);
      case SportType.football:
        return raw.clamp(1, 4);
    }
  }

  String _marginUnit() {
    switch (fixture.sport) {
      case SportType.baseball:
        return '分';
      case SportType.basketball:
        return '分';
      case SportType.football:
        return '球';
    }
  }

  @override
  Widget build(BuildContext context) {
    final odds = fixture.odds;
    final isFootball = fixture.sport == SportType.football;

    // 使用模型 ensemble 機率（最準確），若無則退回賭盤隱含機率
    final hasEnsemble = prediction.ensembleHomeWinPct > 0 ||
        prediction.ensembleAwayWinPct > 0;
    final ensH = hasEnsemble ? prediction.ensembleHomeWinPct : () {
      final rawHome = odds.homeWin > 0 ? 1 / odds.homeWin : 0.0;
      final rawAway = odds.awayWin > 0 ? 1 / odds.awayWin : 0.0;
      final t = rawHome + rawAway;
      return t > 0 ? rawHome / t : 0.5;
    }();
    final ensA = hasEnsemble ? prediction.ensembleAwayWinPct : 1.0 - ensH;
    final ensD = prediction.ensembleDrawPct;

    // 足球和局判斷：預測比分相同 OR ensemble 平局機率是三者最高
    final isDraw = isFootball &&
        (prediction.predictedHomeScore == prediction.predictedAwayScore ||
            (ensD > ensH && ensD > ensA));

    final homeWins = !isDraw && ensH >= ensA;
    final winnerName = homeWins ? fixture.homeTeam : fixture.awayTeam;

    final hasSpread = odds.spread != 0.0;
    final spreadAbs = odds.spread.abs();
    final spreadFavorName =
        odds.spread > 0 ? fixture.homeTeam : fixture.awayTeam;

    // 只有真實賭盤分線才顯示（AI 估算的分線不作為大小分判斷依據）
    // 排除 AI 模型推算的分線（bookmakerName='模型推算'），允許真實賭盤與 mock 示範資料
    final hasOU = odds.overLine > 0 && odds.bookmakerName != '模型推算';
    // 賭盤賠率是否有效（真實資料，且大小分賠率不相同）
    final hasBookmakerOdds = hasOU &&
        odds.overOdds > 1.0 && odds.underOdds > 1.0 &&
        odds.overOdds != odds.underOdds;

    // ── 大小分判斷 ─────────────────────────────────────────────
    // 優先：有真實賠率 → 以賠率比較（overOdds < underOdds → 莊家偏大分）
    // 次之：只有分線 → AI 預估總分 vs 分線
    // 無分線：不顯示推薦
    final double aiTotal =
        (prediction.predictedHomeScore + prediction.predictedAwayScore)
            .toDouble();
    final bool? recommendOver = hasBookmakerOdds
        ? odds.overOdds < odds.underOdds   // 賠率低 = 市場偏好該方向
        : hasOU
            ? aiTotal > odds.overLine
            : null;

    // 賠率輔助訊號（有真實賠率時額外參考）
    final oddsGap = hasBookmakerOdds ? odds.underOdds - odds.overOdds : 0.0;
    final String oddsSignal;
    if (!hasBookmakerOdds) {
      oddsSignal = '';
    } else if (oddsGap.abs() > 0.10) {
      oddsSignal = oddsGap > 0 ? '莊家明顯偏大分' : '莊家明顯偏小分';
    } else if (oddsGap.abs() > 0.02) {
      oddsSignal = oddsGap > 0 ? '莊家微偏大分' : '莊家微偏小分';
    } else {
      oddsSignal = '賠率相近';
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        children: [
          // ── 推薦勝隊 ──
          _RecommendRow(
            icon: isDraw
                ? Icons.handshake_outlined
                : Icons.emoji_events_rounded,
            iconColor: isDraw ? Colors.orange : AppTheme.primaryAccent,
            label: '推薦勝隊',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDraw
                    ? Colors.orange.withValues(alpha: 0.15)
                    : AppTheme.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isDraw
                        ? Colors.orange.withValues(alpha: 0.4)
                        : AppTheme.primaryAccent.withValues(alpha: 0.4)),
              ),
              child: Text(
                isDraw
                    ? '🤝 和局'
                    : '${homeWins ? "主場" : "客場"} $winnerName',
                style: TextStyle(
                  color: isDraw ? Colors.orange : AppTheme.primaryAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0x22FFFFFF)),

          // ── 勝分差 ──
          _RecommendRow(
            icon: Icons.trending_up_rounded,
            iconColor: Colors.orange,
            label: '勝分差',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        isDraw
                            ? '雙方平局 · 0 球差'
                            : '$winnerName 勝 ${_recommendedMargin(hasSpread: hasSpread, spreadAbs: spreadAbs)} ${_marginUnit()}',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (hasSpread && !isDraw) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Bet365 讓分：$spreadFavorName -${spreadAbs.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x22FFFFFF)),

          // ── 大小總分 ──
          _RecommendRow(
            icon: Icons.bar_chart_rounded,
            iconColor: recommendOver == true
                ? Colors.redAccent
                : Colors.lightBlueAccent,
            label: '大小總分',
            child: hasOU
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: (recommendOver == true
                                      ? Colors.red
                                      : Colors.blue)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (recommendOver == true
                                        ? Colors.redAccent
                                        : Colors.lightBlueAccent)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              recommendOver == true
                                  ? '推薦 大(Over)'
                                  : '推薦 小(Under)',
                              style: TextStyle(
                                color: recommendOver == true
                                    ? Colors.redAccent
                                    : Colors.lightBlueAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '總分線 ${_fmtLine(odds.overLine)}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      ...[
                        const SizedBox(height: 6),
                        if (hasBookmakerOdds)
                          Row(children: [
                            _OddsChip(
                              label: '大 ${odds.overOdds.toStringAsFixed(2)}',
                              isHighlight: recommendOver == true,
                              highlightColor: Colors.redAccent,
                            ),
                            const SizedBox(width: 6),
                            _OddsChip(
                              label: '小 ${odds.underOdds.toStringAsFixed(2)}',
                              isHighlight: recommendOver == false,
                              highlightColor: Colors.lightBlueAccent,
                            ),
                            if (oddsSignal.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(oddsSignal, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ],
                          ]),
                      ],
                    ],
                  )
                : const Text(
                    '無大小分盤口資料',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecommendRow extends StatelessWidget {
  const _RecommendRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.child,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 6),
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(
            Icons.circle,
            size: 8,
            color: AppTheme.highlight,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _OddsChip extends StatelessWidget {
  const _OddsChip({
    required this.label,
    required this.isHighlight,
    required this.highlightColor,
  });

  final String label;
  final bool isHighlight;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlight ? highlightColor.withValues(alpha: 0.2) : Colors.white10,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHighlight ? highlightColor : Colors.white24,
          width: isHighlight ? 1.5 : 1.0,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isHighlight ? highlightColor : Colors.white54,
          fontSize: 12,
          fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}