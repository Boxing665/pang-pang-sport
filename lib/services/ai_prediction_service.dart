import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/match_fixture.dart';
import '../models/sport_type.dart';
import 'kelly_criterion_service.dart';
import 'prediction_log_service.dart';
import 'self_learning_service.dart';
import 'pang_pang_sports_service.dart';

// ── 結果模型 ──────────────────────────────────────────────────────

class AiSportPrediction {
  const AiSportPrediction({
    required this.narrative,
    required this.gameFlow,
    required this.marketNote,
    required this.bookmakerNote,
    required this.winner,
    required this.winnerLabel,
    required this.overUnder,
    required this.overUnderLabel,
    required this.scoreOptions,
    required this.spreadLabel,
    required this.marginLabel,
    required this.spreadSide,
    required this.predictedHome,
    required this.predictedAway,
    required this.confidence,
    this.valueBetLabel = '',
    this.fadeBetLabel = '',
    this.signalDetails = const {},
    this.error = '',
  });

  final String narrative;
  final String gameFlow;
  final String marketNote;
  final String bookmakerNote;
  final String winner; // 'home' | 'draw' | 'away'
  final String winnerLabel;
  final String overUnder; // 'over' | 'under' | 'neutral'
  final String overUnderLabel;
  final List<String> scoreOptions;
  final String spreadLabel;
  final String marginLabel;
  final String spreadSide;   // 'home' | 'away' | ''
  final int predictedHome;
  final int predictedAway;
  final int confidence; // 1-100
  /// Value Bet：統計勝率比市場隱含勝率高 ≥6% 時顯示
  final String valueBetLabel;
  /// 倒打訊號：RLM / 疲乏熱門隊 / 強烈反市場時顯示
  final String fadeBetLabel;
  /// 各訊號原始數值（供自我學習校正權重用）
  final Map<String, double> signalDetails;
  final String error;

  bool get hasError => error.isNotEmpty;

  factory AiSportPrediction.fromError(String msg) => AiSportPrediction(
        narrative: '',
        gameFlow: '',
        marketNote: '',
        bookmakerNote: '',
        winner: 'home',
        winnerLabel: '',
        overUnder: 'neutral',
        overUnderLabel: '',
        scoreOptions: [],
        spreadLabel: '',
        marginLabel: '',
        spreadSide: '',
        predictedHome: 0,
        predictedAway: 0,
        confidence: 0,
        error: msg,
      );
}

class AiLotteryPrediction {
  const AiLotteryPrediction({
    required this.recommendedNumbers,
    required this.strategy,
    required this.analysis,
    required this.hotNumbers,
    required this.coldNumbers,
    this.error = '',
  });

  final List<int> recommendedNumbers;
  final String strategy;
  final String analysis;
  final List<int> hotNumbers;
  final List<int> coldNumbers;
  final String error;

  bool get hasError => error.isNotEmpty;

  factory AiLotteryPrediction.fromError(String msg) => AiLotteryPrediction(
        recommendedNumbers: [],
        strategy: '',
        analysis: '',
        hotNumbers: [],
        coldNumbers: [],
        error: msg,
      );
}

class AiBingoPrediction {
  const AiBingoPrediction({
    required this.recommendedNumbers,
    required this.strategy,
    required this.analysis,
    required this.hotNumbers,
    required this.coldNumbers,
    this.error = '',
  });

  final List<int> recommendedNumbers;
  final String strategy;
  final String analysis;
  final List<int> hotNumbers;
  final List<int> coldNumbers;
  final String error;

  bool get hasError => error.isNotEmpty;

  factory AiBingoPrediction.fromError(String msg) => AiBingoPrediction(
        recommendedNumbers: [],
        strategy: '',
        analysis: '',
        hotNumbers: [],
        coldNumbers: [],
        error: msg,
      );
}

// ── 主服務 ────────────────────────────────────────────────────────

class AiPredictionService {
  AiPredictionService._internal();
  static final AiPredictionService instance = AiPredictionService._internal();

  static const _apiKeyPref = 'anthropic_api_key';

  // 記憶體快取：matchId → 預測結果（避免同一場次重複計算）
  final _sportCache = <String, AiSportPrediction>{};
  AiLotteryPrediction? _lotteryCache;
  AiBingoPrediction? _bingoCache;

  // 自我學習：各運動校正後的訊號權重快取
  final _weightCache = <String, Map<String, double>>{};

  /// 在 app 啟動或 resume 時呼叫：背景執行賽果拉取 + 權重校正
  Future<void> runSelfLearning() async {
    final logSvc = PredictionLogService();
    await SelfLearningService.runInBackground(logSvc);
    _weightCache.clear(); // 清除舊快取，讓下次預測重新載入最新權重
  }

  Future<Map<String, double>> _getWeights(String sport) async {
    if (_weightCache.containsKey(sport)) return _weightCache[sport]!;
    final w = await SelfLearningService.loadWeightsFor(sport);
    _weightCache[sport] = w;
    return w;
  }

  // ── API Key 管理 ──────────────────────────────────────────────

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyPref);
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, key.trim());
    // 清除快取，讓新 key 的預測重新取得
    _sportCache.clear();
    _lotteryCache = null;
    _bingoCache = null;
  }

  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  void clearCache() {
    _sportCache.clear();
    _lotteryCache = null;
    _bingoCache = null;
  }

  void clearLotteryCache() => _lotteryCache = null;
  void clearBingoCache() => _bingoCache = null;
  void clearSportCache(String fixtureId) => _sportCache.remove(fixtureId);


  // ── 體育預測 ───────────────────────────────────────────────────

  Future<AiSportPrediction> predictSport(MatchFixture fixture) async {
    if (_sportCache.containsKey(fixture.id)) return _sportCache[fixture.id]!;
    final weights = await _getWeights(fixture.sport.name);
    final local = _localSportPrediction(fixture, calibratedWeights: weights);
    _sportCache[fixture.id] = local;
    return local;
  }

  // ── 539 彩票預測 ───────────────────────────────────────────────

  Future<AiLotteryPrediction> predictLottery({
    required List<Map<String, dynamic>> recentDraws,
    Map<String, dynamic>? newspaperHints,
  }) async {
    if (_lotteryCache != null) return _lotteryCache!;
    final result = _localLotteryPrediction(recentDraws, newspaperHints: newspaperHints);
    _lotteryCache = result;
    return result;
  }

  // ── 賓果賓果預測 ────────────────────────────────────────────────

  Future<AiBingoPrediction> predictBingo({
    required List<Map<String, dynamic>> recentDraws,
  }) async {
    if (_bingoCache != null) return _bingoCache!;
    final result = _localBingoPrediction(recentDraws);
    _bingoCache = result;
    return result;
  }

  // ── 本地統計分析 ─────────────────────────────────────────────────

  // ── 539 彩票：統計期望值 + Z-score + 十位平衡 + 間隔 + 連號 ──────
  AiLotteryPrediction _localLotteryPrediction(
    List<Map<String, dynamic>> recentDraws, {
    Map<String, dynamic>? newspaperHints,
  }) {
    if (recentDraws.isEmpty) {
      return AiLotteryPrediction.fromError('無歷史開獎資料可分析');
    }

    int toInt(dynamic n) => n is int ? n : (n as num).toInt();
    final draws = recentDraws.length;

    // 1. 頻率統計
    final freq = <int, int>{};
    for (var i = 1; i <= 39; i++) { freq[i] = 0; }
    for (final draw in recentDraws) {
      for (final n in (draw['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 39) freq[v] = freq[v]! + 1;
      }
    }

    // 2. 統計期望值 & Z-score：每期選 5/39，N 期後期望 N×5/39 次
    //    z = (實際 - 期望) / stdDev；z 越低 → 回補潛力越大
    final expected = draws * 5.0 / 39.0;
    final variance = expected * (1.0 - 5.0 / 39.0);
    final sd = variance > 0 ? _sqrtApprox(variance) : 1.0;
    final zScore = <int, double>{
      for (var n = 1; n <= 39; n++) n: (freq[n]! - expected) / sd,
    };

    // 3. 遺漏間隔（距上次出現期數）
    final lastSeen = <int, int>{};
    for (var i = 0; i < draws; i++) {
      for (final n in (recentDraws[i]['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 39) lastSeen.putIfAbsent(v, () => i);
      }
    }
    final gap = <int, int>{ for (var n = 1; n <= 39; n++) n: lastSeen[n] ?? draws };
    // Poisson 平均間隔 ≈ 39/5 = 7.8 期；超過 1.5× 間隔 → 加成
    const avgInterval = 39.0 / 5.0;
    final gapBonus = <int, double>{
      for (var n = 1; n <= 39; n++)
        n: gap[n]! > avgInterval * 1.5 ? ((gap[n]! - avgInterval * 1.5) / 10.0).clamp(0.0, 0.60) : 0.0,
    };

    // 4. 十位區段平衡（近 10 期各區命中率）
    //    區段：01-09(A) 10-19(B) 20-29(C) 30-39(D)
    final zoneHits539 = List<int>.filled(4, 0);
    for (final draw in recentDraws.take(10)) {
      for (final n in (draw['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 9) { zoneHits539[0]++; }
        else if (v <= 19) { zoneHits539[1]++; }
        else if (v <= 29) { zoneHits539[2]++; }
        else if (v <= 39) { zoneHits539[3]++; }
      }
    }
    final zoneAvg539 = zoneHits539.reduce((a, b) => a + b) / 4.0;
    double zoneBon539(int n) {
      final z = n <= 9 ? 0 : n <= 19 ? 1 : n <= 29 ? 2 : 3;
      return (zoneAvg539 - zoneHits539[z]) / (zoneAvg539 + 1) * 0.20;
    }

    // 5. 尾數（個位）近 5 期熱度 → 過熱輕懲
    final tailFreq = <int, int>{};
    for (final draw in recentDraws.take(5)) {
      for (final n in (draw['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 39) tailFreq[v % 10] = (tailFreq[v % 10] ?? 0) + 1;
      }
    }
    final hotTails = tailFreq.entries.where((e) => e.value >= 3).map((e) => e.key).toSet();

    // 6. 連號偵測（近 20 期）
    final pairScore = <int, int>{};
    for (final draw in recentDraws.take(20)) {
      final nums = (draw['numbers'] as List? ?? []).map<int>(toInt)
          .where((v) => v >= 1 && v <= 39).toSet();
      for (var n = 1; n <= 38; n++) {
        if (nums.contains(n) && nums.contains(n + 1)) pairScore[n] = (pairScore[n] ?? 0) + 1;
      }
    }
    final strongPairs = pairScore.entries.where((e) => e.value >= 4).map((e) => e.key).toList();

    // 6b. 路線分析（Pattern Path Analysis）
    // 圖表中彩色連線所追蹤的四條「路」：
    //   等差路（d=10/11/1/2 的等差對→提升延伸號）
    //   跨期重複路（近 5 期重複出現→熱路加成）
    //   同尾路（個位數缺失→回補加成）
    //   連號延伸路（(n,n+1)連號對→提升 n-1, n+2）

    // ── 等差路（Arithmetic Path）─────────────────────────────────────
    // 偵測近 5 期內出現「等差對」的號碼，提升其「延伸方向」的候選分數
    const arithmeticDiffs = [10, 11, 1, 2];
    final arithBonus = <int, double>{ for (var n = 1; n <= 39; n++) n: 0.0 };
    for (var di = 0; di < recentDraws.take(5).length; di++) {
      final recency = 1.0 - di * 0.18; // 最近期影響力最大
      final dnums = (recentDraws[di]['numbers'] as List? ?? [])
          .map<int>(toInt).where((v) => v >= 1 && v <= 39).toSet();
      for (final d in arithmeticDiffs) {
        for (final n in dnums) {
          if (dnums.contains(n + d)) {
            // (n, n+d) 形成等差對 → 延伸方向 n-d 和 n+2d 獲得加成
            for (final ext in <int>[n - d, n + 2 * d]) {
              if (ext >= 1 && ext <= 39) {
                arithBonus[ext] = (arithBonus[ext]! + 0.18 * recency).clamp(0.0, 0.60).toDouble();
              }
            }
            // 等差成員本身輕微加成（熱路延續可能）
            arithBonus[n] = (arithBonus[n]! + 0.04 * recency).clamp(0.0, 0.25).toDouble();
            arithBonus[n + d] = (arithBonus[n + d]! + 0.04 * recency).clamp(0.0, 0.25).toDouble();
          }
        }
      }
    }

    // ── 跨期重複路（Cross-draw Repeat Path）─────────────────────────
    // 圖表藍框 = 近期重複出現的號碼；近 5 期 ≥2 次視為「強路」
    final recentRepeat = <int, int>{ for (var n = 1; n <= 39; n++) n: 0 };
    for (final draw in recentDraws.take(5)) {
      for (final n in (draw['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 39) recentRepeat[v] = recentRepeat[v]! + 1;
      }
    }
    // 出現 2 次→+0.10，3 次→+0.20，以此類推
    final repeatBonus = <int, double>{
      for (var n = 1; n <= 39; n++)
        n: recentRepeat[n]! >= 2 ? ((recentRepeat[n]! - 1) * 0.10).clamp(0.0, 0.30) : 0.0,
    };

    // ── 同尾路（Same Tail Digit Path）──────────────────────────────
    // 個位數組型：近 3 期缺席的尾數對應號碼有回補機會
    final recentTailCnt = <int, int>{ for (var t = 0; t < 10; t++) t: 0 };
    for (final draw in recentDraws.take(3)) {
      for (final n in (draw['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 39) recentTailCnt[v % 10] = recentTailCnt[v % 10]! + 1;
      }
    }
    final tailTotal3 = recentTailCnt.values.fold(0, (s, v) => s + v);
    final tailAvg3 = tailTotal3 / 10.0;
    final tailPathBonus = <int, double>{
      for (var n = 1; n <= 39; n++)
        n: (tailAvg3 - recentTailCnt[n % 10]!).clamp(0.0, tailAvg3) /
            (tailAvg3 + 0.1) *
            0.14,
    };

    // ── 連號延伸路（Consecutive Extension Path）──────────────────────
    // 近 3 期出現連號 (n, n+1) → 提升鄰號 n-1 與 n+2 的候選分數
    final consecBonus = <int, double>{ for (var n = 1; n <= 39; n++) n: 0.0 };
    for (var di = 0; di < recentDraws.take(3).length; di++) {
      final recency = 1.0 - di * 0.28;
      final dnums = (recentDraws[di]['numbers'] as List? ?? [])
          .map<int>(toInt).where((v) => v >= 1 && v <= 39).toSet();
      for (final n in dnums) {
        if (dnums.contains(n + 1)) {
          if (n - 1 >= 1) consecBonus[n - 1] = (consecBonus[n - 1]! + 0.12 * recency).clamp(0.0, 0.30);
          if (n + 2 <= 39) consecBonus[n + 2] = (consecBonus[n + 2]! + 0.12 * recency).clamp(0.0, 0.30);
        }
      }
    }

    // 7. 綜合評分：Z-score回補25% + 遺漏加成25% + 頻率10% + 十位平衡10% + 路線分析30%
    final maxFreq = freq.values.reduce((a, b) => a > b ? a : b);
    final score = <int, double>{};
    for (var n = 1; n <= 39; n++) {
      final zBon  = (-zScore[n]!).clamp(-1.0, 2.0) * 0.25;
      final gBon  = gapBonus[n]! * 0.25;
      final fNorm = maxFreq > 0 ? freq[n]! / maxFreq * 0.10 : 0.0;
      final zBon2 = zoneBon539(n) * 0.10;
      final tPen  = hotTails.contains(n % 10) ? -0.06 : 0.0;
      // 路線分析（等差路 + 跨期重複路 + 同尾路 + 連號延伸路）
      final pathBonus = arithBonus[n]! + repeatBonus[n]! + tailPathBonus[n]! + consecBonus[n]!;
      score[n] = zBon + gBon + fNorm + zBon2 + tPen + pathBonus;
    }
    final sortedByScore = score.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final hotNumbers  = (freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(8).map((e) => e.key).toList();
    final coldNumbers = sortedByScore.take(8).map((e) => e.key).toList();

    // 8. 蒙地卡羅加權模擬（50,000 次，無放回抽樣）
    // 用各號碼的統計評分作為抽樣權重，統計每號被「抽中」的頻率
    // 使用 Efraimidis-Spirakis 演算法：key_i = -ln(U_i)/w_i，取最小 key 的 5 個號碼
    final mcTop = _weightedMonteCarlo(
      scores: score, ballCount: 39, pickCount: 5, iterations: 50000,
    );

    // 8a. 選號：蒙地卡羅高頻候選 + 報紙神卦強訊號
    final lastDrawNums = (recentDraws.first['numbers'] as List? ?? []).map<int>(toInt).toSet();
    final recommended = <int>[];

    // 報紙神卦（外部強訊號）優先
    if (newspaperHints != null) {
      final guZhi = newspaperHints['guZhi'];
      if (guZhi is int && guZhi >= 1 && guZhi <= 39) recommended.add(guZhi);
      for (final key in ['erZhong', 'xique']) {
        for (final n in (newspaperHints[key] as List? ?? [])) {
          final v = toInt(n);
          if (v >= 1 && v <= 39 && !recommended.contains(v) && recommended.length < 3) recommended.add(v);
        }
      }
    }
    // MC 高頻候選（排除上期連莊）
    for (final n in mcTop) {
      if (recommended.length >= 5) break;
      if (!recommended.contains(n) && !lastDrawNums.contains(n)) recommended.add(n);
    }
    // 兜底：確保滿 5 個
    for (final e in sortedByScore) {
      if (recommended.length >= 5) break;
      if (!recommended.contains(e.key)) recommended.add(e.key);
    }
    recommended.sort();

    // 8b. 總和約束修正
    // 539 歷史統計：5 顆號碼總和集中在 80~120（均值約 100），超出範圍嘗試替換
    const sumLow = 75, sumHigh = 125;
    int trySum() => recommended.fold(0, (s, n) => s + n);
    if (recommended.length == 5) {
      var attempts = 0;
      while ((trySum() < sumLow || trySum() > sumHigh) && attempts < 30) {
        attempts++;
        final s = trySum();
        if (s < sumLow) {
          // 替換最小號為評分較高的較大號
          final minN = recommended.reduce((a, b) => a < b ? a : b);
          final candidate = sortedByScore.firstWhere(
            (e) => e.key > minN && !recommended.contains(e.key),
            orElse: () => sortedByScore.first,
          );
          recommended.remove(minN);
          recommended.add(candidate.key);
        } else {
          // 替換最大號為評分較高的較小號
          final maxN = recommended.reduce((a, b) => a > b ? a : b);
          final candidate = sortedByScore.firstWhere(
            (e) => e.key < maxN && !recommended.contains(e.key),
            orElse: () => sortedByScore.first,
          );
          recommended.remove(maxN);
          recommended.add(candidate.key);
        }
        recommended.sort();
      }
    }

    // 9. 分析文字
    final dueNums = sortedByScore
        .where((e) => zScore[e.key]! < -0.8 && gap[e.key]! > avgInterval.round())
        .take(3).map((e) => e.key).toList();
    final hotStr = hotNumbers.take(3).map((n) => n.toString().padLeft(2, '0')).join('、');
    final dueStr = dueNums.map((n) =>
        '${n.toString().padLeft(2, '0')}(遺漏${gap[n]}期 z=${zScore[n]!.toStringAsFixed(1)})')
        .join('、');
    final weakZones539 = List.generate(4, (z) => z)
        .where((z) => zoneHits539[z] < zoneAvg539)
        .map((z) => ['01-09', '10-19', '20-29', '30-39'][z]).join('、');

    return AiLotteryPrediction(
      recommendedNumbers: recommended.take(5).toList(),
      strategy: '近$draws期：Poisson加權蒙地卡羅5萬次模擬＋Z-score＋遺漏間隔＋十位平衡'
          '${newspaperHints != null ? "＋報紙神卦" : ""}',
      analysis: '統計回補：${dueStr.isNotEmpty ? dueStr : "暫無顯著回補"}；'
          '熱號（$hotStr）高頻穩定；'
          '${weakZones539.isNotEmpty ? "失衡區段（$weakZones539）具回補潛力；" : ""}'
          '${strongPairs.isNotEmpty ? "連號規律：${strongPairs.take(2).map((n) => "$n-${n+1}").join("、")}。" : ""}',
      hotNumbers: hotNumbers.take(5).toList(),
      coldNumbers: coldNumbers.take(5).toList(),
    );
  }

  // ── 賓果賓果：Z分數＋遺漏間隔＋區段平衡＋連號 ───────────────────
  AiBingoPrediction _localBingoPrediction(List<Map<String, dynamic>> recentDraws) {
    if (recentDraws.isEmpty) {
      return AiBingoPrediction.fromError('無歷史開獎資料可分析');
    }

    int toInt(dynamic n) => n is int ? n : (n as num).toInt();
    final draws = recentDraws.length;

    // 1. 頻率統計
    final freq = <int, int>{};
    for (var i = 1; i <= 80; i++) { freq[i] = 0; }
    for (final draw in recentDraws) {
      for (final n in (draw['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 80) { freq[v] = freq[v]! + 1; }
      }
    }

    // 2. 間隔分析（距上次開出幾期）
    final lastSeen = <int, int>{};
    for (var i = 0; i < recentDraws.length; i++) {
      for (final n in (recentDraws[i]['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 80) lastSeen.putIfAbsent(v, () => i);
      }
    }
    final gap = <int, int>{
      for (var n = 1; n <= 80; n++) n: lastSeen.containsKey(n) ? lastSeen[n]! : draws,
    };

    // 3. Z 分數：每期選 20/80 = 25%，期望次數 = draws × 0.25
    //    stdDev = sqrt(draws × 0.25 × 0.75)
    final expected = draws * 0.25;
    final stdDev   = _sqrtApprox(draws * 0.25 * 0.75);
    final zScore   = <int, double>{
      for (var n = 1; n <= 80; n++) n: stdDev > 0 ? (freq[n]! - expected) / stdDev : 0.0,
    };

    // 4. 遺漏間隔加分：avgInterval = 80/20 = 4 期，超過 1.5× (6期) 開始加分
    const overdueThreshold = 6.0; // 1.5 × avgInterval(4)
    final gapBonus = <int, double>{};
    for (var n = 1; n <= 80; n++) {
      final g = gap[n]!.toDouble();
      gapBonus[n] = g > overdueThreshold ? (g - overdueThreshold) / (draws + 1) * 0.30 : 0.0;
    }

    // 5. 區段分析（1-20、21-40、41-60、61-80）— 近5期各區命中數
    final zoneHits = List<int>.filled(4, 0);
    for (final draw in recentDraws.take(5)) {
      for (final n in (draw['numbers'] as List? ?? [])) {
        final v = toInt(n);
        if (v >= 1 && v <= 80) { zoneHits[(v - 1) ~/ 20]++; }
      }
    }
    final zoneAvg   = zoneHits.reduce((a, b) => a + b) / 4.0;
    final zoneBonus = List.generate(4, (z) => (zoneAvg - zoneHits[z]).clamp(0.0, zoneAvg) / (zoneAvg + 1) * 0.20);

    // 6. 連號偵測（近15期）
    final pairScore = <int, int>{};
    for (final draw in recentDraws.take(15)) {
      final nums = (draw['numbers'] as List? ?? [])
          .map<int>(toInt).where((v) => v >= 1 && v <= 80).toSet();
      for (var n = 1; n <= 79; n++) {
        if (nums.contains(n) && nums.contains(n + 1)) {
          pairScore[n] = (pairScore[n] ?? 0) + 1;
        }
      }
    }
    final strongPairs = pairScore.entries.where((e) => e.value >= 5).map((e) => e.key).toList();

    // 7. 綜合評分：Z分數35% + 遺漏間隔30% + 區段20% + 頻率反向15%
    final maxFreq = freq.values.reduce((a, b) => a > b ? a : b);
    final score   = <int, double>{};
    for (var n = 1; n <= 80; n++) {
      final zone     = (n - 1) ~/ 20;
      // Z 分數越低（偏冷）→ 回補分越高
      final zPart    = (-zScore[n]!).clamp(-3.0, 3.0) / 3.0 * 0.35;
      // 冷頻（出現少）→ 加分
      final fCold    = maxFreq > 0 ? (1.0 - freq[n]! / maxFreq) * 0.15 : 0.0;
      score[n] = zPart + gapBonus[n]! + zoneBonus[zone] + fCold;
    }
    final sortedByScore = score.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final hotNumbers  = sortedByScore.take(10).map((e) => e.key).toList();
    final coldNumbers = (freq.entries.toList()..sort((a, b) => a.value.compareTo(b.value)))
        .take(10).map((e) => e.key).toList();
    final lastDrawNums = (recentDraws.first['numbers'] as List? ?? [])
        .map<int>(toInt).toSet();

    // 蒙地卡羅加權模擬（50,000 次，無放回抽樣 80 選 20）
    final mcTop = _weightedMonteCarlo(
      scores: score, ballCount: 80, pickCount: 20, iterations: 50000,
    );

    final recommended = <int>[];

    // MC 高頻候選（排除上期連莊），取前 8 個
    for (final n in mcTop) {
      if (recommended.length >= 8) break;
      if (!lastDrawNums.contains(n)) recommended.add(n);
    }

    // 強連號夥伴補強
    for (final p in strongPairs) {
      if (recommended.length >= 10) break;
      if (recommended.contains(p) && !recommended.contains(p + 1) && !lastDrawNums.contains(p + 1)) {
        recommended.add(p + 1);
      } else if (recommended.contains(p + 1) && !recommended.contains(p) && !lastDrawNums.contains(p)) {
        recommended.add(p);
      }
    }

    // 兜底補滿 10 個
    for (final e in sortedByScore) {
      if (recommended.length >= 10) break;
      if (!recommended.contains(e.key)) { recommended.add(e.key); }
    }

    recommended.sort();

    final dueNums = sortedByScore
        .where((e) => zScore[e.key]! < -0.8 && gap[e.key]! > overdueThreshold.round())
        .take(4).map((e) => e.key).toList();
    final hotStr  = hotNumbers.take(5).map((n) => n.toString().padLeft(2, '0')).join('、');
    final coldStr = coldNumbers.take(5).map((n) => n.toString().padLeft(2, '0')).join('、');
    final weakZones = List.generate(4, (z) => z)
        .where((z) => zoneHits[z] < zoneAvg)
        .map((z) => '${z * 20 + 1}–${z * 20 + 20}')
        .join('、');
    final dueStr  = dueNums.isNotEmpty
        ? dueNums.map((n) => n.toString().padLeft(2, '0')).join('、') : '';

    return AiBingoPrediction(
      recommendedNumbers: recommended.take(10).toList(),
      strategy: '近$draws期：Poisson加權蒙地卡羅5萬次模擬＋Z分數＋遺漏間隔＋區段平衡${strongPairs.isNotEmpty ? "＋連號補正" : ""}',
      analysis: '熱號（$hotStr）；冷號（$coldStr）。'
          '${dueStr.isNotEmpty ? "回補候選（$dueStr）Z值明顯偏低。" : ""}'
          '${weakZones.isNotEmpty ? "低命中區段（$weakZones）具回補潛力。" : ""}'
          '${strongPairs.isNotEmpty ? "強連號：${strongPairs.take(3).map((n) => "$n-${n + 1}").join("、")}。" : ""}',
      hotNumbers: hotNumbers.take(5).toList(),
      coldNumbers: coldNumbers.take(5).toList(),
    );
  }

  // ── 體育：近3場均值＋連勝＋B2B＋盤口移動＋自我學習權重 ──────────
  AiSportPrediction _localSportPrediction(
    MatchFixture fixture, {
    Map<String, double>? calibratedWeights,
  }) {
    final hf   = fixture.homeForm;
    final af   = fixture.awayForm;
    final odds = fixture.odds;
    final home = fixture.homeTeam;
    final away = fixture.awayTeam;
    final isBasketball = fixture.sport == SportType.basketball;
    final isBaseball   = fixture.sport == SportType.baseball;
    final isFootball   = fixture.sport == SportType.football;
    final isBall       = isBasketball || isBaseball;

    // 1. 近況（使用 TeamForm getter，正確識別中文勝/負/平）
    final hWins   = hf.wins;
    final aWins   = af.wins;
    final hLosses = hf.losses;
    final aLosses = af.losses;

    // 2. 近3場滾動均值混合整季均值（65/35 加權）
    final hScored    = hf.last3AvgScored   != null ? hf.last3AvgScored!   * 0.65 + hf.averageScored    * 0.35 : hf.averageScored;
    final hConceded  = hf.last3AvgConceded != null ? hf.last3AvgConceded! * 0.65 + hf.averageConceded  * 0.35 : hf.averageConceded;
    final aScored    = af.last3AvgScored   != null ? af.last3AvgScored!   * 0.65 + af.averageScored    * 0.35 : af.averageScored;
    final aConceded  = af.last3AvgConceded != null ? af.last3AvgConceded! * 0.65 + af.averageConceded  * 0.35 : af.averageConceded;

    String formDesc(String team, int wins, int losses, double scored, double conceded) {
      final tag = wins >= 4 ? '近況火燙' : wins >= 3 ? '狀態穩定' : losses >= 3 ? '狀態低迷' : '表現平淡';
      return '$team$tag，近${hf.lastFiveResults.length}場 $wins 勝 $losses 負，均得 ${scored.toStringAsFixed(1)} 失 ${conceded.toStringAsFixed(1)}';
    }

    // 3. 連勝/連敗因子（clamp ±5，歸一化至 [-1, 1]）
    final hStreak = hf.currentStreak.clamp(-5, 5);
    final aStreak = af.currentStreak.clamp(-5, 5);
    final normalizedStreak = (hStreak - aStreak) / 10.0;

    // 4. B2B 疲勞因子（主隊B2B → 主隊邊際下降）
    final b2bEdge = (af.isB2B ? 0.12 : 0.0) - (hf.isB2B ? 0.12 : 0.0);

    // 5. 動能（歸一化至 [-1, 1]）
    // ESPN 足球/棒球動能約 ±10；7m 籃球以勝率換算可達 ±100
    final momentumDivisor = isBasketball ? 50.0 : 10.0;
    final normalizedMomentum = ((hf.momentumScore - af.momentumScore) / momentumDivisor).clamp(-1.0, 1.0);

    // 6. 近況勝率（歸一化）
    final normalizedWins = (hWins - aWins) / 5.0;

    // 7. 賠率訊號（足球賠率差距較小，使用較緊的歸一化係數）
    final fairHome = odds.fairHomeProb;
    final fairDraw = odds.fairDrawProb;
    final fairAway = odds.fairAwayProb;
    final oddsNormDivisor = isFootball ? 0.4 : 0.6;
    final normalizedOdds = ((fairHome - fairAway) / oddsNormDivisor).clamp(-1.0, 1.0);

    // 8. 綜合邊際（使用自我學習校正後的權重，預設值為初始設定）
    final wOdds     = calibratedWeights?['odds']     ?? 0.40;
    final wMomentum = calibratedWeights?['momentum'] ?? 0.25;
    final wWins     = calibratedWeights?['wins']     ?? 0.15;
    final wStreak   = calibratedWeights?['streak']   ?? 0.12;
    final wB2b      = calibratedWeights?['b2b']      ?? 0.08;

    final edge = normalizedMomentum * wMomentum
        + normalizedWins    * wWins
        + normalizedOdds    * wOdds
        + normalizedStreak  * wStreak
        + b2bEdge           * wB2b;

    // 9. 足球平局偵測（需同時滿足兩個條件，避免過度偵測壓低信心值）
    final isDraw = isFootball && edge.abs() < 0.08 && fairDraw > 0.28;

    // 10. 基礎信心值
    final confidenceSlope = isFootball ? 125.0 : 95.0;
    int confidence = (50 + (edge.abs() * confidenceSlope).clamp(0, 40)).round();

    // 盤口移動調整（有真實博彩商資料時才使用）
    if (odds.isFromBookmaker && odds.openingHomeWin > 0) {
      if (odds.hasReverseLineMovement) {
        confidence = (confidence * 0.87).round();
      } else if (odds.marketMovement.abs() > 0.08) {
        final withPrediction = (odds.marketMovement > 0 && edge > 0) || (odds.marketMovement < 0 && edge < 0);
        if (withPrediction) confidence = (confidence * 1.08).clamp(50, 90).round();
      }
    }
    if (hf.isB2B || af.isB2B) confidence = (confidence * 0.92).round();

    // 11. 走勢標籤
    final hPct = (fairHome * 100).round();
    final aPct = (fairAway * 100).round();
    final bookmakerFavors = fairHome > fairAway ? home : away;
    final marketNote = '博彩市場去除抽水後：$home真實勝率 $hPct%，$away真實勝率 $aPct%，莊家偏向「$bookmakerFavors」。';

    String movementNote = '';
    if (odds.isFromBookmaker && odds.openingHomeWin > 0) {
      if (odds.hasReverseLineMovement) {
        final moveSide = odds.marketMovement > 0 ? home : away;
        movementNote = '⚠️ 逆向盤口：大眾偏向一邊，資金卻反向流入「$moveSide」，疑似聰明錢介入。';
      } else if (odds.marketMovement.abs() > 0.08) {
        final moveSide = odds.marketMovement > 0 ? home : away;
        movementNote = '盤口資金明顯流向「$moveSide」，市場偏向確立。';
      }
    }

    String momentumNote;
    if ((hf.momentumScore - af.momentumScore).abs() < 3) {
      momentumNote = '雙方動能旗鼓相當，勝負關鍵在細節執行力。';
    } else if (hf.momentumScore > af.momentumScore) {
      momentumNote = '$home動能優於$away（${hf.momentumScore.toStringAsFixed(1)} vs ${af.momentumScore.toStringAsFixed(1)}），主場優勢加持下略佔優。';
    } else {
      momentumNote = '$away客隊動能反超（${af.momentumScore.toStringAsFixed(1)} vs ${hf.momentumScore.toStringAsFixed(1)}），客場挑戰頗具威脅。';
    }

    String b2bNote = '';
    if (hf.isB2B && af.isB2B) {
      b2bNote = '雙方均為背靠背賽，體力消耗不容忽視。';
    } else if (hf.isB2B) {
      b2bNote = '$home背靠背出賽（昨日已出賽），體力略為疲乏。';
    } else if (af.isB2B) {
      b2bNote = '$away背靠背出賽，長途奔波下體力稍有下滑。';
    }

    String injuryNote = '';
    if (hf.injuries > 0 && hf.injuries >= af.injuries) {
      injuryNote = '$home有 ${hf.injuries} 名傷兵，戰力受到一定影響。';
    } else if (af.injuries > 0) {
      injuryNote = '$away有 ${af.injuries} 名傷兵，可能影響客隊整體發揮。';
    }

    // 賽果：有真實賭盤 → 跟市場走；無賭盤 → 才用統計邊際
    final String winner;
    if (isDraw) {
      winner = 'draw';
    } else if (odds.isFromBookmaker) {
      winner = fairHome >= fairAway ? 'home' : 'away';
    } else {
      winner = edge >= 0 ? 'home' : 'away';
    }

    // 統計邊際是否與市場方向一致
    final statsAgree = winner == 'draw' ||
        (winner == 'home' && edge > 0.05) ||
        (winner == 'away' && edge < -0.05);

    // 信心值最終調整：依資料品質與訊號一致性決定
    if (!odds.isFromBookmaker) {
      confidence = confidence.clamp(40, 58);
      if (movementNote.isEmpty) {
        movementNote = '⚠️ 此場次目前無真實賭盤資料，以下為統計估算，不建議依賴本預測下注。';
      }
    } else if (statsAgree) {
      confidence = (confidence + 7).clamp(50, 90);
    } else {
      confidence = (confidence * 0.80).round().clamp(45, 70);
      if (movementNote.isEmpty) {
        movementNote = '⚠️ 數據分析與市場賠率方向不一致，訊號分歧，建議本場觀望。';
      }
    }

    final String winnerLabel;
    final String gameFlow;

    if (isDraw) {
      final drawPct = (fairDraw * 100).round();
      winnerLabel = '平局（市場平局機率 $drawPct%）';
      confidence  = confidence.clamp(52, 72);
      gameFlow    = '${formDesc(home, hWins, hLosses, hScored, hConceded)}；'
          '${formDesc(away, aWins, aLosses, aScored, aConceded)}。'
          '$momentumNote${b2bNote.isNotEmpty ? " $b2bNote" : ""}${injuryNote.isNotEmpty ? " $injuryNote" : ""}'
          '整體看來勝負難分，臨場執行力是關鍵。';
    } else if (winner == 'home') {
      final marketPct = (fairHome * 100).round();
      final tag = odds.isFromBookmaker ? (statsAgree ? '，數據確認' : '，數據分歧') : '（統計估算）';
      winnerLabel = '$home勝出（市場勝率 $marketPct%$tag）';
      confidence  = confidence.clamp(52, 90);
      gameFlow    = '${formDesc(home, hWins, hLosses, hScored, hConceded)}。'
          '$momentumNote${b2bNote.isNotEmpty ? " $b2bNote" : ""}${injuryNote.isNotEmpty ? " $injuryNote" : ""}'
          '${statsAgree ? "市場與數據雙重看好$home，把握主場優勢拿下勝利。" : "市場看好$home，但近期近況訊號偏弱，宜謹慎。"}';
    } else {
      final marketPct = (fairAway * 100).round();
      final tag = odds.isFromBookmaker ? (statsAgree ? '，數據確認' : '，數據分歧') : '（統計估算）';
      winnerLabel = '$away客隊勝出（市場勝率 $marketPct%$tag）';
      confidence  = confidence.clamp(52, 90);
      gameFlow    = '${formDesc(away, aWins, aLosses, aScored, aConceded)}。'
          '$momentumNote${b2bNote.isNotEmpty ? " $b2bNote" : ""}${injuryNote.isNotEmpty ? " $injuryNote" : ""}'
          '${statsAgree ? "市場與數據雙重看好$away客場作戰，動能充足。" : "市場看好$away，但近期近況訊號偏弱，宜謹慎。"}';
    }

    // 12. 實際比分：呼叫完整 PredictionEngine（賭盤錨定 + Dixon-Coles + MC 1000次模擬）
    // 以莊家讓分/大小分為主要錨點，確保預測比分與市場一致
    final ep = const PredictionEngine().predictScore(fixture);
    final predictedHome = ep.predictedHomeScore;
    final predictedAway = ep.predictedAwayScore;

    final String overUnder;
    final String overUnderLabel;
    if (odds.overLine > 0 && odds.overOdds != odds.underOdds) {
      if (odds.overOdds < odds.underOdds) {
        overUnder = 'over';
        overUnderLabel = '大 ${odds.overLine.toStringAsFixed(1)}（賠率 ${odds.overOdds.toStringAsFixed(2)}）';
      } else {
        overUnder = 'under';
        overUnderLabel = '小 ${odds.overLine.toStringAsFixed(1)}（賠率 ${odds.underOdds.toStringAsFixed(2)}）';
      }
    } else {
      overUnder = 'neutral';
      overUnderLabel = '';
    }

    // 13. 讓分（籃球/棒球）：直接使用盤口讓分，不自行推算
    String spreadLabel = '';
    String spreadSide  = '';
    if (isBall && odds.spread != 0) {
      if (odds.spread > 0) {
        spreadSide  = 'home';
        spreadLabel = '主隊讓 ${odds.spread.toStringAsFixed(1)} 分（賠率 ${odds.homeSpreadOdds.toStringAsFixed(2)}）';
      } else {
        spreadSide  = 'away';
        spreadLabel = '客隊讓 ${odds.spread.abs().toStringAsFixed(1)} 分（賠率 ${odds.awaySpreadOdds.toStringAsFixed(2)}）';
      }
    }

    // 14. Value Bet & 倒打訊號
    String valueBetLabel = '';
    String fadeBetLabel  = '';

    if (odds.isFromBookmaker) {
      // 統計勝率估算（edge [-1,1] → 機率）
      final statHomeProb = (0.5 + edge * 0.35).clamp(0.10, 0.90);
      final statAwayProb = (0.5 - edge * 0.35).clamp(0.10, 0.90);
      final homeValue    = statHomeProb - fairHome;
      final awayValue    = statAwayProb - fairAway;

      // Value Bet：統計與市場差距 ≥6%，同步顯示 1/4 Kelly 建議下注比例
      if (!isDraw && homeValue >= 0.06) {
        final excess = (homeValue * 100).round();
        final kelly  = KellyCriterionService.calculateKellyBet(statHomeProb, odds.homeWin);
        final kellyPct = (kelly * 100).toStringAsFixed(1);
        valueBetLabel = '💰 主隊 Value Bet：統計 ${(statHomeProb * 100).round()}%'
            ' vs 市場 ${(fairHome * 100).round()}%（超值 +$excess%）'
            '${kelly > 0 ? "\n📐 Kelly 建議：下注資金的 $kellyPct%（1/4 Kelly）" : ""}';
      } else if (!isDraw && awayValue >= 0.06) {
        final excess = (awayValue * 100).round();
        final kelly  = KellyCriterionService.calculateKellyBet(statAwayProb, odds.awayWin);
        final kellyPct = (kelly * 100).toStringAsFixed(1);
        valueBetLabel = '💰 客隊 Value Bet：統計 ${(statAwayProb * 100).round()}%'
            ' vs 市場 ${(fairAway * 100).round()}%（超值 +$excess%）'
            '${kelly > 0 ? "\n📐 Kelly 建議：下注資金的 $kellyPct%（1/4 Kelly）" : ""}';
      }

      // 倒打①：逆向資金（RLM）—— 聰明錢反向介入
      if (odds.hasReverseLineMovement) {
        final smartSide  = odds.marketMovement < 0 ? away : home;
        final publicSide = odds.marketMovement < 0 ? home : away;
        fadeBetLabel = '🔄 倒打訊號（RLM）：大眾資金偏「$publicSide」，'
            '但聰明錢反向流入「$smartSide」，考慮倒打「$smartSide」。';
      }
      // 倒打②：疲乏熱門——市場看好的客隊今日 B2B
      else if (af.isB2B && fairAway > fairHome + 0.08) {
        fadeBetLabel = '🔄 倒打機會（疲乏熱門）：市場看好客隊「$away」'
            '，但今日背靠背出賽體力透支，可考慮倒打支持主隊「$home」。';
      }
      // 倒打③：市場熱門反近況——大差統計分歧
      else if (!statsAgree && edge.abs() > 0.20) {
        final mktFav  = fairHome >= fairAway ? home : away;
        final statFav = edge > 0 ? home : away;
        if (mktFav != statFav) {
          fadeBetLabel = '🔄 倒打機會（數據分歧）：市場看好「$mktFav」，'
              '但近5場數據強烈偏向「$statFav」，有逆向機會。';
        }
      }
    }

    final narrative = '【數據分析】\n'
        '${formDesc(home, hWins, hLosses, hScored, hConceded)}。\n'
        '${formDesc(away, aWins, aLosses, aScored, aConceded)}。';

    return AiSportPrediction(

      narrative:      narrative,
      gameFlow:       gameFlow,
      marketNote:     marketNote,
      bookmakerNote:  movementNote,
      winner:         winner,
      winnerLabel:    winnerLabel,
      overUnder:      overUnder,
      overUnderLabel: overUnderLabel,
      scoreOptions:   [],
      spreadLabel:    spreadLabel,
      marginLabel:    '',
      spreadSide:     spreadSide,
      predictedHome:  predictedHome,
      predictedAway:  predictedAway,
      confidence:     confidence,
      valueBetLabel:  valueBetLabel,
      fadeBetLabel:   fadeBetLabel,
      signalDetails: {
        'edge':               edge,
        'normalizedOdds':     normalizedOdds,
        'normalizedMomentum': normalizedMomentum,
        'normalizedWins':     normalizedWins,
        'normalizedStreak':   normalizedStreak,
        'b2bEdge':            b2bEdge,
        'isFromBookmaker':    odds.isFromBookmaker ? 1.0 : 0.0,
        'statsAgree':         statsAgree ? 1.0 : 0.0,
      },
    );
  }

  /// 加權蒙地卡羅無放回抽樣（Efraimidis-Spirakis 演算法）
  ///
  /// 對每個號碼計算 key_i = -ln(U_i) / w_i（U_i 為均勻亂數，w_i 為號碼權重），
  /// 取 key 最小的 [pickCount] 個號碼為本次「中獎」組合，
  /// 重複 [iterations] 次後統計各號出現頻率，依頻率降冪排列回傳。
  ///
  /// 原理等價於「以分數比例抽取、無重複」，即 random.choices(weights=...) 的無放回版本。
  static List<int> _weightedMonteCarlo({
    required Map<int, double> scores,
    required int ballCount,
    required int pickCount,
    int iterations = 50000,
  }) {
    final nums = List<int>.generate(ballCount, (i) => i + 1);
    // 平移至全正數，避免 log(0) 或負權重
    final minS = nums.fold(double.infinity, (m, n) => scores[n]! < m ? scores[n]! : m);
    final weights = nums.map((n) => (scores[n]! - minS) + 0.01).toList();

    final rng = Random();
    final freq = <int, int>{};
    // 預先分配 key 陣列（避免每次迭代 GC 壓力）
    final keyVals = List<double>.filled(ballCount, 0.0);
    final keyIdxs = List<int>.generate(ballCount, (i) => i);

    for (var iter = 0; iter < iterations; iter++) {
      // 產生 Efraimidis-Spirakis key
      for (var i = 0; i < ballCount; i++) {
        final u = rng.nextDouble().clamp(1e-12, 1.0);
        keyVals[i] = -log(u) / weights[i];
      }
      // 以 key 升冪排序索引（key 最小 = 被選中優先）
      keyIdxs.sort((a, b) => keyVals[a].compareTo(keyVals[b]));
      // 取前 pickCount 個
      for (var j = 0; j < pickCount; j++) {
        final n = nums[keyIdxs[j]];
        freq[n] = (freq[n] ?? 0) + 1;
      }
    }

    // 回傳依頻率降冪排列的號碼清單
    return (freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => e.key)
        .toList();
  }

  // Newton 近似平方根（用於彩票 Z-score 計算）
  static double _sqrtApprox(double x) {
    if (x <= 0) return 1.0;
    double r = x / 2;
    for (var i = 0; i < 8; i++) { r = (r + x / r) / 2; }
    return r;
  }
}
