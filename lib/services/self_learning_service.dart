import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'prediction_log_service.dart';
import '../models/prediction_log.dart';

/// 自我學習服務
///
/// 運作流程：
///   1. 啟動時在背景替「預測中」的場次向 ESPN 拉取最終賽果，自動更新結果
///   2. 對已有結果的預測紀錄，用 Perceptron 規則調整各訊號權重
///   3. 將校正後的權重存入 SharedPreferences，下次預測時自動套用
class SelfLearningService {
  static const _weightsKey  = 'sl_signal_weights_v2';
  static const _lastRunKey  = 'sl_last_calibration';
  static const _minSamples  = 5;   // 最少樣本數才觸發校正
  static const _learningRate = 0.025;
  static const _maxAge = Duration(days: 60); // 只用近 60 天的紀錄

  // 各運動預設權重（odds 主導，其餘輔助）
  static const _defaultWeights = <String, Map<String, double>>{
    'football':   {'odds': 0.40, 'momentum': 0.25, 'wins': 0.15, 'streak': 0.12, 'b2b': 0.08},
    'basketball': {'odds': 0.40, 'momentum': 0.25, 'wins': 0.15, 'streak': 0.12, 'b2b': 0.08},
    'baseball':   {'odds': 0.40, 'momentum': 0.25, 'wins': 0.15, 'streak': 0.12, 'b2b': 0.08},
  };

  // ESPN 聯賽路徑對應表
  static const _leagueToPath = <String, String>{
    'NBA': 'basketball/nba',
    'MLB': 'baseball/mlb',
    'NFL': 'football/nfl',
    '英超': 'soccer/eng.1',
    '西甲': 'soccer/esp.1',
    '德甲': 'soccer/ger.1',
    '意甲': 'soccer/ita.1',
    '法甲': 'soccer/fra.1',
    '日職': 'soccer/jpn.1',
    '澳職': 'soccer/aus.1',
    '韓職': 'soccer/kor.1',
    '歐冠': 'soccer/UEFA.CHAMPIONS',
    '歐霸': 'soccer/UEFA.EUROPA',
    '美職聯': 'soccer/usa.1',
  };

  static final _client = http.Client();

  // ── 對外 API ──────────────────────────────────────────────────────

  /// 載入校正後的權重（無紀錄時回傳預設值）
  static Future<Map<String, double>> loadWeightsFor(String sport) async {
    final all = await _loadAllWeights();
    final key = _normalizeSport(sport);
    return Map<String, double>.from(
      all[key] ?? _defaultWeights['football']!,
    );
  }

  /// 在背景執行：拉取賽果 → 校正權重（每小時最多一次）
  static Future<void> runInBackground(PredictionLogService logSvc) async {
    final prefs = await SharedPreferences.getInstance();
    final lastRaw = prefs.getString(_lastRunKey);
    if (lastRaw != null) {
      final last = DateTime.tryParse(lastRaw);
      if (last != null &&
          DateTime.now().difference(last) < const Duration(hours: 1)) {
        return;
      }
    }
    await _fetchPendingResults(logSvc);
    await _calibrateWeights(logSvc, prefs);
    await prefs.setString(_lastRunKey, DateTime.now().toIso8601String());
  }

  // ── 私有：拉取賽果 ────────────────────────────────────────────────

  static Future<void> _fetchPendingResults(PredictionLogService logSvc) async {
    final logs = await logSvc.loadByType(PredictionType.sport);
    final pending = logs
        .where((l) =>
            l.outcome == PredictionOutcome.pending &&
            DateTime.now().difference(l.createdAt) > const Duration(hours: 3))
        .toList();

    for (final log in pending) {
      final matchId = log.details['matchId'] as String?;
      final league  = log.details['league']  as String?;
      if (matchId == null || league == null) continue;

      final actual = await _fetchESPNResult(matchId, league);
      if (actual == null) continue;

      final predicted = log.details['winner'] as String?;
      if (predicted == null || predicted.isEmpty) continue;

      final correct = actual == predicted;
      log.actualResult = actual;
      log.outcome      = correct
          ? PredictionOutcome.correct
          : PredictionOutcome.incorrect;
      log.accuracyScore = correct ? 1.0 : 0.0;
      await logSvc.save(log);
    }
  }

  /// 向 ESPN 查詢已完賽事的勝負（'home'|'away'|'draw'|null）
  static Future<String?> _fetchESPNResult(
      String eventId, String league) async {
    final path = _leagueToPath[league];
    if (path == null) return null;

    try {
      final uri = Uri.parse(
        'https://site.api.espn.com/apis/site/v2/sports/$path/summary?event=$eventId',
      );
      final resp = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final data  = jsonDecode(resp.body) as Map<String, dynamic>;
      final compList = data['header']?['competitions'] as List?;
      final comps = (compList != null && compList.isNotEmpty
              ? compList.first
              : null)
          as Map<String, dynamic>?;
      if (comps == null) return null;

      final finished =
          (comps['status']?['type'] as Map<String, dynamic>?)?['completed']
              as bool? ??
          false;
      if (!finished) return null;

      double? homeScore, awayScore;
      for (final c in (comps['competitors'] as List? ?? [])) {
        final comp    = c as Map<String, dynamic>;
        final isHome  = (comp['homeAway'] as String?) == 'home';
        final score   = double.tryParse(comp['score']?.toString() ?? '');
        if (isHome) {
          homeScore = score;
        } else {
          awayScore = score;
        }
      }
      if (homeScore == null || awayScore == null) return null;
      if (homeScore > awayScore) return 'home';
      if (awayScore > homeScore) return 'away';
      return 'draw';
    } catch (_) {
      return null;
    }
  }

  // ── 私有：Perceptron 權重校正 ──────────────────────────────────────

  static Future<void> _calibrateWeights(
      PredictionLogService logSvc, SharedPreferences prefs) async {
    final logs = await logSvc.loadByType(PredictionType.sport);
    final cutoff = DateTime.now().subtract(_maxAge);
    final decided = logs
        .where((l) =>
            l.outcome != PredictionOutcome.pending &&
            l.createdAt.isAfter(cutoff) &&
            l.details.containsKey('edge'))
        .toList();

    if (decided.length < _minSamples) return;

    final weights = await _loadAllWeights();

    for (final log in decided) {
      final sport = _normalizeSport(log.details['sport'] as String? ?? '');
      final w     = weights[sport];
      if (w == null) continue;

      final correct = log.outcome == PredictionOutcome.correct;
      final reward  = correct ? 1.0 : -1.0;

      final edge   = (log.details['edge']               as num?)?.toDouble() ?? 0.0;
      final nOdds  = (log.details['normalizedOdds']     as num?)?.toDouble() ?? 0.0;
      final nMom   = (log.details['normalizedMomentum'] as num?)?.toDouble() ?? 0.0;
      final nWins  = (log.details['normalizedWins']     as num?)?.toDouble() ?? 0.0;
      final nStr   = (log.details['normalizedStreak']   as num?)?.toDouble() ?? 0.0;
      final b2b    = (log.details['b2bEdge']            as num?)?.toDouble() ?? 0.0;

      if (edge == 0) continue;
      final edgeSign = edge > 0 ? 1.0 : -1.0;

      // Perceptron 更新：訊號與 edge 同向 → 加強；反向 → 削弱
      void update(String key, double sig) {
        final aligned = (sig >= 0 ? 1.0 : -1.0) == edgeSign ? 1.0 : -1.0;
        w[key] = (w[key]! + _learningRate * reward * aligned * sig.abs())
            .clamp(0.05, 0.70);
      }

      update('odds',     nOdds);
      update('momentum', nMom);
      update('wins',     nWins);
      update('streak',   nStr);
      update('b2b',      b2b);
    }

    // 每個運動的權重正規化到加總 = 1.0
    for (final sport in weights.keys) {
      final total = weights[sport]!.values.reduce((a, b) => a + b);
      if (total > 0) {
        for (final k in weights[sport]!.keys) {
          weights[sport]![k] = weights[sport]![k]! / total;
        }
      }
    }

    await prefs.setString(_weightsKey, jsonEncode(weights));
  }

  // ── 私有：輔助工具 ─────────────────────────────────────────────────

  static Future<Map<String, Map<String, double>>> _loadAllWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_weightsKey);
    final result = <String, Map<String, double>>{
      for (final e in _defaultWeights.entries)
        e.key: Map<String, double>.from(e.value),
    };
    if (raw == null) return result;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final sport in result.keys) {
        final sm = decoded[sport] as Map<String, dynamic>?;
        if (sm == null) continue;
        for (final signal in result[sport]!.keys) {
          final v = (sm[signal] as num?)?.toDouble();
          if (v != null) result[sport]![signal] = v;
        }
      }
    } catch (_) {}
    return result;
  }

  static String _normalizeSport(String raw) {
    if (raw.contains('basketball') || raw == 'basketball') return 'basketball';
    if (raw.contains('baseball')   || raw == 'baseball')   return 'baseball';
    return 'football';
  }
}
