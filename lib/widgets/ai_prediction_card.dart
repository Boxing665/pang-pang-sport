import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/match_fixture.dart';
import '../models/sport_type.dart';
import '../services/ai_prediction_service.dart';
import '../services/prediction_log_service.dart';
import '../theme/app_theme.dart';

// ── 體育 AI 預測卡片 ───────────────────────────────────────────────

class AiSportPredictionCard extends StatefulWidget {
  const AiSportPredictionCard({super.key, required this.fixture});
  final MatchFixture fixture;

  @override
  State<AiSportPredictionCard> createState() => _AiSportPredictionCardState();
}

class _AiSportPredictionCardState extends State<AiSportPredictionCard> {
  final _aiSvc = AiPredictionService.instance;
  final _logSvc = PredictionLogService();

  AiSportPrediction? _result;
  bool _loading = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; });
    var result = await _aiSvc.predictSport(widget.fixture);
    // Stale detection: old-format cached results have empty narrative+gameFlow
    if (!result.hasError && result.narrative.isEmpty && result.gameFlow.isEmpty) {
      _aiSvc.clearSportCache(widget.fixture.id);
      result = await _aiSvc.predictSport(widget.fixture);
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
    if (!result.hasError) _autoSave(result);
  }

  Future<void> _autoSave(AiSportPrediction r) async {
    if (_saved) return;
    final sportType = widget.fixture.sport.name;
    await _logSvc.saveSportPrediction(
      matchId: widget.fixture.id,
      homeTeam: widget.fixture.homeTeam,
      awayTeam: widget.fixture.awayTeam,
      league: widget.fixture.league,
      matchTime: widget.fixture.startTime,
      predictedHome: r.predictedHome,
      predictedHomeRaw: r.predictedHome,
      predictedAway: r.predictedAway,
      predictedAwayRaw: r.predictedAway,
      confidence: r.confidence / 100.0,
      sportType: sportType,
      winner: r.winner,
      signalDetails: r.signalDetails,
    );
    if (mounted) setState(() => _saved = true);
  }

  Future<void> _showApiKeyDialog() async {
    final controller = TextEditingController(
        text: await _aiSvc.getApiKey() ?? '');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2540),
        title: const Text('設定 Anthropic API Key',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('請輸入你的 Anthropic API Key（sk-ant-...）：',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'sk-ant-api03-...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              await _aiSvc.setApiKey(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: Text('儲存並重新預測',
                style: TextStyle(color: AppTheme.primaryAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0F1A30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題列 ──
            Row(
              children: [
                const Icon(Icons.bar_chart, color: Color(0xFF7C4DFF), size: 18),
                const SizedBox(width: 8),
                const Text('胖胖數據分析',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),

            if (_loading)
              _buildLoading()
            else if (_result == null || _result!.hasError)
              _buildError()
            else
              _buildResult(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            CircularProgressIndicator(color: Color(0xFF7C4DFF)),
            SizedBox(height: 16),
            Text('胖胖數據分析中…',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    final msg = _result?.error ?? '未知錯誤';
    final isKeyMissing = msg.contains('API Key');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(color: Colors.white70, fontSize: 12))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (isKeyMissing)
              _ActionBtn(
                label: '設定 API Key',
                icon: Icons.key_outlined,
                onTap: _showApiKeyDialog,
              ),
            const SizedBox(width: 8),
            _ActionBtn(
              label: '重試',
              icon: Icons.refresh,
              onTap: () {
                _aiSvc.clearCache();
                _load();
              },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildResult(AiSportPrediction r) {
    final fixture = widget.fixture;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 整體局勢分析 ──
        if (r.narrative.isNotEmpty) ...[
          Text(
            r.narrative,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.85),
          ),
          const SizedBox(height: 16),
        ],

        // ── 比賽走向 ──
        if (r.gameFlow.isNotEmpty) ...[
          const Text(
            '比賽走向預測👇',
            style: TextStyle(
                color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            r.gameFlow,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.8),
          ),
          const SizedBox(height: 14),
        ],

        // ── 盤面解讀 ──
        if (r.marketNote.isNotEmpty) ...[
          Text(
            r.marketNote,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.7,
                fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
        ],

        // ── 莊家訊號 ──
        if (r.bookmakerNote.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1200),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD700).withAlpha(50)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Text('🎰 ', style: TextStyle(fontSize: 14)),
                  Text('莊家訊號',
                      style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text(r.bookmakerNote,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5, height: 1.75)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── 結論區塊 ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📌 結論',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              // 勝負
              Row(children: [
                const Text('✅ 勝負：',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Expanded(
                  child: Text(
                    r.winnerLabel.isNotEmpty
                        ? r.winnerLabel
                        : _defaultWinnerLabel(r.winner, fixture),
                    style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              // 足球：大小球
              if (r.overUnder != 'neutral') ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Text('✅ 大小：',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(
                    r.overUnderLabel.isNotEmpty
                        ? r.overUnderLabel
                        : (r.overUnder == 'over' ? '大分' : '小分'),
                    style: const TextStyle(
                        color: Color(0xFF3DDC97),
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ]),
              ],
              // 籃球/棒球：讓分
              if (r.spreadLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Text('✅ 讓分：',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Expanded(
                    child: Text(r.spreadLabel,
                        style: const TextStyle(
                            color: Color(0xFF3DDC97),
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              ],
              // Value Bet
              if (r.valueBetLabel.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF003300),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00E676).withAlpha(80)),
                  ),
                  child: Text(r.valueBetLabel,
                      style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.5)),
                ),
              ],
              // 倒打訊號
              if (r.fadeBetLabel.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0D00),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF6D00).withAlpha(90)),
                  ),
                  child: Text(r.fadeBetLabel,
                      style: const TextStyle(
                          color: Color(0xFFFFAB40),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.5)),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 賠率參考 ──
        const _SectionLabel(text: '賠率參考'),
        const SizedBox(height: 8),
        _OddsRow(fixture: fixture),

        // ── 已儲存徽章 ──
        if (_saved) ...[
          const SizedBox(height: 14),
          const Row(children: [
            Icon(Icons.check_circle_outline,
                color: Color(0xFF3DDC97), size: 14),
            SizedBox(width: 6),
            Text('預測已儲存至記錄',
                style: TextStyle(color: Color(0xFF3DDC97), fontSize: 12)),
          ]),
        ],

        // ── 操作按鈕 ──
        const SizedBox(height: 12),
        _ActionBtn(
          label: '重新分析',
          icon: Icons.refresh,
          onTap: () {
            _aiSvc.clearCache();
            _load();
          },
        ),
      ],
    );
  }

  String _defaultWinnerLabel(String winner, MatchFixture fixture) {
    if (winner == 'home') return '${fixture.homeTeam} 勝';
    if (winner == 'away') return '${fixture.awayTeam} 勝';
    return '和局';
  }
}

// ── 彩票 AI 預測卡片（539 / 樂透）────────────────────────────────

class AiLotteryPredictionCard extends StatefulWidget {
  const AiLotteryPredictionCard({
    super.key,
    required this.lotteryType,
    required this.drawNo,
    required this.recentDraws,
    this.newspaperHints,
    this.onSaved,
  });

  final String lotteryType;
  final String drawNo;
  final List<Map<String, dynamic>> recentDraws;
  final Map<String, dynamic>? newspaperHints; // 報紙預測資料
  final VoidCallback? onSaved;

  @override
  State<AiLotteryPredictionCard> createState() =>
      _AiLotteryPredictionCardState();
}

class _AiLotteryPredictionCardState extends State<AiLotteryPredictionCard> {
  final _aiSvc = AiPredictionService.instance;
  final _logSvc = PredictionLogService();

  AiLotteryPrediction? _result;
  bool _loading = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; });
    final result = await _aiSvc.predictLottery(
      recentDraws: widget.recentDraws,
      newspaperHints: widget.newspaperHints,
    );
    if (!mounted) return;
    setState(() { _result = result; _loading = false; });
    if (!result.hasError) _autoSave(result);
  }

  Future<void> _autoSave(AiLotteryPrediction r) async {
    if (_saved || r.recommendedNumbers.isEmpty) return;
    await _logSvc.saveLotteryPrediction(
      lotteryType: widget.lotteryType,
      drawNo: widget.drawNo,
      numbers: r.recommendedNumbers,
    );
    if (mounted) setState(() => _saved = true);
    widget.onSaved?.call();
  }

  Future<void> _showApiKeyDialog() async {
    final controller =
        TextEditingController(text: await _aiSvc.getApiKey() ?? '');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ApiKeyDialog(controller: controller, onSave: () async {
        await _aiSvc.setApiKey(controller.text);
        if (ctx.mounted) Navigator.pop(ctx);
        _load();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A0A00),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.bar_chart, color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 8),
              const Text('胖胖數據推薦號碼',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 16),
            if (_loading)
              _buildLoading()
            else if (_result == null || _result!.hasError)
              _buildError()
            else
              _buildResult(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            CircularProgressIndicator(color: Color(0xFFFFD700)),
            SizedBox(height: 12),
            Text('數據分析彩票規律中…',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        ),
      );

  Widget _buildError() {
    final msg = _result?.error ?? '未知錯誤';
    return _ErrorPanel(
      message: msg,
      onSetKey: _showApiKeyDialog,
      onRetry: () { _aiSvc.clearCache(); _load(); },
    );
  }

  Widget _buildResult(AiLotteryPrediction r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 號碼展示
        _NumberBubbles(
            numbers: r.recommendedNumbers, color: const Color(0xFFFFD700)),
        const SizedBox(height: 14),
        Row(children: [
          _NumberGroupChip(
              label: '熱號', numbers: r.hotNumbers, color: Colors.red),
          const SizedBox(width: 8),
          _NumberGroupChip(
              label: '冷號', numbers: r.coldNumbers, color: Colors.lightBlue),
        ]),
        if (r.strategy.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionLabel(text: '本期策略'),
          const SizedBox(height: 8),
          Text(r.strategy,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
        ],
        if (r.analysis.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionLabel(text: '數據分析'),
          const SizedBox(height: 8),
          Text(r.analysis,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12, height: 1.6)),
        ],
        if (_saved) ...[
          const SizedBox(height: 12),
          const Row(children: [
            Icon(Icons.check_circle_outline,
                color: Color(0xFF3DDC97), size: 14),
            SizedBox(width: 6),
            Text('預測已儲存至記錄',
                style: TextStyle(color: Color(0xFF3DDC97), fontSize: 12)),
          ]),
        ],
        const SizedBox(height: 12),
        _ActionBtn(
          label: '重新分析',
          icon: Icons.refresh,
          onTap: () { _aiSvc.clearCache(); _load(); },
        ),
      ],
    );
  }
}

// ── 賓果 AI 預測卡片 ───────────────────────────────────────────────

class AiBingoPredictionCard extends StatefulWidget {
  const AiBingoPredictionCard({
    super.key,
    required this.drawNo,
    required this.groupLabel,
    required this.recentDraws,
    this.onSaved,
  });

  final int drawNo;
  final String groupLabel;
  final List<Map<String, dynamic>> recentDraws;
  final VoidCallback? onSaved;

  @override
  State<AiBingoPredictionCard> createState() => _AiBingoPredictionCardState();
}

class _AiBingoPredictionCardState extends State<AiBingoPredictionCard> {
  final _aiSvc = AiPredictionService.instance;
  final _logSvc = PredictionLogService();

  AiBingoPrediction? _result;
  bool _loading = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; });
    final result = await _aiSvc.predictBingo(recentDraws: widget.recentDraws);
    if (!mounted) return;
    setState(() { _result = result; _loading = false; });
    if (!result.hasError) _autoSave(result);
  }

  Future<void> _autoSave(AiBingoPrediction r) async {
    if (_saved || r.recommendedNumbers.isEmpty) return;
    await _logSvc.saveBingoPrediction(
      drawNo: widget.drawNo,
      groupLabel: widget.groupLabel,
      numbers: r.recommendedNumbers,
    );
    if (mounted) setState(() => _saved = true);
    widget.onSaved?.call();
  }

  Future<void> _showApiKeyDialog() async {
    final controller =
        TextEditingController(text: await _aiSvc.getApiKey() ?? '');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ApiKeyDialog(controller: controller, onSave: () async {
        await _aiSvc.setApiKey(controller.text);
        if (ctx.mounted) Navigator.pop(ctx);
        _load();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0A1A0A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.bar_chart, color: Color(0xFF3DDC97), size: 18),
              const SizedBox(width: 8),
              const Text('胖胖數據賓果推薦',
                  style: TextStyle(
                      color: Color(0xFF3DDC97),
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Column(children: [
                    CircularProgressIndicator(color: Color(0xFF3DDC97)),
                    SizedBox(height: 12),
                    Text('數據分析賓果號碼中…',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                ),
              )
            else if (_result == null || _result!.hasError)
              _ErrorPanel(
                message: _result?.error ?? '未知錯誤',
                onSetKey: _showApiKeyDialog,
                onRetry: () { _aiSvc.clearCache(); _load(); },
              )
            else
              _buildResult(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(AiBingoPrediction r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NumberBubbles(numbers: r.recommendedNumbers, color: const Color(0xFF3DDC97)),
        const SizedBox(height: 14),
        Row(children: [
          _NumberGroupChip(label: '熱號', numbers: r.hotNumbers, color: Colors.red),
          const SizedBox(width: 8),
          _NumberGroupChip(label: '冷號', numbers: r.coldNumbers, color: Colors.lightBlue),
        ]),
        if (r.strategy.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionLabel(text: '本期策略'),
          const SizedBox(height: 8),
          Text(r.strategy,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
        ],
        if (r.analysis.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionLabel(text: '數據分析'),
          const SizedBox(height: 8),
          Text(r.analysis,
              style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.6)),
        ],
        if (_saved) ...[
          const SizedBox(height: 12),
          const Row(children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF3DDC97), size: 14),
            SizedBox(width: 6),
            Text('預測已儲存至記錄',
                style: TextStyle(color: Color(0xFF3DDC97), fontSize: 12)),
          ]),
        ],
        const SizedBox(height: 12),
        _ActionBtn(
          label: '重新分析',
          icon: Icons.refresh,
          onTap: () { _aiSvc.clearCache(); _load(); },
        ),
      ],
    );
  }
}

// ── 共用子元件 ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Colors.white70),
      );
}

class _OddsRow extends StatelessWidget {
  const _OddsRow({required this.fixture});
  final MatchFixture fixture;

  @override
  Widget build(BuildContext context) {
    final odds = fixture.odds;
    final isFootball = fixture.sport == SportType.football;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _OddsCell(label: '主勝', value: odds.homeWin.toStringAsFixed(2)),
          if (isFootball)
            _OddsCell(label: '平局', value: odds.draw.toStringAsFixed(2)),
          _OddsCell(label: '客勝', value: odds.awayWin.toStringAsFixed(2)),
          if (odds.overLine > 0)
            _OddsCell(
                label: '大/小',
                value: odds.overLine.toStringAsFixed(1)),
        ],
      ),
    );
  }
}

class _OddsCell extends StatelessWidget {
  const _OddsCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel(
      {required this.message, required this.onSetKey, required this.onRetry});
  final String message;
  final VoidCallback onSetKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withAlpha(60)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(message,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12))),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              if (message.contains('API Key'))
                _ActionBtn(
                    label: '設定 API Key',
                    icon: Icons.key_outlined,
                    onTap: onSetKey),
              _ActionBtn(label: '重試', icon: Icons.refresh, onTap: onRetry),
            ]),
          ],
        ),
      );
}

class _NumberBubbles extends StatelessWidget {
  const _NumberBubbles({required this.numbers, required this.color});
  final List<int> numbers;
  final Color color;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: numbers
            .map((n) => Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withAlpha(30),
                    border: Border.all(color: color.withAlpha(160), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    n.toString().padLeft(2, '0'),
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w900),
                  ),
                ))
            .toList(),
      );
}

class _NumberGroupChip extends StatelessWidget {
  const _NumberGroupChip(
      {required this.label, required this.numbers, required this.color});
  final String label;
  final List<int> numbers;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (numbers.isEmpty) return const SizedBox.shrink();
    final numStr =
        numbers.map((n) => n.toString().padLeft(2, '0')).join('  ');
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(numStr,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ApiKeyDialog extends StatelessWidget {
  const _ApiKeyDialog(
      {required this.controller, required this.onSave});
  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1A2540),
        title: const Text('設定 Anthropic API Key',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('請輸入你的 Anthropic API Key（sk-ant-...）：',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'sk-ant-api03-...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) controller.text = data!.text!;
              },
              child: const Text('從剪貼簿貼上',
                  style: TextStyle(color: Color(0xFF90CAF9), fontSize: 12)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: onSave,
            child: const Text('儲存並套用',
                style: TextStyle(color: Color(0xFF7C4DFF), fontWeight: FontWeight.w800)),
          ),
        ],
      );
}
