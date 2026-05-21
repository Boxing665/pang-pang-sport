import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/match_fixture.dart';
import '../models/prediction_log.dart';
import '../services/ai_prediction_service.dart';
import '../services/bingo_service.dart';
import '../services/lottery_service.dart';
import '../services/pang_pang_sports_service.dart';
import '../services/prediction_log_service.dart';
import '../services/real_data_service.dart';
import '../services/self_learning_service.dart';

/// 圖表分析頁面：體育 / 539 / 賓果的預測 vs 實際比對圖表
/// 讓用戶視覺化地看到哪裡命中、哪裡失誤，幫助 AI 修正數據提高命中率
class ChartAnalysisScreen extends StatefulWidget {
  const ChartAnalysisScreen({super.key});
  @override
  State<ChartAnalysisScreen> createState() => _ChartAnalysisScreenState();
}

class _ChartAnalysisScreenState extends State<ChartAnalysisScreen>
    with SingleTickerProviderStateMixin {
  final _svc        = PredictionLogService();
  final _aiSvc      = AiPredictionService.instance;
  final _sportsSvc  = PangPangSportsService();
  final _lotterySvc = LotteryService();
  final _bingoSvc   = BingoService();

  late TabController _tabCtrl;
  List<PredictionLog> _all = [];
  bool _loading = true;
  bool _learning = false;   // 自我學習進行中

  static const _bg   = Color(0xFF050E24);
  static const _bg1  = Color(0xFF0D1E4A);
  static const _gold = Color(0xFFFFD700);
  static const _cyan = Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // ── A: 體育 ──────────────────────────────────────────────────
    try {
      final upcoming = await _sportsSvc.getMatchesForDays(days: 5);
      final past     = await RealDataService.fetchPastMatchesForDays(daysBack: 30);
      final seen     = <String>{};
      final matches  = [...upcoming, ...past]
          .where((m) => seen.add(m.id))
          .toList();

      // 對未完賽場次：產生預測
      for (final match in matches) {
        if (match.status == MatchStatus.completed) continue;
        try {
          final pred = _sportsSvc.predictMatch(match);
          final ph = pred.predictedHomeScore;
          final pa = pred.predictedAwayScore;
          if (ph == 0 && pa == 0) continue;
          final winner = ph > pa ? 'home' : ph < pa ? 'away' : 'draw';
          final ol = match.odds.overLine;
          final ouCall = ol > 0
              ? (pred.aiTotalExpected > ol * 1.03
                  ? 'over'
                  : pred.aiTotalExpected < ol * 0.97 ? 'under' : '')
              : '';
          final adaptiveStrategy = pred.keyFactors
              .firstWhere((f) => f.startsWith('__adaptive_strategy:'),
                  orElse: () => '__adaptive_strategy:strategy_b')
              .replaceFirst('__adaptive_strategy:', '');
          await _svc.saveSportPrediction(
            matchId:          match.id,
            homeTeam:         match.homeTeam,
            awayTeam:         match.awayTeam,
            league:           match.league,
            matchTime:        match.startTime,
            predictedHome:    ph,
            predictedHomeRaw: ph,
            predictedAway:    pa,
            predictedAwayRaw: pa,
            confidence:       pred.confidence,
            sportType:        match.sport.name,
            winner:           winner,
            mcHomeWinPct:     pred.monteCarloHomeWinPct,
            mcDrawPct:        pred.monteCarloDrawPct,
            mcAwayWinPct:     pred.monteCarloAwayWinPct,
            ouCall:           ouCall,
            overLine:         ol,
            adaptiveStrategy: adaptiveStrategy,
          );
        } catch (_) {}
      }

      // 對已完賽場次：回溯產生預測並立即確認（讓準確率圖表有歷史數據）
      final completedMatches = matches
          .where((m) => m.status == MatchStatus.completed && (m.homeScore > 0 || m.awayScore > 0))
          .toList();
      for (final match in completedMatches) {
        try {
          final pred = _sportsSvc.predictMatch(match);
          final ph = pred.predictedHomeScore;
          final pa = pred.predictedAwayScore;
          if (ph == 0 && pa == 0) continue;
          final winner = ph > pa ? 'home' : ph < pa ? 'away' : 'draw';
          final ol = match.odds.overLine;
          final ouCall = ol > 0
              ? (pred.aiTotalExpected > ol * 1.03
                  ? 'over'
                  : pred.aiTotalExpected < ol * 0.97 ? 'under' : '')
              : '';
          final adaptiveStrategy = pred.keyFactors
              .firstWhere((f) => f.startsWith('__adaptive_strategy:'),
                  orElse: () => '__adaptive_strategy:strategy_b')
              .replaceFirst('__adaptive_strategy:', '');
          await _svc.saveSportPrediction(
            matchId:          match.id,
            homeTeam:         match.homeTeam,
            awayTeam:         match.awayTeam,
            league:           match.league,
            matchTime:        match.startTime,
            predictedHome:    ph,
            predictedHomeRaw: ph,
            predictedAway:    pa,
            predictedAwayRaw: pa,
            confidence:       pred.confidence,
            sportType:        match.sport.name,
            winner:           winner,
            mcHomeWinPct:     pred.monteCarloHomeWinPct,
            mcDrawPct:        pred.monteCarloDrawPct,
            mcAwayWinPct:     pred.monteCarloAwayWinPct,
            ouCall:           ouCall,
            overLine:         ol,
            adaptiveStrategy: adaptiveStrategy,
          );
        } catch (_) {}
      }

      // 回填已完賽實際比分
      final sportScores = <String, (int, int)>{
        for (final m in completedMatches)
          m.id: (m.homeScore, m.awayScore),
      };
      await _svc.autoReportSportsByMatchId(sportScores);
    } catch (_) {}

    // ── B: 539 樂透 ─── 下期預測 + 近 30 期回溯預測 ───────────────
    try {
      final lotteryData = await _lotterySvc.fetchAndAnalyze();
      final records = lotteryData.records539;

      if (records.isNotEmpty) {
        // 回溯：對近 30 期每一期，用更舊的資料模擬預測
        final retroCount = records.length.clamp(0, 30);
        for (var i = 1; i <= retroCount; i++) {
          final historical = records.skip(i).take(60).toList();
          if (historical.length < 5) continue;
          final targetRecord = records[i - 1];
          if (targetRecord.date.isEmpty || targetRecord.numbers.isEmpty) continue;
          try {
            final currentDraws = historical.map((r) =>
                <String, dynamic>{'numbers': r.numbers, 'date': r.date}).toList();
            final lp = await _aiSvc.predictLottery(recentDraws: currentDraws);
            if (!lp.hasError && lp.recommendedNumbers.isNotEmpty) {
              await _svc.saveLotteryPrediction(
                lotteryType: '539',
                drawNo:      targetRecord.date,
                numbers:     lp.recommendedNumbers,
              );
            }
          } catch (_) {}
        }

        // 下期預測
        final now = DateTime.now().toUtc().add(const Duration(hours: 8));
        var nextDraw = DateTime(now.year, now.month, now.day);
        if (now.hour >= 20) nextDraw = nextDraw.add(const Duration(days: 1));
        if (nextDraw.weekday == DateTime.sunday) {
          nextDraw = nextDraw.add(const Duration(days: 1));
        }
        final drawKey =
            '${nextDraw.month.toString().padLeft(2, '0')}/${nextDraw.day.toString().padLeft(2, '0')}';
        try {
          final currentDraws = records.take(60).map((r) =>
              <String, dynamic>{'numbers': r.numbers, 'date': r.date}).toList();
          final lp = await _aiSvc.predictLottery(recentDraws: currentDraws);
          if (!lp.hasError && lp.recommendedNumbers.isNotEmpty) {
            await _svc.saveLotteryPrediction(
              lotteryType: '539',
              drawNo:      drawKey,
              numbers:     lp.recommendedNumbers,
            );
          }
        } catch (_) {}

        // 回填實際開獎結果
        final lottoByDate = <String, List<int>>{
          for (final r in records)
            if (r.date.isNotEmpty && r.numbers.isNotEmpty) r.date: r.numbers,
        };
        await _svc.autoReportLotteryByDate(lottoByDate);
      }
    } catch (_) {}

    // ── C: 賓果 ────────────────────────────────────────────────────
    try {
      final bingoRecs = await _bingoSvc.fetchRecent(forceRefresh: true);

      if (bingoRecs.isNotEmpty) {
        final bingoStrategy = await SelfLearningService.getRecommendedBingoStrategy();

        // 回溯預測：對近 15 期每一期，用更舊的記錄模擬預測
        final retroCount = bingoRecs.length.clamp(0, 15);
        for (var i = 1; i <= retroCount; i++) {
          final historical = bingoRecs.skip(i).take(50).toList();
          if (historical.length < 5) continue;
          final targetDrawNo = bingoRecs[i - 1].drawNo;
          try {
            final pred = BingoService.analyze(historical, seed: 0, strategyMode: bingoStrategy);
            if (pred.recommended.isNotEmpty) {
              await _svc.saveBingoPrediction(
                drawNo:     targetDrawNo,
                groupLabel: '綜合',
                numbers:    pred.recommended,
              );
            }
            if (pred.carryOverNumbers.isNotEmpty) {
              await _svc.saveBingoPrediction(
                drawNo:     targetDrawNo,
                groupLabel: '拖牌',
                numbers:    pred.carryOverNumbers,
              );
            }
          } catch (_) {}
        }

        // 下期預測
        try {
          final pred = BingoService.analyze(bingoRecs.take(50).toList(), seed: 0, strategyMode: bingoStrategy);
          if (pred.nextDrawNo > 0 && pred.recommended.isNotEmpty) {
            await _svc.saveBingoPrediction(
              drawNo:     pred.nextDrawNo,
              groupLabel: '綜合',
              numbers:    pred.recommended,
            );
            if (pred.carryOverNumbers.isNotEmpty) {
              await _svc.saveBingoPrediction(
                drawNo:     pred.nextDrawNo,
                groupLabel: '拖牌',
                numbers:    pred.carryOverNumbers,
              );
            }
          }
        } catch (_) {}

        // 回填實際開獎結果
        final bingoByDrawNo = <int, List<int>>{
          for (final r in bingoRecs)
            if (r.numbers.isNotEmpty) r.drawNo: r.numbers,
        };
        await _svc.autoReportBingoByDrawNo(bingoByDrawNo);
      }
    } catch (_) {}

    // ── D: 載入全部記錄更新圖表 ───────────────────────────────────
    final all = await _svc.loadAll();
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
    });

    // ── E: 自我學習：對預測失敗的場次調整訊號權重 ──────────────────
    // 在背景執行，每小時最多一次，不阻塞 UI
    _triggerSelfLearning();
  }

  Future<void> _triggerSelfLearning() async {
    if (_learning) return;
    if (!mounted) return;
    setState(() => _learning = true);
    try {
      await SelfLearningService.runInBackground(_svc);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _learning = false);
  }

  List<PredictionLog> get _sports =>
      _all.where((l) => l.type == PredictionType.sport).toList();
  List<PredictionLog> get _lottery =>
      _all.where((l) => l.type == PredictionType.lottery).toList();
  List<PredictionLog> get _bingo =>
      _all.where((l) => l.type == PredictionType.bingo).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bg, _bg1],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              _tabBarW(),
              if (!_loading) _aiLearningCenter(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: _gold))
                    : TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _SportChartTab(logs: _sports),
                          _LotteryChartTab(logs: _lottery),
                          _BingoChartTab(logs: _bingo),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── AI 學習中心（所有分頁都顯示）────────────────────────────────

  Widget _aiLearningCenter() {
    final sports  = _sports;
    final lottery = _lottery;
    final bingo   = _bingo;

    int judgedCount(List<PredictionLog> logs) =>
        logs.where((l) => l.outcome != PredictionOutcome.pending).length;
    double hitRate(List<PredictionLog> logs) {
      final j = judgedCount(logs);
      if (j == 0) return 0;
      final c = logs.where((l) => l.outcome == PredictionOutcome.correct).length;
      final p = logs.where((l) => l.outcome == PredictionOutcome.partial).length;
      return (c + p * 0.5) / j;
    }

    final sRate = hitRate(sports);
    final lRate = hitRate(lottery);
    final bRate = hitRate(bingo);

    Color rateColor(double r) =>
        r >= 0.55 ? const Color(0xFF3DDC97) : r >= 0.40 ? Colors.orange : Colors.red.shade400;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withAlpha(40)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('🤖 AI 學習中心',
                  style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              if (_learning)
                const Row(children: [
                  SizedBox(
                    width: 9, height: 9,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF3DDC97)),
                  ),
                  SizedBox(width: 4),
                  Text('學習中', style: TextStyle(color: Color(0xFF3DDC97), fontSize: 10)),
                ]),
              const Spacer(),
              GestureDetector(
                onTap: _loading ? null : _triggerSelfLearning,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _cyan.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _cyan.withAlpha(80)),
                  ),
                  child: const Text('全部重新學習',
                      style: TextStyle(color: _cyan, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniRate('⚽🏀⚾', '體育', sRate, rateColor(sRate)),
              const SizedBox(width: 8),
              _miniRate('🎰', '539', lRate, rateColor(lRate)),
              const SizedBox(width: 8),
              _miniRate('🎱', '賓果', bRate, rateColor(bRate)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniRate(String icon, String label, double rate, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(children: [
          Text('$icon $label',
              style: const TextStyle(color: Colors.white60, fontSize: 10)),
          const SizedBox(height: 2),
          Text('${(rate * 100).round()}%',
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }


  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Row(children: [
          const Text('📊 圖表分析',
              style: TextStyle(
                  color: _gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
          const SizedBox(width: 8),
          if (!_loading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _all.isEmpty
                    ? Colors.red.withAlpha(40)
                    : Colors.white.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _all.isEmpty ? '無資料' : '共 ${_all.length} 筆',
                style: TextStyle(
                    color: _all.isEmpty ? Colors.red.shade300 : Colors.white54,
                    fontSize: 10),
              ),
            ),
          const Spacer(),
          if (_learning)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Row(children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF3DDC97)),
                ),
                SizedBox(width: 4),
                Text('自我學習中',
                    style: TextStyle(color: Color(0xFF3DDC97), fontSize: 10)),
              ]),
            ),
          IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _cyan),
              onPressed: _loading ? null : _load),
        ]),
      );

  Widget _tabBarW() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(12)),
        child: TabBar(
          controller: _tabCtrl,
          indicator: BoxDecoration(
              color: _gold.withAlpha(40),
              borderRadius: BorderRadius.circular(10)),
          labelColor: _gold,
          unselectedLabelColor: Colors.white38,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: '⚽🏀⚾ 體育'),
            Tab(text: '🎰 539'),
            Tab(text: '🎱 賓果'),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
// Sports tab
// ══════════════════════════════════════════════════════════════════

class _SportChartTab extends StatelessWidget {
  final List<PredictionLog> logs;
  const _SportChartTab({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return _emptyView(
        '尚無體育預測記錄',
        hint: '開啟圖表分析頁 → 點擊重新整理即可自動儲存近期比賽預測',
      );
    }

    final judged   = logs.where((l) => l.outcome != PredictionOutcome.pending).toList();
    final correct  = judged.where((l) => l.outcome == PredictionOutcome.correct).length;
    final partial  = judged.where((l) => l.outcome == PredictionOutcome.partial).length;
    final incorrect = judged.where((l) => l.outcome == PredictionOutcome.incorrect).length;
    final pending  = logs.where((l) => l.outcome == PredictionOutcome.pending).length;

    // Football (score prediction) vs other (winner+spread)
    final football    = logs.where((l) => l.details['sport'] == 'football').toList();
    final ballSports  = logs.where((l) => l.details['sport'] != 'football').toList();

    // Football score records (confirmed)
    final footballScores = football
        .where((l) => l.details.containsKey('actualHomeScore'))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        _sectionTitle('整體勝負預測準確率'),
        const SizedBox(height: 8),
        _AccuracyPanel(correct: correct, partial: partial, incorrect: incorrect, pending: pending),
        const SizedBox(height: 16),
        _SportTypeBreakdown(logs: logs),
        const SizedBox(height: 16),
        _BookmakerLogicPanel(logs: judged),
        if (footballScores.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('⚽ 足球波單比分 vs 實際（近 ${footballScores.take(15).length} 場）'),
          const SizedBox(height: 8),
          _ScoreComparisonChart(logs: footballScores.take(15).toList().reversed.toList()),
        ],
        if (ballSports.isNotEmpty) ...[
          const SizedBox(height: 16),
          // 有實際比分的籃球/棒球場次 → 同足球一樣顯示「預測分 vs 實際分」比對圖
          () {
            final withScore = ballSports
                .where((l) => l.details.containsKey('actualHomeScore'))
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            if (withScore.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('🏀⚾ 籃球/棒球 預測比分 vs 實際（近 ${withScore.take(15).length} 場）'),
                const SizedBox(height: 8),
                _ScoreComparisonChart(logs: withScore.take(15).toList().reversed.toList()),
              ],
            );
          }(),
          const SizedBox(height: 16),
          _sectionTitle('🏀⚾ 籃球/棒球 近期記錄'),
          const SizedBox(height: 6),
          ...ballSports.take(12).map((l) => _BallSportRow(log: l)),
        ],
        if (football.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('⚽ 足球近期記錄'),
          const SizedBox(height: 6),
          ...football.take(8).map((l) => _CompactLogRow(log: l, numberCount: 0)),
        ],
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Lottery (539) tab
// ══════════════════════════════════════════════════════════════════

class _LotteryChartTab extends StatelessWidget {
  final List<PredictionLog> logs;
  const _LotteryChartTab({required this.logs});

  @override
  Widget build(BuildContext context) {
    final judged =
        logs.where((l) => l.outcome != PredictionOutcome.pending).toList();
    final correct =
        judged.where((l) => l.outcome == PredictionOutcome.correct).length;
    final partial =
        judged.where((l) => l.outcome == PredictionOutcome.partial).length;
    final incorrect =
        judged.where((l) => l.outcome == PredictionOutcome.incorrect).length;
    final pending =
        logs.where((l) => l.outcome == PredictionOutcome.pending).length;

    // Accumulate predicted and drawn counts per number 1-39
    final predCount = <int, int>{};
    final drawnCount = <int, int>{};
    for (final l in logs) {
      final nums = _parseNums(l.predictedResult);
      for (final n in nums) {
        predCount[n] = (predCount[n] ?? 0) + 1;
      }
      if (l.actualResult != null) {
        final actual = _parseNums(l.actualResult!);
        for (final n in actual) {
          drawnCount[n] = (drawnCount[n] ?? 0) + 1;
        }
      }
    }

    if (logs.isEmpty) {
      return _emptyView('尚無 539 預測記錄',
          hint: '開啟樂透頁面即可自動儲存預測');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        _sectionTitle('539 命中率'),
        const SizedBox(height: 8),
        _AccuracyPanel(
            correct: correct,
            partial: partial,
            incorrect: incorrect,
            pending: pending),
        const SizedBox(height: 16),
        _sectionTitle('號碼頻率圖（藍=預測次數 / 綠=實際開出次數）'),
        const SizedBox(height: 8),
        _NumberFreqChart(
            predCount: predCount,
            drawnCount: drawnCount,
            maxNum: 39),
        const SizedBox(height: 16),
        _sectionTitle('近期記錄'),
        const SizedBox(height: 6),
        ...logs
            .take(12)
            .map((l) => _CompactLogRow(log: l, numberCount: 5)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Bingo tab
// ══════════════════════════════════════════════════════════════════

class _BingoChartTab extends StatelessWidget {
  final List<PredictionLog> logs;
  const _BingoChartTab({required this.logs});

  @override
  Widget build(BuildContext context) {
    final judged =
        logs.where((l) => l.outcome != PredictionOutcome.pending).toList();
    final correct =
        judged.where((l) => l.outcome == PredictionOutcome.correct).length;
    final partial =
        judged.where((l) => l.outcome == PredictionOutcome.partial).length;
    final incorrect =
        judged.where((l) => l.outcome == PredictionOutcome.incorrect).length;
    final pending =
        logs.where((l) => l.outcome == PredictionOutcome.pending).length;

    final predCount = <int, int>{};
    final drawnCount = <int, int>{};
    for (final l in logs) {
      final nums = _parseNums(l.predictedResult);
      for (final n in nums) {
        predCount[n] = (predCount[n] ?? 0) + 1;
      }
      if (l.actualResult != null) {
        final actual = _parseNums(l.actualResult!);
        for (final n in actual) {
          drawnCount[n] = (drawnCount[n] ?? 0) + 1;
        }
      }
    }

    if (logs.isEmpty) {
      return _emptyView('尚無賓果預測記錄',
          hint: '開啟賓果頁面即可自動儲存預測');
    }

    // 計算每局命中數（用於趨勢圖）
    final hitHistory = <int>[];
    for (final l in judged.reversed) {
      final pred   = _parseNums(l.predictedResult);
      final actual = l.actualResult != null ? _parseNums(l.actualResult!).toSet() : <int>{};
      hitHistory.add(pred.where((n) => actual.contains(n)).length);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        _sectionTitle('賓果命中率'),
        const SizedBox(height: 8),
        _AccuracyPanel(
            correct: correct,
            partial: partial,
            incorrect: incorrect,
            pending: pending),
        const SizedBox(height: 16),

        // ── 命中趨勢折線 ──────────────────────────────────────────
        if (hitHistory.length >= 3) ...[
          _sectionTitle('命中數走勢（每局預測 6 個）'),
          const SizedBox(height: 8),
          _HitTrendChart(hitHistory: hitHistory),
          const SizedBox(height: 16),
        ],

        // ── 區間命中率 + 強制換策略 ───────────────────────────────
        _sectionTitle('區間命中率分析'),
        const SizedBox(height: 8),
        _BingoZoneHitRate(predCount: predCount, drawnCount: drawnCount),
        const SizedBox(height: 8),
        // 策略已由 SelfLearningService 自動管理，不需手動切換
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '💡 策略自動管理：近 5 局平均命中 < 1.5 顆時程式自動切換',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
        const SizedBox(height: 12),

        _sectionTitle('號碼熱度圖（綠=預測且開出 / 橙=預測未開 / 藍=未預測但開出）'),
        const SizedBox(height: 8),
        _BingoGrid(predCount: predCount, drawnCount: drawnCount),
        const SizedBox(height: 8),
        _BingoZoneStats(predCount: predCount, drawnCount: drawnCount),
        const SizedBox(height: 16),
        _sectionTitle('近期記錄'),
        const SizedBox(height: 6),
        ...logs
            .take(12)
            .map((l) => _CompactLogRow(log: l, numberCount: 10)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Shared chart widgets
// ══════════════════════════════════════════════════════════════════

/// 命中率甜甜圈圖 + 四色圖例
class _AccuracyPanel extends StatelessWidget {
  final int correct, partial, incorrect, pending;
  const _AccuracyPanel({
    required this.correct,
    required this.partial,
    required this.incorrect,
    required this.pending,
  });

  static const _green  = Color(0xFF3DDC97);
  static const _orange = Color(0xFFFF9800);
  static const _red    = Color(0xFFEF5350);
  static const _grey   = Color(0xFF546E7A);

  @override
  Widget build(BuildContext context) {
    final total = correct + partial + incorrect + pending;
    final judged = correct + partial + incorrect;
    final rate = judged > 0 ? (correct + partial * 0.5) / judged : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Row(
        children: [
          // Donut
          _DonutChart(
            fractions: [
              total > 0 ? correct / total : 0,
              total > 0 ? partial / total : 0,
              total > 0 ? incorrect / total : 0,
              total > 0 ? pending / total : 0,
            ],
            colors: [_green, _orange, _red, _grey],
            centerLabel: '${(rate * 100).round()}%',
            subLabel: '命中率',
          ),
          const SizedBox(width: 20),
          // Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _legendRow(_green, '正確', correct, total),
                const SizedBox(height: 6),
                _legendRow(_orange, '部分', partial, total),
                const SizedBox(height: 6),
                _legendRow(_red, '錯誤', incorrect, total),
                const SizedBox(height: 6),
                _legendRow(_grey, '待確認', pending, total),
                const SizedBox(height: 8),
                Text('共 $total 筆',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label, int count, int total) {
    final pct = total > 0 ? (count / total * 100).round() : 0;
    return Row(children: [
      Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      SizedBox(
          width: 48,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11))),
      Text('$count ($pct%)',
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
    ]);
  }
}

/// 甜甜圈（圓環）圖
class _DonutChart extends StatelessWidget {
  final List<double> fractions;
  final List<Color> colors;
  final String centerLabel;
  final String subLabel;

  const _DonutChart({
    required this.fractions,
    required this.colors,
    required this.centerLabel,
    required this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: CustomPaint(
        painter: _DonutPainter(fractions: fractions, colors: colors),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(centerLabel,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            Text(subLabel,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 9)),
          ]),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> fractions;
  final List<Color> colors;
  _DonutPainter({required this.fractions, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = math.min(cx, cy);
    final sw = r * 0.30;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.butt;

    double start = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      if (fractions[i] <= 0) continue;
      paint.color = colors[i];
      final sweep = fractions[i] * 2 * math.pi;
      canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r - sw / 2),
          start, sweep, false, paint);
      start += sweep;
    }
    // gap ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black26;
    canvas.drawCircle(Offset(cx, cy), r - sw, ringPaint);
    canvas.drawCircle(Offset(cx, cy), r, ringPaint);
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.fractions != fractions;
}

/// 各運動命中率橫條
class _SportTypeBreakdown extends StatelessWidget {
  final List<PredictionLog> logs;
  const _SportTypeBreakdown({required this.logs});

  static const _sports = [
    ('football',   '⚽ 足球'),
    ('basketball', '🏀 籃球'),
    ('baseball',   '⚾ 棒球'),
  ];
  static const _green = Color(0xFF3DDC97);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('各運動命中率'),
        const SizedBox(height: 8),
        ..._sports.map((s) {
          final sl = logs
              .where((l) =>
                  l.details['sport'] == s.$1 &&
                  l.outcome != PredictionOutcome.pending)
              .toList();
          if (sl.isEmpty) return const SizedBox.shrink();
          final correct =
              sl.where((l) => l.outcome == PredictionOutcome.correct).length;
          final partial =
              sl.where((l) => l.outcome == PredictionOutcome.partial).length;
          final rate = (correct + partial * 0.5) / sl.length;
          final color = rate >= 0.55
              ? _green
              : rate >= 0.40
                  ? Colors.orange
                  : Colors.red.shade400;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(
                  width: 60,
                  child: Text(s.$2,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11))),
              Expanded(
                child: Stack(children: [
                  Container(
                      height: 10,
                      decoration: BoxDecoration(
                          color: Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(5))),
                  FractionallySizedBox(
                    widthFactor: rate.clamp(0.0, 1.0),
                    child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                            color: color.withAlpha(200),
                            borderRadius: BorderRadius.circular(5))),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(
                  width: 48,
                  child: Text(
                      '${(rate * 100).round()}% (${sl.length}場)',
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
            ]),
          );
        }),
      ],
    );
  }
}

/// 莊家邏輯分析：MC 勝率 vs 實際結果
class _BookmakerLogicPanel extends StatelessWidget {
  final List<PredictionLog> logs; // already judged (not pending)
  const _BookmakerLogicPanel({required this.logs});

  static const _green = Color(0xFF3DDC97);

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();

    // How often did we follow the MC-favored side (higher win pct) and was it correct?
    int followFav = 0, followFavCorrect = 0;
    int againstFav = 0, againstFavCorrect = 0;

    for (final l in logs) {
      final homeWinPct = (l.details['mcHomeWinPct'] as num?)?.toDouble() ?? 0;
      final awayWinPct = (l.details['mcAwayWinPct'] as num?)?.toDouble() ?? 0;
      if (homeWinPct == 0 && awayWinPct == 0) continue;

      final predWinner = l.details['winner'] as String? ?? '';
      final mcFavored = homeWinPct >= awayWinPct ? 'home' : 'away';
      final followedFav = predWinner == mcFavored;
      final wasCorrect = l.outcome == PredictionOutcome.correct || l.outcome == PredictionOutcome.partial;

      if (followedFav) {
        followFav++;
        if (wasCorrect) followFavCorrect++;
      } else {
        againstFav++;
        if (wasCorrect) againstFavCorrect++;
      }
    }

    final favRate    = followFav > 0 ? followFavCorrect / followFav : 0.0;
    final againstRate = againstFav > 0 ? againstFavCorrect / againstFav : 0.0;

    if (followFav + againstFav == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('莊家邏輯分析'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: Column(
            children: [
              Row(children: [
                Expanded(child: _logicBar(
                  '跟隨熱門', followFavCorrect, followFav,
                  favRate >= 0.55 ? _green : Colors.orange,
                )),
                const SizedBox(width: 12),
                Expanded(child: _logicBar(
                  '逆勢預測', againstFavCorrect, againstFav,
                  againstRate >= 0.55 ? _green : Colors.red.shade400,
                )),
              ]),
              const SizedBox(height: 10),
              Text(
                favRate > againstRate
                    ? '📊 跟隨熱門勝率較高，建議順勢預測'
                    : againstRate > favRate
                        ? '📊 逆勢預測勝率較高，莊家可能虛高熱門賠率'
                        : '📊 熱門與冷門勝率相當',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logicBar(String label, int hit, int total, Color color) {
    final rate = total > 0 ? hit / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const Spacer(),
          Text('${(rate * 100).round()}%',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: rate.clamp(0.0, 1.0),
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 2),
        Text('$hit/$total 場', style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ],
    );
  }
}

/// 籃球/棒球記錄列（只顯示勝負方向 + 勝分差，不顯示比分）
class _BallSportRow extends StatelessWidget {
  final PredictionLog log;
  const _BallSportRow({required this.log});

  static const _green  = Color(0xFF3DDC97);
  static const _orange = Colors.orange;

  @override
  Widget build(BuildContext context) {
    final outcome = log.outcome;
    final dotColor = outcome == PredictionOutcome.correct
        ? _green
        : outcome == PredictionOutcome.partial
            ? _orange
            : outcome == PredictionOutcome.incorrect
                ? Colors.red.shade400
                : Colors.grey.shade600;

    final outcomeLabel = switch (outcome) {
      PredictionOutcome.correct   => '✓',
      PredictionOutcome.partial   => '△',
      PredictionOutcome.incorrect => '✗',
      PredictionOutcome.pending   => '…',
    };

    // Winner direction
    final predWinner = log.details['winner'] as String? ?? '';
    final predLabel  = predWinner == 'home' ? '主隊勝' : predWinner == 'away' ? '客隊勝' : '平局';

    // Point spread from actual scores (if available)
    final actH = (log.details['actualHomeScore'] as num?)?.toInt();
    final actA = (log.details['actualAwayScore'] as num?)?.toInt();
    final spread = (actH != null && actA != null) ? (actH - actA).abs() : null;
    final actualWinner = (actH != null && actA != null)
        ? (actH > actA ? '主隊勝' : actH < actA ? '客隊勝' : '平局')
        : null;

    final sport = log.details['sport'] as String? ?? '';
    final sportIcon = sport == 'basketball' ? '🏀' : '⚾';

    // Predicted scores
    final predH = (log.details['predictedHomeScoreRaw'] as num?)?.toInt()
        ?? (log.details['predictedHome'] as num?)?.toInt();
    final predA = (log.details['predictedAwayScoreRaw'] as num?)?.toInt()
        ?? (log.details['predictedAway'] as num?)?.toInt();
    final hasPredScore = predH != null && predA != null && (predH > 0 || predA > 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: dotColor.withAlpha(60)),
      ),
      child: Row(children: [
        Text(outcomeLabel,
            style: TextStyle(color: dotColor, fontSize: 12, fontWeight: FontWeight.w900)),
        const SizedBox(width: 6),
        Text(sportIcon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(log.title,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 6),
        // Predicted score (or direction fallback)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withAlpha(30),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            hasPredScore ? '預$predH:$predA' : '預$predLabel',
            style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 9),
          ),
        ),
        if (actH != null && actA != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: dotColor.withAlpha(30),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '實$actH:$actA',
              style: TextStyle(color: dotColor, fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
        ] else if (actualWinner != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: dotColor.withAlpha(30),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '實$actualWinner${spread != null ? " +$spread" : ""}',
              style: TextStyle(color: dotColor, fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ]),
    );
  }
}

/// 比分預測 vs 實際橫條圖（最近 N 場）
class _ScoreComparisonChart extends StatelessWidget {
  final List<PredictionLog> logs;
  const _ScoreComparisonChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        children: logs.map((l) {
          final predH =
              (l.details['predictedHomeScoreRaw'] as num?)?.toInt() ?? 0;
          final predA =
              (l.details['predictedAwayScoreRaw'] as num?)?.toInt() ?? 0;
          final actH =
              (l.details['actualHomeScore'] as num?)?.toInt() ?? 0;
          final actA =
              (l.details['actualAwayScore'] as num?)?.toInt() ?? 0;
          final outcome = l.outcome;
          final dotColor = outcome == PredictionOutcome.correct
              ? const Color(0xFF3DDC97)
              : outcome == PredictionOutcome.partial
                  ? Colors.orange
                  : outcome == PredictionOutcome.incorrect
                      ? Colors.red.shade400
                      : Colors.grey;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: dotColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(l.title,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 10),
                      overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Text('預$predH:$predA',
                  style: const TextStyle(
                      color: Color(0xFF00E5FF), fontSize: 10)),
              const SizedBox(width: 6),
              Text('實$actH:$actA',
                  style: TextStyle(
                      color: outcome == PredictionOutcome.correct
                          ? const Color(0xFF3DDC97)
                          : Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

/// 樂透號碼頻率橫條圖（1-39 或 1-80）
class _NumberFreqChart extends StatelessWidget {
  final Map<int, int> predCount;
  final Map<int, int> drawnCount;
  final int maxNum;

  const _NumberFreqChart({
    required this.predCount,
    required this.drawnCount,
    required this.maxNum,
  });

  @override
  Widget build(BuildContext context) {
    if (predCount.isEmpty && drawnCount.isEmpty) {
      return _emptyView('尚無號碼數據');
    }

    final allMax = [
      ...predCount.values,
      ...drawnCount.values,
    ].fold(1, math.max);

    // Show numbers in rows of 13
    const perRow = 13;
    final rows = <Widget>[];
    for (var start = 1; start <= maxNum; start += perRow) {
      final end = math.min(start + perRow - 1, maxNum);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(end - start + 1, (i) {
            final n = start + i;
            final pred = predCount[n] ?? 0;
            final drawn = drawnCount[n] ?? 0;
            final maxH = 40.0;
            return Expanded(
              child: Column(children: [
                // Drawn bar (green)
                Container(
                  height: drawn > 0 ? (drawn / allMax * maxH).clamp(2, maxH) : 2,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                      color: const Color(0xFF3DDC97).withAlpha(200),
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 1),
                // Predicted bar (blue)
                Container(
                  height: pred > 0 ? (pred / allMax * maxH).clamp(2, maxH) : 2,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                      color: Colors.blue.shade300.withAlpha(200),
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 2),
                Text('$n',
                    style: TextStyle(
                        color: drawn > 0 && pred > 0
                            ? const Color(0xFF3DDC97)
                            : Colors.white38,
                        fontSize: 7)),
              ]),
            );
          }),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(children: [
        Row(children: [
          _legend(Colors.blue.shade300, '預測次數'),
          const SizedBox(width: 12),
          _legend(const Color(0xFF3DDC97), '實際開出'),
          const SizedBox(width: 12),
          const Text('（綠色號碼=兩者皆有）',
              style: TextStyle(color: Colors.white30, fontSize: 9)),
        ]),
        const SizedBox(height: 8),
        ...rows,
      ]),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              color: color,
              margin: const EdgeInsets.only(right: 4)),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      );
}

/// 賓果 1-80 熱度格子圖
class _BingoGrid extends StatelessWidget {
  final Map<int, int> predCount;
  final Map<int, int> drawnCount;

  const _BingoGrid({required this.predCount, required this.drawnCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(children: [
        // Legend
        Wrap(spacing: 10, runSpacing: 4, children: [
          _gridLegend(const Color(0xFF3DDC97), '預測且開出'),
          _gridLegend(Colors.orange.shade300, '預測未開出'),
          _gridLegend(Colors.blue.shade300, '開出未預測'),
          _gridLegend(Colors.white12, '無'),
        ]),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          childAspectRatio: 1.15,
          children: List.generate(80, (i) {
            final n = i + 1;
            final pred  = (predCount[n]  ?? 0) > 0;
            final drawn = (drawnCount[n] ?? 0) > 0;
            final color = pred && drawn
                ? const Color(0xFF3DDC97)
                : pred
                    ? Colors.orange.shade300
                    : drawn
                        ? Colors.blue.shade300
                        : Colors.white.withAlpha(12);
            return Container(
              decoration: BoxDecoration(
                  color: color.withAlpha(pred || drawn ? 200 : 30),
                  borderRadius: BorderRadius.circular(3)),
              child: Center(
                child: Text('$n',
                    style: TextStyle(
                        color: pred || drawn
                            ? Colors.black87
                            : Colors.white24,
                        fontSize: 8,
                        fontWeight: FontWeight.w600)),
              ),
            );
          }),
        ),
      ]),
    );
  }

  Widget _gridLegend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 9)),
        ],
      );
}

/// 賓果四區命中率統計
class _BingoZoneStats extends StatelessWidget {
  final Map<int, int> predCount;
  final Map<int, int> drawnCount;
  const _BingoZoneStats({required this.predCount, required this.drawnCount});

  static const _zones = [
    ('第1區 1-20',  1,  20),
    ('第2區 21-40', 21, 40),
    ('第3區 41-60', 41, 60),
    ('第4區 61-80', 61, 80),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: _zones.map((z) {
          int p = 0, hit = 0;
          for (var n = z.$2; n <= z.$3; n++) {
            if ((predCount[n] ?? 0) > 0) p++;
            if ((predCount[n] ?? 0) > 0 && (drawnCount[n] ?? 0) > 0) hit++;
          }
          final rate = p > 0 ? hit / p : 0.0;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(children: [
                Text(z.$1,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 9)),
                const SizedBox(height: 4),
                Text('${(rate * 100).round()}%',
                    style: TextStyle(
                        color: rate >= 0.3
                            ? const Color(0xFF3DDC97)
                            : Colors.orange,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
                Text('$hit/$p',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 9)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 賓果命中數走勢圖（每局預測 6 個中了幾個）
class _HitTrendChart extends StatelessWidget {
  final List<int> hitHistory; // 舊→新排列
  const _HitTrendChart({required this.hitHistory});

  @override
  Widget build(BuildContext context) {
    final recent = hitHistory.length > 20 ? hitHistory.sublist(hitHistory.length - 20) : hitHistory;
    final maxH = 6;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _legend(const Color(0xFF3DDC97), '≥3命中'),
            const SizedBox(width: 10),
            _legend(Colors.orange, '1-2命中'),
            const SizedBox(width: 10),
            _legend(Colors.red.shade400, '未命中'),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: recent.asMap().entries.map((e) {
                final hits = e.value;
                final frac = (hits / maxH).clamp(0.0, 1.0);
                final color = hits >= 3
                    ? const Color(0xFF3DDC97)
                    : hits >= 1
                        ? Colors.orange
                        : Colors.red.shade400;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (hits > 0)
                          Text('$hits',
                              style: TextStyle(color: color, fontSize: 7,
                                  fontWeight: FontWeight.w700)),
                        Container(
                          height: 4 + 48 * frac,
                          decoration: BoxDecoration(
                            color: color.withAlpha(180),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '近 ${recent.length} 局  平均命中 ${recent.isEmpty ? 0 : (recent.reduce((a, b) => a + b) / recent.length).toStringAsFixed(1)} 個',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 3),
    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
  ]);
}

/// 賓果區間命中率橫條（8 個區間 01-10 … 71-80）
class _BingoZoneHitRate extends StatelessWidget {
  final Map<int, int> predCount;
  final Map<int, int> drawnCount;
  const _BingoZoneHitRate({required this.predCount, required this.drawnCount});

  static const _zoneLabels = ['01-10','11-20','21-30','31-40','41-50','51-60','61-70','71-80'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        children: List.generate(8, (z) {
          final start = z * 10 + 1;
          final end   = z * 10 + 10;
          int pred = 0, hit = 0;
          for (var n = start; n <= end; n++) {
            if ((predCount[n] ?? 0) > 0) pred++;
            if ((predCount[n] ?? 0) > 0 && (drawnCount[n] ?? 0) > 0) hit++;
          }
          final rate   = pred > 0 ? hit / pred : 0.0;
          final color  = rate >= 0.35
              ? const Color(0xFF3DDC97)
              : rate >= 0.20
                  ? Colors.orange
                  : Colors.red.shade400;
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(children: [
              SizedBox(
                width: 48,
                child: Text(_zoneLabels[z],
                    style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ),
              Expanded(
                child: Stack(children: [
                  Container(height: 10,
                      decoration: BoxDecoration(
                          color: Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(5))),
                  FractionallySizedBox(
                    widthFactor: rate.clamp(0.0, 1.0),
                    child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                            color: color.withAlpha(200),
                            borderRadius: BorderRadius.circular(5))),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: Text('$hit/$pred  ${(rate*100).round()}%',
                    style: TextStyle(color: color, fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

/// 簡潔版記錄列
class _CompactLogRow extends StatelessWidget {
  final PredictionLog log;
  final int numberCount; // 0 = sport score, 5 = lottery, 10 = bingo

  const _CompactLogRow({required this.log, required this.numberCount});

  @override
  Widget build(BuildContext context) {
    final outcome = log.outcome;
    final dotColor = outcome == PredictionOutcome.correct
        ? const Color(0xFF3DDC97)
        : outcome == PredictionOutcome.partial
            ? Colors.orange
            : outcome == PredictionOutcome.incorrect
                ? Colors.red.shade400
                : Colors.grey.shade600;

    final outcomeLabel = switch (outcome) {
      PredictionOutcome.correct   => '✓',
      PredictionOutcome.partial   => '△',
      PredictionOutcome.incorrect => '✗',
      PredictionOutcome.pending   => '…',
    };

    // Highlight which predicted numbers actually appeared
    Widget resultWidget;
    if (numberCount > 0 && log.actualResult != null) {
      final predicted = _parseNums(log.predictedResult);
      final actual    = _parseNums(log.actualResult!);
      resultWidget = Wrap(
        spacing: 3,
        runSpacing: 2,
        children: predicted.map((n) {
          final hit = actual.contains(n);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: hit
                  ? const Color(0xFF3DDC97).withAlpha(60)
                  : Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: hit
                    ? const Color(0xFF3DDC97).withAlpha(120)
                    : Colors.transparent,
              ),
            ),
            child: Text(n.toString().padLeft(2, '0'),
                style: TextStyle(
                    color: hit ? const Color(0xFF3DDC97) : Colors.white54,
                    fontSize: 10,
                    fontWeight: hit ? FontWeight.w700 : FontWeight.normal)),
          );
        }).toList(),
      );
    } else {
      resultWidget = Text(
        '${log.predictedResult}${log.actualResult != null ? ' → ${log.actualResult}' : ''}',
        style: const TextStyle(color: Colors.white54, fontSize: 10),
        overflow: TextOverflow.ellipsis,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: dotColor.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(outcomeLabel,
                style: TextStyle(
                    color: dotColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(log.title,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11),
                    overflow: TextOverflow.ellipsis)),
            Text(
              '${log.createdAt.month}/${log.createdAt.day}',
              style: const TextStyle(color: Colors.white30, fontSize: 10),
            ),
          ]),
          const SizedBox(height: 4),
          resultWidget,
        ],
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────

List<int> _parseNums(String s) {
  return s
      .split(RegExp(r'[\s,]+'))
      .map((t) => int.tryParse(t.trim()))
      .whereType<int>()
      .toList();
}

Widget _sectionTitle(String text) => Text(text,
    style: const TextStyle(
        color: Color(0xFF00E5FF),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5));

Widget _emptyView(String msg, {String hint = ''}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white24, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
