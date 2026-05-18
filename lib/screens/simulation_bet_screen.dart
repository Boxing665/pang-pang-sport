import 'dart:math';
import 'package:flutter/material.dart';
import '../models/match_fixture.dart';
import '../models/lottery_model.dart';
import '../models/sport_type.dart';
import '../services/pang_pang_sports_service.dart';
import '../services/lottery_service.dart';
import '../services/bingo_service.dart';
import '../theme/app_theme.dart';

/// 預測畫面（體育 / 樂透 / 賓果 三分頁）— 純預測，無投注
class SimulationBetScreen extends StatefulWidget {
  const SimulationBetScreen({super.key});

  @override
  State<SimulationBetScreen> createState() => _SimulationBetScreenState();
}

class _SimulationBetScreenState extends State<SimulationBetScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('預測',
            style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF3DDC97),
          labelColor: const Color(0xFF3DDC97),
          unselectedLabelColor: Colors.white54,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.sports_baseball), text: '體育'),
            Tab(icon: Icon(Icons.confirmation_number), text: '樂透'),
            Tab(icon: Icon(Icons.casino), text: '賓果'),
            Tab(icon: Icon(Icons.auto_awesome), text: '模擬預測'),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.heroGradient,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              _SportsPredictionTab(),
              _LotteryPredictionTab(),
              _BingoPredictionTab(),
              _SimulatePredictionTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 模擬預測分頁
// ═══════════════════════════════════════════════════════════════
class _SimulatePredictionTab extends StatefulWidget {
  const _SimulatePredictionTab();
  @override
  State<_SimulatePredictionTab> createState() => _SimulatePredictionTabState();
}

class _SimulatePredictionTabState extends State<_SimulatePredictionTab> {

  final _rand = Random();
  final _sportsService = PangPangSportsService();
  String? _type;
  List<int> _numbers = [];
  String _result = '';
  BingoPrediction? _bingoPred;
  bool _loadingBingo = false;
  List<PredictionResult> _cachedSports = [];

  @override
  void initState() {
    super.initState();
    _prepareData();
  }

  Future<void> _prepareData() async {
    setState(() => _loadingBingo = true);
    try {
      // 同時準備體育與賓果數據
      final results = await Future.wait([
        _sportsService.getTodaysPredictions(),
        BingoService().fetchRecent(),
      ]);
      
      if (mounted) {
        setState(() {
          _cachedSports = results[0] as List<PredictionResult>;
          final bingoRecords = results[1] as List<BingoRecord>;
          _bingoPred = BingoService.analyze(bingoRecords, seed: _rand.nextInt(100));
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingBingo = false);
    }
  }

  void _generate() {
    // 隨機選一種預測
    final types = ['體育', '樂透', '賓果'];
    _type = types[_rand.nextInt(types.length)];
    if (_type == '體育') {
      if (_cachedSports.isNotEmpty) {
        final highConfPicks = _cachedSports.where((p) => p.prediction.confidence > 0.75).toList();
        final pool = highConfPicks.isNotEmpty ? highConfPicks : _cachedSports;
        final pick = pool[_rand.nextInt(pool.length)];
        
        _result = '${pick.fixture.homeTeam} vs ${pick.fixture.awayTeam}\n預測比分 ${pick.prediction.predictedHomeScore} : ${pick.prediction.predictedAwayScore}';
      } else {
        // 備援：隨機比分
        final home = 1 + _rand.nextInt(4);
        final away = 1 + _rand.nextInt(4);
        _result = '熱門賽事預測比分 $home : $away';
      }
      _numbers = [];
    } else if (_type == '樂透') {
      // 樂透號碼 5 個 1~39
      _numbers = [];
      while (_numbers.length < 5) {
        final n = 1 + _rand.nextInt(39);
        if (!_numbers.contains(n)) _numbers.add(n);
      }
      _numbers.sort();
      _result = '預測號碼: ${_numbers.map((e) => e.toString().padLeft(2, '0')).join(", ")}';
    } else {
      // 賓果號碼 8 個 1~80，優先 hotNumbers、carryOverNumbers、recommended
      final pred = _bingoPred;
      final Set<int> pool = {};
      if (pred != null) {
        pool.addAll(pred.carryOverNumbers);
        pool.addAll(pred.hotNumbers);
        pool.addAll(pred.recommended);
      }
      // 若 pool 不足 8 個，隨機補齊
      while (pool.length < 8) {
        pool.add(1 + _rand.nextInt(80));
      }
      _numbers = pool.toList();
      _numbers.shuffle(_rand);
      _numbers = _numbers.take(8).toList()..sort();
      _result = '預測號碼: ${_numbers.map((e) => e.toString().padLeft(2, '0')).join(", ")}';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('模擬預測',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            if (_loadingBingo)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Color(0xFF3DDC97)),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3DDC97),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _generate,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('產生高命中預測',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            const SizedBox(height: 32),
            if (_type != null) ...[
              Text('$_type 預測',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Text(_result,
                  style: const TextStyle(
                      color: Color(0xFF3DDC97),
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ]
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 體育預測
// ═══════════════════════════════════════════════════════════════

class _SportsPredictionTab extends StatefulWidget {
  const _SportsPredictionTab();
  @override
  State<_SportsPredictionTab> createState() => _SportsPredictionTabState();
}

class _SportsPredictionTabState extends State<_SportsPredictionTab>
    with AutomaticKeepAliveClientMixin {
  final _service = PangPangSportsService();
  late Future<List<PredictionResult>> _future;
  String _selectedLeague = '全部';

  final List<String> _dateLabels = [];
  int _selectedDateIdx = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _buildDateLabels();
    _future = _service.getTodaysPredictions();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<PredictionResult>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF3DDC97)));
        }
        if (snap.hasError) {
          return Center(
              child: Text('載入失敗: ${snap.error}',
                  style: TextStyle(color: Colors.white70)));
        }
        final predictions = snap.data ?? [];

        final leagues = <String>{'全部'};
        for (final p in predictions) {
          leagues.add(p.fixture.league);
        }

        final filtered = _selectedLeague == '全部'
            ? predictions
            : predictions
                .where((p) => p.fixture.league == _selectedLeague)
                .toList();

        return Column(
          children: [
            const SizedBox(height: 8),
            // 日期選擇
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _dateLabels.length,
                itemBuilder: (_, i) {
                  final selected = i == _selectedDateIdx;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(_dateLabels[i],
                          style: TextStyle(
                            fontSize: 11,
                            color: selected ? Colors.black : Colors.white70,
                          )),
                      selected: selected,
                      selectedColor: const Color(0xFF3DDC97),
                      backgroundColor: const Color(0xFF1A2642),
                      onSelected: (_) => setState(() => _selectedDateIdx = i),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            // 聯賽篩選
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: leagues.map((l) {
                  final sel = l == _selectedLeague;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedLeague = l),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF3DDC97).withAlpha(40)
                              : const Color(0xFF1A2642),
                          borderRadius: BorderRadius.circular(8),
                          border: sel
                              ? Border.all(color: const Color(0xFF3DDC97))
                              : Border.all(color: Colors.white12),
                        ),
                        child: Text(l,
                            style: TextStyle(
                              fontSize: 11,
                              color: sel
                                  ? const Color(0xFF3DDC97)
                                  : Colors.white54,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            // 更新：使用專業預測卡片列表
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('目前無賽事', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        return _SportPredictionCard(result: filtered[i]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _buildDateLabels() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    for (int i = -3; i <= 3; i++) {
      final d = now.add(Duration(days: i));
      final wd = weekdays[d.weekday - 1];
      _dateLabels.add(
          '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} $wd');
    }
    _selectedDateIdx = 3;
  }
}

/// 單場體育預測卡片（類似 playsport.cc 風格）
class _SportPredictionCard extends StatelessWidget {
  const _SportPredictionCard({required this.result});
  final PredictionResult result;

  String _formatTime(DateTime t) {
    final tw = t.toUtc().add(const Duration(hours: 8));
    return 'AM ${tw.hour.toString().padLeft(2, '0')}:${tw.minute.toString().padLeft(2, '0')}';
  }

  String _sportLabel(SportType s) => switch (s) {
        SportType.baseball => 'MLB',
        SportType.basketball => 'NBA',
        SportType.football => '足球',
      };

  @override
  Widget build(BuildContext context) {
    final f = result.fixture;
    final p = result.prediction;
    final isCompleted = f.status == MatchStatus.completed;
    final isLive = f.status == MatchStatus.live;

    // 最準確的勝率來源：ensemble > MC fallback
    final ensH = p.ensembleHomeWinPct;
    final ensA = p.ensembleAwayWinPct;
    final ensD = p.ensembleDrawPct;
    final hasEnsemble = ensH > 0 || ensA > 0;
    final dispH = hasEnsemble ? ensH : 0.5;
    final dispA = hasEnsemble ? ensA : 0.5;
    final dispD = hasEnsemble ? ensD : 0.0;
    final isFootball = f.sport == SportType.football;
    final isDraw = isFootball && dispD > dispH && dispD > dispA;
    final predictHome = !isDraw && dispH >= dispA;
    final winnerName = predictHome ? f.homeTeam : f.awayTeam;
    final winnerPct = (predictHome ? dispH : dispA) * 100;

    // 是否命中（已結束）
    bool? mlHit;
    if (isCompleted) {
      if (isDraw) {
        mlHit = f.homeScore == f.awayScore;
      } else {
        mlHit = predictHome
            ? f.homeScore > f.awayScore
            : f.awayScore > f.homeScore;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131C31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        children: [
          // ── 標頭 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1A2642),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3DDC97).withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_sportLabel(f.sport),
                      style: const TextStyle(
                          color: Color(0xFF3DDC97),
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(f.league,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                if (isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(40),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  )
                else
                  Text(_formatTime(f.startTime),
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),

          // ── 比賽資訊 + 整合預測 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                // 左：主客隊
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _TeamRow(score: f.homeScore, team: f.homeTeam, isHome: true, status: f.status),
                      const SizedBox(height: 4),
                      _TeamRow(score: f.awayScore, team: f.awayTeam, isHome: false, status: f.status),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // 右：單一整合預測
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1525),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withAlpha(15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 推薦勝隊
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isDraw ? '🤝 和局' : '${predictHome ? "主" : "客"} $winnerName',
                                style: const TextStyle(
                                    color: Color(0xFF3DDC97),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (mlHit != null)
                              Icon(
                                mlHit ? Icons.check_circle : Icons.cancel,
                                size: 14,
                                color: mlHit ? const Color(0xFF3DDC97) : Colors.redAccent,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 勝率 + 預測比分
                        Text(
                          '勝率 ${winnerPct.round()}%　預測 ${p.predictedHomeScore}:${p.predictedAwayScore}',
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        // 信心度
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: p.confidence.clamp(0.0, 1.0),
                                  minHeight: 4,
                                  backgroundColor: Colors.white12,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    p.confidence >= 0.7
                                        ? const Color(0xFF3DDC97)
                                        : p.confidence >= 0.5
                                            ? Colors.orange
                                            : Colors.redAccent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${(p.confidence * 100).round()}%',
                              style: const TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          ],
                        ),
                        // 已結束：顯示實際比分對照
                        if (isCompleted) ...[
                          const SizedBox(height: 6),
                          Text(
                            '實際 ${f.homeScore}:${f.awayScore}',
                            style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow(
      {required this.score,
      required this.team,
      required this.isHome,
      required this.status});
  final int score;
  final String team;
  final bool isHome;
  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            status == MatchStatus.completed || status == MatchStatus.live
                ? '$score'
                : '',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$team${isHome ? " (主)" : " (客)"}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}


// ═══════════════════════════════════════════════════════════════
// 樂透預測（純預測，無投注金額）
// ═══════════════════════════════════════════════════════════════

class _LotteryPredictionTab extends StatefulWidget {
  const _LotteryPredictionTab();
  @override
  State<_LotteryPredictionTab> createState() => _LotteryPredictionTabState();
}

class _LotteryPredictionTabState extends State<_LotteryPredictionTab>
    with AutomaticKeepAliveClientMixin {
  final _service = LotteryService();
  int _lotteryType = 0; // 0=539, 1=大樂透, 2=威力彩
  bool _isLoading = false;
  LotteryFetchResult? _data;
  String _errorMsg = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });
    try {
      final result = await _service.fetchAndAnalyze();
      if (mounted) setState(() => _data = result);
    } catch (e) {
      if (mounted) setState(() => _errorMsg = '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _lotteryName => switch (_lotteryType) {
        0 => '今彩539',
        1 => '大樂透',
        _ => '威力彩',
      };

  /// 顯示推薦理由彈窗
  void _showReasonDialog(List<dynamic> results) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2642),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Color(0xFFFFD700)),
            const SizedBox(width: 10),
            Text('$_lotteryName 分析詳情',
                style: const TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: results.isEmpty
              ? const Text('暫無分析數據', style: TextStyle(color: Colors.white54))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: results.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Colors.white12, height: 24),
                  itemBuilder: (context, index) {
                    final r = results[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF3DDC97),
                          ),
                          child: Text(
                            r.number.toString().padLeft(2, '0'),
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            r.reason,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14, height: 1.4),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('了解',
                style: TextStyle(
                    color: Color(0xFF3DDC97), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 五格號碼輸入
  final List<TextEditingController> _numCtrls = List.generate(7, (_) => TextEditingController());

  @override
  void dispose() {
    for (final c in _numCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int requiredCount = switch (_lotteryType) {
      0 => 5, // 539
      1 => 6, // 大樂透
      _ => 7, // 威力彩 (6+1)
    };

    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF3DDC97)));
    if (_errorMsg.isNotEmpty) return Center(child: _ErrorCard(msg: _errorMsg, onRetry: _load));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      children: [
        // 彩種切換
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [0, 1, 2].map((i) {
            final labels = ['今彩539', '大樂透', '威力彩'];
            final sel = i == _lotteryType;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: sel ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.w700,
                    )),
                selected: sel,
                selectedColor: const Color(0xFF3DDC97),
                backgroundColor: const Color(0xFF1A2642),
                onSelected: (_) => setState(() => _lotteryType = i),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // 1. AI 預測卡片 (新增調用)
        _buildPredictionCard(),
        const SizedBox(height: 24),
        
        // 2. 手動選號區
        const Text('手動輸入號碼測試', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(requiredCount, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: requiredCount > 6 ? 38 : 46,
              child: TextField(
                controller: _numCtrls[i],
                keyboardType: TextInputType.number,
                maxLength: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF3DDC97)),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF131C31),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Color(0xFF3DDC97), width: 2),
                  ),
                ),
              ),
            ),
          )),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3DDC97),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
                    final nums = _numCtrls.take(requiredCount).map((c) => int.tryParse(c.text)).whereType<int>().toList();
                    final int maxNum = _lotteryType == 1 ? 49 : 39;
                    if (nums.length != requiredCount || nums.any((n) => n < 1 || n > maxNum)) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('請正確輸入 $requiredCount 個號碼 (1~$maxNum)')));
                return;
              }
              for (final c in _numCtrls) { c.clear(); }
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('預測已送出: ${nums.map((e) => e.toString().padLeft(2, '0')).join(', ')}')));
            },
            child: const Text('送出預測', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 18),
        // 3. 歷史開獎紀錄
        _buildHistoryCard(),
      ],
    );
  }

  Widget _buildPredictionCard() {
    final results = _data?.results ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131C31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 6),
              Text('$_lotteryName AI 預測',
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showReasonDialog(results),
                child: Icon(Icons.help_outline_rounded,
                    size: 16, color: Colors.white.withValues(alpha: 0.4)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3DDC97).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14, color: Color(0xFF3DDC97)),
                      SizedBox(width: 4),
                      Text('重算',
                          style: TextStyle(
                              color: Color(0xFF3DDC97),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (results.isEmpty)
            const Text('暫無預測結果',
                style: TextStyle(color: Colors.white54))
          else ...[
            // 號碼球
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: results.map((r) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF3DDC97),
                            const Color(0xFF2BB87D),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3DDC97).withAlpha(60),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Text(
                        r.number.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 56,
                      child: Text(
                        r.reason,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 8),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    final history = switch (_lotteryType) {
      0 => _data?.records539 ?? [],
      1 => _data?.recordsLotto ?? [],
      _ => _data?.recordsPower ?? [],
    };
    if (history.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131C31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history, color: Colors.white54, size: 16),
              SizedBox(width: 6),
              Text('近期開獎紀錄',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ...history.take(10).map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(h.date,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        children: h.numbers
                            .map((n) => Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF0D1E4A),
                                    border: Border.all(
                                        color: Colors.white.withAlpha(15)),
                                  ),
                                  child: Text(
                                    n.toString().padLeft(2, '0'),
                                    style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 賓果預測（含獎金配置表 + 模擬開獎）
// ═══════════════════════════════════════════════════════════════

class _BingoPredictionTab extends StatefulWidget {
  const _BingoPredictionTab();
  @override
  State<_BingoPredictionTab> createState() => _BingoPredictionTabState();
}

class _BingoPredictionTabState extends State<_BingoPredictionTab>
    with AutomaticKeepAliveClientMixin {
  final _service = BingoService();
  final _rand = Random();

  List<BingoRecord> _records = [];
  BingoPrediction? _pred;
  bool _isLoading = false;
  String _errorMsg = '';

  int _starCount = 5;
  final List<TextEditingController> _bingoNumCtrls = List.generate(10, (_) => TextEditingController());

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });
    try {
      final records = await _service.fetchRecent();
      final pred = BingoService.analyze(records, seed: 0);
      if (mounted) {
        setState(() {
          _records = records;
          _pred = pred;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 模擬開獎
  void _simulateDraw() {
    final drawn = <int>{};
    while (drawn.length < 20) {
      drawn.add(_rand.nextInt(80) + 1);
    }
    final drawnList = drawn.toList()..sort();
    final superNumber = drawnList.last;

    final isBig = drawnList.where((n) => n >= 41).length >= 13;
    final isOdd = drawnList.where((n) => n % 2 == 1).length >= 13;

    // 用預測號碼對比
    final predNums = _pred?.carryOverNumbers ?? [];
    final hits = predNums.where((n) => drawn.contains(n)).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2642),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🎱 模擬開獎結果',
            style: TextStyle(
                color: Color(0xFFFFD700), fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('開出號碼：',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: drawnList.map((n) {
                    final isSuper = n == superNumber;
                    final isPredHit = predNums.contains(n);
                    return Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSuper
                            ? const Color(0xFFFFD700)
                            : isPredHit
                                ? const Color(0xFF3DDC97)
                                : const Color(0xFF4FC3F7),
                        border: isPredHit
                            ? Border.all(
                                color: Colors.white, width: 2)
                            : null,
                      ),
                      child: Text(
                        n.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Text(
                    '超級獎號: ${superNumber.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        color: Color(0xFFFFD700), fontSize: 12)),
                Text(
                    '大${isBig ? "✓" : ""} / 小${!isBig ? "✓" : ""}  ·  '
                    '單${isOdd ? "✓" : ""} / 雙${!isOdd ? "✓" : ""}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11)),
                const Divider(color: Colors.white12, height: 20),
                if (predNums.isNotEmpty) ...[
                  Text('預測命中: $hits / ${predNums.length}',
                      style: TextStyle(
                        color: hits > 0
                            ? const Color(0xFF3DDC97)
                            : Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      )),
                  if (hits > 0 && _starCount <= 10) ...[
                    const SizedBox(height: 4),
                    Builder(builder: (_) {
                      final prize = _basicPrize[_starCount]?[hits] ?? 0;
                      return Text(
                        prize > 0
                            ? '$_starCount星中$hits → 獎金 \$${_formatPrize(prize)}'
                            : '$_starCount星中$hits → 未達中獎門檻',
                        style: TextStyle(
                          color: prize > 0
                              ? const Color(0xFFFFD700)
                              : Colors.white38,
                          fontSize: 12,
                        ),
                      );
                    }),
                  ],
                ] else
                  const Text('尚無預測號碼',
                      style: TextStyle(color: Colors.white38)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('確認',
                style: TextStyle(color: Color(0xFF3DDC97))),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _bingoNumCtrls) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF3DDC97)));
    if (_errorMsg.isNotEmpty) return Center(child: _ErrorCard(msg: _errorMsg, onRetry: _load));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      children: [
        // 1. AI 分析區塊
        _buildBasicPrediction(),
        const SizedBox(height: 14),
        _buildSuperPrediction(),
        const SizedBox(height: 14),
        _buildBigSmallPrediction(),
        const SizedBox(height: 14),
        _buildOddEvenPrediction(),
        const SizedBox(height: 20),

        // 2. 模擬功能按鈕
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _simulateDraw,
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('模擬隨機開獎'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFD700),
                  side: const BorderSide(color: Color(0xFFFFD700)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        
        const Divider(height: 40, color: Colors.white12),

        // 3. 手動選號區
        const Text('手動預測選號', 
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        // 星數選擇 (改為橫向滾動防止溢出)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(10, (i) {
              final star = i + 1;
              final sel = star == _starCount;
              return GestureDetector(
                onTap: () => setState(() => _starCount = star),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFFD700) : const Color(0xFF1A2642),
                    borderRadius: BorderRadius.circular(10),
                    border: sel 
                        ? Border.all(color: const Color(0xFFFFD700), width: 2) 
                        : Border.all(color: Colors.white12),
                  ),
                  child: Text('$star 星', 
                    style: TextStyle(
                      color: sel ? Colors.black : Colors.white54, 
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 20),
        // 動態號碼輸入
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_starCount, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 44,
              child: TextField(
                controller: _bingoNumCtrls[i],
                keyboardType: TextInputType.number,
                maxLength: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF3DDC97)),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF131C31),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFF3DDC97), width: 2),
                  ),
                ),
              ),
            ),
          )),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3DDC97),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              final nums = _bingoNumCtrls.take(_starCount).map((c) => int.tryParse(c.text)).whereType<int>().toList();
              if (nums.length != _starCount || nums.any((n) => n < 1 || n > 80)) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('請輸入$_starCount 個 1~80 的號碼')));
                return;
              }
              for (final c in _bingoNumCtrls) { c.clear(); }
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('預測已送出: ${nums.map((e) => e.toString().padLeft(2, '0')).join(', ')}')));
            },
            child: const Text('送出預測', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 18),
        // 4. 獎金配置表
        _buildPrizeTable(),
      ],
    );
  }

  Widget _buildBasicPrediction() {
    final pred = _pred;
    final hotNums = pred?.hotNumbers ?? [];
    final coldNums = pred?.coldNumbers ?? [];
    final carryOver = pred?.carryOverNumbers ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131C31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 星數選擇
          Row(
            children: [
              const Text('選擇星數查看預測',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3DDC97).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh,
                          size: 13, color: Color(0xFF3DDC97)),
                      SizedBox(width: 4),
                      Text('重新分析',
                          style: TextStyle(
                              color: Color(0xFF3DDC97),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: List.generate(10, (i) {
              final star = i + 1;
              final sel = star == _starCount;
              return GestureDetector(
                onTap: () => setState(() => _starCount = star),
                child: Container(
                  width: 36,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF0D1E4A),
                    borderRadius: BorderRadius.circular(8),
                    border: sel
                        ? null
                        : Border.all(color: Colors.white.withAlpha(15)),
                  ),
                  child: Text('$star星',
                      style: TextStyle(
                        color: sel ? Colors.black : Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),

          // 連莊預測
          if (carryOver.isNotEmpty) ...[
            const Text('🔁 連莊預測號碼',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: carryOver.take(_starCount).map((n) {
                return Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFE8A000)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withAlpha(50),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Text(
                    n.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w900),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // 熱門號碼
          if (hotNums.isNotEmpty) ...[
            const Text('🔥 熱門號碼',
                style: TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: hotNums.take(10).map((n) {
                return Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF6B6B).withAlpha(30),
                    border: Border.all(
                        color: const Color(0xFFFF6B6B).withAlpha(80)),
                  ),
                  child: Text(
                    n.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        color: Color(0xFFFF6B6B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],

          // 冷門號碼
          if (coldNums.isNotEmpty) ...[
            const Text('❄️ 冷門號碼',
                style: TextStyle(
                    color: Color(0xFF4FC3F7),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: coldNums.take(10).map((n) {
                return Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4FC3F7).withAlpha(25),
                    border: Border.all(
                        color: const Color(0xFF4FC3F7).withAlpha(70)),
                  ),
                  child: Text(
                    n.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        color: Color(0xFF4FC3F7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuperPrediction() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131C31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star, color: Color(0xFFFFD700), size: 18),
              SizedBox(width: 6),
              Text('超級獎號預測',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
              '當期開出第20個號碼為超級獎號\n猜中可得固定獎金倍數 48 倍，單注獎金 \$1,200',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          // 用最近開獎的超級獎號做簡單預測
          Builder(builder: (_) {
            final recentSuper = _records.isNotEmpty
                ? _records.first.numbers.last
                : _rand.nextInt(80) + 1;
            return Row(
              children: [
                const Text('預測超級獎號：',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13)),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFD700),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withAlpha(60),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Text(
                    recentSuper.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBigSmallPrediction() {
    // 分析最近的大小趨勢
    int bigCount = 0;
    for (final r in _records.take(10)) {
      final bigNums = r.numbers.where((n) => n >= 41).length;
      if (bigNums >= 13) bigCount++;
    }
    final predictBig = bigCount >= 5;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131C31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('猜大小預測',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
              '41~80 開出13個(含)以上為「大」\n01~40 開出13個(含)以上為「小」',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 6),
          const Text('固定獎金倍數 6 倍，單注獎金 \$150',
              style:
                  TextStyle(color: Color(0xFFFFD700), fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: predictBig
                      ? const Color(0xFF3DDC97).withAlpha(30)
                      : const Color(0xFF0D1E4A),
                  borderRadius: BorderRadius.circular(12),
                  border: predictBig
                      ? Border.all(
                          color: const Color(0xFF3DDC97), width: 2)
                      : Border.all(color: Colors.white.withAlpha(15)),
                ),
                child: Text('大',
                    style: TextStyle(
                      color: predictBig
                          ? const Color(0xFF3DDC97)
                          : Colors.white54,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    )),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: !predictBig
                      ? const Color(0xFF3DDC97).withAlpha(30)
                      : const Color(0xFF0D1E4A),
                  borderRadius: BorderRadius.circular(12),
                  border: !predictBig
                      ? Border.all(
                          color: const Color(0xFF3DDC97), width: 2)
                      : Border.all(color: Colors.white.withAlpha(15)),
                ),
                child: Text('小',
                    style: TextStyle(
                      color: !predictBig
                          ? const Color(0xFF3DDC97)
                          : Colors.white54,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    )),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '近10期：大 $bigCount 次 / 小 ${10 - bigCount} 次\n預測下期: ${predictBig ? "大" : "小"}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOddEvenPrediction() {
    int oddCount = 0;
    for (final r in _records.take(10)) {
      final oddNums = r.numbers.where((n) => n % 2 == 1).length;
      if (oddNums >= 13) oddCount++;
    }
    final predictOdd = oddCount >= 5;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131C31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('猜單雙預測',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
              '單數號碼開出13個(含)以上為「單」\n雙數號碼開出13個(含)以上為「雙」',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 6),
          const Text('固定獎金倍數 6 倍，單注獎金 \$150',
              style:
                  TextStyle(color: Color(0xFFFFD700), fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: predictOdd
                      ? const Color(0xFF3DDC97).withAlpha(30)
                      : const Color(0xFF0D1E4A),
                  borderRadius: BorderRadius.circular(12),
                  border: predictOdd
                      ? Border.all(
                          color: const Color(0xFF3DDC97), width: 2)
                      : Border.all(color: Colors.white.withAlpha(15)),
                ),
                child: Text('單',
                    style: TextStyle(
                      color: predictOdd
                          ? const Color(0xFF3DDC97)
                          : Colors.white54,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    )),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: !predictOdd
                      ? const Color(0xFF3DDC97).withAlpha(30)
                      : const Color(0xFF0D1E4A),
                  borderRadius: BorderRadius.circular(12),
                  border: !predictOdd
                      ? Border.all(
                          color: const Color(0xFF3DDC97), width: 2)
                      : Border.all(color: Colors.white.withAlpha(15)),
                ),
                child: Text('雙',
                    style: TextStyle(
                      color: !predictOdd
                          ? const Color(0xFF3DDC97)
                          : Colors.white54,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    )),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '近10期：單 $oddCount 次 / 雙 ${10 - oddCount} 次\n預測下期: ${predictOdd ? "單" : "雙"}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 賓果獎金配置表（台灣彩券官方）────────────────────────────
  static const Map<int, Map<int, int>> _basicPrize = {
    10: {10: 5000000, 9: 250000, 8: 25000, 7: 2500, 6: 250, 5: 25, 0: 25},
    9: {9: 1000000, 8: 100000, 7: 3000, 6: 500, 5: 100, 4: 25, 0: 25},
    8: {8: 500000, 7: 20000, 6: 1000, 5: 200, 4: 25, 3: 25, 0: 25},
    7: {7: 80000, 6: 3000, 5: 300, 4: 50, 3: 25},
    6: {6: 25000, 5: 1000, 4: 200, 3: 25},
    5: {5: 7500, 4: 500, 3: 50, 2: 25},
    4: {4: 1000, 3: 100, 2: 50},
    3: {3: 500, 2: 75},
    2: {2: 50, 1: 25},
    1: {1: 25},
  };

  Widget _buildPrizeTable() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131C31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events,
                  color: Color(0xFFFFD700), size: 18),
              SizedBox(width: 6),
              Text('基本玩法獎金表',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              Spacer(),
              Text('最高獎金 500萬',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 12,
              headingRowHeight: 32,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 28,
              headingTextStyle: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 10,
                  fontWeight: FontWeight.w800),
              dataTextStyle: const TextStyle(
                  color: Colors.white70, fontSize: 10),
              headingRowColor: WidgetStateProperty.all(
                  const Color(0xFF1A2642)),
              columns: const [
                DataColumn(label: Text('獎項')),
                DataColumn(label: Text('10星')),
                DataColumn(label: Text('9星')),
                DataColumn(label: Text('8星')),
                DataColumn(label: Text('7星')),
                DataColumn(label: Text('6星')),
                DataColumn(label: Text('5星')),
                DataColumn(label: Text('4星')),
                DataColumn(label: Text('3星')),
                DataColumn(label: Text('2星')),
                DataColumn(label: Text('1星')),
              ],
              rows: [
                _prizeRow('中10',
                    [5000000, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
                _prizeRow(
                    '中9', [250000, 1000000, 0, 0, 0, 0, 0, 0, 0, 0]),
                _prizeRow('中8',
                    [25000, 100000, 500000, 0, 0, 0, 0, 0, 0, 0]),
                _prizeRow('中7',
                    [2500, 3000, 20000, 80000, 0, 0, 0, 0, 0, 0]),
                _prizeRow('中6',
                    [250, 500, 1000, 3000, 25000, 0, 0, 0, 0, 0]),
                _prizeRow(
                    '中5', [25, 100, 200, 300, 1000, 7500, 0, 0, 0, 0]),
                _prizeRow(
                    '中4', [0, 25, 25, 50, 200, 500, 1000, 0, 0, 0]),
                _prizeRow(
                    '中3', [0, 0, 25, 25, 25, 50, 100, 500, 0, 0]),
                _prizeRow(
                    '中2', [0, 0, 0, 0, 0, 25, 50, 75, 50, 0]),
                _prizeRow(
                    '中1', [0, 0, 0, 0, 0, 0, 0, 0, 25, 25]),
                _prizeRow(
                    '中0', [25, 25, 25, 0, 0, 0, 0, 0, 0, 0]),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1E4A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('⭐ 超級獎號: 固定 48 倍，獎金 \$1,200',
                    style: TextStyle(
                        color: Color(0xFFFFD700), fontSize: 11)),
                SizedBox(height: 4),
                Text('📊 猜大小: 固定 6 倍，獎金 \$150',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 11)),
                SizedBox(height: 4),
                Text('🔢 猜單雙: 固定 6 倍，獎金 \$150',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _prizeRow(String label, List<int> prizes) {
    return DataRow(
      cells: [
        DataCell(Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700))),
        ...prizes.map((p) => DataCell(
              Text(
                p > 0 ? _formatPrize(p) : '',
                style: TextStyle(
                  color: p >= 100000
                      ? const Color(0xFFFFD700)
                      : p > 0
                          ? const Color(0xFF3DDC97)
                          : Colors.transparent,
                  fontWeight:
                      p >= 100000 ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 10,
                ),
              ),
            )),
      ],
    );
  }

  String _formatPrize(int p) {
    if (p >= 1000000) return '${(p / 10000).round()}萬';
    if (p >= 10000) return '${(p / 10000).toStringAsFixed(1)}萬';
    return '\$$p';
  }
}

// ═══════════════════════════════════════════════════════════════
// 共用小元件
// ═══════════════════════════════════════════════════════════════

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.msg, required this.onRetry});
  final String msg;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withAlpha(40)),
      ),
      child: Column(
        children: [
          Text('載入失敗: $msg',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onRetry,
            child: const Text('點此重試',
                style: TextStyle(
                    color: Color(0xFF3DDC97),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
