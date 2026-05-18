import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lottery_model.dart';
import '../models/newspaper_539_data.dart';
import '../models/prediction_log.dart';
import '../services/ai_prediction_service.dart';
import '../services/lottery_service.dart';
import '../services/prediction_log_service.dart';
import '../services/failure_analysis_service.dart';
import '../widgets/lottery_prediction_card.dart';

/// 財神爺樂透預測頁面
///
/// 功能：539 / 大樂透 / 威力彩 AI 推薦號碼 + 歷史開獎記錄 + 紅框輸入
class LotteryScreen extends StatefulWidget {
  const LotteryScreen({super.key});

  @override
  State<LotteryScreen> createState() => _LotteryScreenState();
}

class _LotteryScreenState extends State<LotteryScreen> with WidgetsBindingObserver {
  final _service = LotteryService();
  // 孤支/二中一/三中一 分欄輸入
  final _guzhiCtrl    = TextEditingController(); // 孤支（1個）
  final _erzhongCtrl  = TextEditingController(); // 二中一（最多2個，逗號分隔）
  final _sanzhongCtrl = TextEditingController(); // 三中一（最多3個，逗號分隔）

  LotteryFetchResult? _data;
  String? _loadError;
  bool _isLoading = false;
  bool _showHistory = true;   // 預設展開
  bool _showHintInput = false;
  bool _showFiveDayProjection = true;
  int _historyTab = 0; // 0=539 1=大樂透 2=威力彩
  PredictionLog? _lastLotteryLog;

  bool _isRefreshing = false; // 背景更新中（已有快取資料時）

  // ── 今日開獎比對 ───────────────────────────────────────────────
  final List<TextEditingController> _drawnCtrls =
      List.generate(5, (_) => TextEditingController());
  List<int>? _hitNumbers;    // null = 尚未比對
  bool _showDrawnInput = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoFillNewspaper();
    _loadWithCache();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _guzhiCtrl.dispose();
    _erzhongCtrl.dispose();
    _sanzhongCtrl.dispose();
    for (final c in _drawnCtrls) { c.dispose(); }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AiPredictionService.instance.clearLotteryCache();
      AiPredictionService.instance.clearBingoCache();
      _load();
    }
  }

  // ── 報紙資料 ───────────────────────────────────────────────────

  Newspaper539Entry? get _todayNewspaper {
    final now = _taiwanNow;
    final key = '${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')}';
    return newspaper539Data[key];
  }

  void _autoFillNewspaper() {
    final np = _todayNewspaper;
    if (np == null) return;
    _guzhiCtrl.text = np.guZhi.toString();
    _erzhongCtrl.text = np.erZhong.join(', ');
    _sanzhongCtrl.text = np.sanZhong.join(', ');
  }

  // ── 台灣時區 ───────────────────────────────────────────────────

  DateTime get _taiwanNow =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  String get _todayLabel {
    final now = _taiwanNow;
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final wd = weekdays[now.weekday - 1];
    return '${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')} (週$wd)';
  }

  String get _todayDrawKey {
    final now = _taiwanNow;
    return '${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')}';
  }

  // ── 資料載入 ───────────────────────────────────────────────────

  final _logSvc = PredictionLogService();
  late final _analysisSvc = FailureAnalysisService(_logSvc);

  /// 先顯示快取資料（零延遲），再背景拉取最新開獎更新 UI
  Future<void> _loadWithCache() async {
    final cached = await LotteryService.loadCached539();
    if (cached.isNotEmpty && mounted) {
      // 有快取 → 先顯示舊資料，同時背景更新
      setState(() { _isRefreshing = true; _loadError = null; });
      _load(); // fire & forget
    } else {
      // 無快取 → 正常全屏載入
      _load();
    }
  }

  Future<void> _load() async {
    if (!_isRefreshing) setState(() { _isLoading = true; _loadError = null; });

    try {
      Map<String, double> multipliers = {};
      try {
        final analysis = await _analysisSvc.analyze();
        multipliers = analysis.strategyMultipliers;
      } catch (_) {}

      final hints = _buildHints();
      final npBonuses = _todayNewspaper?.extraBonuses ?? {};
      final result = await _service.fetchAndAnalyze(
          redHints: hints,
          excludeNumbers: [_taiwanNow.day],
          strategyMultipliers: multipliers,
          newspaperBonuses: npBonuses);

      final numbers = result.results.map((r) => r.number).toList();
      if (numbers.isNotEmpty) {
        final Map<int, String> reasons = {for (final r in result.results) r.number: r.reason};
        await _logSvc.saveLotteryPrediction(
          lotteryType: '539',
          drawNo: _todayDrawKey,
          numbers: numbers,
          reasonsByNumber: reasons,
        );
      }

      final byDate = <String, List<int>>{};
      for (final r in result.records539) {
        if (r.date.isEmpty || r.numbers.isEmpty) continue;
        byDate[r.date] = r.numbers;
      }
      await _logSvc.autoReportLotteryByDate(byDate);

      final lotteryLogs = await _logSvc.loadByType(PredictionType.lottery);
      final lastCompleted = lotteryLogs.firstWhere(
        (l) => (l.actualResult ?? '').isNotEmpty,
        orElse: () => lotteryLogs.isNotEmpty ? lotteryLogs.first : PredictionLog(
          id: '', type: PredictionType.lottery, createdAt: DateTime.now(),
          title: '', subtitle: '', predictedResult: '',
        ),
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _data = result;
        if (lastCompleted.id.isNotEmpty &&
            (lastCompleted.actualResult ?? '').isNotEmpty) {
          _lastLotteryLog = lastCompleted;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        if (_data == null) _loadError = e.toString();
      });
    }
  }

  /// 從三個分欄組合出 redHints 陣列：孤支 → 二中一 → 三中一
  List<int> _buildHints() {
    List<int> parseNums(String text, int max) => text
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((n) => n >= 1 && n <= 39)
        .take(max)
        .toList();
    final guZhi   = parseNums(_guzhiCtrl.text, 1);
    final erZhong = parseNums(_erzhongCtrl.text, 2);
    final sanZhong = parseNums(_sanzhongCtrl.text, 3);
    return [...guZhi, ...erZhong, ...sanZhong];
  }

  // ── 顏色常數（財神爺紅金配色）─────────────────────────────────

  static const Color _bgDeep  = Color(0xFF6B0000);
  static const Color _bgMid   = Color(0xFFA52A2A);
  static const Color _bgLight = Color(0xFFC0392B);
  static const Color _gold    = Color(0xFFFFD700);
  static const Color _goldAlt = Color(0xFFFFB800);

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bgDeep, _bgMid, _bgLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: _gold,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _headerSection(),
                const SizedBox(height: 10),
                _statusBar(),
                if (_isLoading) ...[
                  const SizedBox(height: 40),
                  const Center(child: CircularProgressIndicator(color: _gold)),
                ] else if (_loadError != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(40),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withAlpha(100)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 32),
                        const SizedBox(height: 8),
                        Text('載入失敗，請下拉重試', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(_loadError!, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (_lastLotteryLog != null) _lastDrawComparison(_lastLotteryLog!),
                if (_lastLotteryLog != null) const SizedBox(height: 14),
                if (_data != null)
                  Lottery539PredictionCard(
                    data: _data!,
                    taiwanNow: _taiwanNow,
                  ),
                if (_data != null) const SizedBox(height: 14),
                _predictionCard(),
                const SizedBox(height: 14),
                _drawnNumberInput(),
                const SizedBox(height: 14),
                _analysisSection(),
                const SizedBox(height: 14),
                _dragPatternSection(),
                const SizedBox(height: 14),
                _fiveDayProjectionSection(),
                const SizedBox(height: 14),
                _historySection(),
                const SizedBox(height: 14),
                _hintSection(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 上一期預測對照 ──────────────────────────────────────────────

  Widget _lastDrawComparison(PredictionLog log) {
    final predicted = log.predictedResult
        .split(' ')
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toList();
    final actualStr = log.actualResult ?? '';
    final actual = actualStr
        .split(' ')
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toSet();
    final hits = predicted.where((n) => actual.contains(n)).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6B0000).withAlpha(180),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: Color(0xFFFFD700), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(log.title,
                    style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hits.length >= 3
                      ? Colors.green.withAlpha(60)
                      : hits.length >= 2
                          ? Colors.orange.withAlpha(60)
                          : Colors.red.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '命中 ${hits.length} / ${predicted.length}',
                  style: TextStyle(
                    color: hits.length >= 3
                        ? Colors.greenAccent
                        : hits.length >= 2
                            ? Colors.orange
                            : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('上期預測', style: TextStyle(color: _gold.withAlpha(160), fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: predicted.map((n) {
              final isHit = actual.contains(n);
              return Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isHit ? _gold : const Color(0xFF8B0000),
                  border: isHit ? null : Border.all(color: _gold.withAlpha(80)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$n',
                  style: TextStyle(
                    color: isHit ? Colors.black : Colors.white70,
                    fontSize: 12,
                    fontWeight: isHit ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
          if (actual.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('實際開獎', style: TextStyle(color: _gold.withAlpha(160), fontSize: 11)),
            const SizedBox(height: 4),
            Text(actualStr.replaceAll(' ', '  '),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  // ── 今日開獎比對輸入 ───────────────────────────────────────────

  void _compareDrawnNumbers() {
    final drawn = _drawnCtrls
        .map((c) => int.tryParse(c.text.trim()))
        .whereType<int>()
        .where((n) => n >= 1 && n <= 39)
        .toSet();
    if (drawn.length < 5) return;

    final predicted = (_data?.results ?? [])
        .map((r) => r.number)
        .toSet();
    final hits = predicted.intersection(drawn).toList()..sort();

    setState(() => _hitNumbers = hits);

    // 自動回填最新一筆待定的樂透預測記錄
    _logSvc.autoReportLotteryByDate({_todayDrawKey: drawn.toList()..sort()});
  }

  Widget _drawnNumberInput() {
    final predicted = (_data?.results ?? []).map((r) => r.number).toSet();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          GestureDetector(
            onTap: () => setState(() => _showDrawnInput = !_showDrawnInput),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: _gold, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '今日開獎比對',
                    style: TextStyle(
                        color: _gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                if (_hitNumbers != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _hitNumbers!.length >= 3
                          ? Colors.green.withAlpha(60)
                          : _hitNumbers!.length >= 2
                              ? Colors.orange.withAlpha(60)
                              : Colors.red.withAlpha(50),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '命中 ${_hitNumbers!.length} 個',
                      style: TextStyle(
                        color: _hitNumbers!.length >= 3
                            ? Colors.greenAccent
                            : _hitNumbers!.length >= 2
                                ? Colors.orange
                                : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _showDrawnInput ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Colors.white38, size: 20),
                ),
              ],
            ),
          ),

          if (_showDrawnInput) ...[
            const SizedBox(height: 12),
            const Text('輸入今日開獎 5 個號碼（1–39）',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 10),

            // 5 number inputs
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _DrawnNumberBox(ctrl: _drawnCtrls[i]),
                );
              }),
            ),
            const SizedBox(height: 12),

            // Compare button
            Center(
              child: ElevatedButton.icon(
                onPressed: _compareDrawnNumbers,
                icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                label: const Text('比對結果'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold.withAlpha(200),
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            // Hit result
            if (_hitNumbers != null) ...[
              const SizedBox(height: 14),
              const Divider(color: Colors.white12),
              const SizedBox(height: 10),
              if (_hitNumbers!.isEmpty)
                const Center(
                  child: Text('本次未命中任何推薦號碼',
                      style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                )
              else ...[
                Text(
                  '命中號碼：${_hitNumbers!.map((n) => n.toString().padLeft(2, '0')).join('  ')}',
                  style: const TextStyle(
                      color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                // Show all predicted numbers with hit highlight
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: predicted.map((n) {
                    final isHit = _hitNumbers!.contains(n);
                    return Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isHit ? _gold : Colors.white.withAlpha(18),
                        border: isHit ? null : Border.all(color: Colors.white24),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        n.toString().padLeft(2, '0'),
                        style: TextStyle(
                          color: isHit ? Colors.black : Colors.white54,
                          fontSize: 11,
                          fontWeight: isHit ? FontWeight.w900 : FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────

  Widget _headerSection() {
    return Row(
      children: [
        // 胖胖體育 logo（同一張熊貓照片）
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/bear.jpeg',
            width: 52,
            height: 52,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '財神爺樂透',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '539 數據智能引擎',
                style: TextStyle(fontSize: 12, color: Color(0xAAFFD700)),
              ),
            ],
          ),
        ),
        if (_isRefreshing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
            ),
          )
        else
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: _gold),
            tooltip: '重新分析',
          ),
      ],
    );
  }

  // ── Status Bar ─────────────────────────────────────────────────

  Widget _statusBar() {
    final hasNewspaper = _todayNewspaper != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 15, color: _gold),
              const SizedBox(width: 6),
              Text(
                _todayLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _gold,
                ),
              ),
              const Spacer(),
              const Icon(Icons.cancel_outlined, size: 15, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                '今日排除：${_taiwanNow.day.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.orange),
              ),
            ],
          ),
          if (hasNewspaper) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _gold.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _gold.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Text('📰', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已載入喜雀神卦：孤支 ${_todayNewspaper!.guZhi.toString().padLeft(2, '0')}　'
                      '二中一 ${_todayNewspaper!.erZhong.map((n) => n.toString().padLeft(2, '0')).join(', ')}　'
                      '三中一 ${_todayNewspaper!.sanZhong.map((n) => n.toString().padLeft(2, '0')).join(', ')}',
                      style: TextStyle(
                          color: _gold.withAlpha(220),
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }


  // ── 拖牌提示區塊 ───────────────────────────────────────────────

  bool _showDrag = true;

  Widget _dragPatternSection() {
    final patterns = _data?.dragPatterns ?? [];
    final due = patterns.where((p) => p.isDueNext).toList();
    final nearDue = patterns.where((p) =>
        !p.isDueNext &&
        p.currentGap >= 0 &&
        p.currentGap == p.interval - 1 &&
        p.hitRate >= 0.75).toList();

    final active = _data?.activeDragNumbers ?? [];

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _showDrag = !_showDrag),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Colors.black.withAlpha(55),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 16, color: _gold),
                  const SizedBox(width: 6),
                  const Text('拖牌提示',
                      style: TextStyle(
                          fontSize: 13,
                          color: _gold,
                          fontWeight: FontWeight.w600)),
                  if (active.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(180),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${active.length}個命中',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                  const Spacer(),
                  Icon(_showDrag ? Icons.expand_less : Icons.expand_more,
                      color: _gold, size: 18),
                ],
              ),
            ),
          ),
          if (_showDrag)
            Container(
              width: double.infinity,
              color: Colors.black.withAlpha(33),
              padding: const EdgeInsets.all(12),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _gold))
                  : patterns.isEmpty
                      ? Text('拖牌資料載入中…',
                          style: TextStyle(
                              fontSize: 12, color: Colors.white.withAlpha(160)))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (active.isNotEmpty) ...[
                              Text('🔴 本期拖牌目標號碼',
                                  style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: active.map((n) => Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.red.withAlpha(200),
                                    border: Border.all(color: _gold, width: 1.5),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(n.toString().padLeft(2, '0'),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13)),
                                )).toList(),
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (due.isNotEmpty) ...[
                              Text('🔴 即將命中（本期）',
                                  style: TextStyle(
                                      color: Colors.red.withAlpha(220),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              ...due.map((p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(p.description,
                                        style: TextStyle(
                                            color: Colors.red.withAlpha(200),
                                            fontSize: 11,
                                            fontFamily: 'monospace')),
                                  )),
                              const SizedBox(height: 8),
                            ],
                            if (nearDue.isNotEmpty) ...[
                              Text('🟡 下一期即到（命中率≥75%）',
                                  style: TextStyle(
                                      color: Colors.orange.withAlpha(220),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              ...nearDue.map((p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(p.description,
                                        style: TextStyle(
                                            color: Colors.orange.withAlpha(180),
                                            fontSize: 11,
                                            fontFamily: 'monospace')),
                                  )),
                            ],
                            if (due.isEmpty && nearDue.isEmpty)
                              Text('目前無即將命中的拖牌訊號',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withAlpha(130))),
                          ],
                        ),
            ),
        ],
      ),
    );
  }

  // ── 統計預測卡片 ───────────────────────────────────────────────

  Widget _predictionCard() {
    final results = _data?.results ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: _gold, size: 16),
            const SizedBox(width: 8),
            const Text('胖胖推薦號碼',
                style: TextStyle(
                    color: _gold, fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: _gold))
          else if (results.isEmpty)
            Text('資料載入中，請稍後…',
                style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13))
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: results.map((r) => _numberBubble(r.number)).toList(),
            ),
            const SizedBox(height: 14),
            ...results.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.displayNumber,
                        style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r.reason,
                            style: TextStyle(
                                color: Colors.white.withAlpha(180),
                                fontSize: 12)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // ── 五星智能分析區塊 ───────────────────────────────────────────

  bool _showAnalysis = true;

  Widget _analysisSection() {
    final da = _data?.detailedAnalysis;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _showAnalysis = !_showAnalysis),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Colors.black.withAlpha(55),
              child: Row(
                children: [
                  const Icon(Icons.analytics_rounded, size: 16, color: _gold),
                  const SizedBox(width: 6),
                  const Text('五星智能分析',
                      style: TextStyle(
                          fontSize: 13,
                          color: _gold,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(
                    _showAnalysis ? Icons.expand_less : Icons.expand_more,
                    color: _gold,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_showAnalysis)
            Container(
              color: Colors.black.withAlpha(38),
              padding: const EdgeInsets.all(14),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _gold))
                  : da == null || da.recommendedCombos.isEmpty
                      ? Text('資料載入中…',
                          style: TextStyle(
                              color: Colors.white.withAlpha(140),
                              fontSize: 12))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── 走勢摘要 ──────────────────────
                            _analysisSummaryRow(da),
                            const SizedBox(height: 12),
                            // ── 三組推薦 ──────────────────────
                            ...da.recommendedCombos
                                .asMap()
                                .entries
                                .map((e) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _comboCard(e.key, e.value),
                                    )),
                            // ── 同尾 & 連號參考 ───────────────
                            if (da.topConsecutivePairs.isNotEmpty ||
                                da.topSameTailPairs.isNotEmpty)
                              _pairReferenceRow(da),
                          ],
                        ),
            ),
        ],
      ),
    );
  }

  Widget _analysisSummaryRow(dynamic da) {
    final d = da;
    final hotTails = (d.hotTailDigits as List<int>)
        .map((t) => '$t尾')
        .join('、');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _gold.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _gold.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.bar_chart_rounded, size: 13, color: _gold),
            const SizedBox(width: 5),
            Text('近期走勢摘要',
                style: TextStyle(
                    color: _gold.withAlpha(220),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          _summaryChip('熱門尾數', hotTails.isEmpty ? '—' : hotTails),
          const SizedBox(height: 4),
          _summaryChip('奇偶', d.oddEvenTrend as String),
          const SizedBox(height: 4),
          _summaryChip('大小', d.bigSmallTrend as String),
          const SizedBox(height: 4),
          _summaryChip('近15期均值', '和值 ${(d.avgSum as double).toStringAsFixed(1)}（標準100）'),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: TextStyle(
                  color: _gold.withAlpha(160), fontSize: 11)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _comboCard(int index, dynamic combo) {
    final c = combo as dynamic;
    final numbers = c.numbers as List<int>;
    final colors = [Colors.red.shade700, Colors.orange.shade700, Colors.green.shade700];
    final headerColor = colors[index % 3];
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(40),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: headerColor.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: headerColor.withAlpha(60),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Text(c.strategy as String,
                    style: TextStyle(
                        color: headerColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${c.oddEvenLabel}  ${c.bigSmallLabel}  和值${c.sumTotal}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 10)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: numbers.map((n) => _comboBubble(n, headerColor)).toList(),
                ),
                const SizedBox(height: 8),
                Text(c.rationale as String,
                    style: TextStyle(
                        color: Colors.white.withAlpha(160), fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comboBubble(int n, Color borderColor) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _bgDeep,
        border: Border.all(color: borderColor, width: 1.8),
      ),
      alignment: Alignment.center,
      child: Text(
        n.toString().padLeft(2, '0'),
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  Widget _pairReferenceRow(dynamic da) {
    final d = da as dynamic;
    final consecPairs = d.topConsecutivePairs as List<List<int>>;
    final tailPairs = d.topSameTailPairs as List<List<int>>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text('參考號碼對',
            style: TextStyle(
                color: _gold.withAlpha(180),
                fontSize: 11,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (consecPairs.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('連號：',
                  style: TextStyle(color: Colors.orange.withAlpha(200), fontSize: 10)),
              ...consecPairs.take(3).map((p) => _pairChip(
                  p.map((n) => n.toString().padLeft(2, '0')).join('-'),
                  Colors.orange)),
            ],
          ),
        if (tailPairs.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('同尾：',
                  style: TextStyle(color: Colors.cyan.withAlpha(200), fontSize: 10)),
              ...tailPairs.take(3).map((p) => _pairChip(
                  p.map((n) => n.toString().padLeft(2, '0')).join('&'),
                  Colors.cyan)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _pairChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color.withAlpha(220), fontSize: 10, fontFamily: 'monospace')),
    );
  }

  Widget _numberBubble(int n) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _bgDeep,
        border: Border.all(color: _gold, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        n.toString().padLeft(2, '0'),
        style: const TextStyle(
            color: _gold, fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );
  }

  // ── 歷史開獎區 ─────────────────────────────────────────────────

  Widget _historySection() {
    final labels = ['539', '大樂透', '威力彩'];
    final List<List<DrawRecord>> allRecords = [
      _data?.records539 ?? [],
      _data?.recordsLotto ?? [],
      _data?.recordsPower ?? [],
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _showHistory = !_showHistory),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Colors.black.withAlpha(55),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 16, color: _gold),
                  const SizedBox(width: 6),
                  const Text(
                    '近期開獎紀錄',
                    style: TextStyle(
                        fontSize: 13,
                        color: _gold,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_isLoading)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xB4FFD700)),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _showHistory
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: _gold,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_showHistory) ...[
            // 分頁標籤
            Row(
              children: List.generate(3, (i) {
                final selected = _historyTab == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _historyTab = i),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 7),
                      color: selected
                          ? _gold
                          : Colors.black.withAlpha(50),
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? Colors.black
                                : _gold.withAlpha(180),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            Container(
              color: Colors.black.withAlpha(33),
              child: allRecords[_historyTab].isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          '無資料',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withAlpha(128)),
                        ),
                      ),
                    )
                  : Column(
                      children: allRecords[_historyTab]
                          .map((rec) => Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 88,
                                          child: Text(
                                            rec.date,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                              color: Colors.white
                                                  .withAlpha(165),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            rec.displayNumbers,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              fontFamily: 'monospace',
                                              color: _gold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: Colors.white.withAlpha(25),
                                  ),
                                ],
                              ))
                          .toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fiveDayProjectionSection() {
    final projection = _buildFiveDayProjection();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _showFiveDayProjection = !_showFiveDayProjection),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Colors.black.withAlpha(55),
              child: Row(
                children: [
                  const Icon(Icons.timeline_rounded, size: 16, color: _gold),
                  const SizedBox(width: 6),
                  const Text(
                    '5天機率推算（含連莊）',
                    style: TextStyle(
                        fontSize: 13,
                        color: _gold,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Icon(
                    _showFiveDayProjection
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: _gold,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_showFiveDayProjection)
            Container(
              width: double.infinity,
              color: Colors.black.withAlpha(40),
              padding: const EdgeInsets.all(12),
              child: projection == null
                  ? Text(
                      '資料不足，需有本週星期一神卦資料與近期開獎紀錄。',
                      style: TextStyle(
                          fontSize: 12, color: Colors.white.withAlpha(180)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '星期一未開：${projection.mondayMissing.map((n) => n.toString().padLeft(2, '0')).join('  ')}',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '連莊關注：${projection.streakWatch.map((n) => n.toString().padLeft(2, '0')).join('  ')}',
                          style: TextStyle(
                            color: _gold.withAlpha(220),
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '自動權重：未開追補 x${projection.weights.mondayMissingWeight.toStringAsFixed(2)}'
                          '　連莊延續 x${projection.weights.streakWeight.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...projection.nextThreeDays.entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Text(
                                '${e.key} 推算：${e.value.map((n) => n.toString().padLeft(2, '0')).join('  ')}',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(210),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            )),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  _FiveDayProjection? _buildFiveDayProjection() {
    final records = _data?.records539 ?? [];
    if (records.isEmpty) return null;

    final mondayKey = _thisWeekMondayKey();
    final mondayEntry = newspaper539Data[mondayKey];
    if (mondayEntry == null) return null;

    final mondayCandidates = <int>{
      mondayEntry.guZhi,
      ...mondayEntry.erZhong,
      ...mondayEntry.sanZhong,
    };
    final mondayDraw = records
        .firstWhere(
          (r) => r.date == mondayKey,
          orElse: () => const DrawRecord(date: '', numbers: []),
        )
        .numbers
        .toSet();
    final mondayMissing = mondayCandidates.difference(mondayDraw).toList()..sort();

    final latest = records.isNotEmpty ? records[0].numbers.toSet() : <int>{};
    final second = records.length > 1 ? records[1].numbers.toSet() : <int>{};
    final streakWatch = latest.intersection(second).toList()..sort();
    final adaptiveWeights = _deriveAdaptiveWeights(records);

    final nextThree = <String, List<int>>{};
    final weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
    for (var offset = 1; offset <= 3; offset++) {
      final dt = _weekMondayDate().add(Duration(days: offset));
      final key =
          '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
      final entry = newspaper539Data[key];
      if (entry == null) continue;
      final label = '$key(週${weekdayLabels[dt.weekday - 1]})';
      nextThree[label] = _rankForFollowDays(
        dayNumbers: [entry.guZhi, ...entry.erZhong, ...entry.sanZhong],
        mondayMissing: mondayMissing,
        streakWatch: streakWatch,
        records: records,
        weights: adaptiveWeights,
      );
    }

    return _FiveDayProjection(
      mondayMissing: mondayMissing,
      streakWatch: streakWatch,
      nextThreeDays: nextThree,
      weights: adaptiveWeights,
    );
  }

  List<int> _rankForFollowDays({
    required List<int> dayNumbers,
    required List<int> mondayMissing,
    required List<int> streakWatch,
    required List<DrawRecord> records,
    required _AdaptiveProjectionWeights weights,
  }) {
    final recent = records.take(20).toList();
    final score = <int, double>{};
    for (final n in {...dayNumbers, ...mondayMissing, ...streakWatch}) {
      if (n < 1 || n > 39) continue;
      var s = 0.0;
      if (dayNumbers.contains(n)) s += 2.5;
      if (mondayMissing.contains(n)) s += 3.2 * weights.mondayMissingWeight;
      if (streakWatch.contains(n)) s += 2.0 * weights.streakWeight;
      final freq = recent.where((r) => r.numbers.contains(n)).length;
      s += freq * 0.35;
      final miss = recent.indexWhere((r) => r.numbers.contains(n));
      if (miss >= 4 || miss == -1) s += 1.1;
      score[n] = s;
    }
    final sorted = score.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }

  DateTime _weekMondayDate() {
    final now = _taiwanNow;
    return now.subtract(Duration(days: now.weekday - 1));
  }

  String _thisWeekMondayKey() {
    final m = _weekMondayDate();
    return '${m.month.toString().padLeft(2, '0')}/${m.day.toString().padLeft(2, '0')}';
  }

  _AdaptiveProjectionWeights _deriveAdaptiveWeights(List<DrawRecord> records) {
    if (records.length < 5) {
      return const _AdaptiveProjectionWeights(
        mondayMissingWeight: 1.0,
        streakWeight: 1.0,
      );
    }

    final sorted = [...records]..sort((a, b) {
      final ad = _toDate(a.date);
      final bd = _toDate(b.date);
      if (ad == null || bd == null) return 0;
      return ad.compareTo(bd);
    });

    double mondayOpportunities = 0;
    double mondaySuccess = 0;
    double streakOpportunities = 0;
    double streakSuccess = 0;

    for (var i = 0; i < sorted.length; i++) {
      final d = _toDate(sorted[i].date);
      if (d == null) continue;
      if (d.weekday != DateTime.monday) continue;

      final key = sorted[i].date;
      final entry = newspaper539Data[key];
      if (entry == null) continue;
      if (i + 1 >= sorted.length) continue;

      final mondayCandidates = <int>{
        entry.guZhi,
        ...entry.erZhong,
        ...entry.sanZhong,
      };
      final mondayDraw = sorted[i].numbers.toSet();
      final missing = mondayCandidates.difference(mondayDraw).toList();
      if (missing.isNotEmpty) {
        mondayOpportunities += missing.length;
      }

      final followUnion = <int>{};
      for (var j = i + 1; j <= i + 3 && j < sorted.length; j++) {
        followUnion.addAll(sorted[j].numbers);
      }
      mondaySuccess += missing.where((n) => followUnion.contains(n)).length;

      // 連莊延續回測：週一與週二重疊號，是否在週三/週四續開
      final streakSeed = sorted[i].numbers.toSet().intersection(sorted[i + 1].numbers.toSet());
      if (streakSeed.isNotEmpty) {
        streakOpportunities += streakSeed.length;
      }
      final streakFollow = <int>{};
      for (var j = i + 2; j <= i + 3 && j < sorted.length; j++) {
        streakFollow.addAll(sorted[j].numbers);
      }
      streakSuccess += streakSeed.where((n) => streakFollow.contains(n)).length;
    }

    final missingRate = mondayOpportunities > 0 ? (mondaySuccess / mondayOpportunities) : 0.35;
    final streakRate = streakOpportunities > 0 ? (streakSuccess / streakOpportunities) : 0.35;

    return _AdaptiveProjectionWeights(
      mondayMissingWeight: _rateToWeight(missingRate),
      streakWeight: _rateToWeight(streakRate),
    );
  }

  DateTime? _toDate(String mmdd) {
    final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(mmdd);
    if (m == null) return null;
    final month = int.tryParse(m.group(1)!);
    final day = int.tryParse(m.group(2)!);
    if (month == null || day == null) return null;
    final year = _taiwanNow.year;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  double _rateToWeight(double rate) {
    if (rate >= 0.60) return 1.35;
    if (rate >= 0.50) return 1.20;
    if (rate >= 0.40) return 1.08;
    if (rate < 0.25) return 0.80;
    if (rate < 0.35) return 0.92;
    return 1.0;
  }

  // ── 紅框輸入區 ─────────────────────────────────────────────────

  Widget _hintSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _showHintInput = !_showHintInput),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Colors.black.withAlpha(55),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high_rounded,
                      size: 16, color: _gold),
                  const SizedBox(width: 6),
                  Text(
                    '輸入今日神卦號碼（選填）',
                    style: TextStyle(
                        fontSize: 13, color: _gold.withAlpha(218)),
                  ),
                  const Spacer(),
                  Icon(
                    _showHintInput
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: _goldAlt,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_showHintInput)
            Container(
              padding: const EdgeInsets.all(14),
              color: Colors.black.withAlpha(45),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '未開出的號碼將在前後 3 期內追蹤開出，自動累積加分',
                    style: TextStyle(
                        fontSize: 11, color: Colors.orange.withAlpha(218)),
                  ),
                  const SizedBox(height: 12),
                  // ── 孤支 ───────────────────────────────────────
                  _hintRow(
                    label: '孤支',
                    badge: '+165',
                    hint: '例：12',
                    controller: _guzhiCtrl,
                    maxLen: 2,
                  ),
                  const SizedBox(height: 10),
                  // ── 二中一 ─────────────────────────────────────
                  _hintRow(
                    label: '二中一',
                    badge: '+105',
                    hint: '例：28, 37',
                    controller: _erzhongCtrl,
                    maxLen: 5,
                  ),
                  const SizedBox(height: 10),
                  // ── 三中一 ─────────────────────────────────────
                  _hintRow(
                    label: '三中一',
                    badge: '+80',
                    hint: '例：04, 19, 21',
                    controller: _sanzhongCtrl,
                    maxLen: 8,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '套用分析',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        ),
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

  Widget _hintRow({
    required String label,
    required String badge,
    required String hint,
    required TextEditingController controller,
    required int maxLen,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: _gold.withAlpha(180)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      color: _gold, fontWeight: FontWeight.w700, fontSize: 12)),
              Text(badge,
                  style: TextStyle(
                      color: _gold.withAlpha(180), fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(
                decimal: false, signed: false),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d,\s]')),
            ],
            maxLength: maxLen,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: _gold,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  color: Colors.white.withAlpha(77), fontSize: 12),
              counterText: '',
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0x55FFD700)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _gold),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 推薦號碼列 ────────────────────────────────────────────────────


class _FiveDayProjection {
  const _FiveDayProjection({
    required this.mondayMissing,
    required this.streakWatch,
    required this.nextThreeDays,
    required this.weights,
  });

  final List<int> mondayMissing;
  final List<int> streakWatch;
  final Map<String, List<int>> nextThreeDays;
  final _AdaptiveProjectionWeights weights;
}

class _AdaptiveProjectionWeights {
  const _AdaptiveProjectionWeights({
    required this.mondayMissingWeight,
    required this.streakWeight,
  });

  final double mondayMissingWeight;
  final double streakWeight;
}

// ── 開獎號碼輸入格 ────────────────────────────────────────────────
class _DrawnNumberBox extends StatelessWidget {
  const _DrawnNumberBox({required this.ctrl});
  final TextEditingController ctrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        maxLength: 2,
        style: const TextStyle(
            color: Color(0xFFFFD700), fontSize: 15, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          counterText: '',
          hintText: '00',
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0x66FFD700)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFFFFD700), width: 1.5),
          ),
          filled: true,
          fillColor: Colors.white.withAlpha(10),
        ),
      ),
    );
  }
}
