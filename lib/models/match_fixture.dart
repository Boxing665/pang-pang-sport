import 'odds_snapshot.dart';
import 'sport_type.dart';
import 'team_form.dart';

// Match status enumeration
enum MatchStatus {
  scheduled,
  live,
  completed,
  postponed,
}

class MatchFixture {
  const MatchFixture({
    required this.id,
    required this.sport,
    required this.league,
    required this.startTime,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeForm,
    required this.awayForm,
    required this.odds,
    required this.analystNote,
    this.status = MatchStatus.scheduled,
    this.homeScore = 0,
    this.awayScore = 0,
    this.progressDetail = '',
    this.outs = 0,
    this.homeProbableK9 = '',
    this.awayProbableK9 = '',
    this.onFirst = false,
    this.onSecond = false,
    this.onThird = false,
    this.balls = 0,
    this.strikes = 0,
    this.homeProbablePitcher = '',
    this.awayProbablePitcher = '',
    this.homeProbablePitcherId = '',
    this.awayProbablePitcherId = '',
    this.homeProbableEra = '',
    this.awayProbableEra = '',
    this.homeProbableWins = '',
    this.homeProbableLosses = '',
    this.awayProbableWins = '',
    this.awayProbableLosses = '',
    this.homeProbableWhip = '',
    this.awayProbableWhip = '',
    this.currentPitcherName = '',
    this.currentPitcherPlayerId = '',
    this.currentBatterName = '',
    this.currentBatterPlayerId = '',
    this.lastPlayText = '',
    this.homeIsB2B = false,
    this.awayIsB2B = false,
    this.homeRestDays = 2,
    this.awayRestDays = 2,
    this.h2hHomeWins = 0,
    this.h2hAwayWins = 0,
    this.h2hDraws = 0,
    this.h2hAvgGoals = 0.0,
    this.espnHomePct = 0.0,
  });

  final String id;
  final SportType sport;
  final String league;
  final DateTime startTime;
  final String homeTeam;
  final String awayTeam;
  final TeamForm homeForm;
  final TeamForm awayForm;
  final OddsSnapshot odds;
  final String analystNote;
  final MatchStatus status;
  final int homeScore;
  final int awayScore;
  /// 比賽進度文字，如 "Top 6th"、"Q3 4:32"、"45'" 等
  final String progressDetail;
  /// 棒球即時壘包 & 球數（僅 live 棒球填入）
  final int outs;
  final String homeProbableK9;
  final String awayProbableK9;
  final bool onFirst;
  final bool onSecond;
  final bool onThird;
  final int balls;
  final int strikes;
  /// 棒球預定先發投手（空字串表示未知）
  final String homeProbablePitcher;
  final String awayProbablePitcher;
  final String homeProbablePitcherId;
  final String awayProbablePitcherId;
  final String homeProbableEra;
  final String awayProbableEra;
  final String homeProbableWins;
  final String homeProbableLosses;
  final String awayProbableWins;
  final String awayProbableLosses;
  /// 棒球先發投手 WHIP（每局被壘次數，越低越好）
  final String homeProbableWhip;
  final String awayProbableWhip;
  /// 棒球即時投手（場中）
  final String currentPitcherName;
  final String currentPitcherPlayerId;
  /// 棒球即時打者（ESPN situation.batter）
  final String currentBatterName;
  final String currentBatterPlayerId;
  /// 棒球即時 lastPlay 文字（用於判斷安打等事件）
  final String lastPlayText;
  /// 主隊昨天有比賽（Back-to-Back）
  final bool homeIsB2B;
  /// 客隊昨天有比賽（Back-to-Back）
  final bool awayIsB2B;
  /// 主隊距上場天數（default 2 = 正常休息）
  final int homeRestDays;
  /// 客隊距上場天數（default 2 = 正常休息）
  final int awayRestDays;
  /// H2H 對戰記錄：主隊勝場數（近 5 場）
  final int h2hHomeWins;
  /// H2H 對戰記錄：客隊勝場數（近 5 場）
  final int h2hAwayWins;
  /// H2H 對戰記錄：平局場數（近 5 場）
  final int h2hDraws;
  /// H2H 平均總進球（足球用）
  final double h2hAvgGoals;
  /// ESPN 預測主隊勝率（0.0 = 無數據）
  final double espnHomePct;

  MatchFixture copyWith({
    String? id,
    SportType? sport,
    String? league,
    DateTime? startTime,
    String? homeTeam,
    String? awayTeam,
    TeamForm? homeForm,
    TeamForm? awayForm,
    OddsSnapshot? odds,
    String? analystNote,
    MatchStatus? status,
    int? homeScore,
    int? awayScore,
    String? progressDetail,
    int? outs,
    String? homeProbableK9,
    String? awayProbableK9,
    bool? onFirst,
    bool? onSecond,
    bool? onThird,
    int? balls,
    int? strikes,
    String? homeProbablePitcher,
    String? awayProbablePitcher,
    String? homeProbablePitcherId,
    String? awayProbablePitcherId,
    String? homeProbableEra,
    String? awayProbableEra,
    String? homeProbableWins,
    String? homeProbableLosses,
    String? awayProbableWins,
    String? awayProbableLosses,
    String? homeProbableWhip,
    String? awayProbableWhip,
    String? currentPitcherName,
    String? currentPitcherPlayerId,
    String? currentBatterName,
    String? currentBatterPlayerId,
    String? lastPlayText,
    bool? homeIsB2B,
    bool? awayIsB2B,
    int? homeRestDays,
    int? awayRestDays,
    int? h2hHomeWins,
    int? h2hAwayWins,
    int? h2hDraws,
    double? h2hAvgGoals,
    double? espnHomePct,
  }) {
    return MatchFixture(
      id: id ?? this.id,
      sport: sport ?? this.sport,
      league: league ?? this.league,
      startTime: startTime ?? this.startTime,
      homeTeam: homeTeam ?? this.homeTeam,
      awayTeam: awayTeam ?? this.awayTeam,
      homeForm: homeForm ?? this.homeForm,
      awayForm: awayForm ?? this.awayForm,
      odds: odds ?? this.odds,
      analystNote: analystNote ?? this.analystNote,
      status: status ?? this.status,
      homeScore: homeScore ?? this.homeScore,
      awayScore: awayScore ?? this.awayScore,
      progressDetail: progressDetail ?? this.progressDetail,
      outs: outs ?? this.outs,
      homeProbableK9: homeProbableK9 ?? this.homeProbableK9,
      awayProbableK9: awayProbableK9 ?? this.awayProbableK9,
      onFirst: onFirst ?? this.onFirst,
      onSecond: onSecond ?? this.onSecond,
      onThird: onThird ?? this.onThird,
      balls: balls ?? this.balls,
      strikes: strikes ?? this.strikes,
      homeProbablePitcher: homeProbablePitcher ?? this.homeProbablePitcher,
      awayProbablePitcher: awayProbablePitcher ?? this.awayProbablePitcher,
      homeProbablePitcherId: homeProbablePitcherId ?? this.homeProbablePitcherId,
      awayProbablePitcherId: awayProbablePitcherId ?? this.awayProbablePitcherId,
      homeProbableEra: homeProbableEra ?? this.homeProbableEra,
      awayProbableEra: awayProbableEra ?? this.awayProbableEra,
      homeProbableWins: homeProbableWins ?? this.homeProbableWins,
      homeProbableLosses: homeProbableLosses ?? this.homeProbableLosses,
      awayProbableWins: awayProbableWins ?? this.awayProbableWins,
      awayProbableLosses: awayProbableLosses ?? this.awayProbableLosses,
      homeProbableWhip: homeProbableWhip ?? this.homeProbableWhip,
      awayProbableWhip: awayProbableWhip ?? this.awayProbableWhip,
      currentPitcherName: currentPitcherName ?? this.currentPitcherName,
      currentPitcherPlayerId: currentPitcherPlayerId ?? this.currentPitcherPlayerId,
      currentBatterName: currentBatterName ?? this.currentBatterName,
      currentBatterPlayerId: currentBatterPlayerId ?? this.currentBatterPlayerId,
      lastPlayText: lastPlayText ?? this.lastPlayText,
      homeIsB2B: homeIsB2B ?? this.homeIsB2B,
      awayIsB2B: awayIsB2B ?? this.awayIsB2B,
      homeRestDays: homeRestDays ?? this.homeRestDays,
      awayRestDays: awayRestDays ?? this.awayRestDays,
      h2hHomeWins: h2hHomeWins ?? this.h2hHomeWins,
      h2hAwayWins: h2hAwayWins ?? this.h2hAwayWins,
      h2hDraws: h2hDraws ?? this.h2hDraws,
      h2hAvgGoals: h2hAvgGoals ?? this.h2hAvgGoals,
      espnHomePct: espnHomePct ?? this.espnHomePct,
    );
  }

  // 提供基礎的 Json 轉換，確保離線備援功能不會失效
  Map<String, dynamic> toJson() => {
        'id': id,
        'sport': sport.name,
        'league': league,
        'startTime': startTime.toIso8601String(),
        'homeTeam': homeTeam,
        'awayTeam': awayTeam,
        'status': status.name,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'progressDetail': progressDetail,
        'homeForm': homeForm.toJson(),
        'awayForm': awayForm.toJson(),
        'homeProbableK9': homeProbableK9,
        'awayProbableK9': awayProbableK9,
        'odds': odds.toJson(),
        'h2hHomeWins': h2hHomeWins,
        'h2hAwayWins': h2hAwayWins,
        'h2hDraws': h2hDraws,
        'h2hAvgGoals': h2hAvgGoals,
        'espnHomePct': espnHomePct,
      };

  factory MatchFixture.fromJson(Map<String, dynamic> json) {
    return MatchFixture(
      id: json['id'] as String? ?? '',
      sport: SportType.values.byName(json['sport'] as String),
      league: json['league'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      status: MatchStatus.values.byName(json['status'] as String),
      homeScore: json['homeScore'] as int,
      awayScore: json['awayScore'] as int,
      progressDetail: json['progressDetail'] as String,
      homeProbableK9: json['homeProbableK9'] as String? ?? '',
      awayProbableK9: json['awayProbableK9'] as String? ?? '',
      // 以下為必要物件，若 Json 中無資料則使用預設值防止崩潰
      homeForm: json['homeForm'] != null ? TeamForm.fromJson(json['homeForm']) : const TeamForm(teamName: '', lastFiveResults: [], averageScored: 0, averageConceded: 0, injuries: 0, momentumScore: 0),
      awayForm: json['awayForm'] != null ? TeamForm.fromJson(json['awayForm']) : const TeamForm(teamName: '', lastFiveResults: [], averageScored: 0, averageConceded: 0, injuries: 0, momentumScore: 0),
      odds: json['odds'] != null ? OddsSnapshot.fromJson(json['odds']) : const OddsSnapshot(homeWin: 1.91, draw: 3.3, awayWin: 1.91, overLine: 2.5, overOdds: 1.91, underOdds: 1.91),
      analystNote: '快取資料',
      h2hHomeWins: json['h2hHomeWins'] as int? ?? 0,
      h2hAwayWins: json['h2hAwayWins'] as int? ?? 0,
      h2hDraws: json['h2hDraws'] as int? ?? 0,
      h2hAvgGoals: (json['h2hAvgGoals'] as num?)?.toDouble() ?? 0.0,
      espnHomePct: (json['espnHomePct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
