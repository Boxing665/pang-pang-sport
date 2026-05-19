import 'package:flutter/material.dart';

import '../models/match_fixture.dart';
import '../models/match_prediction.dart';
import '../models/sport_type.dart';
import '../services/real_data_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 比賽完整分析頁面
// ─────────────────────────────────────────────────────────────────────────────

class MatchAnalysisScreen extends StatefulWidget {
  const MatchAnalysisScreen({
    super.key,
    required this.fixture,
    required this.prediction,
  });

  final MatchFixture fixture;
  final MatchPrediction prediction;

  @override
  State<MatchAnalysisScreen> createState() => _MatchAnalysisScreenState();
}

class _MatchAnalysisScreenState extends State<MatchAnalysisScreen> {
  MatchFixture get f => widget.fixture;
  MatchPrediction get p => widget.prediction;

  // Extended data loaded asynchronously
  Map<String, double> _homeStats = {};
  Map<String, double> _awayStats = {};
  List<Map<String, dynamic>> _homeRecentMatches = [];
  List<Map<String, dynamic>> _awayRecentMatches = [];
  List<Map<String, dynamic>> _h2hMatches = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _fetchExtendedData();
  }

  Future<void> _fetchExtendedData() async {
    final slug = RealDataService.soccerSlugFromLeague(f.league) ?? '';
    final eventId = RealDataService.eventIdFromFixture(f.id);
    final homeId = f.homeForm.teamId;
    final awayId = f.awayForm.teamId;

    final results = await Future.wait([
      RealDataService.fetchTeamExtendedStats(homeId, f.sport, slug),
      RealDataService.fetchTeamExtendedStats(awayId, f.sport, slug),
      RealDataService.fetchTeamRecentMatchDetails(homeId, f.sport, slug),
      RealDataService.fetchTeamRecentMatchDetails(awayId, f.sport, slug),
      RealDataService.fetchH2HMatchDetails(eventId, f.sport, slug),
    ]);

    var h2h = results[4] as List<Map<String, dynamic>>;
    // ESPN summary 無 headToHead 時改用賽程交叉比對
    if (h2h.isEmpty && homeId.isNotEmpty && awayId.isNotEmpty) {
      h2h = await RealDataService.fetchH2HFromSchedules(homeId, awayId, f.sport, slug);
    }

    if (!mounted) return;
    setState(() {
      _homeStats = results[0] as Map<String, double>;
      _awayStats = results[1] as Map<String, double>;
      _homeRecentMatches = results[2] as List<Map<String, dynamic>>;
      _awayRecentMatches = results[3] as List<Map<String, dynamic>>;
      _h2hMatches = h2h;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A1020),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(theme),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                _MatchHeader(fixture: f, prediction: p),
                const SizedBox(height: 20),
                _buildStats(theme),
                const SizedBox(height: 20),
                _buildRecentForm(theme),
                const SizedBox(height: 20),
                _buildH2H(theme),
                const SizedBox(height: 20),
                _buildKeyFactors(theme),
                const SizedBox(height: 20),
                _buildFinalPrediction(theme),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(ThemeData theme) {
    return SliverAppBar(
      backgroundColor: const Color(0xFF0A1020),
      foregroundColor: Colors.white,
      expandedHeight: 56,
      floating: true,
      snap: true,
      title: Text(
        '${f.homeTeam} vs ${f.awayTeam}',
        style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ── 統計對比 ────────────────────────────────────────────────────────────────

  Widget _buildStats(ThemeData theme) {
    // 棒球永遠顯示投手面板：有 ESPN probables 則顯示真實數據，否則顯示球隊 ERA 推算值
    final hasPitcher = f.sport == SportType.baseball;
    return _Section(
      title: '球隊統計對比',
      icon: Icons.bar_chart_rounded,
      child: Column(
        children: [
          _loaded
              ? _StatsTable(fixture: f, homeStats: _homeStats, awayStats: _awayStats)
              : const _LoadingPanel(),
          if (hasPitcher) ...[
            const SizedBox(height: 12),
            _PitcherPanel(fixture: f),
          ],
        ],
      ),
    );
  }

  // ── 近期戰績 ────────────────────────────────────────────────────────────────

  Widget _buildRecentForm(ThemeData theme) {
    return _Section(
      title: '近期戰績',
      icon: Icons.history_rounded,
      child: Column(
        children: [
          _RecentFormPanel(
            teamName: f.homeTeam,
            recentResults: f.homeForm.lastFiveResults,
            recentScores: f.homeForm.recentScores,
            recentMatches: _homeRecentMatches,
            accentColor: AppTheme.primaryAccent,
            seasonRecord: f.homeForm.seasonRecord,
            streakLabel: f.homeForm.streakLabel,
            sport: f.sport,
          ),
          const SizedBox(height: 12),
          _RecentFormPanel(
            teamName: f.awayTeam,
            recentResults: f.awayForm.lastFiveResults,
            recentScores: f.awayForm.recentScores,
            recentMatches: _awayRecentMatches,
            accentColor: AppTheme.highlight,
            seasonRecord: f.awayForm.seasonRecord,
            streakLabel: f.awayForm.streakLabel,
            sport: f.sport,
          ),
        ],
      ),
    );
  }

  // ── H2H ──────────────────────────────────────────────────────────────────────

  Widget _buildH2H(ThemeData theme) {
    return _Section(
      title: '歷史對戰',
      icon: Icons.compare_arrows_rounded,
      child: _H2HPanel(
        fixture: f,
        h2hMatches: _h2hMatches,
      ),
    );
  }

  // ── 關鍵因子 ─────────────────────────────────────────────────────────────────

  Widget _buildKeyFactors(ThemeData theme) {
    final factors = p.keyFactors;
    if (factors.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: '關鍵分析因子',
      icon: Icons.lightbulb_outline_rounded,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: _panelDecor(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final factor in factors) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 8),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.highlight,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(factor,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70, height: 1.5)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  // ── 最終預測 ─────────────────────────────────────────────────────────────────

  Widget _buildFinalPrediction(ThemeData theme) {
    return _Section(
      title: '最終預測',
      icon: Icons.emoji_events_rounded,
      child: Column(
        children: [
          _FinalPredictionPanel(fixture: f, prediction: p),
          if (f.sport != SportType.basketball && p.topScores.isNotEmpty)
            _PoissonMatrixPanel(prediction: p),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 比賽頭部（比分卡）
// ─────────────────────────────────────────────────────────────────────────────

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.fixture, required this.prediction});
  final MatchFixture fixture;
  final MatchPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final p = prediction;
    final isFootball = f.sport == SportType.football;

    final homeP = f.odds.fairHomeProb > 0.05 ? f.odds.fairHomeProb : p.ensembleHomeWinPct;
    final awayP = f.odds.fairAwayProb > 0.05 ? f.odds.fairAwayProb : p.ensembleAwayWinPct;
    final drawP = isFootball ? (f.odds.fairDrawProb > 0.05 ? f.odds.fairDrawProb : p.ensembleDrawPct) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2B50), Color(0xFF0E1A35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        children: [
          // League + time
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(f.league,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
              const SizedBox(width: 8),
              Text('·', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white30)),
              const SizedBox(width: 8),
              Text(_formatTime(f.startTime),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 16),
          // Teams row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(f.homeTeam,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(f.homeForm.seasonRecord.isNotEmpty ? f.homeForm.seasonRecord : '—',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38)),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x22FFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('VS',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.highlight, fontWeight: FontWeight.w900)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(f.awayTeam,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(f.awayForm.seasonRecord.isNotEmpty ? f.awayForm.seasonRecord : '—',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Win probability bar
          _WinProbBar(homeP: homeP, drawP: drawP, awayP: awayP, isFootball: isFootball),
          const SizedBox(height: 12),
          // Odds row
          if (f.odds.isFromBookmaker || f.odds.homeWin > 1.0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _OddsPill(label: '主場', value: f.odds.homeWin.toStringAsFixed(2), color: AppTheme.primaryAccent),
                if (isFootball)
                  _OddsPill(label: '平局', value: f.odds.draw.toStringAsFixed(2), color: Colors.orange),
                _OddsPill(label: '客場', value: f.odds.awayWin.toStringAsFixed(2), color: AppTheme.highlight),
              ],
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final m = dt.month.toString();
    final d = dt.day.toString();
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m/$d $h:$min';
  }
}

class _WinProbBar extends StatelessWidget {
  const _WinProbBar({
    required this.homeP,
    required this.drawP,
    required this.awayP,
    required this.isFootball,
  });
  final double homeP;
  final double drawP;
  final double awayP;
  final bool isFootball;

  @override
  Widget build(BuildContext context) {
    final total = homeP + drawP + awayP;
    if (total <= 0) return const SizedBox.shrink();
    final hF = homeP / total;
    final dF = isFootball ? drawP / total : 0.0;
    final aF = awayP / total;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              Flexible(
                flex: (hF * 100).round(),
                child: Container(height: 10, color: AppTheme.primaryAccent),
              ),
              if (isFootball && dF > 0)
                Flexible(
                  flex: (dF * 100).round(),
                  child: Container(height: 10, color: Colors.orange),
                ),
              Flexible(
                flex: (aF * 100).round(),
                child: Container(height: 10, color: AppTheme.highlight),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${(hF * 100).round()}%',
                style: const TextStyle(color: AppTheme.primaryAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            if (isFootball)
              Text('平 ${(dF * 100).round()}%',
                  style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
            Text('${(aF * 100).round()}%',
                style: const TextStyle(color: AppTheme.highlight, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}

class _OddsPill extends StatelessWidget {
  const _OddsPill({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color.withAlpha(180), fontSize: 10)),
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 統計表格
// ─────────────────────────────────────────────────────────────────────────────

class _StatsTable extends StatelessWidget {
  const _StatsTable({
    required this.fixture,
    required this.homeStats,
    required this.awayStats,
  });
  final MatchFixture fixture;
  final Map<String, double> homeStats;
  final Map<String, double> awayStats;

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    if (rows.isEmpty) return const _NoDataPanel(message: '統計資料載入中…');

    return Container(
      decoration: _panelDecor(),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                    child: Text(fixture.homeTeam,
                        style: const TextStyle(
                            color: AppTheme.primaryAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8, child: Text('')),
                const SizedBox(width: 90),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(fixture.awayTeam,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            color: AppTheme.highlight,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x22FFFFFF)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Text('★ 真實數據  ~ 估算', style: TextStyle(color: Colors.white38, fontSize: 9)),
              ],
            ),
          ),
          for (final row in rows) ...[
            _StatRow(
              label: row['label'] as String,
              homeVal: row['home'] as String,
              awayVal: row['away'] as String,
              homeRaw: row['homeRaw'] as double,
              awayRaw: row['awayRaw'] as double,
              higherIsBetter: (row['higherIsBetter'] as bool?) ?? true,
            ),
            if (row != rows.last) const Divider(height: 1, color: Color(0x11FFFFFF)),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildRows() {
    final hf = fixture.homeForm;
    final af = fixture.awayForm;
    final sport = fixture.sport;
    final rows = <Map<String, dynamic>>[];

    switch (sport) {
      case SportType.football:
        rows.addAll([
          _row('均進球', hf.averageScored, af.averageScored, fmt: '%.2f', higher: true,
              homeSuffix: hf.averageScored > 0.10 ? '★' : '~',
              awaySuffix: af.averageScored > 0.10 ? '★' : '~'),
          _row('均失球', hf.averageConceded, af.averageConceded, fmt: '%.2f', higher: false,
              homeSuffix: hf.averageConceded > 0.10 ? '★' : '~',
              awaySuffix: af.averageConceded > 0.10 ? '★' : '~'),
          if (_has(homeStats, awayStats, ['possessionPct', 'possessionAverage', 'possession']))
            _row('控球率%', _pick(homeStats, ['possessionPct', 'possessionAverage', 'possession']),
                _pick(awayStats, ['possessionPct', 'possessionAverage', 'possession']),
                fmt: '%.1f', higher: true),
          if (_has(homeStats, awayStats, ['totalShots', 'shotsTotal', 'shots']))
            _row('射門數/場', _pick(homeStats, ['totalShots', 'shotsTotal', 'shots']),
                _pick(awayStats, ['totalShots', 'shotsTotal', 'shots']),
                fmt: '%.1f', higher: true),
          if (_has(homeStats, awayStats, ['passAccuracy', 'passingAccuracy', 'passSuccessPct']))
            _row('傳球成功率%', _pick(homeStats, ['passAccuracy', 'passingAccuracy', 'passSuccessPct']),
                _pick(awayStats, ['passAccuracy', 'passingAccuracy', 'passSuccessPct']),
                fmt: '%.1f', higher: true),
          if (_has(homeStats, awayStats, ['yellowCards', 'yellowCardsTotal']))
            _row('黃牌', _pick(homeStats, ['yellowCards', 'yellowCardsTotal']),
                _pick(awayStats, ['yellowCards', 'yellowCardsTotal']),
                fmt: '%.0f', higher: false),
          if (_has(homeStats, awayStats, ['redCards', 'redCardsTotal']))
            _row('紅牌', _pick(homeStats, ['redCards', 'redCardsTotal']),
                _pick(awayStats, ['redCards', 'redCardsTotal']),
                fmt: '%.0f', higher: false),
          if (_has(homeStats, awayStats, ['cornerKicks', 'corners', 'cornersTotal']))
            _row('角球', _pick(homeStats, ['cornerKicks', 'corners', 'cornersTotal']),
                _pick(awayStats, ['cornerKicks', 'corners', 'cornersTotal']),
                fmt: '%.1f', higher: true),
        ]);
        break;
      case SportType.basketball:
        rows.addAll([
          _row('均得分', hf.averageScored, af.averageScored, fmt: '%.1f', higher: true,
              homeSuffix: hf.averageScored > 0.10 ? '★' : '~',
              awaySuffix: af.averageScored > 0.10 ? '★' : '~'),
          _row('均失分', hf.averageConceded, af.averageConceded, fmt: '%.1f', higher: false,
              homeSuffix: hf.averageConceded > 0.10 ? '★' : '~',
              awaySuffix: af.averageConceded > 0.10 ? '★' : '~'),
          if (_has(homeStats, awayStats, ['avgPoints', 'points']))
            _row('場均得分', _pick(homeStats, ['avgPoints', 'points']),
                _pick(awayStats, ['avgPoints', 'points']),
                fmt: '%.1f', higher: true),
          if (_has(homeStats, awayStats, ['fieldGoalPct', 'FGPct', 'avgFieldGoalsAttempted']))
            _row('投籃命中率%', _pick(homeStats, ['fieldGoalPct', 'FGPct']) * (_pick(homeStats, ['fieldGoalPct', 'FGPct']) < 1 ? 100 : 1),
                _pick(awayStats, ['fieldGoalPct', 'FGPct']) * (_pick(awayStats, ['fieldGoalPct', 'FGPct']) < 1 ? 100 : 1),
                fmt: '%.1f', higher: true),
          if (_has(homeStats, awayStats, ['avgRebounds', 'rebounds', 'REB']))
            _row('籃板/場', _pick(homeStats, ['avgRebounds', 'rebounds', 'REB']),
                _pick(awayStats, ['avgRebounds', 'rebounds', 'REB']),
                fmt: '%.1f', higher: true),
          if (_has(homeStats, awayStats, ['avgAssists', 'assists', 'AST']))
            _row('助攻/場', _pick(homeStats, ['avgAssists', 'assists', 'AST']),
                _pick(awayStats, ['avgAssists', 'assists', 'AST']),
                fmt: '%.1f', higher: true),
          if (hf.playerEfficiencyRating > 0 || af.playerEfficiencyRating > 0)
            _row('效率評分', hf.playerEfficiencyRating, af.playerEfficiencyRating, fmt: '%.1f', higher: true),
        ]);
        break;
      case SportType.baseball:
        rows.addAll([
          _row('均得分', hf.averageScored, af.averageScored, fmt: '%.2f', higher: true,
              homeSuffix: hf.averageScored > 0.10 ? '★' : '~',
              awaySuffix: af.averageScored > 0.10 ? '★' : '~'),
          _row('均失分', hf.averageConceded, af.averageConceded, fmt: '%.2f', higher: false,
              homeSuffix: hf.averageConceded > 0.10 ? '★' : '~',
              awaySuffix: af.averageConceded > 0.10 ? '★' : '~'),
          if (_has(homeStats, awayStats, ['battingAverage', 'avg', 'AVG']))
            _row('打擊率', _pick(homeStats, ['battingAverage', 'avg', 'AVG']),
                _pick(awayStats, ['battingAverage', 'avg', 'AVG']),
                fmt: '%.3f', higher: true),
          if (_has(homeStats, awayStats, ['ERA', 'era']))
            _row('先發 ERA', _pick(homeStats, ['ERA', 'era']),
                _pick(awayStats, ['ERA', 'era']),
                fmt: '%.2f', higher: false),
          if (_has(homeStats, awayStats, ['WHIP', 'whip']))
            _row('WHIP', _pick(homeStats, ['WHIP', 'whip']),
                _pick(awayStats, ['WHIP', 'whip']),
                fmt: '%.2f', higher: false),
          if (hf.playerEfficiencyRating > 0 || af.playerEfficiencyRating > 0)
            _row('K/9', hf.playerEfficiencyRating, af.playerEfficiencyRating, fmt: '%.1f', higher: true),
        ]);
        break;
    }

    return rows.where((r) => r['homeRaw'] as double > 0 || r['awayRaw'] as double > 0).toList();
  }

  bool _has(Map<String, double> home, Map<String, double> away, List<String> keys) {
    for (final k in keys) {
      if (home.containsKey(k) || away.containsKey(k)) return true;
    }
    return false;
  }

  double _pick(Map<String, double> stats, List<String> keys) {
    for (final k in keys) {
      if (stats.containsKey(k)) return stats[k]!;
    }
    return 0.0;
  }

  Map<String, dynamic> _row(String label, double home, double away,
      {required String fmt, required bool higher, String homeSuffix = '', String awaySuffix = ''}) {
    String format(double v) {
      if (fmt == '%.3f') return v.toStringAsFixed(3);
      if (fmt == '%.2f') return v.toStringAsFixed(2);
      if (fmt == '%.1f') return v.toStringAsFixed(1);
      return v.toStringAsFixed(0);
    }
    return {
      'label': label,
      'home': '${format(home)}$homeSuffix',
      'away': '${format(away)}$awaySuffix',
      'homeRaw': home,
      'awayRaw': away,
      'higherIsBetter': higher,
    };
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.homeVal,
    required this.awayVal,
    required this.homeRaw,
    required this.awayRaw,
    required this.higherIsBetter,
  });
  final String label;
  final String homeVal;
  final String awayVal;
  final double homeRaw;
  final double awayRaw;
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final homeBetter = higherIsBetter ? homeRaw >= awayRaw : homeRaw <= awayRaw;
    final awayBetter = higherIsBetter ? awayRaw >= homeRaw : awayRaw <= homeRaw;
    final tie = homeRaw == awayRaw;
    final hColor = tie ? Colors.white60 : (homeBetter ? AppTheme.primaryAccent : Colors.white38);
    final aColor = tie ? Colors.white60 : (awayBetter ? AppTheme.highlight : Colors.white38);

    final maxVal = homeRaw > awayRaw ? homeRaw : awayRaw;
    final hFrac = maxVal > 0 ? (homeRaw / maxVal).clamp(0.0, 1.0) : 0.0;
    final aFrac = maxVal > 0 ? (awayRaw / maxVal).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Home value + bar
          Expanded(
            child: Row(
              children: [
                Text(homeVal,
                    style: TextStyle(color: hColor, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: hFrac,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: hColor.withAlpha(homeBetter ? 180 : 80),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Label
          SizedBox(
            width: 90,
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          // Away bar + value
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: FractionallySizedBox(
                    widthFactor: aFrac,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: aColor.withAlpha(awayBetter ? 180 : 80),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(awayVal,
                    style: TextStyle(color: aColor, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 近期戰績面板
// ─────────────────────────────────────────────────────────────────────────────

class _RecentFormPanel extends StatelessWidget {
  const _RecentFormPanel({
    required this.teamName,
    required this.recentResults,
    required this.recentMatches,
    required this.accentColor,
    this.recentScores = const [],
    this.seasonRecord = '',
    this.streakLabel = '',
    this.sport = SportType.football,
  });

  final String teamName;
  final List<String> recentResults;
  final List<String> recentScores;
  final List<Map<String, dynamic>> recentMatches;
  final Color accentColor;
  final String seasonRecord;
  final String streakLabel;
  final SportType sport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool allowDraw = sport == SportType.football;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Team name row
          Row(
            children: [
              Text(teamName,
                  style: TextStyle(
                      color: accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              if (seasonRecord.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('($seasonRecord)',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38)),
              ],
              if (streakLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                _StreakChip(label: streakLabel),
              ],
              const Spacer(),
              // W/D/L dots
              Row(
                children: recentResults.take(5).map((r) => _ResultDot(result: r)).toList(),
              ),
            ],
          ),
          // Detailed match list: prefer async ESPN data; fallback to recentScores from rolling stats
          if (recentMatches.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final m in recentMatches) _MatchResultRow(match: m, accentColor: accentColor),
          ] else if (recentScores.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final s in recentScores.take(10))
              _ScoreStringRow(scoreStr: s, allowDraw: allowDraw),
          ] else ...[
            const SizedBox(height: 8),
            Text('近況：${recentResults.join(' ')}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ],
        ],
      ),
    );
  }
}

class _MatchResultRow extends StatelessWidget {
  const _MatchResultRow({required this.match, required this.accentColor});
  final Map<String, dynamic> match;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final opponent = match['opponent'] as String? ?? '';
    final teamScore = match['teamScore'] as int? ?? 0;
    final oppScore = match['oppScore'] as int? ?? 0;
    final isHome = match['isHome'] as bool? ?? false;
    final date = match['date'] as String? ?? '';
    final result = match['result'] as String? ?? '';

    Color resultColor;
    switch (result) {
      case '勝': resultColor = const Color(0xFF3DDC97); break;
      case '平': resultColor = Colors.orange; break;
      default:   resultColor = const Color(0xFFFF5252);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 40,
              child: Text(date, style: const TextStyle(color: Colors.white38, fontSize: 10))),
          Container(
            width: 22,
            height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(isHome ? '主' : '客',
                style: const TextStyle(color: Colors.white54, fontSize: 9)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(opponent,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          Text('$teamScore - $oppScore',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(
            width: 22,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: resultColor.withAlpha(40),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: resultColor.withAlpha(120)),
            ),
            child: Text(result, style: TextStyle(color: resultColor, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Displays a single score string like "112-105 湖人" with win/loss color chip.
/// Format: "`myScore`-`oppScore` `opponentName`"
class _ScoreStringRow extends StatelessWidget {
  const _ScoreStringRow({required this.scoreStr, this.allowDraw = false});
  final String scoreStr;
  final bool allowDraw;

  @override
  Widget build(BuildContext context) {
    // Parse "myScore-oppScore opponentName"
    final parts = scoreStr.split(' ');
    final scorePart = parts.first; // e.g. "112-105"
    final opponentName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final scores = scorePart.split('-');
    final my = int.tryParse(scores.isNotEmpty ? scores[0] : '');
    final opp = int.tryParse(scores.length > 1 ? scores[1] : '');

    String result = '';
    Color resultColor = Colors.white54;
    if (my != null && opp != null) {
      if (my > opp) {
        result = '勝';
        resultColor = const Color(0xFF3DDC97);
      } else if (allowDraw && my == opp) {
        result = '平';
        resultColor = Colors.orange;
      } else {
        result = '負';
        resultColor = const Color(0xFFFF5252);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              opponentName.isNotEmpty ? 'vs $opponentName' : 'vs —',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(scorePart,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          if (result.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: resultColor.withAlpha(40),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: resultColor.withAlpha(120)),
              ),
              child: Text(result,
                  style: TextStyle(color: resultColor, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultDot extends StatelessWidget {
  const _ResultDot({required this.result});
  final String result;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (result) {
      case '勝': color = const Color(0xFF3DDC97); break;
      case '平': color = Colors.orange; break;
      default:   color = const Color(0xFFFF5252);
    }
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(left: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withAlpha(40), shape: BoxShape.circle,
          border: Border.all(color: color.withAlpha(160))),
      child: Text(result[0], style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final isHot = label.contains('🔥');
    final isCold = label.contains('❄️');
    final color = isHot ? const Color(0xFFFF6B35) : (isCold ? const Color(0xFF4FC3F7) : Colors.white60);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// H2H 對戰面板
// ─────────────────────────────────────────────────────────────────────────────

class _H2HPanel extends StatelessWidget {
  const _H2HPanel({required this.fixture, required this.h2hMatches});
  final MatchFixture fixture;
  final List<Map<String, dynamic>> h2hMatches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final preloadedHasH2H = f.h2hHomeWins + f.h2hAwayWins + f.h2hDraws > 0;

    // Compute aggregate from detailed list if preloaded data unavailable
    final schedHomeWins = h2hMatches.where((m) => m['result'] == '主勝').length;
    final schedAwayWins = h2hMatches.where((m) => m['result'] == '客勝').length;
    final schedDraws = h2hMatches.where((m) => m['result'] == '平').length;
    final useScheduleH2H = !preloadedHasH2H && h2hMatches.isNotEmpty;

    final displayHomeWins = preloadedHasH2H ? f.h2hHomeWins : schedHomeWins;
    final displayAwayWins = preloadedHasH2H ? f.h2hAwayWins : schedAwayWins;
    final displayDraws = preloadedHasH2H ? f.h2hDraws : schedDraws;
    final hasH2H = preloadedHasH2H || useScheduleH2H;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasH2H) ...[
            // Summary bar
            Row(
              children: [
                Expanded(child: _H2HBar(
                  homeWins: displayHomeWins,
                  draws: displayDraws,
                  awayWins: displayAwayWins,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${f.homeTeam} $displayHomeWins勝',
                    style: const TextStyle(color: AppTheme.primaryAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                if (f.sport == SportType.football && displayDraws > 0)
                  Text('$displayDraws平',
                      style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
                Text('$displayAwayWins勝 ${f.awayTeam}',
                    style: const TextStyle(color: AppTheme.highlight, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
            if (f.sport == SportType.football && f.h2hAvgGoals > 0) ...[
              const SizedBox(height: 6),
              Text('近期 H2H 平均總進球 ${f.h2hAvgGoals.toStringAsFixed(1)} 球',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38)),
            ],
          ] else ...[
            Text('歷史對戰記錄載入中…', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38)),
          ],
          // Detailed H2H match list
          if (h2hMatches.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            const SizedBox(height: 8),
            for (final m in h2hMatches)
              _H2HMatchRow(match: m, homeTeam: f.homeTeam),
          ],
          if (f.espnHomePct > 0) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.sports_score_rounded, size: 13, color: Colors.white38),
                const SizedBox(width: 6),
                Text('ESPN 預測主隊勝率：${(f.espnHomePct * 100).round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _H2HBar extends StatelessWidget {
  const _H2HBar({required this.homeWins, required this.draws, required this.awayWins});
  final int homeWins;
  final int draws;
  final int awayWins;

  @override
  Widget build(BuildContext context) {
    final total = homeWins + draws + awayWins;
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          Flexible(
            flex: homeWins,
            child: Container(height: 10, color: AppTheme.primaryAccent.withAlpha(200)),
          ),
          if (draws > 0)
            Flexible(
              flex: draws,
              child: Container(height: 10, color: Colors.orange.withAlpha(180)),
            ),
          Flexible(
            flex: awayWins,
            child: Container(height: 10, color: AppTheme.highlight.withAlpha(200)),
          ),
        ],
      ),
    );
  }
}

class _H2HMatchRow extends StatelessWidget {
  const _H2HMatchRow({required this.match, required this.homeTeam});
  final Map<String, dynamic> match;
  final String homeTeam;

  @override
  Widget build(BuildContext context) {
    final home = match['home'] as String? ?? '';
    final away = match['away'] as String? ?? '';
    final hs = match['homeScore'] as int? ?? 0;
    final as_ = match['awayScore'] as int? ?? 0;
    final date = match['date'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 54, child: Text(date, style: const TextStyle(color: Colors.white30, fontSize: 10))),
          Expanded(
            child: Text(home,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
          Text('$hs - $as_',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          Expanded(
            child: Text(away,
                textAlign: TextAlign.end,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 棒球先發投手對比面板
// ─────────────────────────────────────────────────────────────────────────────

class _PitcherPanel extends StatelessWidget {
  const _PitcherPanel({required this.fixture});
  final MatchFixture fixture;

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    // 推算 ERA：有 ESPN 數據用真實數據；無則從球隊近期失分均值估算
    String deriveEra(String espnEra, double avgConceded, double? last3) {
      if (espnEra.isNotEmpty) return espnEra;
      final base = last3 ?? avgConceded;
      if (base <= 0) return '';
      return (base / 0.85).clamp(2.5, 8.0).toStringAsFixed(2);
    }
    final homeEra = deriveEra(f.homeProbableEra, f.homeForm.averageConceded, f.homeForm.last3AvgConceded);
    final awayEra = deriveEra(f.awayProbableEra, f.awayForm.averageConceded, f.awayForm.last3AvgConceded);
    final homeInferred = f.homeProbableEra.isEmpty && homeEra.isNotEmpty;
    final awayInferred = f.awayProbableEra.isEmpty && awayEra.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _panelDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('先發投手對比',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
            if (homeInferred || awayInferred) ...[
              const SizedBox(width: 6),
              const Text('（ERA 由近期失分推算）',
                  style: TextStyle(color: Colors.white30, fontSize: 9)),
            ],
          ]),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _pitcherCard(f.homeTeam, f.homeProbablePitcher, homeEra,
                  f.homeProbableWhip, f.homeProbableK9, f.homeProbableWins, f.homeProbableLosses,
                  homeInferred, AppTheme.primaryAccent)),
              const SizedBox(width: 8),
              Expanded(child: _pitcherCard(f.awayTeam, f.awayProbablePitcher, awayEra,
                  f.awayProbableWhip, f.awayProbableK9, f.awayProbableWins, f.awayProbableLosses,
                  awayInferred, AppTheme.highlight)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pitcherCard(String teamName, String name, String era, String whip, String k9,
      String wins, String losses, bool inferred, Color accent) {
    final eraVal = double.tryParse(era);
    final eraColor = eraVal == null
        ? Colors.white54
        : eraVal <= 3.00
            ? Colors.greenAccent
            : eraVal <= 4.50
                ? Colors.white70
                : Colors.redAccent;
    final eraLabel = inferred ? '≈$era' : era; // 推算值加「≈」標示
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(teamName,
              style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(name.isNotEmpty ? name : (inferred ? '未公告' : '—'),
              style: TextStyle(
                  color: inferred ? Colors.white38 : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
          if (wins.isNotEmpty || losses.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('${wins.isNotEmpty ? wins : "0"}勝${losses.isNotEmpty ? losses : "0"}敗',
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
          const SizedBox(height: 6),
          _statChip('ERA', eraLabel.isNotEmpty ? eraLabel : '—', eraColor),
          const SizedBox(height: 3),
          _statChip('WHIP', whip.isNotEmpty ? whip : '—', Colors.white60),
          const SizedBox(height: 3),
          _statChip('K/9', k9.isNotEmpty ? k9 : '—', Colors.white60),
        ],
      ),
    );
  }

  Widget _statChip(String label, String val, Color color) {
    return Row(
      children: [
        Text('$label ', style: const TextStyle(color: Colors.white38, fontSize: 10)),
        Text(val.isNotEmpty ? val : '—', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 泊松比數矩陣面板
// ─────────────────────────────────────────────────────────────────────────────

class _PoissonMatrixPanel extends StatelessWidget {
  const _PoissonMatrixPanel({required this.prediction});
  final MatchPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final scores = prediction.topScores;
    if (scores.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: _panelDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('泊松分佈比數矩陣（機率最高前3組合）',
              style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          for (int i = 0; i < scores.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 20, height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 0 ? AppTheme.highlight.withAlpha(60) : Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            color: i == 0 ? AppTheme.highlight : Colors.white38,
                            fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${scores[i].h} : ${scores[i].a}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  Text('${(scores[i].prob * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: i == 0 ? AppTheme.highlight : Colors.white54,
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 最終預測面板
// ─────────────────────────────────────────────────────────────────────────────

class _FinalPredictionPanel extends StatelessWidget {
  const _FinalPredictionPanel({required this.fixture, required this.prediction});
  final MatchFixture fixture;
  final MatchPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final p = prediction;
    final odds = f.odds;
    final isFootball = f.sport == SportType.football;

    // Winner determination
    final homeP = odds.fairHomeProb > 0.05 ? odds.fairHomeProb : p.ensembleHomeWinPct;
    final awayP = odds.fairAwayProb > 0.05 ? odds.fairAwayProb : p.ensembleAwayWinPct;
    final drawP = isFootball ? (odds.fairDrawProb > 0.05 ? odds.fairDrawProb : p.ensembleDrawPct) : 0.0;

    final isDrawFavored = isFootball && odds.draw > 0 && odds.draw < 99 &&
        odds.draw <= odds.homeWin && odds.draw <= odds.awayWin;
    final isDraw = isDrawFavored || (isFootball && drawP > homeP && drawP > awayP);
    final homeWins = !isDraw && homeP >= awayP;

    // ── 預測比分（足球）/ 大小分（棒球籃球）────────────────────────
    // 足球：用盤口大小分 × 勝率比推算預測比分
    // 棒球/籃球：不顯示精確比分，改顯示「預測大/小分」+ 勝分差
    final bool hasRealLine = odds.overLine > 0 && odds.bookmakerName != '模型推算';
    final String lineStr = hasRealLine
        ? (odds.overLine % 1 == 0
            ? odds.overLine.toInt().toString()
            : odds.overLine.toStringAsFixed(1))
        : '';

    // 足球：預測比分卡片
    String scoreLabel = '';
    if (isFootball) {
      if (hasRealLine) {
        // 用盤口總分 × 勝率比分配主客得分
        final total = odds.overLine;
        final ratio = (homeP / (homeP + awayP)).clamp(0.20, 0.80);
        final h = (total * ratio).round();
        final a = (total - h).round();
        // 確保勝負方向正確
        if (homeWins && h <= a) {
          scoreLabel = '${a + 1} : $a';
        } else if (!homeWins && !isDraw && a <= h) {
          scoreLabel = '$h : ${h + 1}';
        } else if (isDraw) {
          final g = ((h + a) / 2).round();
          scoreLabel = '$g : $g';
        } else {
          scoreLabel = '$h : $a';
        }
      } else if (p.marketHomeExp > 0 && p.marketAwayExp > 0) {
        scoreLabel = '${p.marketHomeExp.round()} : ${p.marketAwayExp.round()}';
      } else {
        scoreLabel = '${p.predictedHomeScore} : ${p.predictedAwayScore}';
      }
    }

    // 大小分標籤（所有運動）
    // 將 AI 模型預測總分與盤口比較，判斷「預測大/小分」
    String ouLabel = '';
    if (hasRealLine) {
      final unit = isFootball ? '球' : '分';
      final ai = p.aiTotalExpected;
      final line = odds.overLine;
      // 差距超過 3% 才給出明確大/小方向
      if (ai > line * 1.03) {
        ouLabel = '預測大$lineStr$unit';
      } else if (ai < line * 0.97) {
        ouLabel = '預測小$lineStr$unit';
      } else {
        ouLabel = '盤口$lineStr$unit（中性）';
      }
    } else if (f.sport == SportType.baseball || f.sport == SportType.basketball) {
      ouLabel = '暫無盤口';
    }

    // 勝分差標籤（棒球 / 籃球）
    // 用 predictedMargin（勝率差 × 比例係數）推算，每場比賽依強弱不同
    String spreadLabel = '';
    if (!isFootball) {
      final margin = p.predictedMargin.abs();
      final winner = homeWins ? f.homeTeam : f.awayTeam;
      final short = winner.length > 4 ? '${winner.substring(0, 4)}..' : winner;
      if (f.sport == SportType.baseball) {
        final runs = margin < 0.75 ? '1分以內'
            : margin < 1.5  ? '約1分'
            : margin < 2.5  ? '約2分'
            : margin < 3.5  ? '約3分'
            : '4分以上';
        spreadLabel = '$short $runs';
      } else if (f.sport == SportType.basketball) {
        // 籃球：優先用賭盤讓分，若讓分為標準值則用模型
        final hasRealSpread = odds.spread != 0.0 && odds.bookmakerName != '模型推算';
        final displayMargin = hasRealSpread ? odds.spread.abs() : margin;
        final pts = displayMargin < 3.5   ? '1-3分'
            : displayMargin < 6.5   ? '4-6分'
            : displayMargin < 10.5  ? '7-10分'
            : displayMargin < 15.5  ? '11-15分'
            : displayMargin < 20.5  ? '16-20分'
            : '20分以上';
        spreadLabel = '$short $pts';
      }
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2B50), Color(0xFF0E1A35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryAccent.withAlpha(60)),
      ),
      child: Column(
        children: [
          // Winner card
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(isDraw ? '🤝 和局' : (homeWins ? '🏠 主場 ${f.homeTeam}' : '✈️ 客場 ${f.awayTeam}'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  isDraw
                      ? '看好平局 ${(drawP * 100).round().clamp(20, 65)}%'
                      : (homeWins
                          ? '${(homeP * 100).round().clamp(40, 99)}% 勝率'
                          : '${(awayP * 100).round().clamp(40, 99)}% 勝率'),
                  style: TextStyle(
                      color: isDraw ? Colors.orange : AppTheme.primaryAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                if (isFootball && scoreLabel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.highlight.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.highlight.withAlpha(80)),
                    ),
                    child: Text(scoreLabel,
                        style: const TextStyle(
                            color: AppTheme.highlight,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x22FFFFFF)),
          // O/U + spread row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                if (ouLabel.isNotEmpty) ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('大小分', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(ouLabel,
                            style: TextStyle(
                                color: ouLabel.contains('大') ? Colors.redAccent
                                    : ouLabel.contains('小') ? Colors.lightBlueAccent
                                    : Colors.white54,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
                if (spreadLabel.isNotEmpty) ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('勝分差', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(spreadLabel,
                            style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Summary
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(p.summary,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

BoxDecoration _panelDecor() => BoxDecoration(
      color: const Color(0xFF0D1B35),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x33FFFFFF)),
    );

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.highlight),
            const SizedBox(width: 6),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      alignment: Alignment.center,
      decoration: _panelDecor(),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.highlight)),
          SizedBox(width: 12),
          Text('載入統計資料中…', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

class _NoDataPanel extends StatelessWidget {
  const _NoDataPanel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      alignment: Alignment.center,
      decoration: _panelDecor(),
      child: Text(message, style: const TextStyle(color: Colors.white38, fontSize: 12)),
    );
  }
}
