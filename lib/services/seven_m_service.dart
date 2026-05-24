import 'package:http/http.dart' as http;
import '../models/match_fixture.dart';
import '../models/sport_type.dart';
import '../models/team_form.dart';
import '../models/odds_snapshot.dart';

/// 7m.hk 足球賽程服務
///
/// 資料來源：https://px-data.7mdt.com/fixture_data/big_{day}.js
/// day=1 = 今天，day=2 = 明天，...，day=7 = 7天後
///
/// 支援聯賽（League ID）：
///   英超 = 92 | 德甲 = 39 | 法甲 = 93 | 意甲 = 34 | 西甲 = 85
///   歐國盃 = 見 _euroLeagueIds
class SevenMService {
  static const _base = 'https://px-data.7mdt.com/fixture_data/big_';
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://www.7m.hk/',
  };

  // 目標聯賽名稱（直接比對 Match_name_Arr）
  static const _targetLeagueNames = {
    '英超', '德甲', '法甲', '意甲', '西甲',
    '歐冠', '歐洲聯賽', '歐協聯',
    '歐國盃', '世界盃', '世預歐洲', '世預南美', '世預亞洲', '世預北美',
  };

  // 保留 ID 對照作為後備（當 Match_name_Arr 缺項時）
  static const _fallbackLeagueIds = {
    92: '英超', 39: '德甲', 93: '法甲', 34: '意甲', 85: '西甲',
    5: '歐國盃', 6: '歐國盃', 7: '歐國盃', 8: '歐國盃', 137: '歐國盃',
    44: '歐冠', 45: '歐洲聯賽', 46: '歐協聯',
  };

  /// 抓取未來 [days] 天內指定聯賽的賽程（預設 7 天）
  Future<List<MatchFixture>> fetchSchedule({int days = 7}) async {
    final fixtures = <MatchFixture>[];
    for (var d = 1; d <= days; d++) {
      try {
        final resp = await http.get(
          Uri.parse('$_base$d.js'),
          headers: _headers,
        ).timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) continue;
        final parsed = _parseJs(resp.body);
        fixtures.addAll(parsed);
      } catch (_) {
        continue;
      }
    }
    return fixtures;
  }

  /// 只抓今天（day=1）
  Future<List<MatchFixture>> fetchToday() => fetchSchedule(days: 1);

  List<MatchFixture> _parseJs(String js) {
    List<String> strArr(String name) {
      final m = RegExp(
        r'var ' + name + r'\s*=\s*\[(.*?)\];',
        dotAll: true,
      ).firstMatch(js);
      if (m == null) return [];
      return RegExp(r"'([^']*)'").allMatches(m.group(1)!).map((e) => e.group(1)!).toList();
    }

    List<int> intArr(String name) {
      final m = RegExp(
        r'var ' + name + r'\s*=\s*\[(.*?)\];',
        dotAll: true,
      ).firstMatch(js);
      if (m == null) return [];
      return RegExp(r'(\d+)').allMatches(m.group(1)!).map((e) => int.parse(e.group(1)!)).toList();
    }

    final matchIds    = intArr('live_bh_Arr');
    final times       = strArr('Start_time_Arr');
    final leagueIds   = intArr('Match_bh_Arr');
    final leagueNames = strArr('Match_name_Arr');
    final teamsA      = strArr('Team_A_Arr');
    final teamsB      = strArr('Team_B_Arr');

    final fixtures = <MatchFixture>[];
    final n = [matchIds, times, leagueIds, teamsA, teamsB].map((l) => l.length).reduce((a, b) => a < b ? a : b);

    for (var i = 0; i < n; i++) {
      // 優先用 Match_name_Arr 直接比對聯賽名稱，後備用 ID 對照表
      final nameFromArr = i < leagueNames.length ? leagueNames[i] : '';
      final leagueName = _targetLeagueNames.contains(nameFromArr)
          ? nameFromArr
          : _fallbackLeagueIds[leagueIds[i]];
      if (leagueName == null) continue;
      final timeStr = times[i]; // '2026,05,09,19,30,0'
      final startTime = _parseTime(timeStr);
      if (startTime == null) continue;

      final homeTeam = teamsA[i];
      final awayTeam = teamsB[i];
      final mid = matchIds[i];
      fixtures.add(MatchFixture(
        id: '7m_$mid',
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        startTime: startTime,
        league: leagueName,
        sport: SportType.football,
        homeForm: _defaultForm(homeTeam),
        awayForm: _defaultForm(awayTeam),
        odds: _estimateMatchOdds(homeTeam, awayTeam),
        status: MatchStatus.scheduled,
        analystNote: '',
      ));
    }
    return fixtures;
  }

  DateTime? _parseTime(String s) {
    // '2026,05,09,19,30,0' — 7m 使用 UTC+8，轉回 UTC
    final parts = s.split(',');
    if (parts.length < 5) return null;
    try {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
        int.parse(parts[3]),
        int.parse(parts[4]),
      ).subtract(const Duration(hours: 8));
    } catch (_) {
      return null;
    }
  }

  TeamForm _defaultForm(String name) {
    final hash = name.codeUnits.fold(0, (int a, int b) => (a * 31 + b) & 0xFFFF);
    final scoreFactor = 0.75 + (hash % 10000) / 20000.0; // [0.75, 1.25]
    return TeamForm(
      teamName: name,
      lastFiveResults: const [],
      averageScored: double.parse((1.4 * scoreFactor).toStringAsFixed(2)),
      averageConceded: double.parse((1.2 / scoreFactor).toStringAsFixed(2)),
      injuries: 0,
      momentumScore: ((hash % 16) - 3).toDouble(), // [-3, 12]
      seasonRecord: '',
      hasRealStats: false,
    );
  }

  OddsSnapshot _estimateMatchOdds(String homeTeam, String awayTeam) {
    final hh = homeTeam.codeUnits.fold(0, (int a, int b) => (a * 31 + b) & 0xFFFF);
    final ah = awayTeam.codeUnits.fold(0, (int a, int b) => (a * 31 + b) & 0xFFFF);
    final homeStr = 0.75 + (hh % 10000) / 20000.0;
    final awayStr = 0.75 + (ah % 10000) / 20000.0;
    const homeAdv = 1.12;
    final totalStr = homeStr * homeAdv + awayStr;
    final homeWinProb = (homeStr * homeAdv / totalStr).clamp(0.25, 0.72);
    final awayWinProb = (awayStr / totalStr).clamp(0.20, 0.65);
    final drawProb = (1.0 - homeWinProb - awayWinProb).clamp(0.15, 0.35);
    const vig = 1.08;
    return OddsSnapshot(
      homeWin: double.parse((vig / homeWinProb).toStringAsFixed(2)),
      draw: double.parse((vig / drawProb).toStringAsFixed(2)),
      awayWin: double.parse((vig / awayWinProb).toStringAsFixed(2)),
      overLine: 0.0,
      overOdds: 1.91,
      underOdds: 1.91,
      bookmakerName: '模型推算',
      isFromBookmaker: false,
    );
  }
}
