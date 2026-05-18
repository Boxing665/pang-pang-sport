import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prediction_log.dart';

/// 預測紀錄本地儲存服務（SharedPreferences）
///
/// 分類存放三個命名空間：
///   sport_log_ids   / sport_log_{id}    → 體育（籃球／棒球／足球）
///   lottery_log_ids / lottery_log_{id}  → 樂透（539）
///   bingo_log_ids   / bingo_log_{id}    → 賓果賓果
///
/// 舊版 pred_log_ids / pred_log_{id} 在首次載入時自動遷移至新命名空間。
class PredictionLogService {
  // ── 命名空間 ──────────────────────────────────────────────────
  static const _sportIdsKey   = 'sport_log_ids';
  static const _lotteryIdsKey = 'lottery_log_ids';
  static const _bingoIdsKey   = 'bingo_log_ids';
  static const _sportPrefix   = 'sport_log_';
  static const _lotteryPrefix = 'lottery_log_';
  static const _bingoPrefix   = 'bingo_log_';
  // 舊版（遷移用）
  static const _legacyIdsKey = 'pred_log_ids';
  static const _legacyPrefix = 'pred_log_';

  // ── 工具 ──────────────────────────────────────────────────────

  String _idsKeyFor(PredictionType t) => switch (t) {
    PredictionType.sport   => _sportIdsKey,
    PredictionType.lottery => _lotteryIdsKey,
    PredictionType.bingo   => _bingoIdsKey,
  };

  String _prefixFor(PredictionType t) => switch (t) {
    PredictionType.sport   => _sportPrefix,
    PredictionType.lottery => _lotteryPrefix,
    PredictionType.bingo   => _bingoPrefix,
  };

  List<String> _loadIds(SharedPreferences prefs, [String key = _legacyIdsKey]) =>
      prefs.getStringList(key) ?? [];

  // ── 遷移（舊版 → 新版）────────────────────────────────────────

  Future<void> _migrateIfNeeded(SharedPreferences prefs) async {
    final legacyIds = prefs.getStringList(_legacyIdsKey);
    if (legacyIds == null || legacyIds.isEmpty) return;

    final allNewEmpty =
        _loadIds(prefs, _sportIdsKey).isEmpty &&
        _loadIds(prefs, _lotteryIdsKey).isEmpty &&
        _loadIds(prefs, _bingoIdsKey).isEmpty;

    if (!allNewEmpty) {
      await prefs.remove(_legacyIdsKey);
      return;
    }

    for (final id in legacyIds) {
      final raw = prefs.getString('$_legacyPrefix$id');
      if (raw == null) continue;
      try {
        final log = PredictionLog.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
        final idsKey = _idsKeyFor(log.type);
        final prefix = _prefixFor(log.type);
        final ids = _loadIds(prefs, idsKey);
        if (!ids.contains(id)) ids.add(id);
        await prefs.setStringList(idsKey, ids);
        await prefs.setString('$prefix$id', raw);
        await prefs.remove('$_legacyPrefix$id');
      } catch (_) {}
    }
    await prefs.remove(_legacyIdsKey);
  }

  // ── 讀取 ─────────────────────────────────────────────────────

  Future<List<PredictionLog>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    final logs = <PredictionLog>[];
    for (final t in PredictionType.values) {
      final ids = _loadIds(prefs, _idsKeyFor(t));
      final prefix = _prefixFor(t);
      for (final id in ids) {
        final raw = prefs.getString('$prefix$id');
        if (raw == null) continue;
        try {
          logs.add(PredictionLog.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map)));
        } catch (_) {}
      }
    }
    logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return logs;
  }

  Future<List<PredictionLog>> loadByType(PredictionType type) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    final ids = _loadIds(prefs, _idsKeyFor(type));
    final prefix = _prefixFor(type);
    final logs = <PredictionLog>[];
    for (final id in ids) {
      final raw = prefs.getString('$prefix$id');
      if (raw == null) continue;
      try {
        logs.add(PredictionLog.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map)));
      } catch (_) {}
    }
    logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return logs;
  }

  // ── 儲存 ─────────────────────────────────────────────────────

  Future<void> save(PredictionLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final key    = _idsKeyFor(log.type);
    final prefix = _prefixFor(log.type);
    final ids = _loadIds(prefs, key);
    if (!ids.contains(log.id)) ids.add(log.id);
    await prefs.setStringList(key, ids);
    await prefs.setString('$prefix${log.id}', log.toJsonString());
  }

  /// 只在該 ID 尚未儲存時才儲存（防止重複）
  Future<void> saveIfNew(PredictionLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _prefixFor(log.type);
    // Check both new and legacy namespaces
    if (prefs.containsKey('$prefix${log.id}')) return;
    if (prefs.containsKey('$_legacyPrefix${log.id}')) return;
    await save(log);
  }

  /// 更新實際結果並重新計算準確度
  Future<void> reportResult({
    required String id,
    required String actualResult,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? raw;
    String? usedPrefix;

    for (final t in PredictionType.values) {
      final p = _prefixFor(t);
      final candidate = prefs.getString('$p$id');
      if (candidate != null) { raw = candidate; usedPrefix = p; break; }
    }
    raw      ??= prefs.getString('$_legacyPrefix$id');
    usedPrefix ??= _legacyPrefix;
    if (raw == null) return;

    final log = PredictionLog.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
    log.actualResult = actualResult;
    _evaluateOutcome(log);
    // Write to the correct (new) namespace
    await prefs.setString('${_prefixFor(log.type)}${log.id}', log.toJsonString());
    if (usedPrefix == _legacyPrefix) {
      // Ensure it's in the new index
      final key = _idsKeyFor(log.type);
      final ids = _loadIds(prefs, key);
      if (!ids.contains(log.id)) {
        ids.add(log.id);
        await prefs.setStringList(key, ids);
      }
    }
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    for (final t in PredictionType.values) {
      final key    = _idsKeyFor(t);
      final prefix = _prefixFor(t);
      final ids = _loadIds(prefs, key);
      if (ids.contains(id)) {
        ids.remove(id);
        await prefs.setStringList(key, ids);
        await prefs.remove('$prefix$id');
        return;
      }
    }
    // Legacy fallback
    final legacyIds = _loadIds(prefs, _legacyIdsKey)..remove(id);
    await prefs.setStringList(_legacyIdsKey, legacyIds);
    await prefs.remove('$_legacyPrefix$id');
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final t in PredictionType.values) {
      final key    = _idsKeyFor(t);
      final prefix = _prefixFor(t);
      for (final id in _loadIds(prefs, key)) {
        await prefs.remove('$prefix$id');
      }
      await prefs.remove(key);
    }
    // Clear legacy
    for (final id in _loadIds(prefs, _legacyIdsKey)) {
      await prefs.remove('$_legacyPrefix$id');
    }
    await prefs.remove(_legacyIdsKey);
  }

  // ── 自動回填實際結果（免手動 key）────────────────────────────

  /// 依比賽 ID 自動回填體育完賽比分。
  Future<int> autoReportSportsByMatchId(
      Map<String, (int home, int away)> scoreByMatchId) async {
    if (scoreByMatchId.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final ids = _loadIds(prefs, _sportIdsKey);
    var updated = 0;

    for (final id in ids) {
      final raw = prefs.getString('$_sportPrefix$id');
      if (raw == null) continue;
      PredictionLog log;
      try {
        log = PredictionLog.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        continue;
      }
      if (log.type != PredictionType.sport) continue;
      if ((log.actualResult ?? '').isNotEmpty) continue;

      final matchId = (log.details['matchId'] ?? '').toString();
      if (matchId.isEmpty) continue;
      final score = scoreByMatchId[matchId];
      if (score == null) continue;

      log.actualResult = '${score.$1}:${score.$2}';
      _evaluateOutcome(log);
      await prefs.setString('$_sportPrefix${log.id}', log.toJsonString());
      updated++;
    }
    return updated;
  }

  /// 依 539 開獎日期（MM/DD）自動回填樂透實際號碼。
  Future<int> autoReportLotteryByDate(Map<String, List<int>> numbersByDate) async {
    if (numbersByDate.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final ids = _loadIds(prefs, _lotteryIdsKey);
    var updated = 0;

    for (final id in ids) {
      final raw = prefs.getString('$_lotteryPrefix$id');
      if (raw == null) continue;
      PredictionLog log;
      try {
        log = PredictionLog.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) { continue; }
      if (log.type != PredictionType.lottery) continue;
      if ((log.actualResult ?? '').isNotEmpty) continue;

      final drawNoRaw = (log.details['drawNo'] ?? '').toString();
      final drawDate = _extractMonthDay(drawNoRaw);
      if (drawDate == null) continue;

      final nums = numbersByDate[drawDate];
      if (nums == null || nums.isEmpty) continue;

      log.actualResult = nums.map((n) => n.toString().padLeft(2, '0')).join(' ');
      _evaluateOutcome(log);
      await prefs.setString('$_lotteryPrefix${log.id}', log.toJsonString());
      updated++;
    }
    return updated;
  }

  /// 依賓果期數自動回填實際號碼。
  Future<int> autoReportBingoByDrawNo(Map<int, List<int>> numbersByDrawNo) async {
    if (numbersByDrawNo.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final ids = _loadIds(prefs, _bingoIdsKey);
    var updated = 0;

    for (final id in ids) {
      final raw = prefs.getString('$_bingoPrefix$id');
      if (raw == null) continue;
      PredictionLog log;
      try {
        log = PredictionLog.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) { continue; }
      if (log.type != PredictionType.bingo) continue;
      if ((log.actualResult ?? '').isNotEmpty) continue;

      final drawNo = log.details['drawNo'];
      final drawNoInt = drawNo is int ? drawNo : int.tryParse(drawNo?.toString() ?? '');
      if (drawNoInt == null) continue;

      final nums = numbersByDrawNo[drawNoInt];
      if (nums == null || nums.isEmpty) continue;

      log.actualResult = nums.map((n) => n.toString().padLeft(2, '0')).join(' ');
      _evaluateOutcome(log);
      await prefs.setString('$_bingoPrefix${log.id}', log.toJsonString());
      updated++;
    }
    return updated;
  }

  // ── 統計 ─────────────────────────────────────────────────────

  Future<AccuracyStats> getStats({PredictionType? type}) async {
    final logs = type != null ? await loadByType(type) : await loadAll();
    int correct = 0, partial = 0, incorrect = 0, pending = 0;
    double scoreSum = 0;
    int scoredCount = 0;
    for (final l in logs) {
      switch (l.outcome) {
        case PredictionOutcome.correct:
          correct++;
          break;
        case PredictionOutcome.partial:
          partial++;
          break;
        case PredictionOutcome.incorrect:
          incorrect++;
          break;
        case PredictionOutcome.pending:
          pending++;
          break;
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

  // ── 私有：結果評估 ────────────────────────────────────────────

  void _evaluateOutcome(PredictionLog log) {
    final actual = log.actualResult;
    if (actual == null || actual.isEmpty) return;

    switch (log.type) {
      case PredictionType.sport:
        _evaluateSport(log, actual);
        break;
      case PredictionType.lottery:
        _evaluateLottery(log, actual);
        break;
      case PredictionType.bingo:
        _evaluateBingo(log, actual);
        break;
    }
  }

  /// 體育：判斷勝負方向 + 比分吻合度 + MC準確度
  /// actual 可以是比分（如 "2:1"）或勝負方向（如 "home"/"away"/"draw"）
  void _evaluateSport(PredictionLog log, String actual) {
    // 解析實際結果
    final String? actualWinner;
    final (int, int)? act;
    if (actual == 'home' || actual == 'away' || actual == 'draw') {
      actualWinner = actual;
      act = null;
    } else {
      act = _parseScore(actual);
      actualWinner = act != null ? _winner(act.$1, act.$2) : null;
    }
    if (actualWinner == null) {
      log.outcome = PredictionOutcome.pending;
      return;
    }

    // 解析預測方向：比分非 0:0 時從比分推算，否則用 details['winner']
    final pred = _parseScore(log.predictedResult);
    final hasRealScore = pred != null && !(pred.$1 == 0 && pred.$2 == 0);
    final String? predictedWinner;
    if (hasRealScore) {
      predictedWinner = _winner(pred.$1, pred.$2);
    } else {
      final detailWinner = log.details['winner'] as String?;
      predictedWinner = (detailWinner != null && detailWinner.isNotEmpty)
          ? detailWinner
          : null;
    }
    if (predictedWinner == null) {
      log.outcome = PredictionOutcome.pending;
      return;
    }

    if (predictedWinner == actualWinner) {
      if (hasRealScore && act != null) {
        // 有真實比分：判斷精確度
        if (pred.$1 == act.$1 && pred.$2 == act.$2) {
          log.outcome = PredictionOutcome.correct;
          log.accuracyScore = 1.0;
        } else {
          final totalErr = (pred.$1 - act.$1).abs() + (pred.$2 - act.$2).abs();
          log.outcome = PredictionOutcome.partial;
          log.accuracyScore = (1.0 - totalErr * 0.08).clamp(0.3, 0.85);
        }
      } else {
        // 方向預測正確
        log.outcome = PredictionOutcome.correct;
        log.accuracyScore = 1.0;
      }
    } else {
      log.outcome = PredictionOutcome.incorrect;
      log.accuracyScore = 0.0;
    }

    // 比分誤差記錄（有真實比分時才計算）
    if (act != null) {
      final predRaw = _parseScore(log.predictedResultRaw ?? log.predictedResult);
      if (predRaw != null && !(predRaw.$1 == 0 && predRaw.$2 == 0)) {
        log.details['predictedHomeScoreRaw'] = predRaw.$1;
        log.details['predictedAwayScoreRaw'] = predRaw.$2;
        log.details['actualHomeScore'] = act.$1;
        log.details['actualAwayScore'] = act.$2;
        log.details['homeError'] = act.$1 - predRaw.$1;
        log.details['awayError'] = act.$2 - predRaw.$2;
      }
    }

    // MC 勝率準確度回填
    final mcHome = (log.details['mcHomeWinPct'] as num?)?.toDouble() ?? 0.0;
    final mcDraw = (log.details['mcDrawPct'] as num?)?.toDouble() ?? 0.0;
    final mcAway = (log.details['mcAwayWinPct'] as num?)?.toDouble() ?? 0.0;
    if (mcHome + mcAway > 0) {
      final String mcWinner;
      if (mcHome > mcAway && mcHome > mcDraw) {
        mcWinner = 'home';
      } else if (mcAway > mcHome && mcAway > mcDraw) {
        mcWinner = 'away';
      } else {
        mcWinner = 'draw';
      }
      log.details['mcPredictedWinner'] = mcWinner;
      log.details['mcCorrect'] = mcWinner == actualWinner;
    }
  }

  /// 樂透：比對號碼命中數
  void _evaluateLottery(PredictionLog log, String actual) {
    final predNums = _parseNumbers(log.predictedResult);
    final actNums = _parseNumbers(actual).toSet();
    if (predNums.isEmpty || actNums.isEmpty) {
      log.outcome = PredictionOutcome.pending;
      return;
    }
    final hits = predNums.where((n) => actNums.contains(n)).length;
    final rate = hits / predNums.length;
    log.accuracyScore = rate;
    if (hits >= 3) {
      log.outcome = hits == predNums.length
          ? PredictionOutcome.correct
          : PredictionOutcome.partial;
    } else {
      log.outcome = PredictionOutcome.incorrect;
    }
    // 儲存命中數到 details
    log.details['hits'] = hits;
  }

  /// 賓果：和樂透相同邏輯（6 顆 / 20 顆對）
  void _evaluateBingo(PredictionLog log, String actual) {
    _evaluateLottery(log, actual); // 共用邏輯
  }

  // ── 私有：工具 ────────────────────────────────────────────────

  String? _extractMonthDay(String s) {
    final m = RegExp(r'\b\d{2}/\d{2}\b').firstMatch(s);
    return m?.group(0);
  }

  (int, int)? _parseScore(String s) {
    final parts = s.trim().split(RegExp(r'[:：]'));
    if (parts.length < 2) return null;
    final a = int.tryParse(parts[0].trim());
    final b = int.tryParse(parts[1].trim());
    if (a == null || b == null) return null;
    return (a, b);
  }

  String _winner(int a, int b) {
    if (a > b) return 'home';
    if (b > a) return 'away';
    return 'draw';
  }

  List<int> _parseNumbers(String s) => s
      .split(RegExp(r'[,\s，]+'))
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toList();

  // ── 快速建立輔助方法 ──────────────────────────────────────────

  /// 快速建立一筆體育預測並儲存
  /// [sportType]: 'football' | 'basketball' | 'baseball'
  Future<PredictionLog> saveSportPrediction({
    required String matchId,
    required String homeTeam,
    required String awayTeam,
    required String league,
    required DateTime matchTime,
    required int predictedHome,
    required int predictedHomeRaw, // 新增：原始預測比分
    required int predictedAway,
    required int predictedAwayRaw, // 新增：原始預測比分
    required double confidence,
    String sportType = 'football',
    String winner = '',
    Map<String, double> signalDetails = const {},
    double mcHomeWinPct = 0.0,
    double mcDrawPct = 0.0,
    double mcAwayWinPct = 0.0,
    double kellyHome = 0.0,
    double kellyAway = 0.0,
  }) async {
    final log = PredictionLog(
      id: 'sport_${matchId}_$sportType',
      type: PredictionType.sport,
      createdAt: DateTime.now(),
      title: '$homeTeam vs $awayTeam',
      subtitle:
          '$league  ${matchTime.month}/${matchTime.day} ${matchTime.hour.toString().padLeft(2, '0')}:${matchTime.minute.toString().padLeft(2, '0')}',
      predictedResult: '$predictedHome:$predictedAway',
      predictedResultRaw: '$predictedHomeRaw:$predictedAwayRaw',
      details: {
        'matchId': matchId,
        'homeTeam': homeTeam,
        'awayTeam': awayTeam,
        'league': league,
        'confidence': confidence,
        'sport': sportType,
        'winner': winner,
        ...signalDetails,
        'mcHomeWinPct': mcHomeWinPct,
        'mcDrawPct': mcDrawPct,
        'mcAwayWinPct': mcAwayWinPct,
        'kellyHome': kellyHome,
        'kellyAway': kellyAway,
      },
    );
    // 若新預測有真實比分（非 0:0），但舊紀錄是 0:0，則覆蓋舊紀錄
    // 確保歷史儲存的無效 0:0 預測被修正版本取代
    final hasRealScore = predictedHome != 0 || predictedAway != 0;
    if (hasRealScore) {
      final prefs = await SharedPreferences.getInstance();
      final existingRaw = prefs.getString('$_sportPrefix${log.id}');
      if (existingRaw != null) {
        try {
          final existing = PredictionLog.fromJson(
              Map<String, dynamic>.from(jsonDecode(existingRaw) as Map));
          if (existing.predictedResult == '0:0') {
            // 覆蓋舊的 0:0 預測，但保留已填寫的 actualResult
            if ((existing.actualResult ?? '').isNotEmpty) {
              log.actualResult = existing.actualResult;
              _evaluateOutcome(log);
            }
            await prefs.setString('$_sportPrefix${log.id}', log.toJsonString());
            return log;
          }
        } catch (_) {}
      }
    }
    await saveIfNew(log);
    return log;
  }

  /// 快速建立一筆樂透預測並儲存
  /// [reasonsByNumber] 可選：每個推薦號碼的策略標籤（供失敗分析使用）
  Future<PredictionLog> saveLotteryPrediction({
    required String lotteryType,
    required String drawNo,
    required List<int> numbers,
    Map<int, String>? reasonsByNumber,
  }) async {
    final det = <String, dynamic>{
      'lotteryType': lotteryType,
      'drawNo': drawNo,
    };
    if (reasonsByNumber != null && reasonsByNumber.isNotEmpty) {
      det['reasons'] = reasonsByNumber.map(
          (k, v) => MapEntry(k.toString(), v));
    }
    final log = PredictionLog(
      id: 'lottery_${lotteryType}_$drawNo',
      type: PredictionType.lottery,
      createdAt: DateTime.now(),
      title: '$lotteryType  第 $drawNo 期',
      subtitle: '推薦號碼',
      predictedResult: numbers.map((n) => n.toString().padLeft(2, '0')).join(' '),
      details: det,
    );
    await saveIfNew(log);
    return log;
  }

  /// 快速建立一筆賓果預測並儲存
  Future<PredictionLog> saveBingoPrediction({
    required int drawNo,
    required String groupLabel,
    required List<int> numbers,
  }) async {
    final log = PredictionLog(
      id: 'bingo_${drawNo}_$groupLabel',
      type: PredictionType.bingo,
      createdAt: DateTime.now(),
      title: '賓果賓果  第 $drawNo 期',
      subtitle: groupLabel,
      predictedResult: numbers.map((n) => n.toString().padLeft(2, '0')).join(' '),
      details: {'drawNo': drawNo, 'group': groupLabel},
    );
    await saveIfNew(log);
    return log;
  }
}
