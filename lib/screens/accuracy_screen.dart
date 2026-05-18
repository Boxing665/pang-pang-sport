import 'package:flutter/material.dart';
import '../models/prediction_log.dart';
import '../models/lottery_model.dart';
import '../models/sport_type.dart';
import '../services/prediction_log_service.dart';
import '../services/failure_analysis_service.dart';
import '../services/pang_pang_sports_service.dart';
import '../services/lottery_service.dart';
import '../services/bingo_service.dart';
import '../models/match_fixture.dart';

/// 預測準確率總覽頁面
///
/// - 顯示體育 / 樂透 / 賓果三類別的整體命中率
/// - 列出所有歷史紀錄（可篩選）
/// - 每筆紀錄可回報實際結果
class AccuracyScreen extends StatefulWidget {
  const AccuracyScreen({super.key});

  @override
  State<AccuracyScreen> createState() => _AccuracyScreenState();
}

class _AccuracyScreenState extends State<AccuracyScreen>
    with SingleTickerProviderStateMixin {
  final _svc = PredictionLogService();
  late final _analysisSvc = FailureAnalysisService(_svc);
  final _sportsSvc = PangPangSportsService();
  final _lotterySvc = LotteryService();
  final _bingoSvc = BingoService();
  late TabController _tabCtrl;

  // tag: 'all' | 'basketball' | 'baseball' | 'football' | 'lottery' | 'bingo'
  static const _tabs = [
    (label: '全部', tag: 'all'),
    (label: '🏀籃球', tag: 'basketball'),
    (label: '⚾棒球', tag: 'baseball'),
    (label: '⚽足球', tag: 'football'),
    (label: '🎰樂透', tag: 'lottery'),
    (label: '🎱賓果', tag: 'bingo'),
  ];

  List<PredictionLog> _all = [];
  AccuracyStats? _statsAll;
  Map<String, AccuracyStats> _statsByTag = {};
  FailureAnalysisResult _analysis = FailureAnalysisResult.empty();
  Map<SportType, SportBiasData> _biasSnapshot = {};
  Map<String, LotteryLearningData> _lotteryLearning = {};
  bool _learningInProgress = false;
  bool _loading = true;

  static const _bg = Color(0xFF050E24);
  static const _bg1 = Color(0xFF0D1E4A);
  static const _gold = Color(0xFFFFD700);
  static const _cyan = Color(0xFF00E5FF);
  static const _green = Color(0xFF3DDC97);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _refresh();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    // 每次進入紀錄頁都自動抓最新資料，回填實際結果與準確率
    try {
      final sportsFuture = _sportsSvc.getMatchesForDays(days: 5);
      final lotteryFuture = _lotterySvc.fetchAndAnalyze();
      final bingoFuture = _bingoSvc.fetchRecent(forceRefresh: true);

      final results = await Future.wait([
        sportsFuture,
        lotteryFuture,
        bingoFuture,
      ]);

      final sportsMatches = results[0] as List<MatchFixture>;
      final lotteryData = results[1] as LotteryFetchResult;
      final bingoRecords = results[2] as List<BingoRecord>;

      final sportScores = <String, (int, int)>{};
      for (final m in sportsMatches) {
        if (m.status != MatchStatus.completed) continue;
        sportScores[m.id] = (m.homeScore, m.awayScore);
      }

      final lottoByDate = <String, List<int>>{};
      for (final r in lotteryData.records539) {
        if (r.date.isEmpty || r.numbers.isEmpty) continue;
        lottoByDate[r.date] = r.numbers;
      }

      final bingoByDrawNo = <int, List<int>>{};
      for (final r in bingoRecords) {
        if (r.numbers.isEmpty) continue;
        bingoByDrawNo[r.drawNo] = r.numbers;
      }

      await Future.wait([
        _svc.autoReportSportsByMatchId(sportScores),
        _svc.autoReportLotteryByDate(lottoByDate),
        _svc.autoReportBingoByDrawNo(bingoByDrawNo),
      ]);
    } catch (_) {
      // 任一來源失敗時不中斷紀錄頁載入，保留既有資料顯示
    }

    final all = await _svc.loadAll();
    if (!mounted) return;
    // Compute stats for all tags inline
    AccuracyStats computeStats(List<PredictionLog> logs) {
      int correct = 0, partial = 0, incorrect = 0, pending = 0;
      double scoreSum = 0;
      int scoredCount = 0;
      for (final l in logs) {
        switch (l.outcome) {
          case PredictionOutcome.correct: correct++; break;
          case PredictionOutcome.partial: partial++; break;
          case PredictionOutcome.incorrect: incorrect++; break;
          case PredictionOutcome.pending: pending++; break;
        }
        if (l.accuracyScore != null) {
          scoreSum += l.accuracyScore!;
          scoredCount++;
        }
      }
      return AccuracyStats(
        total: logs.length,
        correct: correct,
        partial: partial,
        incorrect: incorrect,
        pending: pending,
        avgScore: scoredCount > 0 ? scoreSum / scoredCount : 0,
      );
    }
    final byTag = <String, AccuracyStats>{};
    for (final tab in _tabs) {
      if (tab.tag == 'all') continue;
      byTag[tab.tag] = computeStats(_filterByTag(all, tab.tag));
    }

    // 失敗分析（不阻塞主流程）
    FailureAnalysisResult analysis = FailureAnalysisResult.empty();
    try { analysis = await _analysisSvc.analyze(); } catch (_) {}

    // 觸發 AI 學習：重新計算體育 + 樂透 + 賓果偏差修正
    await _sportsSvc.triggerBiasRefresh();
    final biasSnapshot    = _sportsSvc.getBiasDataSnapshot();
    final lotterySnapshot = _sportsSvc.getLotteryLearningSnapshot();

    if (!mounted) return;
    setState(() {
      _all = all;
      _statsAll = computeStats(all);
      _statsByTag = byTag;
      _analysis = analysis;
      _biasSnapshot    = Map.from(biasSnapshot);
      _lotteryLearning = Map.from(lotterySnapshot);
      _loading = false;
    });
  }

  Future<void> _triggerLearning() async {
    if (_learningInProgress) return;
    setState(() => _learningInProgress = true);
    await _sportsSvc.triggerBiasRefresh();
    final biasSnapshot    = _sportsSvc.getBiasDataSnapshot();
    final lotterySnapshot = _sportsSvc.getLotteryLearningSnapshot();
    if (!mounted) return;
    setState(() {
      _biasSnapshot    = Map.from(biasSnapshot);
      _lotteryLearning = Map.from(lotterySnapshot);
      _learningInProgress = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ AI 已重新學習歷史預測數據'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF1A3A2A),
      ),
    );
  }

  List<PredictionLog> _filterByTag(List<PredictionLog> src, String tag) {
    switch (tag) {
      case 'lottery':
        return src.where((l) => l.type == PredictionType.lottery).toList();
      case 'bingo':
        return src.where((l) => l.type == PredictionType.bingo).toList();
      default:
        return src.where((l) =>
            l.type == PredictionType.sport &&
            l.details['sport'] == tag).toList();
    }
  }

  List<PredictionLog> get _filtered {
    final tag = _tabs[_tabCtrl.index].tag;
    if (tag == 'all') return _all;
    return _filterByTag(_all, tag);
  }

  // ── Build ─────────────────────────────────────────────────────

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
              if (!_loading && _statsAll != null) _statsRow(),
              _tabBar(),
              if (!_loading) _aiLearningPanel(),
              if (!_loading) _analysisPanel(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: _gold))
                    : RefreshIndicator(
                        color: _gold,
                        backgroundColor: _bg1,
                        onRefresh: _refresh,
                        child: _filtered.isEmpty
                            ? _emptyView()
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                    14, 8, 14, 32),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) =>
                                    _LogCard(
                                      log: _filtered[i],
                                      onDelete: () => _delete(_filtered[i]),
                                    ),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 失敗分析 Panel ────────────────────────────────────────────

  Widget _analysisPanel() {
    final tag = _tabs[_tabCtrl.index].tag;
    List<String> insights;
    List<(String, double)> barItems = [];
    String panelTitle;

    switch (tag) {
      case 'lottery':
        insights = _analysis.lotteryInsights;
        panelTitle = '🔬 樂透策略分析';
        final sorted = _analysis.lotteryTagStats.values.toList()
          ..sort((a, b) => b.hitRate.compareTo(a.hitRate));
        barItems = sorted
            .where((s) => s.total >= 3)
            .take(8)
            .map((s) => (s.tag, s.hitRate))
            .toList();
      case 'bingo':
        insights = _analysis.bingoInsights;
        panelTitle = '🔬 賓果組別分析';
        barItems = _analysis.bingoGroupStats.entries
            .map((e) => (e.key, e.value))
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
      case 'basketball':
        insights = _analysis.sportsInsights
            .where((s) => s.contains('籃球') || s.contains('分析'))
            .toList();
        panelTitle = '🔬 籃球預測分析';
        final r = _analysis.sportsStats['basketball'];
        if (r != null) barItems = [('籃球命中率', r)];
      case 'baseball':
        insights = _analysis.sportsInsights
            .where((s) => s.contains('棒球') || s.contains('分析'))
            .toList();
        panelTitle = '🔬 棒球預測分析';
        final r = _analysis.sportsStats['baseball'];
        if (r != null) barItems = [('棒球命中率', r)];
      case 'football':
        insights = _analysis.sportsInsights
            .where((s) => s.contains('足球') || s.contains('分析'))
            .toList();
        panelTitle = '🔬 足球預測分析';
        final r = _analysis.sportsStats['football'];
        if (r != null) barItems = [('足球命中率', r)];
      default: // 'all'
        insights = [
          ..._analysis.sportsInsights.take(2),
          ..._analysis.lotteryInsights.take(2),
          ..._analysis.bingoInsights.take(2),
        ];
        panelTitle = '🔬 預測失敗分析';
        barItems = _analysis.sportsStats.entries
            .map((e) {
              const m = {'basketball': '籃球', 'baseball': '棒球', 'football': '足球'};
              return (m[e.key] ?? e.key, e.value);
            })
            .toList();
    }

    if (insights.isEmpty && barItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.indigo.withAlpha(30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.indigo.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(children: [
            Text(panelTitle, style: const TextStyle(
                color: Color(0xFFB0BFFF), fontSize: 12,
                fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_analysis.totalAnalyzed.isNotEmpty)
              Text(
                _insightSampleSize(tag),
                style: const TextStyle(color: Colors.white30, fontSize: 10),
              ),
          ]),
          // Insight bullets
          if (insights.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...insights.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $s',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 11, height: 1.5)),
            )),
          ],
          // Bar chart
          if (barItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...barItems.map((item) => _barRow(item.$1, item.$2)),
          ],
        ],
      ),
    );
  }

  String _insightSampleSize(String tag) {
    final a = _analysis.totalAnalyzed;
    switch (tag) {
      case 'lottery': return '樣本 ${a['lottery'] ?? 0} 期';
      case 'bingo':   return '樣本 ${a['bingo'] ?? 0} 期';
      case 'basketball': case 'baseball': case 'football':
        return '樣本 ${a['sports'] ?? 0} 場';
      default:
        return '共 ${(a.values.fold(0, (s, v) => s + v))} 筆';
    }
  }

  Widget _barRow(String label, double rate) {
    final pct = (rate * 100).round();
    final color = pct >= 55
        ? _green
        : pct >= 40
            ? Colors.orange
            : Colors.red.shade300;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Stack(children: [
              Container(
                  height: 8,
                  decoration: BoxDecoration(
                      color: Colors.white.withAlpha(12),
                      borderRadius: BorderRadius.circular(4))),
              FractionallySizedBox(
                widthFactor: rate.clamp(0.0, 1.0),
                child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                        color: color.withAlpha(180),
                        borderRadius: BorderRadius.circular(4))),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          Text('$pct%',
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          const Text(
            '🤖 AI預測',
            style: TextStyle(
                color: _gold,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1),
          ),
          const Spacer(),
          if (_learningInProgress)
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _green),
            )
          else
            IconButton(
              icon: const Icon(Icons.psychology_rounded, color: _green),
              tooltip: '觸發 AI 學習',
              onPressed: _triggerLearning,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _cyan),
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined,
                color: Colors.red),
            tooltip: '清除所有紀錄',
            onPressed: _confirmClear,
          ),
        ],
      ),
    );
  }

  // ── AI 學習狀態面板 ───────────────────────────────────────────

  Widget _aiLearningPanel() {
    final sportSamples   = _biasSnapshot.values.fold(0, (s, b) => s + b.sampleCount);
    final lottoSamples   = _lotteryLearning['lottery539']?.sampleCount ?? 0;
    final bingoSamples   = _lotteryLearning['bingo']?.sampleCount ?? 0;
    final totalSamples   = sportSamples + lottoSamples + bingoSamples;

    const sportLabel = {
      SportType.football:   '⚽足球',
      SportType.basketball: '🏀籃球',
      SportType.baseball:   '⚾棒球',
    };

    final hasAny = totalSamples > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.teal.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 標題列 ─────────────────────────────────────────────
          Row(children: [
            const Icon(Icons.psychology_rounded, size: 14, color: _green),
            const SizedBox(width: 6),
            const Text('🧠 AI 自我學習狀態',
                style: TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(
              hasAny ? '已學習 $totalSamples 筆' : '尚無學習資料',
              style: TextStyle(
                  color: hasAny ? _green.withAlpha(180) : Colors.white30, fontSize: 10),
            ),
          ]),

          if (!hasAny)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '• 儲存並回報預測結果後，AI 將自動修正體育、539 與賓果的預測偏差',
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
              ),
            )
          else ...[
            const SizedBox(height: 10),

            // ── 體育學習 ─────────────────────────────────────────
            if (_biasSnapshot.isNotEmpty) ...[
              _sectionLabel('⚽🏀⚾ 體育預測偏差修正'),
              const SizedBox(height: 6),
              ..._biasSnapshot.entries.map((e) {
                final bias  = e.value;
                final label = sportLabel[e.key] ?? e.key.name;
                final mcPct = bias.mcSampleCount > 0
                    ? '${(bias.mcAccuracyRate * 100).round()}%' : '--';
                final homeCorr = bias.homeLambdaFactor != 1.0
                    ? '×${bias.homeLambdaFactor.toStringAsFixed(2)}' : '標準';
                final awayCorr = bias.awayLambdaFactor != 1.0
                    ? '×${bias.awayLambdaFactor.toStringAsFixed(2)}' : '標準';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(children: [
                    SizedBox(width: 52,
                        child: Text(label,
                            style: const TextStyle(color: Colors.white60, fontSize: 11))),
                    _learnChip('主 $homeCorr', Colors.cyan),
                    const SizedBox(width: 4),
                    _learnChip('客 $awayCorr', Colors.orange),
                    const SizedBox(width: 4),
                    _learnChip('方向 $mcPct', _green),
                    if (bias.sampleCount > 0) ...[
                      const SizedBox(width: 4),
                      Text('(${bias.sampleCount}場)',
                          style: const TextStyle(color: Colors.white30, fontSize: 9)),
                    ],
                  ]),
                );
              }),
              const SizedBox(height: 8),
            ],

            // ── 539 學習 ─────────────────────────────────────────
            if (_lotteryLearning.containsKey('lottery539')) ...[
              _sectionLabel('🎰 539 學習結果'),
              const SizedBox(height: 6),
              _lotteryLearningRow(_lotteryLearning['lottery539']!,
                  rangeOrder: ['1-13', '14-26', '27-39']),
              const SizedBox(height: 8),
            ],

            // ── 賓果學習 ──────────────────────────────────────────
            if (_lotteryLearning.containsKey('bingo')) ...[
              _sectionLabel('🎱 賓果學習結果'),
              const SizedBox(height: 6),
              _lotteryLearningRow(_lotteryLearning['bingo']!,
                  rangeOrder: ['1-20', '21-40', '41-60', '61-80']),
              if (_lotteryLearning['bingo']!.strategyHitRates.isNotEmpty) ...[
                const SizedBox(height: 4),
                _strategyRow(_lotteryLearning['bingo']!),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600));

  Widget _lotteryLearningRow(LotteryLearningData data,
      {required List<String> rangeOrder}) {
    final hitPct = '${(data.hitRate * 100).round()}%';
    final avgHit = data.avgHitCount.toStringAsFixed(1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _learnChip('命中率 $hitPct', _gold),
        const SizedBox(width: 4),
        _learnChip('均命中 $avgHit 球', Colors.orange),
        const SizedBox(width: 4),
        Text('(${data.sampleCount}期)',
            style: const TextStyle(color: Colors.white30, fontSize: 9)),
      ]),
      if (data.rangeHitRates.isNotEmpty) ...[
        const SizedBox(height: 4),
        Row(children: [
          for (final k in rangeOrder) ...[
            if (data.rangeHitRates.containsKey(k))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _learnChip(
                  '$k ${(data.rangeHitRates[k]! * 100).round()}%',
                  _barColor(data.rangeHitRates[k]!),
                ),
              ),
          ],
        ]),
      ],
      if (data.hotLearned.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          '熱門學習號: ${data.hotLearned.map((n) => n.toString().padLeft(2, '0')).join(' ')}',
          style: const TextStyle(color: Colors.white54, fontSize: 9),
        ),
      ],
    ]);
  }

  Widget _strategyRow(LotteryLearningData data) {
    final sorted = data.strategyHitRates.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final e in sorted.take(3))
        _learnChip('${e.key} ${(e.value * 100).round()}%', _barColor(e.value)),
    ]);
  }

  Color _barColor(double rate) {
    if (rate >= 0.55) return _green;
    if (rate >= 0.40) return Colors.orange;
    return Colors.red.shade300;
  }

  Widget _learnChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────

  Widget _statsRow() {
    final stats = _statsAll!;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(60),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withAlpha(50)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatCell('總紀錄', '${stats.total}', _cyan),
          _divider(),
          _StatCell(
              '勝率',
              stats.judged > 0
                  ? '${(stats.winRate * 100).round()}%'
                  : '--',
              _green),
          _divider(),
          _StatCell(
              '正確',
              '${stats.correct}',
              Colors.greenAccent),
          _divider(),
          _StatCell('部分', '${stats.partial}', Colors.orange),
          _divider(),
          _StatCell('錯誤', '${stats.incorrect}', Colors.red.shade300),
          _divider(),
          _StatCell('待回', '${stats.pending}', Colors.white38),
        ],
      ),
    );
  }

  Widget _divider() => Container(
      width: 1, height: 28, color: Colors.white.withAlpha(20));

  // ── Tab Bar ───────────────────────────────────────────────────

  Widget _tabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabCtrl,
        dividerHeight: 0,
        indicator: BoxDecoration(
          color: _cyan.withAlpha(40),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _cyan.withAlpha(100)),
        ),
        labelColor: _cyan,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700),
        tabs: _tabs.map((t) {
          final stats =
              t.tag == 'all' ? _statsAll : _statsByTag[t.tag];
          final judged = stats?.judged ?? 0;
          final label = judged > 0
              ? '${t.label}\n${(stats!.winRate * 100).round()}%'
              : t.label;
          return Tab(text: label);
        }).toList(),
      ),
    );
  }

  Widget _emptyView() {
    return ListView(
      children: const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(
            child: Text('還沒有預測紀錄\n從體育（籃球／棒球／足球）/ 樂透 / 賓果頁面儲存預測',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                    height: 1.7)),
          ),
        ),
      ],
    );
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _delete(PredictionLog log) async {
    await _svc.delete(log.id);
    await _refresh();
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131C31),
        title: const Text('清除所有紀錄',
            style: TextStyle(color: _gold)),
        content: const Text('確定要刪除全部預測紀錄嗎？',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消',
                  style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('確認刪除',
                  style: TextStyle(color: Colors.red.shade400))),
        ],
      ),
    );
    if (confirmed == true) {
      await _svc.clearAll();
      await _refresh();
    }
  }
}

// ── Log Card ──────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.log,
    required this.onDelete,
  });
  final PredictionLog log;
  final VoidCallback onDelete;

  static const _cyan = Color(0xFF00E5FF);

  @override
  Widget build(BuildContext context) {
    final outcomeColor = switch (log.outcome) {
      PredictionOutcome.correct => Colors.greenAccent,
      PredictionOutcome.partial => Colors.orange,
      PredictionOutcome.incorrect => Colors.red.shade300,
      PredictionOutcome.pending => Colors.white38,
    };
    final outcomeLabel = switch (log.outcome) {
      PredictionOutcome.correct => '✅ 正確',
      PredictionOutcome.partial => '🟡 部分',
      PredictionOutcome.incorrect => '❌ 錯誤',
      PredictionOutcome.pending => '⏳ 待回',
    };
    final typeEmoji = switch (log.type) {
      PredictionType.sport => switch (log.details['sport'] as String? ?? '') {
        'basketball' => '🏀',
        'baseball' => '⚾',
        _ => '⚽',
      },
      PredictionType.lottery => '🎰',
      PredictionType.bingo => '🎱',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: log.outcome == PredictionOutcome.pending
              ? Colors.white.withAlpha(20)
              : outcomeColor.withAlpha(80),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Text('$typeEmoji ',
                  style: const TextStyle(fontSize: 16)),
              Expanded(
                child: Text(log.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: outcomeColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: outcomeColor.withAlpha(100)),
                ),
                child: Text(outcomeLabel,
                    style: TextStyle(
                        color: outcomeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Subtitle + date
          Row(
            children: [
              Expanded(
                child: Text(log.subtitle,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ),
              Text(
                _fmtDate(log.createdAt),
                style: const TextStyle(
                    color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Predicted
          _ResultRow(
              label: '預測',
              value: log.predictedResult,
              color: _cyan.withAlpha(200)),
          // ── 主勝 / 客勝 預測（體育專用）──────────────────────
          if (log.type == PredictionType.sport) ...[
            Builder(builder: (_) {
              final predScore = _tryParseScore(log.predictedResult);
              if (predScore == null) return const SizedBox.shrink();
              final predWin = predScore.$1 > predScore.$2
                  ? '主勝'
                  : predScore.$2 > predScore.$1
                      ? '客勝'
                      : '平手';
              // 若有實際結果，判斷主客勝是否正確
              if (log.actualResult != null) {
                final actScore = _tryParseScore(log.actualResult!);
                if (actScore != null) {
                  final actWin = actScore.$1 > actScore.$2
                      ? '主勝'
                      : actScore.$2 > actScore.$1
                          ? '客勝'
                          : '平手';
                  final isCorrect = predWin == actWin;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Text('預測：',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 11)),
                        Text(predWin,
                            style: TextStyle(
                                color: isCorrect
                                    ? Colors.greenAccent
                                    : Colors.red.shade300,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Text(isCorrect ? '✅' : '❌',
                            style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 8),
                        Text('實際：',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                        Text(actWin,
                            style: TextStyle(
                                color: outcomeColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }
              }
              // 尚無實際結果，只顯示預測
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Text('預測：',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 11)),
                    Text(predWin,
                        style: TextStyle(
                            color: _cyan.withAlpha(200),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            }),
          ],
          if (log.actualResult != null) ...[
            const SizedBox(height: 4),
            _ResultRow(
                label: '實際',
                value: log.actualResult!,
                color: outcomeColor),
          ],
          if (log.accuracyScore != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: log.accuracyScore!.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.white.withAlpha(15),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(outcomeColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(log.accuracyScore! * 100).round()}%',
                  style: TextStyle(
                      color: outcomeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          // Action row
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.red.withAlpha(60)),
                ),
                child: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static (int, int)? _tryParseScore(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final a = int.tryParse(parts[0].trim());
    final b = int.tryParse(parts[1].trim());
    if (a == null || b == null) return null;
    return (a, b);
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Text('$label：',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 9)),
      ],
    );
  }
}
