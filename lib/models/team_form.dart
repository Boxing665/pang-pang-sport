class TeamForm {
  const TeamForm({
    required this.teamName,
    required this.lastFiveResults,
    required this.averageScored,
    required this.averageConceded,
    required this.injuries,
    required this.momentumScore,
    this.teamId = '',
    this.seasonRecord = '',
    this.playerEfficiencyRating = 15.0,
    this.hasRealStats = false,
    this.streakDisplay = '',
    this.last3AvgScored,
    this.last3AvgConceded,
    this.last10AvgScored,
    this.last10AvgConceded,
    this.isB2B = false,
    this.restDays = 2,
    this.recentScores = const [],
  });

  final String teamName;
  final String teamId;
  final List<String> lastFiveResults;
  final double averageScored;
  final double averageConceded;
  final int injuries;
  final double momentumScore;
  /// ESPN 賽季完整勝敗紀錄（如 "51-29"），直接從 ESPN scoreboard API 解析
  final String seasonRecord;
  final double playerEfficiencyRating;
  /// 是否有來自 API 的真實統計數據（非依勝率模擬）
  final bool hasRealStats;
  /// ESPN 真實連勝/連敗字串（如 "連勝3"、"連敗2"），空白時退回模擬值
  final String streakDisplay;
  /// 滾動視窗：近 3 場平均得分（null = 無資料）
  final double? last3AvgScored;
  /// 滾動視窗：近 3 場平均失分（null = 無資料）
  final double? last3AvgConceded;
  /// 滾動視窗：近 10 場平均得分（null = 無資料）
  final double? last10AvgScored;
  /// 滾動視窗：近 10 場平均失分（null = 無資料）
  final double? last10AvgConceded;
  /// 是否為背靠背賽（昨天已出賽），NBA/MLB 專用
  final bool isB2B;
  /// 距上場比賽的休息天數（0 = 同日連賽，1 = B2B，2+ = 正常休息）
  final int restDays;
  /// 近期每場比分字串（如 ["112-105 湖人", "98-110 勇士"]，最新在前）
  final List<String> recentScores;

  int get wins => lastFiveResults.where((result) => result == '勝').length;

  int get draws => lastFiveResults.where((result) => result == '平').length;

  int get losses => lastFiveResults.where((result) => result == '負').length;

  String get recentTrend => lastFiveResults.join('-');

  /// 計算目前連勝/連敗數（從最近一場往回數）
  /// 回傳 >0 = 連勝N場；<0 = 連敗N場；0 = 無明顯連勝/連敗
  int get currentStreak {
    if (lastFiveResults.isEmpty) return 0;
    final first = lastFiveResults.first;
    if (first == '平') return 0;
    int streak = 0;
    for (final r in lastFiveResults) {
      if (r == first) {
        streak++;
      } else {
        break;
      }
    }
    return first == '勝' ? streak : -streak;
  }

  /// 文字說明連勝/連敗狀態（優先使用 ESPN 真實數據）
  String get streakLabel {
    if (streakDisplay.isNotEmpty) {
      if (streakDisplay.startsWith('連勝')) {
        final n = int.tryParse(streakDisplay.replaceFirst('連勝', '')) ?? 0;
        return n >= 3 ? '🔥 $streakDisplay場' : '$streakDisplay場';
      }
      if (streakDisplay.startsWith('連敗')) {
        final n = int.tryParse(streakDisplay.replaceFirst('連敗', '')) ?? 0;
        return n >= 3 ? '❄️ $streakDisplay場' : '$streakDisplay場';
      }
      return streakDisplay;
    }
    final s = currentStreak;
    if (s >= 3) return '🔥 連勝$s場';
    if (s == 2) return '連勝2場';
    if (s <= -3) return '❄️ 連敗${s.abs()}場';
    if (s == -2) return '連敗2場';
    return '';
  }

  Map<String, dynamic> toJson() => {
    'teamName': teamName,
    'teamId': teamId,
    'lastFiveResults': lastFiveResults,
    'averageScored': averageScored,
    'averageConceded': averageConceded,
    'injuries': injuries,
    'momentumScore': momentumScore,
    'seasonRecord': seasonRecord,
    'playerEfficiencyRating': playerEfficiencyRating,
    'hasRealStats': hasRealStats,
    'streakDisplay': streakDisplay,
    if (last3AvgScored != null) 'last3AvgScored': last3AvgScored,
    if (last3AvgConceded != null) 'last3AvgConceded': last3AvgConceded,
    if (last10AvgScored != null) 'last10AvgScored': last10AvgScored,
    if (last10AvgConceded != null) 'last10AvgConceded': last10AvgConceded,
    'isB2B': isB2B,
    'restDays': restDays,
    'recentScores': recentScores,
  };

  factory TeamForm.fromJson(Map<String, dynamic> json) {
    return TeamForm(
      teamName: json['teamName'] as String? ?? '',
      teamId: json['teamId'] as String? ?? '',
      lastFiveResults: List<String>.from(json['lastFiveResults'] as List? ?? []),
      averageScored: (json['averageScored'] as num?)?.toDouble() ?? 0.0,
      averageConceded: (json['averageConceded'] as num?)?.toDouble() ?? 0.0,
      injuries: json['injuries'] as int? ?? 0,
      momentumScore: (json['momentumScore'] as num?)?.toDouble() ?? 0.0,
      seasonRecord: json['seasonRecord'] as String? ?? '',
      playerEfficiencyRating: (json['playerEfficiencyRating'] as num?)?.toDouble() ?? 15.0,
      hasRealStats: json['hasRealStats'] as bool? ?? false,
      streakDisplay: json['streakDisplay'] as String? ?? '',
      last3AvgScored: (json['last3AvgScored'] as num?)?.toDouble(),
      last3AvgConceded: (json['last3AvgConceded'] as num?)?.toDouble(),
      last10AvgScored: (json['last10AvgScored'] as num?)?.toDouble(),
      last10AvgConceded: (json['last10AvgConceded'] as num?)?.toDouble(),
      isB2B: json['isB2B'] as bool? ?? false,
      restDays: json['restDays'] as int? ?? 2,
      recentScores: List<String>.from(json['recentScores'] as List? ?? []),
    );
  }
}