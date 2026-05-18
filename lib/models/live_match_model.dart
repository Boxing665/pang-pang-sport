import 'match_prediction.dart';

/// 實時比賽狀態模型
class LiveMatchStatus {
  const LiveMatchStatus({
    required this.matchId,
    required this.status, // scheduled, live, finished, postponed
    required this.homeScore,
    required this.awayScore,
    required this.minute,
    required this.period,
    required this.lastUpdate,
    this.events = const [],
    this.possession,
    this.homeShots,
    this.awayShots,
    this.homeCorners,
    this.awayCorners,
    this.homeCards,
    this.awayCards,
  });

  final String matchId;
  final String status; // scheduled, live, finished, postponed
  final int homeScore;
  final int awayScore;
  final int minute; // 比賽進行到第幾分鐘
  final int period; // 第幾節/第幾局
  final DateTime lastUpdate;
  final List<MatchEvent> events;
  final double? possession; // 控球率 (0.0-1.0)
  final int? homeShots;
  final int? awayShots;
  final int? homeCorners;
  final int? awayCorners;
  final Map<String, int>? homeCards; // 黃紅牌
  final Map<String, int>? awayCards;

  bool get isLive => status == 'live';
  bool get isFinished => status == 'finished';
  bool get isScheduled => status == 'scheduled';

  // 計算當前得分差
  int get scoreDifference => homeScore - awayScore;

  // 計算總進球數
  int get totalGoals => homeScore + awayScore;
}

/// 比賽事件（進球、黃牌、紅牌等）
class MatchEvent {
  const MatchEvent({
    required this.minute,
    required this.type, // goal, yellowCard, redCard, substitution, pen, missedPen
    required this.team, // home or away
    required this.playerName,
    this.assistPlayer,
    this.note,
  });

  final int minute;
  final String type; // goal, yellowCard, redCard, substitution, pen
  final String team; // home, away
  final String playerName;
  final String? assistPlayer;
  final String? note;

  String get description {
    switch (type) {
      case 'goal':
        return '⚽ $playerName 進球';
      case 'yellowCard':
        return '🟨 $playerName 黃牌';
      case 'redCard':
        return '🔴 $playerName 紅牌';
      case 'substitution':
        return '🔄 $playerName 替補出場';
      case 'penaltyGoal':
        return '⚽ $playerName 點球進球';
      default:
        return '$type - $playerName';
    }
  }
}

/// 增強的球隊信息（包含傷病和連勝連敗）
class EnhancedTeamForm {
  const EnhancedTeamForm({
    required this.teamName,
    required this.teamId,
    required this.lastFiveResults,
    required this.recentForm,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.currentStreak,
    required this.averageScored,
    required this.averageConceded,
    required this.injuries,
    required this.momentumScore,
    this.injuredPlayers = const [],
    this.yellowCards = 0,
    this.redCards = 0,
    this.homeRecord,
    this.awayRecord,
    this.headToHeadRecord,
  });

  final String teamName;
  final String teamId;
  final List<String> lastFiveResults; // ['W', 'D', 'L', ...]
  final String recentForm; // '形態說明'
  final int wins;
  final int draws;
  final int losses;
  final Map<String, dynamic> currentStreak; // {type: 'win'/'draw'/'loss', count: 3}
  final double averageScored;
  final double averageConceded;
  final int injuries;
  final double momentumScore;
  final List<InjuredPlayer> injuredPlayers;
  final int yellowCards;
  final int redCards;
  final Map<String, int>? homeRecord; // {wins, draws, losses}
  final Map<String, int>? awayRecord;
  final Map<String, int>? headToHeadRecord;

  // 計算勝率
  double get winRate {
    final total = wins + draws + losses;
    return total == 0 ? 0 : wins / total;
  }

  // 計算進攻效率
  double get attackEfficiency => averageScored / (averageScored + averageConceded + 0.1);

  // 計算防守效率
  double get defenseEfficiency =>
      averageConceded > 0 ? 1.0 / (averageConceded / 2) : 0.5;

  // 獲取連勝連敗說明
  String get streakDescription {
    final type = currentStreak['type'] as String?;
    final count = currentStreak['count'] as int? ?? 0;

    if (type == 'win') {
      return '🔥 連勝 $count 場';
    } else if (type == 'loss') {
      return '❄️ 連敗 $count 場';
    } else {
      return '平衡狀態';
    }
  }
}

/// 受傷球員信息
class InjuredPlayer {
  const InjuredPlayer({
    required this.name,
    required this.playerId,
    required this.position,
    required this.injuryType,
    required this.expectedReturn,
    this.severity, // minor, moderate, serious
  });

  final String name;
  final String playerId;
  final String position;
  final String injuryType;
  final DateTime? expectedReturn;
  final String? severity;

  bool get isLongTerm => expectedReturn != null && 
      expectedReturn!.difference(DateTime.now()).inDays > 14;

  String get daysUntilReturn {
    if (expectedReturn == null) return '未知';
    final diff = expectedReturn!.difference(DateTime.now()).inDays;
    return diff > 0 ? '還需 $diff 天' : '可能已復出';
  }
}

/// 比賽預測結果（增強版）
class LiveMatchPrediction extends MatchPrediction {
  const LiveMatchPrediction({
    required this.matchId,
    required super.predictedHomeScore,
    required super.predictedAwayScore,
    required super.confidence,
    required super.impliedHomeStrength,
    required super.impliedAwayStrength,
    required super.summary,
    required super.keyFactors,
    super.upsetAlert,
    super.injuryWarning,
    super.monteCarloHomeWinPct,
    super.monteCarloDrawPct,
    super.monteCarloAwayWinPct,
    super.kellyHome,
    super.kellyAway,
    super.mcModeHomeScore,
    super.mcModeAwayScore,
    super.ensembleHomeWinPct,
    super.ensembleDrawPct,
    super.ensembleAwayWinPct,
    super.poissonHomeWinPct,
    super.poissonDrawPct,
    super.poissonAwayWinPct,
    super.marketMovement,
    super.overround,
    this.multiBookOdds,
    this.injuryImpact,
    this.streakImpact,
    this.headToHeadAdvantage,
    this.lastUpdate,
  });

  final String matchId;
  final Map<String, dynamic>? multiBookOdds;
  final Map<String, dynamic>? injuryImpact;
  final Map<String, dynamic>? streakImpact;
  final String? headToHeadAdvantage;
  final DateTime? lastUpdate;

  // 預測結果
  String get result {
    if (predictedHomeScore > predictedAwayScore) {
      return '主勝';
    } else if (predictedHomeScore < predictedAwayScore) {
      return '客勝';
    } else {
      return '平局';
    }
  }

  // 大小分預測
  String get overUnderPrediction {
    final total = predictedHomeScore + predictedAwayScore;
    if (total > 2.5) {
      return '大分 ($total 球)';
    } else if (total < 2.5) {
      return '小分 ($total 球)';
    } else {
      return '邊界值 ($total)';
    }
  }
}

/// 比賽統計數據
class MatchStatistics {
  const MatchStatistics({
    required this.matchId,
    required this.homeTeamStats,
    required this.awayTeamStats,
  });

  final String matchId;
  final TeamStatistics homeTeamStats;
  final TeamStatistics awayTeamStats;
}

/// 球隊統計
class TeamStatistics {
  const TeamStatistics({
    required this.teamName,
    this.possession = 0.0,
    this.shots = 0,
    this.shotsOnTarget = 0,
    this.corners = 0,
    this.fouls = 0,
    this.offsides = 0,
    this.passes = 0,
    this.accuracy = 0.0,
    this.tackles = 0,
    this.interceptions = 0,
    this.clearances = 0,
    this.dribbles = 0,
  });

  final String teamName;
  final double possession;
  final int shots;
  final int shotsOnTarget;
  final int corners;
  final int fouls;
  final int offsides;
  final int passes;
  final double accuracy; // 傳球準確率
  final int tackles;
  final int interceptions;
  final int clearances;
  final int dribbles;

  double get shootingAccuracy =>
      shots == 0 ? 0 : (shotsOnTarget / shots * 100);
}
