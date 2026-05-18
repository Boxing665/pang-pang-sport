import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/odds_snapshot.dart';
import '../config/app_config.dart';
import 'team_name_service.dart';

/// The-Odds-API v4 — 取得 Bet365 即時賠率
/// 註冊免費 key: https://the-odds-api.com/
/// 免費方案每月 500 次請求；每 15 分鐘批次快取以節省配額
class OddsApiService {
  static const _apiKey = AppConfig.oddsApiKey;
  static const _base = AppConfig.oddsApiBaseUrl;
  static const _bookmaker = 'bet365';
  static final _client = http.Client();

  // sport key → (快取時間, 事件列表)
  final _cache = <String, (DateTime, List<Map<String, dynamic>>)>{};
  static const _cacheDuration = Duration(minutes: 15);

  // 開盤賠率快取（session 層級，首次抓到即鎖定）
  // key = "homeTeamZh|awayTeamZh"
  final _openingCache = <String, (double, double, double)>{};

  bool get isConfigured =>
      _apiKey.isNotEmpty && _apiKey != 'YOUR_ODDS_API_KEY';

  /// 聯賽中文名 → The-Odds-API sport key
  static const leagueToSportKey = <String, String>{
    '英超': 'soccer_epl',
    '西甲': 'soccer_spain_la_liga',
    '德甲': 'soccer_germany_bundesliga',
    '意甲': 'soccer_italy_serie_a',
    '法甲': 'soccer_france_ligue_one',
    '葡超': 'soccer_portugal_primeira_liga',
    '荷甲': 'soccer_netherlands_eredivisie',
    '澳超': 'soccer_australia_aleague',
    '日職': 'soccer_japan_j_league',
    'MLS': 'soccer_usa_mls',
    '歐冠': 'soccer_uefa_champs_league',
    '歐洲聯賽': 'soccer_uefa_europa_league',
    '歐協聯': 'soccer_uefa_europa_conference_league',
    '世界盃': 'soccer_fifa_world_cup',
    '世預歐洲': 'soccer_uefa_euro_qualification',
    '世預南美': 'soccer_conmebol_world_cup_qualification',
    '世預亞洲': 'soccer_afc_asian_cup_qualification',
    'NBA': 'basketball_nba',
    '美職棒': 'baseball_mlb',
  };

  /// 批次抓取某 sport key 的所有今日賽事賠率（含 15 分鐘快取）
  Future<List<Map<String, dynamic>>> fetchSport(String sportKey) async {
    final cached = _cache[sportKey];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < _cacheDuration) {
      return cached.$2;
    }
    try {
      final uri =
          Uri.parse('$_base/sports/$sportKey/odds').replace(queryParameters: {
        'apiKey': _apiKey,
        'regions': 'eu,uk',
        'markets': 'h2h,spreads,totals',
        'bookmakers': _bookmaker,
        'oddsFormat': 'decimal',
      });
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final list = (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      _cache[sportKey] = (DateTime.now(), list);
      return list;
    } catch (_) {
      return [];
    }
  }

  /// 從已抓取的事件列表裡找出指定場次的 Bet365 賠率
  OddsSnapshot? findInEvents(
    List<Map<String, dynamic>> events,
    String homeTeamZh,
    String awayTeamZh,
  ) {
    for (final event in events) {
      final apiHomeZh =
          TeamNameService.translate(event['home_team'] as String? ?? '');
      final apiAwayZh =
          TeamNameService.translate(event['away_team'] as String? ?? '');

      // 正向 + 反向比對（部分資料源主客定義不同）
      final matched = (_nameMatch(homeTeamZh, apiHomeZh) &&
              _nameMatch(awayTeamZh, apiAwayZh)) ||
          (_nameMatch(homeTeamZh, apiAwayZh) &&
              _nameMatch(awayTeamZh, apiHomeZh));
      if (!matched) continue;

      final bookmakers = (event['bookmakers'] as List<dynamic>?) ?? [];
      Map<String, dynamic>? bet365;
      for (final b in bookmakers) {
        if (b is Map<String, dynamic> && b['key'] == _bookmaker) {
          bet365 = b;
          break;
        }
      }
      if (bet365 == null) continue;

      final markets = (bet365['markets'] as List<dynamic>?) ?? [];

      // ── h2h (獨贏賠率) ────────────────────────────────────────────
      double homeWin = 0, awayWin = 0, draw = 99.0;
      final h2h = _market(markets, 'h2h');
      if (h2h != null) {
        for (final o in (h2h['outcomes'] as List<dynamic>? ?? [])) {
          if (o is! Map<String, dynamic>) continue;
          final name = o['name'] as String? ?? '';
          final price = (o['price'] as num?)?.toDouble() ?? 0.0;
          final nameZh = TeamNameService.translate(name);
          if (_nameMatch(homeTeamZh, nameZh)) {
            homeWin = price;
          } else if (_nameMatch(awayTeamZh, nameZh)) {
            awayWin = price;
          } else if (name == 'Draw') {
            draw = price;
          }
        }
      }
      if (homeWin <= 1.0 || awayWin <= 1.0) continue;

      // ── spreads (讓分盤) ──────────────────────────────────────────
      double spread = 0.0, homeSpreadOdds = 1.91, awaySpreadOdds = 1.91;
      final spr = _market(markets, 'spreads');
      if (spr != null) {
        for (final o in (spr['outcomes'] as List<dynamic>? ?? [])) {
          if (o is! Map<String, dynamic>) continue;
          final name = o['name'] as String? ?? '';
          final price = (o['price'] as num?)?.toDouble() ?? 1.91;
          final point = (o['point'] as num?)?.toDouble() ?? 0.0;
          final nameZh = TeamNameService.translate(name);
          if (_nameMatch(homeTeamZh, nameZh)) {
            // Odds API 的 home point 負值表示主隊讓分，轉換為我們的約定：正值 = 主場讓分
            spread = -point;
            homeSpreadOdds = price;
          } else if (_nameMatch(awayTeamZh, nameZh)) {
            awaySpreadOdds = price;
          }
        }
      }

      // ── totals (大小分) ───────────────────────────────────────────
      double overLine = 0.0, overOdds = 1.91, underOdds = 1.91;
      final tot = _market(markets, 'totals');
      if (tot != null) {
        for (final o in (tot['outcomes'] as List<dynamic>? ?? [])) {
          if (o is! Map<String, dynamic>) continue;
          final name = (o['name'] as String? ?? '').toLowerCase();
          final price = (o['price'] as num?)?.toDouble() ?? 1.91;
          final point = (o['point'] as num?)?.toDouble() ?? 0.0;
          if (name == 'over') {
            overLine = point;
            overOdds = price;
          } else if (name == 'under') {
            underOdds = price;
          }
        }
      }

      // ── 開盤賠率追蹤（session 層級，首次抓到即鎖定）────────────────
      final matchKey = '$homeTeamZh|$awayTeamZh';
      final opening = _openingCache[matchKey];
      if (opening == null) {
        _openingCache[matchKey] = (homeWin, draw, awayWin);
      }
      final (openH, openD, openA) = opening ?? (homeWin, draw, awayWin);

      return OddsSnapshot(
        homeWin: homeWin,
        draw: draw,
        awayWin: awayWin,
        overLine: overLine,
        overOdds: overOdds,
        underOdds: underOdds,
        bookmakerName: 'Bet365',
        spread: spread,
        homeSpreadOdds: homeSpreadOdds,
        awaySpreadOdds: awaySpreadOdds,
        isFromBookmaker: true,
        openingHomeWin: openH,
        openingDraw: openD,
        openingAwayWin: openA,
      );
    }
    return null;
  }

  Map<String, dynamic>? _market(List<dynamic> markets, String key) {
    for (final m in markets) {
      if (m is Map<String, dynamic> && m['key'] == key) return m;
    }
    return null;
  }

  bool _nameMatch(String a, String b) {
    if (a == b) return true;
    final aL = a.toLowerCase();
    final bL = b.toLowerCase();
    if (aL.contains(bL) || bL.contains(aL)) return true;
    return false;
  }
}
