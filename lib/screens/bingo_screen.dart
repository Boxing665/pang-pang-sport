import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/prediction_log.dart';
import '../services/bingo_service.dart';
import '../services/prediction_log_service.dart';
import '../widgets/lottery_prediction_card.dart';

// Top-level functions required by compute() to run on separate isolate
BingoPrediction _computeAnalysis(List<BingoRecord> records) =>
    BingoService.analyze(records, seed: 0);


List<AccuracySummary> _computeAccuracyIsolate(List<BingoRecord> records) =>
    BingoService.computeAccuracy(records, testDraws: 20);

/// 台灣賓果賓果預測頁面
///
/// 功能：
/// - 熱力球圖（顏色 = 熱度，深藍→橙→紅）
/// - 每顆球顯示距上次開出幾局
/// - 連帶分析（哪幾號最常一起開）
/// - 號碼統計（頻率 + 平均間隔）
/// - 倒數計時，T-3 分自動刷新
class BingoScreen extends StatefulWidget {
  const BingoScreen({super.key});

  @override
  State<BingoScreen> createState() => _BingoScreenState();
}

class _BingoScreenState extends State<BingoScreen>
    with TickerProviderStateMixin {
  final _service = BingoService();

  List<BingoRecord> _records = [];
  BingoPrediction? _pred;
  bool _isLoading = false;
  String _errorMsg = '';
  bool _alerted = false;
  int _secondsLeft = 0;
  int? _selectedBall;    // tapped ball number
  int _tab = 0;          // 0=連帶 1=統計 2=歷史 3=準確率
  List<AccuracySummary> _accuracy = [];
  // 上一期預測對照
  PredictionLog? _lastPredLog;

  Timer? _timer;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── 顏色常數 ──────────────────────────────────────────────────
  static const _bg0   = Color(0xFF050E24);
  static const _bg1   = Color(0xFF0D1E4A);
  static const _gold  = Color(0xFFFFD700);
  static const _cyan  = Color(0xFF00E5FF);

  // 熱力圖顏色（冷 → 溫 → 熱）
  static const _colorCold   = Color(0xFF1A3A6B);
  static const _colorWarm   = Color(0xFFE8700A);
  static const _colorHot    = Color(0xFFFF1800);
  static const _colorLatest = Color(0xFFFFD700); // 本期開出

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _load();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────

  final _logSvc = PredictionLogService();


  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });
    final records = await _service.fetchRecent(forceRefresh: forceRefresh);
    BingoPrediction? pred;
    List<AccuracySummary> accuracy = [];
    if (records.isNotEmpty) {
      pred = await compute(_computeAnalysis, records);
      if (records.length >= 22) {
        accuracy = await compute(_computeAccuracyIsolate, records);
      }
    }

    // 自動比對已開獎期數，回填賓果準確率（免手動 key）
    final byDrawNo = <int, List<int>>{};
    for (final r in records) {
      if (r.numbers.isEmpty) continue;
      byDrawNo[r.drawNo] = r.numbers;
    }
    await _logSvc.autoReportBingoByDrawNo(byDrawNo);

    // 儲存本期預測（每次載入都更新，確保最新預測存在）
    if (pred != null) {
      await _logSvc.saveBingoPrediction(
        drawNo: pred.nextDrawNo,
        groupLabel: '綜合',
        numbers: pred.recommended,
      );
      await _logSvc.saveBingoPrediction(
        drawNo: pred.nextDrawNo,
        groupLabel: '拖牌',
        numbers: pred.carryOverNumbers,
      );
    }

    // 取得最近一筆已有實際開獎結果的預測（用於「上一期對照」）
    final bingoLogs = await _logSvc.loadByType(PredictionType.bingo);
    final lastCompleted = bingoLogs.firstWhere(
      (l) => (l.actualResult ?? '').isNotEmpty,
      orElse: () => bingoLogs.isNotEmpty ? bingoLogs.first : PredictionLog(
        id: '', type: PredictionType.bingo, createdAt: DateTime.now(),
        title: '', subtitle: '', predictedResult: '',
      ),
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _records = records;
      _accuracy = accuracy;
      if (pred != null) {
        _pred = pred;
      } else {
        _errorMsg = '資料載入失敗，請確認網路後重試';
      }
      if (lastCompleted.id.isNotEmpty &&
          (lastCompleted.actualResult ?? '').isNotEmpty) {
        _lastPredLog = lastCompleted;
      }
    });
  }

  void _startTimer() {
    _secondsLeft = BingoService.secondsToNextDraw();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      final s = BingoService.secondsToNextDraw();
      setState(() => _secondsLeft = s);
      if (!_alerted && s <= 180 && s > 0) {
        _alerted = true;
        await _load(forceRefresh: true);
        if (mounted && _pred != null) _showPredictionAlert();
      } else if (_alerted && s > 180) {
        _alerted = false;
        Future.delayed(const Duration(seconds: 15),
            () { if (mounted) _load(forceRefresh: true); });
      }
    });
  }

  void _showPredictionAlert() {
    if (_pred == null) return;
    final pred = _pred!;
    final latestNums =
        _records.isNotEmpty ? _records.first.numbers.toSet() : <int>{};
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF100020), Color(0xFF0A1535)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.red.withAlpha(180), width: 2),
            boxShadow: [
              BoxShadow(color: Colors.red.withAlpha(60), blurRadius: 24)
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              // Title + countdown
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('⚡',
                      style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    '第 ${pred.nextDrawNo} 期 即將開獎',
                    style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: 1),
                  ),
                  const SizedBox(width: 6),
                  const Text('⚡',
                      style: TextStyle(fontSize: 18)),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '🔁 連莊預測  ·  上期最可能再開的 6 顆',
                style: TextStyle(
                    color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 16),
              // Carry-over 6 balls
              if (pred.carryOverNumbers.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: pred.carryOverNumbers.map((n) {
                    final s = pred.stats[n]!;
                    final isLatest = latestNums.contains(n);
                    final ballColor = isLatest
                        ? _colorLatest
                        : _heatColor(s.heatScore);
                    return Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ballColor,
                        border: Border.all(
                            color: _gold.withAlpha(200), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                              color: ballColor.withAlpha(120),
                              blurRadius: 8)
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            n.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: isLatest
                                  ? Colors.black
                                  : Colors.white,
                              height: 1,
                            ),
                          ),
                          Text(
                            s.gap == 0 ? '◎' : '${s.gap}',
                            style: TextStyle(
                              fontSize: 8,
                              color: isLatest
                                  ? Colors.black54
                                  : s.gap <= 4
                                      ? Colors.greenAccent
                                      : Colors.white54,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
              // Dismiss
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(40),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.red.withAlpha(120)),
                  ),
                  child: const Text('知道了',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _fmtCountdown(int s) {
    if (s <= 0) return '00:00';
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  String get _nextTimeLabel {
    final dt = BingoService.nextDrawTime();
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _heatColor(double heat) {
    if (heat >= 0.66) {
      return Color.lerp(_colorWarm, _colorHot, (heat - 0.66) / 0.34)!;
    } else if (heat >= 0.33) {
      return Color.lerp(_colorCold, _colorWarm, (heat - 0.33) / 0.33)!;
    } else {
      return Color.lerp(
          const Color(0xFF0A1F3B), _colorCold, heat / 0.33)!;
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg0,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bg0, _bg1],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: _gold,
            backgroundColor: _bg1,
            onRefresh: () => _load(forceRefresh: true),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _countdownCard()),
                if (_isLoading && _pred == null)
                  SliverFillRemaining(child: _loadingView())
                else if (_errorMsg.isNotEmpty && _pred == null)
                  SliverFillRemaining(child: _errorView())
                else if (_pred != null) ...[
                  SliverToBoxAdapter(child: _latestDraw()),
                  if (_lastPredLog != null)
                    SliverToBoxAdapter(child: _lastDrawComparison(_lastPredLog!)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: BingoPredictionCard(records: _records, pred: _pred!),
                    ),
                  ),
                  SliverToBoxAdapter(child: _predictionPanel()),
                  SliverToBoxAdapter(child: _heatmapGrid()),
                  if (_selectedBall != null)
                    SliverToBoxAdapter(child: _ballDetail()),
                  SliverToBoxAdapter(child: _tabSection()),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 32)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎱 台灣賓果賓果',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _gold,
                        letterSpacing: 1)),
                Text(
                  '1–80 選 20・每 5 分鐘一局',
                  style: TextStyle(
                      fontSize: 11, color: _cyan.withAlpha(180)),
                ),
              ],
            ),
          ),
          if (_pred != null)
            Text(
              '分析 ${_pred!.analyzedDraws} 局',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          const SizedBox(width: 4),
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: _gold, strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: _gold),
                  onPressed: () => _load(forceRefresh: true),
                ),
        ],
      ),
    );
  }

  // ── Countdown Card ────────────────────────────────────────────

  Widget _countdownCard() {
    final urgent = _secondsLeft <= 180 && _secondsLeft > 0;
    final borderColor = urgent ? Colors.red : _cyan.withAlpha(80);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(urgent ? 90 : 50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: urgent ? 2 : 1),
        boxShadow: urgent
            ? [BoxShadow(
                color: Colors.red.withAlpha(60), blurRadius: 16)]
            : [],
      ),
      child: Row(
        children: [
          // Big countdown
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                urgent ? '⚡ 即將開獎' : '下局倒數',
                style: TextStyle(
                    color: urgent ? Colors.red : _cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              urgent
                  ? FadeTransition(
                      opacity: _pulseAnim,
                      child: _countdownText(urgent),
                    )
                  : _countdownText(urgent),
            ],
          ),
          const SizedBox(width: 16),
          // Right side info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('開獎時間 $_nextTimeLabel',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                if (_pred != null && _pred!.nextDrawNo > 0)
                  Text(
                    '第 ${_pred!.nextDrawNo} 期',
                    style: TextStyle(
                        color: _gold.withAlpha(200),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countdownText(bool urgent) {
    return Text(
      _fmtCountdown(_secondsLeft),
      style: TextStyle(
        fontSize: 38,
        fontWeight: FontWeight.w900,
        color: urgent ? Colors.red : _cyan,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1,
      ),
    );
  }

  // ── Latest Draw Strip ─────────────────────────────────────────

  Widget _latestDraw() {
    if (_records.isEmpty) return const SizedBox();
    final r = _records.first;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(60),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: _gold, size: 14),
              const SizedBox(width: 4),
              Text('最新: 第 ${r.drawNo} 期  ${r.drawTime}',
                  style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
              if (r.superNum.isNotEmpty) ...[
                const Spacer(),
                Text(' 超獎 ${r.superNum}',
                    style: const TextStyle(
                        color: Colors.orange, fontSize: 11)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: r.numbers.map((n) => _miniLatestBall(n)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _miniLatestBall(int n) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _gold,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: _gold.withAlpha(80), blurRadius: 6)
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        n.toString().padLeft(2, '0'),
        style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: Colors.black),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1E4A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold.withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, color: Color(0xFFFFD700), size: 16),
                const SizedBox(width: 6),
                Text(log.title,
                    style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.w700, fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hits.length >= 3
                        ? Colors.green.withAlpha(50)
                        : hits.length >= 2
                            ? Colors.orange.withAlpha(50)
                            : Colors.red.withAlpha(40),
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
            // 預測號碼列
            Text('上期預測', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: predicted.map((n) {
                final isHit = actual.contains(n);
                return Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isHit ? _gold.withAlpha(200) : const Color(0xFF1A3A6B),
                    border: isHit ? null : Border.all(color: Colors.white24),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: isHit ? Colors.black : Colors.white54,
                      fontSize: 11,
                      fontWeight: isHit ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (actual.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('實際開獎', style: TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 4),
              Text(
                actualStr.replaceAll(' ', '  '),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Prediction Panel (胖胖賓果預測) ──────────────────────────

  Widget _predictionPanel() {
    final pred = _pred;
    if (pred == null) return const SizedBox();
    final latestNums =
        _records.isNotEmpty ? _records.first.numbers.toSet() : <int>{};

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF100828), Color(0xFF0A1535)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withAlpha(80), width: 1.5),
        boxShadow: [
          BoxShadow(color: _gold.withAlpha(30), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              const Text('🎱', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                '胖胖賓果預測  ·  第 ${pred.nextDrawNo} 期',
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (pred.strategy.isNotEmpty)
            Text(
              pred.strategy,
              style: TextStyle(color: _cyan.withAlpha(200), fontSize: 11),
            ),
          const SizedBox(height: 12),

          // Carry-over section
          if (pred.carryOverNumbers.isNotEmpty) ...[
            Row(
              children: [
                const Text('🔁 連莊推薦',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text(
                  '信心 ${(pred.carryOverConfidence * 100).round()}%',
                  style: TextStyle(
                      color: _cyan.withAlpha(180), fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: pred.carryOverNumbers.map((n) {
                final s = pred.stats[n]!;
                final isLatest = latestNums.contains(n);
                final ballColor =
                    isLatest ? _colorLatest : _heatColor(s.heatScore);
                return _predBall(n, ballColor, isLatest, s.gap);
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // Recommended section
          const Text('⭐ 統計推薦',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pred.recommended.map((n) {
              final s = pred.stats[n]!;
              final isLatest = latestNums.contains(n);
              final ballColor =
                  isLatest ? _colorLatest : _heatColor(s.heatScore);
              return _predBall(n, ballColor, isLatest, s.gap);
            }).toList(),
          ),

          // Hot numbers
          if (pred.hotNumbers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('🔥 熱門號碼',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: pred.hotNumbers.take(10).map((n) {
                final isLatest = latestNums.contains(n);
                return Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isLatest
                        ? _colorLatest
                        : _colorHot.withAlpha(160),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.orange.withAlpha(120)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    n.toString().padLeft(2, '0'),
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color:
                            isLatest ? Colors.black : Colors.white),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _predBall(int n, Color ballColor, bool isLatest, int gap) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ballColor,
        border: Border.all(color: _gold.withAlpha(160), width: 1.5),
        boxShadow: [
          BoxShadow(color: ballColor.withAlpha(100), blurRadius: 8)
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            n.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isLatest ? Colors.black : Colors.white,
              height: 1,
            ),
          ),
          Text(
            gap == 0 ? '◎' : '$gap',
            style: TextStyle(
              fontSize: 8,
              color: isLatest
                  ? Colors.black54
                  : gap <= 4
                      ? Colors.greenAccent
                      : Colors.white54,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Heatmap Grid ─────────────────────────────────────────────

  Widget _heatmapGrid() {
    final pred = _pred!;
    final latestNums =
        _records.isNotEmpty ? _records.first.numbers.toSet() : <int>{};
    final recNums = pred.recommended.toSet();
    final coPartners = _selectedBall != null
        ? pred.topPairs
            .where((p) => p.a == _selectedBall || p.b == _selectedBall)
            .map((p) => p.a == _selectedBall ? p.b : p.a)
            .take(5)
            .toSet()
        : <int>{};

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend row
          Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 2),
            child: Row(
              children: [
                const Text('號碼熱力圖',
                    style: TextStyle(
                        color: _cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const Spacer(),
                _legendItem(_colorHot, '熱'),
                const SizedBox(width: 8),
                _legendItem(_colorCold, '冷'),
                const SizedBox(width: 8),
                _legendItem(_gold, '本期'),
                const SizedBox(width: 8),
                _legendItem(Colors.white.withAlpha(180), '推薦★'),
              ],
            ),
          ),
          // 8 rows × 10 cols
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
              childAspectRatio: 0.82,
            ),
            itemCount: 80,
            itemBuilder: (_, i) {
              final n = i + 1;
              final stats = pred.stats[n]!;
              final isLatest = latestNums.contains(n);
              final isRec = recNums.contains(n);
              final isSelected = _selectedBall == n;
              final isPartner = coPartners.contains(n);
              return GestureDetector(
                onTap: () => setState(() =>
                    _selectedBall = _selectedBall == n ? null : n),
                child: _heatBall(
                  n, stats, isLatest, isRec, isSelected, isPartner),
              );
            },
          ),
          const SizedBox(height: 4),
          // Tap hint
          Center(
            child: Text(
              _selectedBall != null
                  ? '點選其他球取消選擇'
                  : '點選號碼查看詳細統計',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatBall(int n, BingoStats s, bool isLatest, bool isRec,
      bool isSelected, bool isPartner) {
    Color ballColor;
    if (isLatest) {
      ballColor = _colorLatest;
    } else {
      ballColor = _heatColor(s.heatScore);
    }

    // Overlay tint for partners
    if (isPartner && !isLatest) {
      ballColor = Color.lerp(ballColor, Colors.purple, 0.5)!;
    }

    final textColor = isLatest ? Colors.black : Colors.white;
    final borderColor = isSelected
        ? Colors.white
        : isRec
            ? _gold
            : isPartner
                ? Colors.purpleAccent
                : Colors.transparent;
    final borderWidth = (isSelected || isRec || isPartner) ? 1.5 : 0.0;

    // Gap badge color
    Color gapColor;
    if (s.gap == 0) {
      gapColor = _gold;
    } else if (s.gap <= 4) {
      gapColor = Colors.green.shade300;
    } else if (s.gap <= 8) {
      gapColor = Colors.orange;
    } else {
      gapColor = Colors.red.shade300;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: ballColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: isSelected
            ? [BoxShadow(
                color: Colors.white.withAlpha(120), blurRadius: 8)]
            : isLatest
                ? [BoxShadow(
                    color: _gold.withAlpha(120), blurRadius: 6)]
                : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Star for recommended
          if (isRec)
            const SizedBox() // replaced with overlay in stack approach
          else
            const SizedBox(height: 2),
          Text(
            n.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: n < 10 ? 11 : 10,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1,
            ),
          ),
          // Gap badge
          Text(
            s.gapLabel == '本期' ? '◎' : '${s.gap}',
            style: TextStyle(
              fontSize: 7,
              color: gapColor,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          if (isRec)
            Text('★',
                style: TextStyle(
                    fontSize: 7,
                    color: _gold,
                    height: 1,
                    fontWeight: FontWeight.w900))
          else
            const SizedBox(height: 5),
        ],
      ),
    );
  }

  Widget _legendItem(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 3),
        Text(label,
            style:
                const TextStyle(color: Colors.white60, fontSize: 9)),
      ],
    );
  }

  // ── Ball Detail Panel ─────────────────────────────────────────

  Widget _ballDetail() {
    final n = _selectedBall!;
    final s = _pred!.stats[n]!;
    final partners = _pred!.topPairs
        .where((p) => p.a == n || p.b == n)
        .take(5)
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _heatColor(s.heatScore),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  n.toString().padLeft(2, '0'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('號碼 $n 詳細統計',
                      style: const TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    '熱度指數：${(s.heatScore * 100).round()}%  |  '
                    '頻率：${s.frequency} 次 / ${_pred!.analyzedDraws} 局',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    '距上次：${s.gapLabel}  |  平均每 ${s.avgGap.toStringAsFixed(1)} 局開一次',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _selectedBall = null),
                child: const Icon(Icons.close,
                    color: Colors.white38, size: 18),
              ),
            ],
          ),
          if (partners.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('最常一起出現的號碼（連帶）',
                style: TextStyle(
                    color: Colors.purpleAccent.withAlpha(200),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: partners.map((p) {
                final partner = p.a == n ? p.b : p.a;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withAlpha(60),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.purple.withAlpha(120)),
                  ),
                  child: Text(
                    '${partner.toString().padLeft(2, '0')}  '
                    '${p.count}次 (${(p.rate * 100).round()}%)',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 10),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab Section ───────────────────────────────────────────────

  Widget _tabSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        children: [
          // Tab bar – scrollable row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tabBtn(0, '🔗 連帶'),
                const SizedBox(width: 6),
                _tabBtn(1, '🔢 頭號遺漏'),
                const SizedBox(width: 6),
                _tabBtn(2, '🔢 尾號遺漏'),
                const SizedBox(width: 6),
                _tabBtn(3, '📊 統計'),
                const SizedBox(width: 6),
                _tabBtn(4, '📋 歷史'),
                const SizedBox(width: 6),
                _tabBtn(5, '📈 準確率'),
                const SizedBox(width: 6),
                _tabBtn(6, '🧩 同出/型態'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_tab == 0) _coOccurrenceTab(),
          if (_tab == 1) _headGapTab(),
          if (_tab == 2) _tailGapTab(),
          if (_tab == 3) _statsTab(),
          if (_tab == 4) _historyTab(),
          if (_tab == 5) _accuracyTab(),
          if (_tab == 6) _patternTab(),
        ],
      ),
    );
  }

  Widget _patternTab() {
    final pred = _pred!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '同出組合與型態未開分析（共 ${pred.analyzedDraws} 局）',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 10),
        _comboSection('二同出', pred.topTwoCombos),
        const SizedBox(height: 10),
        _comboSection('三同出', pred.topThreeCombos),
        const SizedBox(height: 10),
        _comboSection('四同出', pred.topFourCombos),
        const SizedBox(height: 10),
        _balanceSection('大小未開', pred.bigSmallPatterns),
        const SizedBox(height: 10),
        _balanceSection('單雙未開', pred.oddEvenPatterns),
      ],
    );
  }

  Widget _comboSection(String title, List<ComboPatternStat> data) {
    if (data.isEmpty) return _emptyMsg('$title 資料不足');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: _gold, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...data.take(6).map((c) {
            final label = c.numbers.map((n) => n.toString().padLeft(2, '0')).join(' ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  Text('出現${c.count}次',
                      style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  const SizedBox(width: 8),
                  Text('未開${c.gap}期',
                      style: const TextStyle(color: Colors.orange, fontSize: 10)),
                  const SizedBox(width: 8),
                  Text(
                    c.suggestAfter == 0 ? '建議下期' : '建議${c.suggestAfter}期後',
                    style: TextStyle(
                      color: c.suggestAfter == 0 ? Colors.greenAccent : Colors.cyanAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _balanceSection(String title, List<BalancePatternStat> data) {
    if (data.isEmpty) return _emptyMsg('$title 資料不足');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: _gold, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...data.take(6).map((p) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.label,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  Text('出現${p.count}次',
                      style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  const SizedBox(width: 8),
                  Text('未開${p.gap}期',
                      style: const TextStyle(color: Colors.orange, fontSize: 10)),
                  const SizedBox(width: 8),
                  Text(
                    p.suggestAfter == 0 ? '建議下期' : '建議${p.suggestAfter}期後',
                    style: TextStyle(
                      color: p.suggestAfter == 0 ? Colors.greenAccent : Colors.cyanAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _tabBtn(int idx, String label) {
    final active = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? _cyan.withAlpha(40)
              : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active
                  ? _cyan.withAlpha(120)
                  : Colors.white.withAlpha(20)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight:
                active ? FontWeight.w700 : FontWeight.normal,
            color: active ? _cyan : Colors.white54,
          ),
        ),
      ),
    );
  }

  // ── 頭號遺漏分析 Tab ───────────────────────────────────────────

  Widget _headGapTab() {
    final pred = _pred!;
    // 1頭(10-19) … 7頭(70-79)，每頭 10 顆，橫排顯示
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '頭號遺漏分析（1頭–7頭 × 10 星）  ·  共 ${pred.analyzedDraws} 局',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          '數字 = 幾期未開  ·  紅色 = 超過平均間隔，建議關注',
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 10),
        ...List.generate(7, (hi) {
          final headDigit = hi + 1; // 1~7
          final numbers = List.generate(
              10, (j) => headDigit * 10 + j); // 10-19, 20-29, ..., 70-79
          return _headGapRow(headDigit, numbers, pred);
        }),
      ],
    );
  }

  Widget _headGapRow(int headDigit, List<int> numbers, BingoPrediction pred) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$headDigit 頭  (${headDigit}0–${headDigit}9)',
            style: const TextStyle(
                color: _gold, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Row(
            children: numbers.map((n) {
              if (n > 80) return const SizedBox();
              final s = pred.stats[n];
              if (s == null) return const SizedBox();
              final isDue = s.gap >= s.avgGap;
              final suggestAfter = isDue
                  ? 0
                  : max(0, (s.avgGap - s.gap).ceil());
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() =>
                      _selectedBall = _selectedBall == n ? null : n),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isDue
                          ? Colors.red.withAlpha(40)
                          : s.gap == 0
                              ? _gold.withAlpha(40)
                              : Colors.white.withAlpha(8),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDue
                            ? Colors.red.withAlpha(100)
                            : s.gap == 0
                                ? _gold.withAlpha(80)
                                : Colors.white.withAlpha(15),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          n.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isDue
                                ? Colors.red.shade300
                                : s.gap == 0
                                    ? _gold
                                    : Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.gap == 0 ? '◎' : '${s.gap}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: isDue
                                ? Colors.red
                                : s.gap == 0
                                    ? _gold
                                    : s.gap <= 4
                                        ? Colors.greenAccent
                                        : Colors.white54,
                          ),
                        ),
                        if (isDue)
                          const Text('▲',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 7,
                                  height: 1))
                        else
                          Text(
                            suggestAfter <= 0
                                ? ''
                                : '$suggestAfter期',
                            style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 7,
                                height: 1),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── 尾號遺漏分析 Tab ───────────────────────────────────────────

  Widget _tailGapTab() {
    final pred = _pred!;
    // 1尾(01,11,...,71) … 9尾(09,19,...,79) + 0尾(10,20,...,80)
    // 直排顯示：每尾一行，8 顆
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '尾號遺漏分析（1尾–0尾 × 8 星）  ·  共 ${pred.analyzedDraws} 局',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          '數字 = 幾期未開  ·  紅色 = 超過平均間隔，建議關注',
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 10),
        // 1尾~9尾, then 0尾
        ...List.generate(10, (ti) {
          final tailDigit = (ti + 1) % 10; // 1,2,...,9,0
          List<int> numbers;
          if (tailDigit == 0) {
            // 0 尾: 10, 20, 30, 40, 50, 60, 70, 80
            numbers = [10, 20, 30, 40, 50, 60, 70, 80];
          } else {
            // N 尾: 0N, 1N, 2N, 3N, 4N, 5N, 6N, 7N
            numbers = List.generate(8, (j) => j * 10 + tailDigit);
            // j=0 → tailDigit (e.g. 01), j=1 → 10+tailDigit, ..., j=7 → 70+tailDigit
          }
          return _tailGapRow(tailDigit, numbers, pred);
        }),
      ],
    );
  }

  Widget _tailGapRow(int tailDigit, List<int> numbers, BingoPrediction pred) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Row(
        children: [
          // Tail label
          SizedBox(
            width: 40,
            child: Text(
              '$tailDigit 尾',
              style: const TextStyle(
                  color: _gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
          // 8 numbers
          ...numbers.map((n) {
            if (n < 1 || n > 80) return const Expanded(child: SizedBox());
            final s = pred.stats[n];
            if (s == null) return const Expanded(child: SizedBox());
            final isDue = s.gap >= s.avgGap;
            final suggestAfter = isDue
                ? 0
                : max(0, (s.avgGap - s.gap).ceil());
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() =>
                    _selectedBall = _selectedBall == n ? null : n),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isDue
                        ? Colors.red.withAlpha(40)
                        : s.gap == 0
                            ? _gold.withAlpha(40)
                            : Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDue
                          ? Colors.red.withAlpha(100)
                          : s.gap == 0
                              ? _gold.withAlpha(80)
                              : Colors.white.withAlpha(15),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        n.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: isDue
                              ? Colors.red.shade300
                              : s.gap == 0
                                  ? _gold
                                  : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.gap == 0 ? '◎' : '${s.gap}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: isDue
                              ? Colors.red
                              : s.gap == 0
                                  ? _gold
                                  : s.gap <= 4
                                      ? Colors.greenAccent
                                      : Colors.white54,
                        ),
                      ),
                      if (isDue)
                        const Text('▲',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 7,
                                height: 1))
                      else
                        Text(
                          suggestAfter <= 0
                              ? ''
                              : '$suggestAfter期',
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 7,
                              height: 1),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 連帶分析 Tab ──────────────────────────────────────────────

  Widget _coOccurrenceTab() {
    final pairs = _pred!.topPairs.take(15).toList();
    if (pairs.isEmpty) {
      return _emptyMsg('歷史資料不足，無法計算連帶');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '最常一起出現的號碼組合（共分析 ${_pred!.analyzedDraws} 局）',
            style: const TextStyle(
                color: Colors.white54, fontSize: 11),
          ),
        ),
        ...pairs.asMap().entries.map((e) {
          final rank = e.key + 1;
          final p = e.value;
          final pct = (p.rate * 100).round();
          // bar width
          final barFraction = pairs.first.count > 0
              ? p.count / pairs.first.count
              : 0.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.purple.withAlpha(rank <= 3 ? 40 : 20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.purple.withAlpha(rank <= 3 ? 80 : 30)),
            ),
            child: Row(
              children: [
                // Rank
                SizedBox(
                  width: 22,
                  child: Text(
                    '$rank',
                    style: TextStyle(
                        color: rank <= 3
                            ? _gold
                            : Colors.white38,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
                // Ball pair
                _pairBall(p.a),
                const SizedBox(width: 4),
                const Text('+',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 4),
                _pairBall(p.b),
                const SizedBox(width: 10),
                // Count + bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.count} 次  ($pct%)',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11),
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: barFraction,
                          minHeight: 4,
                          backgroundColor:
                              Colors.purple.withAlpha(30),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(
                                  Colors.purpleAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _pairBall(int n) {
    final s = _pred!.stats[n]!;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _heatColor(s.heatScore),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        n.toString().padLeft(2, '0'),
        style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: Colors.white),
      ),
    );
  }

  // ── 號碼統計 Tab ──────────────────────────────────────────────

  Widget _statsTab() {
    final pred = _pred!;
    final statsList = pred.stats.values.toList()
      ..sort((a, b) => b.frequency.compareTo(a.frequency));

    return Column(
      children: statsList.map((s) {
        final barFraction = statsList.first.frequency > 0
            ? s.frequency / statsList.first.frequency
            : 0.0;
        final isHot = pred.hotNumbers.contains(s.number);
        final isCold = pred.coldNumbers.contains(s.number);

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(
                s.number % 2 == 0 ? 8 : 5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Ball
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedBall = _selectedBall == s.number
                        ? null
                        : s.number;
                  });
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _heatColor(s.heatScore),
                    shape: BoxShape.circle,
                    border: _selectedBall == s.number
                        ? Border.all(
                            color: Colors.white, width: 1.5)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    s.number.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Stats
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${s.frequency} 次  ',
                          style: TextStyle(
                              color: isHot
                                  ? Colors.orange
                                  : isCold
                                      ? _cyan
                                      : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '最近 ${s.gapLabel}  平均 ${s.avgGap.toStringAsFixed(1)} 局/次',
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10),
                        ),
                        const Spacer(),
                        if (isHot)
                          const Text('🔥',
                              style: TextStyle(fontSize: 10))
                        else if (isCold)
                          const Text('❄️',
                              style: TextStyle(fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: barFraction,
                        minHeight: 3,
                        backgroundColor:
                            Colors.white.withAlpha(15),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _heatColor(s.heatScore)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── 歷史開獎 Tab ──────────────────────────────────────────────

  Widget _historyTab() {
    if (_records.isEmpty) return _emptyMsg('無歷史資料');
    return Column(
      children: _records.take(15).toList().asMap().entries.map((e) {
        final i = e.key;
        final r = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(i.isEven ? 10 : 6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Colors.white.withAlpha(i == 0 ? 40 : 12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '第 ${r.drawNo} 期  ${r.drawTime}',
                    style: TextStyle(
                        color: i == 0 ? _gold : Colors.white60,
                        fontWeight: FontWeight.w700,
                        fontSize: 11),
                  ),
                  if (r.superNum.isNotEmpty) ...[
                    const Spacer(),
                    Text('超獎 ${r.superNum}',
                        style: const TextStyle(
                            color: Colors.orange, fontSize: 10)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 3,
                runSpacing: 3,
                children: r.numbers.map((n) {
                  final s = _pred?.stats[n];
                  return Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: s != null
                          ? _heatColor(s.heatScore)
                          : _colorCold,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      n.toString().padLeft(2, '0'),
                      style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── 準確率 Tab ────────────────────────────────────────────────

  Widget _accuracyTab() {
    if (_accuracy.isEmpty) {
      return _emptyMsg('資料不足，需要至少 22 局歷史資料');
    }
    final testedDraws = _accuracy.first.testedDraws;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info bar
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '回測最近 $testedDraws 局 · 每組預測 6 個號碼 · 隨機基準 1.5 個/局',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
        ..._accuracy.map((s) => _accuracyCard(s)),
      ],
    );
  }

  Widget _accuracyCard(AccuracySummary s) {
    final above = s.vsBaseline >= 0;
    final vsColor = above ? Colors.greenAccent : Colors.redAccent;
    final dist = s.distribution;
    final maxDist =
        dist.values.isEmpty ? 1 : dist.values.fold(0, (a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: above
              ? Colors.green.withAlpha(60)
              : Colors.white.withAlpha(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Text(s.groupLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                '${s.avgHits.toStringAsFixed(2)} 個/局',
                style: const TextStyle(
                    color: _gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Sub info
          Row(
            children: [
              Text(
                '命中率 ${(s.hitRate * 100).toStringAsFixed(1)}%',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 8),
              Text(
                above
                    ? '+${s.vsBaseline.toStringAsFixed(2)} vs 隨機'
                    : '${s.vsBaseline.toStringAsFixed(2)} vs 隨機',
                style: TextStyle(
                    color: vsColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar – actual vs baseline
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (AccuracySummary.baseline / 6).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.white.withAlpha(15),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white24),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: s.hitRate.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    above ? Colors.green.shade400 : Colors.orange.shade400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Hit distribution histogram (0–6 hits)
          Text('命中分布（共 ${s.testedDraws} 局）',
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (hits) {
              final count = dist[hits] ?? 0;
              final frac = maxDist > 0 ? count / maxDist : 0.0;
              final barColor = hits == 0
                  ? Colors.grey.withAlpha(100)
                  : hits <= 2
                      ? Colors.blue.shade400
                      : hits <= 4
                          ? Colors.orange
                          : Colors.greenAccent;
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 4 + 28 * frac,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('$hits',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 9)),
                    Text('$count',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 9)),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Misc ──────────────────────────────────────────────────────

  Widget _emptyMsg(String msg) {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Center(
          child: Text(msg,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 13))),
    );
  }

  Widget _loadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _gold),
          SizedBox(height: 14),
          Text('載入開獎資料…',
              style: TextStyle(color: _gold)),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Colors.red, size: 48),
            const SizedBox(height: 10),
            Text(_errorMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => _load(forceRefresh: true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: _gold),
              child: const Text('重新載入',
                  style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
}
