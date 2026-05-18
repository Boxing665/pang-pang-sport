import 'dart:convert';

/// 預測類型
enum PredictionType { sport, lottery, bingo }

/// 預測結果狀態
enum PredictionOutcome {
  pending,   // 未回報
  correct,   // 預測正確（勝負方向 / 有中獎）
  partial,   // 部分正確（比分接近 / 號碼部分命中）
  incorrect, // 預測錯誤
}

/// 一筆預測紀錄（跨體育／樂透／賓果通用）
class PredictionLog {
  PredictionLog({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.title,
    required this.subtitle,
    required this.predictedResult,
    this.predictedResultRaw,
    this.actualResult,
    this.outcome = PredictionOutcome.pending,
    this.accuracyScore,
    this.details = const {},
  });

  final String id;
  final PredictionType type;
  final DateTime createdAt;

  /// 顯示標題，例如 「西漢姆 vs 狼隊」「大樂透 第 xxx 期」「賓果 第 xxx 期」
  final String title;

  /// 副標題，例如 「英超 4/11 03:00」
  final String subtitle;

  /// 預測內容（人類可讀），例如 「1:2」「03 17 23 38 42」「06 14 ... (熱門組)」
  final String predictedResult;

  /// 原始預測比分，用於誤差修正計算
  final String? predictedResultRaw;

  /// 實際結果（使用者回報後填入）
  String? actualResult;

  /// 預測結論
  PredictionOutcome outcome;

  /// 準確度分數 0.0-1.0（體育：比分誤差；樂透：命中號碼比；賓果：命中數）
  double? accuracyScore;

  /// 額外數字資料（serialised — 儲存預測號碼列表等）
  final Map<String, dynamic> details;

  // ── 序列化 ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'createdAt': createdAt.toIso8601String(),
        'title': title,
        'subtitle': subtitle,
        'predictedResult': predictedResult,
        'predictedResultRaw': predictedResultRaw,
        'actualResult': actualResult,
        'outcome': outcome.name,
        'accuracyScore': accuracyScore,
        'details': details,
      };

  factory PredictionLog.fromJson(Map<String, dynamic> j) => PredictionLog(
        id: j['id'] as String,
        type: PredictionType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => PredictionType.sport,
        ),
        createdAt: DateTime.parse(j['createdAt'] as String),
        title: j['title'] as String,
        subtitle: j['subtitle'] as String,
        predictedResult: j['predictedResult'] as String,
        predictedResultRaw: j['predictedResultRaw'] as String?,
        actualResult: j['actualResult'] as String?,
        outcome: PredictionOutcome.values.firstWhere(
          (e) => e.name == (j['outcome'] as String? ?? 'pending'),
          orElse: () => PredictionOutcome.pending,
        ),
        accuracyScore: (j['accuracyScore'] as num?)?.toDouble(),
        details: Map<String, dynamic>.from(
            (j['details'] as Map<String, dynamic>?) ?? {}),
      );

  String toJsonString() => jsonEncode(toJson());
}

/// 整體準確率統計
class AccuracyStats {
  const AccuracyStats({
    required this.total,
    required this.correct,
    required this.partial,
    required this.incorrect,
    required this.pending,
    required this.avgScore,
  });

  final int total;
  final int correct;
  final int partial;
  final int incorrect;
  final int pending;
  final double avgScore; // 0.0-1.0

  int get judged => correct + partial + incorrect;
  double get winRate => judged > 0 ? (correct + partial * 0.5) / judged : 0;
}
