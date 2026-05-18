import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/match_fixture.dart';
import '../models/sport_type.dart';
import '../models/team_form.dart';
import '../models/odds_snapshot.dart';
import 'seven_m_service.dart';
import 'seven_m_basketball_service.dart';

/// 網路數據服務 - 使用 ESPN 免費公開 API 獲取真實賽事數據
class RealDataService {
  static const _base = 'https://site.api.espn.com/apis/site/v2/sports';

  // 共用 HTTP 客戶端（連線池化，加速後續請求）
  static final _client = http.Client();
  static const _defaultHeaders = {'Accept': 'application/json'};

  // 近況快取：teamId → 近 N 場結果（session 層級，避免重複請求）
  static final _teamFormCache = <String, List<String>>{};

  // 滾動統計快取：'rolling:sport:teamId' → rolling stats record
  static final _rollingCache = <String, dynamic>{};

  // 聯賽排行榜快取：league → (teamName → entry)，session 層級
  static final _soccerStandingsCache = <String, Map<String, LeagueStandingEntry>>{};

  // ESPN summary H2H 快取：eventId → (homeWins, awayWins, draws, avgGoals, espnHomePct)
  static final _summaryCache = <String, (int, int, int, double, double)>{};

  /// 清除所有 session 層級快取（app 回到前景時呼叫）
  static void clearSessionCaches() {
    _teamFormCache.clear();
    _rollingCache.clear();
    _soccerStandingsCache.clear();
  }

  static Future<void> _ensureStandingsLoaded(String league) async {
    if (_soccerStandingsCache.containsKey(league)) return;
    final entries = await fetchStandings(league);
    final map = <String, LeagueStandingEntry>{};
    for (final e in entries) {
      if (e.teamName.isNotEmpty) map[e.teamName] = e;
      if (e.teamNameEn.isNotEmpty) map[e.teamNameEn] = e;
    }
    _soccerStandingsCache[league] = map;
  }

  /// 將 ESPN 英文連勝/連敗標記轉為中文（"W3"→"連勝3", "L2"→"連敗2"）
  static String _translateStreak(String s) {
    if (s.isEmpty) return s;
    final upper = s.toUpperCase();
    if (upper.startsWith('W')) return '連勝${s.substring(1)}';
    if (upper.startsWith('L')) return '連敗${s.substring(1)}';
    return s;
  }

  /// 帶重試的 HTTP GET（最多 [maxRetries] 次，每次 timeout [timeout]）
  static Future<http.Response> _httpGetWithRetry(
    Uri uri, {
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: _defaultHeaders)
            .timeout(timeout);
        if (response.statusCode == 200) return response;
        // 非 200 但非暫時性錯誤 → 不重試
        if (response.statusCode >= 400 && response.statusCode < 500) {
          return response;
        }
      } catch (_) {
        if (attempt == maxRetries) rethrow;
        // 短暫等待後重試（指數退避：300ms, 900ms）
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw Exception('HTTP GET failed after ${maxRetries + 1} attempts');
  }

  // 各運動 ESPN API 端點（鍵為中文聯賽名）
  // 主要使用 ESPN API，playsport.cc 作為備用數據源
  static const _endpoints = {
    '英超': '$_base/soccer/eng.1/scoreboard',
    '西甲': '$_base/soccer/esp.1/scoreboard',
    '德甲': '$_base/soccer/ger.1/scoreboard',
    '意甲': '$_base/soccer/ita.1/scoreboard',
    '法甲': '$_base/soccer/fra.1/scoreboard',
    '日職': '$_base/soccer/jpn.1/scoreboard',
    '葡超': '$_base/soccer/por.1/scoreboard',
    '荷甲': '$_base/soccer/ned.1/scoreboard',
    '澳超': '$_base/soccer/aus.1/scoreboard',
    '歐冠': '$_base/soccer/uefa.champions/scoreboard',
    '歐洲聯賽': '$_base/soccer/uefa.europa/scoreboard',
    '歐協聯': '$_base/soccer/uefa.conference/scoreboard',
    '歐國盃': '$_base/soccer/uefa.nations/scoreboard',
    '世界盃': '$_base/soccer/fifa.world/scoreboard',
    '世預歐洲': '$_base/soccer/fifa.worldq.uefa/scoreboard',
    '世預南美': '$_base/soccer/fifa.worldq.conmebol/scoreboard',
    '世預亞洲': '$_base/soccer/fifa.worldq.afc/scoreboard',
    '世預北美': '$_base/soccer/fifa.worldq.concacaf/scoreboard',
    '世預非洲': '$_base/soccer/fifa.worldq.caf/scoreboard',
    '美職聯': '$_base/soccer/usa.1/scoreboard',
    '美職棒': '$_base/baseball/mlb/scoreboard',
    '日本職棒': '$_base/baseball/jpn/scoreboard',
    '中華職棒': '$_base/baseball/cpbl/scoreboard',
    'NBA': '$_base/basketball/nba/scoreboard',
  };

  // ── NBA 球隊中文名對照 ──────────────────────────────────────────
  static const _nbaTeams = {
    'Atlanta Hawks': '亞特蘭大老鷹',
    'Boston Celtics': '波士頓塞爾提克',
    'Brooklyn Nets': '布魯克林籃網',
    'Charlotte Hornets': '夏洛特黃蜂',
    'Chicago Bulls': '芝加哥公牛',
    'Cleveland Cavaliers': '克里夫蘭騎士',
    'Dallas Mavericks': '達拉斯獨行俠',
    'Denver Nuggets': '丹佛金塊',
    'Detroit Pistons': '底特律活塞',
    'Golden State Warriors': '金州勇士',
    'Houston Rockets': '休士頓火箭',
    'Indiana Pacers': '印第安那溜馬',
    'LA Clippers': '洛杉磯快艇',
    'Los Angeles Lakers': '洛杉磯湖人',
    'Memphis Grizzlies': '曼菲斯灰熊',
    'Miami Heat': '邁阿密熱火',
    'Milwaukee Bucks': '密爾瓦基公鹿',
    'Minnesota Timberwolves': '明尼蘇達灰狼',
    'New Orleans Pelicans': '紐奧良鵜鶘',
    'New York Knicks': '紐約尼克',
    'Oklahoma City Thunder': '奧克拉荷馬雷霆',
    'Orlando Magic': '奧蘭多魔術',
    'Philadelphia 76ers': '費城76人',
    'Phoenix Suns': '鳳凰城太陽',
    'Portland Trail Blazers': '波特蘭拓荒者',
    'Sacramento Kings': '沙加緬度國王',
    'San Antonio Spurs': '聖安東尼奧馬刺',
    'Toronto Raptors': '多倫多暴龍',
    'Utah Jazz': '猶他爵士',
    'Washington Wizards': '華盛頓巫師',
  };

  // ── MLB 球隊中文名對照 ──────────────────────────────────────────
  static const _mlbTeams = {
    'Arizona Diamondbacks': '亞利桑那響尾蛇',
    'Atlanta Braves': '亞特蘭大勇士',
    'Baltimore Orioles': '巴爾的摩金鶯',
    'Boston Red Sox': '波士頓紅襪',
    'Chicago Cubs': '芝加哥小熊',
    'Chicago White Sox': '芝加哥白襪',
    'Cincinnati Reds': '辛辛那提紅人',
    'Cleveland Guardians': '克里夫蘭守護者',
    'Colorado Rockies': '科羅拉多落磯',
    'Detroit Tigers': '底特律老虎',
    'Houston Astros': '休士頓太空人',
    'Kansas City Royals': '堪薩斯市皇家',
    'Los Angeles Angels': '洛杉磯天使',
    'Los Angeles Dodgers': '洛杉磯道奇',
    'Miami Marlins': '邁阿密馬林魚',
    'Milwaukee Brewers': '密爾瓦基釀酒人',
    'Minnesota Twins': '明尼蘇達雙城',
    'New York Mets': '紐約大都會',
    'New York Yankees': '紐約洋基',
    'Oakland Athletics': '奧克蘭運動家',
    'Philadelphia Phillies': '費城費城人',
    'Pittsburgh Pirates': '匹茲堡海盜',
    'San Diego Padres': '聖地牙哥教士',
    'San Francisco Giants': '舊金山巨人',
    'Seattle Mariners': '西雅圖水手',
    'St. Louis Cardinals': '聖路易紅雀',
    'Tampa Bay Rays': '坦帕灣光芒',
    'Texas Rangers': '德克薩斯遊騎兵',
    'Toronto Blue Jays': '多倫多藍鳥',
    'Washington Nationals': '華盛頓國民',
  };

  // ── 英超球隊中文名對照 ──────────────────────────────────────────
  static const _eplTeams = {
    'Arsenal': '阿森納',
    'Aston Villa': '阿斯頓維拉',
    'AFC Bournemouth': '伯恩茅斯',
    'Bournemouth': '伯恩茅斯',
    'Brentford': '布倫特福德',
    'Brighton & Hove Albion': '布萊頓',
    'Burnley': '伯恩利',
    'Chelsea': '切爾西',
    'Crystal Palace': '水晶宮',
    'Everton': '艾佛頓',
    'Fulham': '富勒姆',
    'Ipswich Town': '伊普斯維奇',
    'Leeds United': '里茲聯',
    'Leicester City': '萊斯特城',
    'Liverpool': '利物浦',
    'Manchester City': '曼城',
    'Manchester United': '曼聯',
    'Newcastle United': '紐卡索',
    'Nottingham Forest': '諾丁漢森林',
    'Southampton': '南安普頓',
    'Sunderland': '桑德蘭',
    'Tottenham Hotspur': '熱刺',
    'West Ham United': '西漢姆',
    'Wolverhampton Wanderers': '狼隊',
  };

  // ── 西甲球隊中文名對照 ──────────────────────────────────────────
  static const _laLigaTeams = {
    'Real Madrid': '皇家馬德里',
    'Barcelona': '巴塞隆納',
    'FC Barcelona': '巴塞隆納',
    'Atlético Madrid': '馬德里競技',
    'Atletico Madrid': '馬德里競技',
    'Sevilla': '塞維利亞',
    'Sevilla FC': '塞維利亞',
    'Real Betis': '皇家貝蒂斯',
    'Real Sociedad': '皇家社會',
    'Villarreal': '比利亞雷亞爾',
    'Villarreal CF': '比利亞雷亞爾',
    'Athletic Club': '畢爾包競技',
    'Osasuna': '奧薩蘇納',
    'Celta Vigo': '塞爾塔',
    'Getafe': '赫塔費',
    'Getafe CF': '赫塔費',
    'Rayo Vallecano': '巴列卡諾',
    'Valencia': '瓦倫西亞',
    'Valencia CF': '瓦倫西亞',
    'Espanyol': '西班牙人',
    'Las Palmas': '拉斯帕爾馬斯',
    'Mallorca': '馬略卡',
    'Girona': '赫羅納',
    'Girona FC': '赫羅納',
    'Alavés': '阿拉維斯',
    'Deportivo Alaves': '阿拉維斯',
    'Leganes': '萊加內斯',
    'Real Valladolid': '巴利亞多利德',
    'Elche': '埃爾切',
    'Levante': '萊萬特',
    'Real Oviedo': '奧維耶多',
  };

  // ── 德甲球隊中文名對照 ──────────────────────────────────────────
  static const _bundesligaTeams = {
    'Bayern Munich': '拜仁慕尼黑',
    'Borussia Dortmund': '多特蒙德',
    'Bayer Leverkusen': '勒沃庫森',
    'RB Leipzig': '萊比錫',
    'Eintracht Frankfurt': '法蘭克福',
    'SC Freiburg': '弗萊堡',
    'Werder Bremen': '不來梅',
    'VfB Stuttgart': '斯圖加特',
    '1. FC Union Berlin': '柏林聯',
    'Union Berlin': '柏林聯',
    'Borussia Mönchengladbach': '門興格拉德巴赫',
    'Borussia M\'gladbach': '門興格拉德巴赫',
    'VfL Wolfsburg': '沃爾夫斯堡',
    'TSG Hoffenheim': '霍芬海姆',
    'FC Augsburg': '奧格斯堡',
    'Mainz': '美因茨',
    'Mainz 05': '美因茨',
    '1. FC Heidenheim 1846': '海登海姆',
    'FC Heidenheim 1846': '海登海姆',
    'Holstein Kiel': '基爾',
    'St. Pauli': '聖保利',
    'FC St. Pauli': '聖保利',
    'Bochum': '波鴻',
    'FC Cologne': '科隆',
    'Hamburg SV': '漢堡',
  };

  // ── 意甲球隊中文名對照 ──────────────────────────────────────────
  static const _serieATeams = {
    'Juventus': '尤文圖斯',
    'AC Milan': 'AC米蘭',
    'Internazionale': '國際米蘭',
    'Inter Milan': '國際米蘭',
    'AS Roma': '羅馬',
    'Lazio': '拉齊奧',
    'Napoli': '那不勒斯',
    'Atalanta': '亞特蘭大',
    'Fiorentina': '佛羅倫薩',
    'Torino': '都靈',
    'Bologna': '波隆那',
    'Udinese': '烏迪內斯',
    'Sassuolo': '薩索洛',
    'Sampdoria': '桑普多利亞',
    'Genoa': '熱那亞',
    'Cagliari': '卡利亞里',
    'Hellas Verona': '維羅納',
    'Empoli': '恩波利',
    'Lecce': '萊切',
    'Venezia': '威尼斯',
    'Monza': '蒙扎',
    'Parma': '帕爾馬',
    'Como': '科莫',
    'Cremonese': '克雷莫納',
    'Pisa': '比薩',
  };

  // ── 法甲球隊中文名對照 ──────────────────────────────────────────
  static const _ligue1Teams = {
    'Paris Saint-Germain': '巴黎聖日耳曼',
    'Marseille': '馬賽',
    'Lyon': '里昂',
    'AS Monaco': '摩納哥',
    'Monaco': '摩納哥',
    'Lille': '里爾',
    'Nice': '尼斯',
    'Stade Rennais': '雷恩',
    'Rennes': '雷恩',
    'Lens': '朗斯',
    'Strasbourg': '史特拉斯堡',
    'Nantes': '南特',
    'Montpellier': '蒙彼利埃',
    'Brest': '布雷斯特',
    'Toulouse': '土魯斯',
    'Reims': '漢斯',
    'Lorient': '洛里昂',
    'Metz': '梅茲',
    'Clermont Foot': '克萊蒙',
    'Le Havre AC': '勒哈佛',
    'Le Havre': '勒哈佛',
    'Saint-Etienne': '聖埃蒂安',
    'AJ Auxerre': '歐塞爾',
    'Auxerre': '歐塞爾',
    'Angers': '昂傑',
    'Paris FC': '巴黎FC',
  };

  // ── 葡超球隊中文名對照 ──────────────────────────────────────────
  static const _primeiraLigaTeams = {
    'Sporting CP': '里斯本競技',
    'FC Porto': '波爾圖',
    'Benfica': '本菲卡',
    'SL Benfica': '本菲卡',
    'Braga': '布拉加',
    'SC Braga': '布拉加',
    'Vitória de Guimaraes': '基馬拉斯',
    'Vitória de Guimarães': '基馬拉斯',
    'Gil Vicente': '吉爾維森特',
    'Moreirense': '莫雷倫塞',
    'Casa Pia': '卡薩皮亞',
    'Estoril': '埃斯托里爾',
    'Arouca': '阿羅卡',
    'FC Famalicao': '法馬利廣',
    'Famalicão': '法馬利廣',
    'Boavista': '博阿維斯塔',
    'Rio Ave': '里奧阿維',
    'C.D. Nacional': '國民',
    'Nacional': '國民',
    'Estrela': '埃斯特雷拉',
    'Santa Clara': '聖克拉拉',
    'AVS': 'AVS',
    'Alverca': '阿爾韋卡',
    'Tondela': '通德拉',
  };

  // ── 荷甲球隊中文名對照 ──────────────────────────────────────────
  static const _eredivisieTeams = {
    'PSV Eindhoven': 'PSV埃因霍溫',
    'Ajax Amsterdam': '阿賈克斯',
    'Feyenoord': '費耶諾德',
    'AZ Alkmaar': 'AZ阿爾克馬爾',
    'FC Twente': '特溫特',
    'FC Utrecht': '烏特勒支',
    'Vitesse': '維特斯',
    'NEC Nijmegen': 'NEC奈梅亨',
    'SC Heerenveen': '海倫芬',
    'FC Groningen': '格羅寧根',
    'Go Ahead Eagles': '前進之鷹',
    'Sparta Rotterdam': '斯巴達',
    'Heracles Almelo': '赫拉克勒斯',
    'PEC Zwolle': 'PEC茲沃勒',
    'Fortuna Sittard': '福利納席塔德',
    'Almere City': '阿爾梅勒城',
    'RKC Waalwijk': 'RKC瓦爾韋克',
    'Willem II': '威廉二世',
    'NAC Breda': 'NAC布雷達',
    'Telstar': '特爾斯塔',
  };

  // ── 日職球隊中文名對照 ──────────────────────────────────────────
  static const _j1Teams = {
    'Gamba Osaka': '大阪飛腳',
    'Cerezo Osaka': '大阪櫻花',
    'Vissel Kobe': '神戶勝利船',
    'Kashima Antlers': '鹿島鹿角',
    'Urawa Red Diamonds': '浦和紅鑽',
    'FC Tokyo': '東京FC',
    'Yokohama F. Marinos': '橫濱水手',
    'Kawasaki Frontale': '川崎前鋒',
    'Nagoya Grampus': '名古屋鯨八',
    'Sanfrecce Hiroshima': '廣島三箭',
    'Consadole Sapporo': '札幌岡薩多',
    'Vegalta Sendai': '仙台維加泰',
    'Sagan Tosu': '鳥棲砂岩',
    'Shonan Bellmare': '湘南海洋',
    'Albirex Niigata': '新潟天鵝',
    'Kyoto Sanga': '京都不死鳥',
    'Avispa Fukuoka': '福岡黃蜂',
    'Jubilo Iwata': '磐田喜悅',
    'Machida Zelvia': '町田澤維亞',
    'Tokyo Verdy': '東京綠茵',
    'Tokyo Verdy 1969': '東京綠茵',
    'Fagiano Okayama': '岡山綠雉',
    'JEF United Ichihara-Chiba': 'JEF聯市原千葉',
    'Kashiwa Reysol': '柏雷素爾',
    'Mito Hollyhock': '水戶蜀葵',
    'Shimizu S-Pulse': '清水心跳',
    'V-Varen Nagasaki': 'V長崎',
  };

  // ── 澳超球隊中文名對照 ──────────────────────────────────────────
  static const _aLeagueTeams = {
    'Adelaide United': '阿德萊德聯',
    'Auckland FC': '奧克蘭FC',
    'Brisbane Roar': '布里斯班獅吼',
    'Central Coast Mariners': '中央海岸水手',
    'Macarthur FC': '麥克阿瑟FC',
    'Melbourne City FC': '墨爾本城',
    'Melbourne Victory': '墨爾本勝利',
    'Newcastle Jets': '紐卡索噴射機',
    'Perth Glory': '珀斯光榮',
    'Sydney FC': '雪梨FC',
    'Wellington Phoenix FC': '威靈頓鳳凰',
    'Western Sydney Wanderers': '西雪梨流浪者',
    'Western United FC': '西部聯',
  };

  // ── MLS 球隊中文名對照 ──────────────────────────────────────────
  static const _mlsTeams = {
    'Atlanta United FC': '亞特蘭大聯',
    'Austin FC': '奧斯丁FC',
    'CF Montréal': '蒙特婁CF',
    'CF Montreal': '蒙特婁CF',
    'Charlotte FC': '夏洛特FC',
    'Chicago Fire FC': '芝加哥火焰',
    'FC Cincinnati': '辛辛那提FC',
    'Colorado Rapids': '科羅拉多激流',
    'Columbus Crew': '哥倫布機組員',
    'D.C. United': '華盛頓聯',
    'DC United': '華盛頓聯',
    'FC Dallas': '達拉斯FC',
    'Houston Dynamo FC': '休士頓發電機',
    'Inter Miami CF': '邁阿密國際',
    'LA Galaxy': '洛杉磯銀河',
    'Los Angeles FC': '洛杉磯FC',
    'Minnesota United FC': '明尼蘇達聯',
    'Nashville SC': '納許維爾SC',
    'New England Revolution': '新英格蘭革命',
    'New York City FC': '紐約城FC',
    'New York Red Bulls': '紐約紅牛',
    'Orlando City SC': '奧蘭多城',
    'Philadelphia Union': '費城聯',
    'Portland Timbers': '波特蘭伐木者',
    'Real Salt Lake': '鹽湖城皇家',
    'San Jose Earthquakes': '聖荷西地震',
    'Seattle Sounders FC': '西雅圖探索者',
    'Sporting Kansas City': '堪薩斯城競技',
    'St. Louis City SC': '聖路易城SC',
    'Toronto FC': '多倫多FC',
    'Vancouver Whitecaps FC': '溫哥華白帽',
    'San Diego FC': '聖地牙哥FC',
    'New York Red Bulls II': '紐約紅牛II',
  };

  // ── 歐冠球隊中文名對照（跨聯賽，含常見參賽隊）───────────────────
  static const _uclTeams = {
    'Real Madrid': '皇家馬德里',
    'Barcelona': '巴塞隆納',
    'Bayern Munich': '拜仁慕尼黑',
    'Liverpool': '利物浦',
    'Manchester City': '曼城',
    'Chelsea': '切爾西',
    'Arsenal': '阿森納',
    'Paris Saint-Germain': '巴黎聖日耳曼',
    'Juventus': '尤文圖斯',
    'AC Milan': 'AC米蘭',
    'Internazionale': '國際米蘭',
    'Napoli': '那不勒斯',
    'Borussia Dortmund': '多特蒙德',
    'Bayer Leverkusen': '勒沃庫森',
    'Atlético Madrid': '馬德里競技',
    'Atletico Madrid': '馬德里競技',
    'Benfica': '本菲卡',
    'Sporting CP': '士砲丁',
    'FC Porto': '波爾圖',
    'Ajax Amsterdam': '阿賈克斯',
    'PSV Eindhoven': 'PSV埃因霍溫',
    'Feyenoord': '費耶諾德',
    'Marseille': '馬賽',
    'Lyon': '里昂',
    'AS Monaco': '摩納哥',
    'Lille': '里爾',
    'Atalanta': '亞特蘭大',
    'Lazio': '拉齊奧',
    'AS Roma': '羅馬',
    'Fiorentina': '佛羅倫薩',
    'Bologna': '波隆那',
    'Sevilla': '塞維利亞',
    'Villarreal': '比利亞雷亞爾',
    'Real Sociedad': '皇家社會',
    'Athletic Club': '畢爾包競技',
    'Eintracht Frankfurt': '法蘭克福',
    'RB Leipzig': '萊比錫',
    'VfB Stuttgart': '斯圖加特',
    'Newcastle United': '紐卡索',
    'Tottenham Hotspur': '熱刺',
    'Aston Villa': '阿斯頓維拉',
    'Brest': '布雷斯特',
    'Club Brugge': '布魯日',
    'Celtic': '凱爾特人',
    'Rangers': '流浪者',
    'Red Bull Salzburg': '薩爾茨堡紅牛',
    'Shakhtar Donetsk': '頓內次克礦工',
    'Dinamo Zagreb': '薩格勒布迪納摩',
    'Galatasaray': '加拉塔薩雷',
    'Bodo/Glimt': '博德/格林特',
    'Slavia Prague': '布拉格斯拉維亞',
    'F.C. København': '哥本哈根',
    'FK Qarabag': '卡拉巴赫',
    'Union St.-Gilloise': '聖吉爾聯合',
    'Olympiacos': '奧林匹亞科斯',
    'Pafos': '帕福斯',
    'Kairat Almaty': '阿拉木圖凱拉特',
    'Braga': '布拉加',
    'Girona': '赫羅納',
  };

  // ── 歐足總歐洲聯賽球隊中文名對照 ──────────────────────────────
  static const _uefaEuropaLeagueTeams = {
    'Manchester United': '曼聯',
    'Arsenal': '阿森納',
    'Juventus': '尤文圖斯',
    'AS Roma': '羅馬',
    'Lazio': '拉齊奧',
    'Atalanta': '亞特蘭大',
    'Napoli': '那不勒斯',
    'AC Milan': 'AC米蘭',
    'Internazionale': '國際米蘭',
    'Inter Milan': '國際米蘭',
    'Fiorentina': '佛羅倫薩',
    'Villarreal': '比利亞雷亞爾',
    'Real Sociedad': '皇家社會',
    'Athletic Club': '畢爾包競技',
    'Sevilla': '塞維利亞',
    'Barcelona': '巴塞隆納',
    'Bayern Munich': '拜仁慕尼黑',
    'Borussia Dortmund': '多特蒙德',
    'Bayer Leverkusen': '勒沃庫森',
    'Eintracht Frankfurt': '法蘭克福',
    'SC Freiburg': '弗萊堡',
    'RB Leipzig': '萊比錫',
    'Paris Saint-Germain': '巴黎聖日耳曼',
    'Lyon': '里昂',
    'Marseille': '馬賽',
    'AS Monaco': '摩納哥',
    'Lille': '里爾',
    'Lens': '朗斯',
    'Benfica': '本菲卡',
    'Sporting CP': '士砲丁',
    'FC Porto': '波爾圖',
    'Braga': '布拉加',
    'Ajax Amsterdam': '阿賈克斯',
    'PSV Eindhoven': 'PSV埃因霍溫',
    'Feyenoord': '費耶諾德',
    'AZ Alkmaar': 'AZ阿爾克馬爾',
    'FC Twente': '特溫特',
    'FC Utrecht': '烏特勒支',
    'Slavia Prague': '布拉格斯拉維亞',
    'West Ham United': '西漢姆',
    'Tottenham Hotspur': '熱刺',
    'Aston Villa': '阿斯頓維拉',
    'Newcastle United': '紐卡索',
    'Liverpool': '利物浦',
    'Chelsea': '切爾西',
    'Genoa': '熱那亞',
    'Empoli': '恩波利',
    'Bologna': '波隆那',
    'Udinese': '烏迪內斯',
    'Torino': '都靈',
    'Hellas Verona': '維羅納',
    'Union Berlin': '柏林聯',
    'Bodo/Glimt': '博德/格林特',
    'Partizan Belgrade': '貝爾格勒游擊隊',
    'Dinamo Zagreb': '薩格勒布迪納摩',
    'Legia Warsaw': '華沙萊吉亞',
    'PAOK Thessaloniki': '塞薩洛尼基帕奧克',
    'Ferencváros': '費倫茨瓦羅什',
    'FK Krasnodar': '克拉斯諾達爾',
    'Trabzonspor': '特拉布宗體育',
    'Basaksehir': '伊斯坦布爾巴沙克謝希爾',
    'Galatasaray': '加拉塔薩雷',
    'Sivasspor': '錫瓦斯體育',
    'Rapid Wien': '維也納速度',
    'Gent': '根特',
    'Molde': '莫爾德',
    'FK Qarabag': '卡拉巴赫',
    'Slovan Bratislava': '布拉迪斯拉發斯洛伐克',
    'FC Zurich': '蘇黎世FC',
    'Apollon Limassol': '利馬索爾阿波羅',
    'Hearts': '心臟',
    'Rangers': '流浪者',
    'Shamrock Rovers': '沙姆洛克流浪者',
    'Aberdeen': '阿伯丁',
    'Jagiellonia Bialystok': '比亞瓦斯托克雅吉隆尼亞',
    'Panathinaikos': '帕納吐尼克',
    'Almaty': '阿拉木圖',
  };

  // ── 歐洲協會聯賽球隊中文名對照 ────────────────────────────────
  static const _uefaConferenceLeagueTeams = {
    'AS Roma': '羅馬',
    'Tottenham Hotspur': '熱刺',
    'Fiorentina': '佛羅倫薩',
    'AZ Alkmaar': 'AZ阿爾克馬爾',
    'Slavia Prague': '布拉格斯拉維亞',
    'West Ham United': '西漢姆',
    'Genoa': '熱那亞',
    'Villarreal': '比利亞雷亞爾',
    'Rennes': '雷恩',
    'Eintracht Frankfurt': '法蘭克福',
    'Real Betis': '皇家貝蒂斯',
    'Gent': '根特',
    'Molde': '莫爾德',
    'FK Qarabag': '卡拉巴赫',
    'Slovan Bratislava': '布拉迪斯拉發斯洛伐克',
    'Union Berlin': '柏林聯',
    'Ferencváros': '費倫茨瓦羅什',
    'Hellas Verona': '維羅納',
    'Basaksehir': '伊斯坦布爾巴沙克謝希爾',
    'Sivasspor': '錫瓦斯體育',
    'Rapid Wien': '維也納速度',
    'Bodo/Glimt': '博德/格林特',
    'Partizan Belgrade': '貝爾格勒游擊隊',
    'Dinamo Zagreb': '薩格勒布迪納摩',
    'Legia Warsaw': '華沙萊吉亞',
    'PAOK Thessaloniki': '塞薩洛尼基帕奧克',
    'FC Zurich': '蘇黎世FC',
    'FK Krasnodar': '克拉斯諾達爾',
    'Trabzonspor': '特拉布宗體育',
    'Apollon Limassol': '利馬索爾阿波羅',
    'Hearts': '心臟',
    'Rangers': '流浪者',
    'Shamrock Rovers': '沙姆洛克流浪者',
    'Aberdeen': '阿伯丁',
    'Jagiellonia Bialystok': '比亞瓦斯托克雅吉隆尼亞',
    'Panathinaikos': '帕納吐尼克',
    'Almaty': '阿拉木圖',
    'Istanbul Basaksehir': '伊斯坦布爾巴沙克謝希爾',
  };

  // ── 日本職棒球隊中文名對照 ────────────────────────────────────────
  static const _npbTeams = {
    // 太平洋聯盟
    'Fukuoka SoftBank Hawks': '福岡軟銀鷹隊',
    'Saitama Seibu Lions': '埼玉西武獅隊',
    'Hokkaido Nippon Ham Fighters': '北海道日本火腿鬥士隊',
    'Orix Buffaloes': '大阪歐力士野牛隊',
    'Tohoku Rakuten Golden Eagles': '東北樂天金鷹隊',
    // 中央聯盟
    'Tokyo Yomiuri Giants': '東京讀賣巨人隊',
    'Chunichi Dragons': '中日龍隊',
    'Osaka Hanshin Tigers': '大阪阪神虎隊',
    'Tokyo Yakult Swallows': '東京養樂多燕子隊',
    'Yokohama DeNA BayStars': '橫濱DeNA灣星隊',
    'Hiroshima Carp': '廣島鯉隊',
  };

  // ── 中華職棒球隊中文名對照 ──────────────────────────────────────────
  static const _cpblTeams = {
    'Chinatrust Brothers': '中信兄弟',
    'Rakuten Monkeys': '樂天猴子',
    'Taiwan Cement Reds': '台泥紅隊',
    'CTBC Bees': 'CTBC蜜蜂隊',
    'Taichung Whales': '台中鯨隊',
    'Kaohsiung Eagles': '高雄鷹隊',
    'Taichung Baystars': '台中灣星隊',
    'Taiwan Power Company Eagles': '台灣電力鷹隊',
  };

  // ── 國家隊中文名對照（世界盃 / 世預賽）──────────────────────────
  static const _nationalTeams = {
    // 南美
    'Argentina': '阿根廷', 'Brazil': '巴西', 'Uruguay': '烏拉圭',
    'Colombia': '哥倫比亞', 'Ecuador': '厄瓜多', 'Chile': '智利',
    'Paraguay': '巴拉圭', 'Peru': '秘魯', 'Bolivia': '玻利維亞',
    'Venezuela': '委內瑞拉',
    // 歐洲
    'Italy': '義大利', 'Germany': '德國', 'France': '法國',
    'Spain': '西班牙', 'England': '英格蘭', 'Portugal': '葡萄牙',
    'Netherlands': '荷蘭', 'Belgium': '比利時', 'Croatia': '克羅埃西亞',
    'Denmark': '丹麥', 'Sweden': '瑞典', 'Poland': '波蘭',
    'Türkiye': '土耳其', 'Turkey': '土耳其',
    'Switzerland': '瑞士', 'Austria': '奧地利',
    'Czechia': '捷克', 'Czech Republic': '捷克',
    'Scotland': '蘇格蘭', 'Wales': '威爾斯',
    'Serbia': '塞爾維亞', 'Ukraine': '烏克蘭',
    'Bosnia and Herzegovina': '波士尼亞', 'Kosovo': '科索沃',
    'Norway': '挪威', 'Finland': '芬蘭', 'Iceland': '冰島',
    'Ireland': '愛爾蘭', 'Republic of Ireland': '愛爾蘭',
    'Northern Ireland': '北愛爾蘭',
    'Greece': '希臘', 'Romania': '羅馬尼亞', 'Hungary': '匈牙利',
    'Slovakia': '斯洛伐克', 'Slovenia': '斯洛維尼亞',
    'Albania': '阿爾巴尼亞', 'North Macedonia': '北馬其頓',
    'Montenegro': '蒙特內哥羅', 'Bulgaria': '保加利亞',
    'Georgia': '喬治亞', 'Luxembourg': '盧森堡',
    'Armenia': '亞美尼亞', 'Azerbaijan': '亞塞拜然',
    'Belarus': '白俄羅斯', 'Moldova': '摩爾多瓦',
    'Lithuania': '立陶宛', 'Latvia': '拉脫維亞', 'Estonia': '愛沙尼亞',
    'Cyprus': '賽普勒斯', 'Malta': '馬爾他',
    'Faroe Islands': '法羅群島', 'Gibraltar': '直布羅陀',
    'Andorra': '安道爾', 'San Marino': '聖馬利諾',
    'Liechtenstein': '列支敦士登',
    'Russia': '俄羅斯',
    // 亞洲
    'Japan': '日本', 'South Korea': '南韓', 'Korea Republic': '南韓',
    'Australia': '澳洲', 'Saudi Arabia': '沙烏地阿拉伯',
    'Iran': '伊朗', 'Iraq': '伊拉克',
    'United Arab Emirates': '阿聯酋', 'Qatar': '卡達',
    'China PR': '中國', 'China': '中國',
    'Uzbekistan': '烏茲別克', 'Bahrain': '巴林',
    'Oman': '阿曼', 'Jordan': '約旦', 'Palestine': '巴勒斯坦',
    'Syria': '敘利亞', 'Lebanon': '黎巴嫩', 'Kuwait': '科威特',
    'Thailand': '泰國', 'Vietnam': '越南', 'Indonesia': '印尼',
    'India': '印度', 'North Korea': '北韓',
    'Kyrgyzstan': '吉爾吉斯', 'Tajikistan': '塔吉克',
    // 北中美
    'Mexico': '墨西哥', 'United States': '美國', 'USA': '美國',
    'Canada': '加拿大', 'Costa Rica': '哥斯大黎加',
    'Panama': '巴拿馬', 'Jamaica': '牙買加',
    'Honduras': '宏都拉斯', 'El Salvador': '薩爾瓦多',
    'Guatemala': '瓜地馬拉', 'Trinidad and Tobago': '千里達及托巴哥',
    'Haiti': '海地', 'Curacao': '乃索', 'Curaçao': '乃索',
    'Nicaragua': '尼加拉瓜', 'Suriname': '蘇利南',
    'Bermuda': '百慕達',
    // 非洲
    'Nigeria': '奈及利亞', 'Cameroon': '喀麥隆',
    'Morocco': '摩洛哥', 'Senegal': '塞內加爾',
    'Ghana': '迦納', 'Egypt': '埃及',
    'Algeria': '阿爾及利亞', 'Tunisia': '突尼西亞',
    'Ivory Coast': '象牙海岸', "Côte d'Ivoire": '象牙海岸',
    'Congo DR': '剛果民主', 'DR Congo': '剛果民主',
    'Mali': '馬利', 'Burkina Faso': '布吉納法索',
    'South Africa': '南非', 'Tanzania': '坦尚尼亞',
    'Uganda': '烏干達', 'Guinea': '幾內亞',
    'Madagascar': '馬達加斯加', 'Zambia': '尚比亞',
    'Zimbabwe': '辛巴威', 'Kenya': '肯亞',
    'Mozambique': '莫三比克', 'Gabon': '加彭',
    'Benin': '貝南', 'Angola': '安哥拉',
    'Equatorial Guinea': '赤道幾內亞', 'Libya': '利比亞',
    'Togo': '多哥', 'Congo': '剛果',
    'Cape Verde': '維德角', 'Rwanda': '盧安達',
    // 大洋洲
    'New Zealand': '紐西蘭', 'New Caledonia': '新喀里多尼亞',
    'Fiji': '斐濟', 'Papua New Guinea': '巴布亞紐幾內亞',
    'Solomon Islands': '所羅門群島', 'Tahiti': '大溪地',
    'Vanuatu': '萬那杜', 'Samoa': '薩摩亞',
    'Tonga': '東加', 'Cook Islands': '庫克群島',
  };

  /// 翻譯球隊名稱為中文
  static String _translateTeam(String name, String league) {
    final Map<String, String> map;
    switch (league) {
      case 'NBA':
        map = _nbaTeams;
        break;
      case '美職棒':
        map = _mlbTeams;
        break;
      case '日職':
        // 日職可能是足球（J1 League）或棒球（NPB）
        // 根據上下文判斷，優先使用棒球隊名
        map = _npbTeams.containsKey(name) ? _npbTeams : _j1Teams;
        break;
      case '日本職棒':
        // 日本職棒（棒球）
        map = _npbTeams;
        break;
      case '中華職棒':
        map = _cpblTeams;
        break;
      case '英超':
        map = _eplTeams;
        break;
      case '西甲':
        map = _laLigaTeams;
        break;
      case '德甲':
        map = _bundesligaTeams;
        break;
      case '意甲':
        map = _serieATeams;
        break;
      case '法甲':
        map = _ligue1Teams;
        break;
      case '葡超':
        map = _primeiraLigaTeams;
        break;
      case '荷甲':
        map = _eredivisieTeams;
        break;
      case '澳超':
        map = _aLeagueTeams;
        break;
      case '歐冠':
        map = _uclTeams;
        break;
      case '歐洲聯賽':
        map = _uefaEuropaLeagueTeams;
        break;
      case '歐協聯':
        map = _uefaConferenceLeagueTeams;
        break;
      case '美職聯':
        map = _mlsTeams;
        break;
      case '世界盃':
      case '世預歐洲':
      case '世預南美':
      case '世預亞洲':
      case '世預北美':
      case '世預非洲':
        map = _nationalTeams;
        break;
      default:
        return name;
    }
    return map[name] ?? name;
  }

  /// 用 slug（如 "por.1"）翻譯球隊名
  static String _translateTeamBySlug(String name, String slug) {
    const slugToLeague = {
      'eng.1': '英超', 'esp.1': '西甲', 'ger.1': '德甲',
      'ita.1': '意甲', 'fra.1': '法甲', 'jpn.1': '日職 J1',
      'por.1': '葡超', 'ned.1': '荷甲', 'aus.1': '澳超',
      'uefa.champions': '歐冠',
      'fifa.world': '世界盃',
      'fifa.worldq.uefa': '世預歐洲',
      'fifa.worldq.conmebol': '世預南美',
      'fifa.worldq.afc': '世預亞洲',
      'fifa.worldq.concacaf': '世預北美',
      'fifa.worldq.caf': '世預非洲',
      'usa.1': '美職聯',
    };
    final league = slugToLeague[slug];
    if (league == null) return name;
    return _translateTeam(name, league);
  }

  // ── 聯賽排行榜 slug 對照 ──────────────────────────────────────
  static const _standingsSlugs = {
    '英超': 'soccer/eng.1',
    '西甲': 'soccer/esp.1',
    '德甲': 'soccer/ger.1',
    '意甲': 'soccer/ita.1',
    '法甲': 'soccer/fra.1',
    '日職': 'soccer/jpn.1',
    '日本職棒': 'baseball/jpn',
    '葡超': 'soccer/por.1',
    '荷甲': 'soccer/ned.1',
    '澳超': 'soccer/aus.1',
    '歐冠': 'soccer/uefa.champions',
    '歐洲聯賽': 'soccer/uefa.europa',
    '歐協聯': 'soccer/uefa.conference',
    '世界盃': 'soccer/fifa.world',
    '世預歐洲': 'soccer/fifa.worldq.uefa',
    '世預南美': 'soccer/fifa.worldq.conmebol',
    '世預亞洲': 'soccer/fifa.worldq.afc',
    '世預北美': 'soccer/fifa.worldq.concacaf',
    '世預非洲': 'soccer/fifa.worldq.caf',
    '美職聯': 'soccer/usa.1',
    '美職棒': 'baseball/mlb',
    '中華職棒': 'baseball/cpbl',
    'NBA': 'basketball/nba',
  };

  /// 抓取聯賽排行榜
  static Future<List<LeagueStandingEntry>> fetchStandings(String league) async {
    final slug = _standingsSlugs[league];
    if (slug == null) return const [];
    try {
      final url = 'https://site.api.espn.com/apis/v2/sports/$slug/standings';
      final resp = await _httpGetWithRetry(Uri.parse(url));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final children = (data['children'] as List<dynamic>?) ?? const [];
      final results = <LeagueStandingEntry>[];
      for (final child in children) {
        if (child is! Map<String, dynamic>) continue;
        final groupName = child['name'] as String? ?? '';
        final entries = (child['standings'] as Map<String, dynamic>?)?['entries'] as List<dynamic>? ?? const [];
        for (final e in entries) {
          if (e is! Map<String, dynamic>) continue;
          final team = e['team'] as Map<String, dynamic>? ?? {};
          final teamName = team['displayName'] as String? ?? '';
          final teamAbbr = team['abbreviation'] as String? ?? '';
          final statsRaw = (e['stats'] as List<dynamic>?) ?? const [];
          final stats = <String, String>{};
          for (final s in statsRaw) {
            if (s is! Map<String, dynamic>) continue;
            final abbr = s['abbreviation'] as String? ?? '';
            final val = s['displayValue'] as String? ?? '';
            if (abbr.isNotEmpty) stats[abbr] = val;
          }
          results.add(LeagueStandingEntry(
            teamName: _translateTeam(teamName, league),
            teamNameEn: teamName,
            teamAbbr: teamAbbr,
            group: groupName,
            rank: int.tryParse(stats['R'] ?? '') ?? results.length + 1,
            gamesPlayed: int.tryParse(stats['GP'] ?? '') ?? 0,
            wins: int.tryParse(stats['W'] ?? '') ?? 0,
            draws: int.tryParse(stats['D'] ?? '') ?? 0,
            losses: int.tryParse(stats['L'] ?? '') ?? 0,
            points: int.tryParse(stats['P'] ?? stats['PTS'] ?? '') ?? 0,
            goalsFor: int.tryParse(stats['F'] ?? '') ?? 0,
            goalsAgainst: int.tryParse(stats['A'] ?? '') ?? 0,
            goalDifference: stats['GD'] ?? '',
            winPct: stats['PCT'] ?? '',
          ));
        }
      }
      return results;
    } catch (e) {
      return const [];
    }
  }

  /// 計算台灣時間日期字串列表（今天起共 days 天）
  static List<String> _taiwanDateStrings(int days) {
    // 台灣時間 = UTC+8
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return List.generate(days, (i) {
      final d = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    });
  }

  static String _taiwanYesterdayString() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    return '${yesterday.year}${yesterday.month.toString().padLeft(2, '0')}${yesterday.day.toString().padLeft(2, '0')}';
  }

  // 棒球和籃球用美國東岸時區日期
  // 夏令時間 EDT = UTC-4（三月第二個週日 ~ 十一月第一個週日）
  // 冬令時間 EST = UTC-5（其餘月份）
  static int _usEasternOffsetHours() {
    final utcNow = DateTime.now().toUtc();
    final year = utcNow.year;
    // 三月第二個週日：找到三月第一個週日後加7天
    final marchFirst = DateTime.utc(year, 3, 1);
    final marchFirstSunday = DateTime.utc(year, 3, 1 + (7 - marchFirst.weekday) % 7);
    final dstStart = marchFirstSunday.add(const Duration(days: 7, hours: 2)); // 02:00 UTC
    // 十一月第一個週日
    final novFirst = DateTime.utc(year, 11, 1);
    final novFirstSunday = DateTime.utc(year, 11, 1 + (7 - novFirst.weekday) % 7);
    final dstEnd = novFirstSunday.add(const Duration(hours: 2)); // 02:00 UTC
    return utcNow.isAfter(dstStart) && utcNow.isBefore(dstEnd) ? 4 : 5;
  }

  static List<String> _usDateStrings(int days) {
    final offset = _usEasternOffsetHours();
    final now = DateTime.now().toUtc().subtract(Duration(hours: offset));
    return List.generate(days, (i) {
      final d = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    });
  }

  /// 從 ESPN API 抓取比賽（棒球/籃球抓今日美國賽程，足球抓今日）
  static Future<List<MatchFixture>> fetchTodaysMatches() async {
    return fetchMatchesForDays(days: 1);
  }

  /// 從 ESPN API 抓取未來 [days] 天的比賽（包含今日）
  static Future<List<MatchFixture>> fetchMatchesForDays({int days = 5}) async {

    // 足球用台灣時區日期；MLB/NBA 用美國時區日期，避免跨夜時區差
    final twDates = _taiwanDateStrings(days);
    final usDates = _usDateStrings(days);

    // 足球昨天的日期：台灣 UTC+8，歐洲晚場比賽約 UTC 19-21點
    // 對應台灣凌晨 3-5點，此時 ESPN 記錄的是前一天 UTC 日期，所以要補查昨天
    final twYesterday = _taiwanYesterdayString();

    // 美職聯 (MLS) 比賽在美東時間進行，須使用美東日期避免跨夜抓到空資料
    const usLeagues = {'NBA', '美職棒', '美職聯'};
    const soccerLeagues = {'英超', '西甲', '德甲', '意甲', '法甲', '日職', '葡超', '荷甲', '澳超', '歐冠', '歐洲聯賽', '歐協聯', '歐國盃', '世界盃', '世預歐洲', '世預南美', '世預亞洲', '世預北美', '世預非洲'};

    // 預先載入足球各聯賽排行榜（取得真實場均進失球數）
    await Future.wait(
      soccerLeagues.map(_ensureStandingsLoaded),
      eagerError: false,
    );

    final futures = <Future<List<MatchFixture>>>[];

    // 補查足球昨天（捕捉歐洲晚場進行中或剛結束的比賽）
    for (final entry in _endpoints.entries) {
      if (soccerLeagues.contains(entry.key)) {
        final url = '${entry.value}?dates=$twYesterday';
        futures.add(
          _fetchLeague(entry.key, url).catchError((_) => <MatchFixture>[]),
        );
      }
    }

    for (var i = 0; i < days; i++) {
      for (final entry in _endpoints.entries) {
        final dateStr = usLeagues.contains(entry.key) ? usDates[i] : twDates[i];
        final url = '${entry.value}?dates=$dateStr';
        futures.add(
          _fetchLeague(entry.key, url).catchError((_) => <MatchFixture>[]),
        );
      }
    }

    final results = await Future.wait(futures);
    final seen = <String>{};
    final allMatches = <MatchFixture>[];
    for (final batch in results) {
      for (final m in batch) {
        if (seen.add(m.id)) allMatches.add(m);
      }
    }

    // 補充 7m.hk 足球賽程（ESPN 未涵蓋的未來場次）
    try {
      final sevenMMatches = await SevenMService().fetchSchedule(days: days);
      for (final m in sevenMMatches) {
        if (seen.add(m.id)) allMatches.add(m);
      }
    } catch (_) {}

    // 用 7m.hk NBA 勝率強化籃球預測精準度
    try {
      final nbaRates = await SevenMBasketballService().fetchNBAWinRates();
      if (nbaRates.isNotEmpty) {
        for (var i = 0; i < allMatches.length; i++) {
          final m = allMatches[i];
          if (m.league != 'NBA') continue;
          final homeRate = nbaRates[m.homeTeam];
          final awayRate = nbaRates[m.awayTeam];
          if (homeRate == null && awayRate == null) continue;
          allMatches[i] = m.copyWith(
            homeForm: _applyWinRate(m.homeForm, homeRate),
            awayForm: _applyWinRate(m.awayForm, awayRate),
          );
        }
      }
    } catch (_) {}

    return allMatches;
  }

  /// 抓取過去 [daysBack] 天的已完賽比賽（供圖表分析比對用）
  static Future<List<MatchFixture>> fetchPastMatchesForDays({int daysBack = 5}) async {
    final twPast = _taiwanPastDateStrings(daysBack);
    final usPast = _usPastDateStrings(daysBack);

    const usLeagues = {'NBA', '美職棒', '美職聯'};

    final futures = <Future<List<MatchFixture>>>[];
    for (var i = 0; i < daysBack; i++) {
      for (final entry in _endpoints.entries) {
        final dateStr = usLeagues.contains(entry.key) ? usPast[i] : twPast[i];
        final url = '${entry.value}?dates=$dateStr';
        futures.add(_fetchLeague(entry.key, url).catchError((_) => <MatchFixture>[]));
      }
    }

    final results = await Future.wait(futures);
    final seen = <String>{};
    final allMatches = <MatchFixture>[];
    for (final batch in results) {
      for (final m in batch) {
        if (m.status == MatchStatus.completed && seen.add(m.id)) {
          allMatches.add(m);
        }
      }
    }
    return allMatches;
  }

  /// 台灣時間過去 N 天的日期字串（從昨天起往前）
  static List<String> _taiwanPastDateStrings(int days) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return List.generate(days, (i) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i + 1));
      return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    });
  }

  /// 美東時間過去 N 天的日期字串（從昨天起往前）
  static List<String> _usPastDateStrings(int days) {
    final offset = _usEasternOffsetHours();
    final now = DateTime.now().toUtc().subtract(Duration(hours: offset));
    return List.generate(days, (i) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i + 1));
      return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    });
  }

  /// 將 7m 勝率注入 TeamForm.momentumScore，其餘欄位保持不變
  static TeamForm _applyWinRate(TeamForm form, double? winRate) {
    if (winRate == null) return form;
    return TeamForm(
      teamName: form.teamName,
      lastFiveResults: form.lastFiveResults,
      averageScored: form.averageScored,
      averageConceded: form.averageConceded,
      injuries: form.injuries,
      momentumScore: winRate * 100,
      seasonRecord: form.seasonRecord,
      playerEfficiencyRating: form.playerEfficiencyRating,
      hasRealStats: true,
      streakDisplay: form.streakDisplay,
      last3AvgScored: form.last3AvgScored,
      last3AvgConceded: form.last3AvgConceded,
      last10AvgScored: form.last10AvgScored,
      last10AvgConceded: form.last10AvgConceded,
    );
  }

  static Future<List<MatchFixture>> _fetchLeague(
    String leagueName,
    String url,
  ) async {
    final response = await _httpGetWithRetry(Uri.parse(url));

    if (response.statusCode != 200) {
      return [];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final events = (data['events'] as List<dynamic>?) ?? [];

    // 並行解析所有賽事（每場含 pickcenter 非同步請求）
    final results = await Future.wait(
      events.map((e) =>
          _parseEvent(e as Map<String, dynamic>, leagueName)
              .catchError((_) => null as MatchFixture?)),
    );
    final matches = results.whereType<MatchFixture>().toList();

    return matches;
  }

  static Future<MatchFixture?> _parseEvent(
    Map<String, dynamic> event,
    String leagueName,
  ) async {
    try {
      final competitions = (event['competitions'] as List<dynamic>?) ?? [];
      if (competitions.isEmpty) return null;

      final competition = competitions.first as Map<String, dynamic>;
      final competitors = (competition['competitors'] as List<dynamic>?) ?? [];
      if (competitors.length < 2) return null;

      String homeTeam = '';
      String awayTeam = '';
      int homeScore = 0;
      int awayScore = 0;
      Map<String, dynamic> homeComp = {};
      Map<String, dynamic> awayComp = {};

      for (final c in competitors) {
        final comp = c as Map<String, dynamic>;
        final teamName =
            (comp['team'] as Map<String, dynamic>?)?['displayName'] as String? ?? '';
        final scoreStr = comp['score'] as String? ?? '0';
        final score = int.tryParse(scoreStr) ?? 0;

        if (comp['homeAway'] == 'home') {
          homeTeam = teamName;
          homeScore = score;
          homeComp = comp;
        } else {
          awayTeam = teamName;
          awayScore = score;
          awayComp = comp;
        }
      }

      if (homeTeam.isEmpty || awayTeam.isEmpty) return null;

      // 過濾掉季後賽尚未確定對手的場次（ESPN 用 "TBD" 佔位）
      if (homeTeam.toUpperCase() == 'TBD' || awayTeam.toUpperCase() == 'TBD') return null;

      // 翻譯球隊名稱為中文
      homeTeam = _translateTeam(homeTeam, leagueName);
      awayTeam = _translateTeam(awayTeam, leagueName);

      final dateStr = event['date'] as String? ?? '';
      final startTime = dateStr.isNotEmpty
          ? _toTaiwanTime(DateTime.tryParse(dateStr)) ?? DateTime.now()
          : DateTime.now();

      // 解析比賽狀態
      final statusMap = (event['status'] as Map<String, dynamic>?);
      final statusTypeMap = statusMap?['type'] as Map<String, dynamic>?;
      final statusType = statusTypeMap?['name'] as String? ?? '';
      final statusState = statusTypeMap?['state'] as String? ?? ''; // 'in' | 'pre' | 'post'
      final progressDetail = statusTypeMap?['shortDetail'] as String? ?? '';
      final matchStatus = _parseStatus(statusType, statusState);

      final sport = _sportFromLeague(leagueName);

      // 棒球即時壘包 & 球數
      final situation =
          (competition['situation'] as Map<String, dynamic>?) ?? {};
      final isLiveBall = matchStatus == MatchStatus.live &&
          sport == SportType.baseball;
      final outs = (situation['outs'] as int?) ?? 0;
      final onFirst = (situation['onFirst'] as bool?) ?? false;
      final onSecond = (situation['onSecond'] as bool?) ?? false;
      final onThird = (situation['onThird'] as bool?) ?? false;
      final balls = (situation['balls'] as int?) ?? 0;
      final strikes = (situation['strikes'] as int?) ?? 0;
      final formResults = await Future.wait([
        _parseTeamForm(homeComp, homeTeam, sport, leagueName),
        _parseTeamForm(awayComp, awayTeam, sport, leagueName),
      ]);
      final homeForm = formResults[0];
      final awayForm = formResults[1];

      // B2B / 休息天數（僅 NBA / MLB）
      bool homeIsB2B = false;
      bool awayIsB2B = false;
      int homeRestDays = 2;
      int awayRestDays = 2;
      if (sport == SportType.basketball || sport == SportType.baseball) {
        final homeTeamId = (homeComp['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
        final awayTeamId = (awayComp['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
        final rollingResults = await Future.wait([
          if (homeTeamId.isNotEmpty) _fetchTeamRollingStats(homeTeamId, sport) else Future.value(null),
          if (awayTeamId.isNotEmpty) _fetchTeamRollingStats(awayTeamId, sport) else Future.value(null),
        ]);
        final homeRolling = rollingResults[0];
        final awayRolling = rollingResults[1];
        if (homeRolling != null) {
          homeIsB2B = homeRolling.isB2B;
          homeRestDays = homeRolling.restDays;
        }
        if (awayRolling != null) {
          awayIsB2B = awayRolling.isB2B;
          awayRestDays = awayRolling.restDays;
        }
      }

      // 棒球先發投手（probables）
      String homeProbablePitcher = '';
      String awayProbablePitcher = '';
      String homeProbablePitcherId = '';
      String awayProbablePitcherId = '';
      String homeProbableEra = '';
      String homeProbableK9 = '';
      String homeProbableWhip = '';
      String awayProbableK9 = '';
      String awayProbableWhip = '';
      String awayProbableEra = '';
      String homeProbableWins = '';
      String awayProbableWins = '';
      String homeProbableLosses = '';
      String awayProbableLosses = '';
      if (sport == SportType.baseball) {
        for (final c in competitors) {
          final comp = c as Map<String, dynamic>;
          final probablesList = (comp['probables'] as List<dynamic>?) ?? [];
          String pitcherName = '';
          String pitcherId = '';
          String pitcherEra = '';
          String pitcherK9 = '';
          String pitcherWhip = '';
          String pitcherWins = '';
          String pitcherLosses = '';
          if (probablesList.isNotEmpty) {
            final probable = probablesList.first as Map<String, dynamic>;
            final athleteMap = probable['athlete'] as Map<String, dynamic>?;
            pitcherName = (athleteMap?['shortName'] as String?) ?? '';
            pitcherId = (athleteMap?['id'] as String?) ?? '';
            final statsObj = probable['statistics'];
            final statsMap = statsObj is Map<String, dynamic> ? statsObj : null;
            final splitsObj = statsMap?['splits'];
            final splitsMap = splitsObj is Map<String, dynamic> ? splitsObj : null;
            final categoriesObj = splitsMap?['categories'];
            final categories = categoriesObj is List<dynamic> ? categoriesObj : const [];
            for (final cat in categories) {
              if (cat is! Map<String, dynamic>) continue;
              // ESPN 兩種格式：flat（category 本身是 stat）或 nested（category.stats[]）
              void apply(String abbr, String val) {
                if (abbr == 'ERA')  pitcherEra = val;
                if (abbr == 'WHIP') pitcherWhip = val;
                if (abbr == 'K/9' || abbr == 'SO9')  pitcherK9 = val;
                if (abbr == 'W')    pitcherWins = val;
                if (abbr == 'L')    pitcherLosses = val;
              }
              // Flat format: category itself is a stat
              final flatAbbr = cat['abbreviation'] as String? ?? '';
              final flatVal = cat['displayValue'] as String? ?? '';
              if (flatAbbr.isNotEmpty && flatVal.isNotEmpty) apply(flatAbbr, flatVal);
              // Nested format: category.stats[]
              for (final s in (cat['stats'] as List<dynamic>?) ?? const []) {
                if (s is! Map<String, dynamic>) continue;
                final abbr = s['abbreviation'] as String? ?? s['name'] as String? ?? '';
                final val = s['displayValue'] as String?
                    ?? (s['value'] as num?)?.toStringAsFixed(2)
                    ?? '';
                if (abbr.isNotEmpty && val.isNotEmpty) apply(abbr, val);
              }
            }
          }
          if (comp['homeAway'] == 'home') {
            homeProbablePitcher = pitcherName;
            homeProbablePitcherId = pitcherId;
            homeProbableEra = pitcherEra;
            homeProbableK9 = pitcherK9;
            homeProbableWhip = pitcherWhip;
            homeProbableWins = pitcherWins;
            homeProbableLosses = pitcherLosses;
          } else {
            awayProbablePitcher = pitcherName;
            awayProbablePitcherId = pitcherId;
            awayProbableEra = pitcherEra;
            awayProbableK9 = pitcherK9;
            awayProbableWhip = pitcherWhip;
            awayProbableWins = pitcherWins;
            awayProbableLosses = pitcherLosses;
          }
        }
      }

      final odds = _parseOdds(competition, homeForm, awayForm, sport);

      // 抓取 H2H 與 ESPN 預測數據
      final espnEventId = event['id'] as String? ?? '';
      int h2hHomeWins = 0;
      int h2hAwayWins = 0;
      int h2hDraws = 0;
      double h2hAvgGoals = 0.0;
      double espnHomePct = 0.0;
      if (espnEventId.isNotEmpty) {
        final soccerSlug = _soccerSlugFromLeague(leagueName);
        final summarySlug = sport == SportType.football && soccerSlug != null
            ? soccerSlug
            : '';
        final h2hResult = await _fetchEventSummary(espnEventId, sport, summarySlug);
        h2hHomeWins = h2hResult.$1;
        h2hAwayWins = h2hResult.$2;
        h2hDraws = h2hResult.$3;
        h2hAvgGoals = h2hResult.$4;
        espnHomePct = h2hResult.$5;
      }

      return MatchFixture(
        id: 'espn_${event['id']}',
        sport: sport,
        league: leagueName,
        startTime: startTime,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        homeScore: homeScore,
        awayScore: awayScore,
        status: matchStatus,
        progressDetail: matchStatus == MatchStatus.live ? progressDetail : '',
        outs: isLiveBall ? outs : 0,
        onFirst: isLiveBall ? onFirst : false,
        onSecond: isLiveBall ? onSecond : false,
        onThird: isLiveBall ? onThird : false,
        balls: isLiveBall ? balls : 0,
        strikes: isLiveBall ? strikes : 0,
        homeProbablePitcher: homeProbablePitcher,
        awayProbablePitcher: awayProbablePitcher,
        homeProbablePitcherId: homeProbablePitcherId,
        awayProbablePitcherId: awayProbablePitcherId,
        homeProbableEra: homeProbableEra,
        homeProbableK9: homeProbableK9,
        homeProbableWhip: homeProbableWhip,
        awayProbableEra: awayProbableEra,
        awayProbableK9: awayProbableK9,
        awayProbableWhip: awayProbableWhip,
        homeProbableWins: homeProbableWins,
        homeProbableLosses: homeProbableLosses,
        awayProbableWins: awayProbableWins,
        awayProbableLosses: awayProbableLosses,
        currentPitcherName: isLiveBall
            ? (() {
              // 假設 ESPN summary 裡有 K/9
                final pitcher = situation['pitcher'] as Map<String, dynamic>?;
                final ath = pitcher?['athlete'] as Map<String, dynamic>?;
                return ath?['shortName'] as String? ?? '';
              })()
            : '',
        currentPitcherPlayerId: isLiveBall
            ? (() {
                final pitcher = situation['pitcher'] as Map<String, dynamic>?;
                final ath = pitcher?['athlete'] as Map<String, dynamic>?;
                return ath?['id'] as String? ?? '';
              })()
            : '',
        currentBatterName: isLiveBall
            ? (() {
                final batter = situation['batter'] as Map<String, dynamic>?;
                final ath = batter?['athlete'] as Map<String, dynamic>?;
                return ath?['shortName'] as String? ?? '';
              })()
            : '',
        currentBatterPlayerId: isLiveBall
            ? (() {
                final batter = situation['batter'] as Map<String, dynamic>?;
                final ath = batter?['athlete'] as Map<String, dynamic>?;
                return ath?['id'] as String? ?? '';
              })()
            : '',
        lastPlayText: isLiveBall
          ? ((situation['lastPlay'] as Map<String, dynamic>?)?['text']
              as String? ??
            '')
          : '',
        homeForm: homeForm,
        awayForm: awayForm,
        odds: odds,
        analystNote: '來自 ESPN 即時數據',
        homeIsB2B: homeIsB2B,
        awayIsB2B: awayIsB2B,
        homeRestDays: homeRestDays,
        awayRestDays: awayRestDays,
        h2hHomeWins: h2hHomeWins,
        h2hAwayWins: h2hAwayWins,
        h2hDraws: h2hDraws,
        h2hAvgGoals: h2hAvgGoals,
        espnHomePct: espnHomePct,
      );
    } catch (e) {
      return null;
    }
  }

  /// 抓取棒球賽事 summary（先發名單 + 傷兵 + 大小盤）
  /// [espnEventId] = MatchFixture.id 去掉 "espn_" 前綴
  static Future<BaseballGameDetail?> fetchBaseballSummary(
      String espnEventId) async {
    try {
      final url =
          'https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/summary?event=$espnEventId';
      final response = await _httpGetWithRetry(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // ── Over/Under ────────────────────────────────────────────────
      double? overUnder;
      double? overOdds;
      double? underOdds;
      final pickcenter = (data['pickcenter'] as List<dynamic>?) ?? [];
      if (pickcenter.isNotEmpty) {
        final pc = pickcenter.first as Map<String, dynamic>;
        overUnder = (pc['overUnder'] as num?)?.toDouble();
        overOdds = (pc['overOdds'] as num?)?.toDouble();
        underOdds = (pc['underOdds'] as num?)?.toDouble();
      }

      // ── Rosters（先發名單）───────────────────────────────────────
      // ESPN rosters.team 通常沒有 homeAway，需要從 header.competitors 透過 team id 回推
      final competitors = (data['header'] as Map<String, dynamic>?)?['competitions']
              as List<dynamic>? ??
          const [];
      final firstComp =
          competitors.isNotEmpty ? competitors.first as Map<String, dynamic> : <String, dynamic>{};
      final compTeams = (firstComp['competitors'] as List<dynamic>?) ?? const [];
      final homeAwayByTeamId = <String, String>{};
      for (final c in compTeams) {
        if (c is! Map<String, dynamic>) continue;
        final team = c['team'];
        if (team is! Map<String, dynamic>) continue;
        final id = team['id'] as String? ?? '';
        final homeAway = c['homeAway'] as String? ?? '';
        if (id.isNotEmpty && homeAway.isNotEmpty) {
          homeAwayByTeamId[id] = homeAway;
        }
      }

      final rosters = (data['rosters'] as List<dynamic>?) ?? [];
      List<BaseballPlayer> homeLineup = [];
      List<BaseballPlayer> awayLineup = [];
      List<BaseballLineScore> homeLineScores = [];
      List<BaseballLineScore> awayLineScores = [];
      String homeHits = '';
      String awayHits = '';
      String homeErrors = '';
      String awayErrors = '';
      String homeRecord = '';
      String awayRecord = '';
      String homeStreak = '';
      String awayStreak = '';
      String homeLast10 = '';
      String awayLast10 = '';
      String homeHomeRecord = '';
      String awayHomeRecord = '';
      String homeRoadRecord = '';
      String awayRoadRecord = '';
      final batterAvgByPlayerId = <String, String>{};
      final batterHitsByPlayerId = <String, String>{};
      final pitcherPitchesByPlayerId = <String, String>{};
      final pitcherEraByPlayerId = <String, String>{};
      final pitcherGameStatsByPlayerId = <String, BaseballPitcherGameStats>{};

      for (final c in compTeams) {
        if (c is! Map<String, dynamic>) continue;
        final homeAway = c['homeAway'] as String? ?? '';
        final linescores = (c['linescores'] as List<dynamic>?) ?? const [];
        final parsed = linescores.map((inning) {
          final inningMap = inning as Map<String, dynamic>;
          return BaseballLineScore(
            runs: inningMap['displayValue']?.toString() ?? '',
            hits: inningMap['hits']?.toString() ?? '',
            errors: inningMap['errors']?.toString() ?? '',
          );
        }).toList();

        if (homeAway == 'home') {
          homeLineScores = parsed;
          homeHits = c['hits']?.toString() ?? '';
          homeErrors = c['errors']?.toString() ?? '';
          // parse team record (e.g. "51-29")
          final homeRecords = (c['records'] as List<dynamic>?) ?? const [];
          for (final rec in homeRecords) {
            final recMap = rec as Map<String, dynamic>;
            final type = recMap['type'] as String? ?? '';
            final summary = recMap['summary'] as String? ?? '';
            if (type == 'total' && homeRecord.isEmpty) homeRecord = summary;
            if (type == 'home' || type == 'homeAndAway') homeHomeRecord = summary;
            if (type == 'road') homeRoadRecord = summary;
            if ((type == 'lastTen' || type == 'vsown') && homeLast10.isEmpty) homeLast10 = summary;
          }
          if (homeRecord.isEmpty && homeRecords.isNotEmpty) {
            homeRecord = (homeRecords.first as Map<String, dynamic>)['summary'] as String? ?? '';
          }
          // streak e.g. "W2" or "L3" → 轉中文
          final homeStreakMap = c['streak'] as Map<String, dynamic>?;
          homeStreak = _translateStreak(homeStreakMap?['shortDisplayName'] as String? ?? '');
        } else if (homeAway == 'away') {
          awayLineScores = parsed;
          awayHits = c['hits']?.toString() ?? '';
          awayErrors = c['errors']?.toString() ?? '';
          final awayRecords = (c['records'] as List<dynamic>?) ?? const [];
          for (final rec in awayRecords) {
            final recMap = rec as Map<String, dynamic>;
            final type = recMap['type'] as String? ?? '';
            final summary = recMap['summary'] as String? ?? '';
            if (type == 'total' && awayRecord.isEmpty) awayRecord = summary;
            if (type == 'home' || type == 'homeAndAway') awayHomeRecord = summary;
            if (type == 'road') awayRoadRecord = summary;
            if ((type == 'lastTen' || type == 'vsown') && awayLast10.isEmpty) awayLast10 = summary;
          }
          if (awayRecord.isEmpty && awayRecords.isNotEmpty) {
            awayRecord = (awayRecords.first as Map<String, dynamic>)['summary'] as String? ?? '';
          }
          final awayStreakMap = c['streak'] as Map<String, dynamic>?;
          awayStreak = _translateStreak(awayStreakMap?['shortDisplayName'] as String? ?? '');
        }
      }

      for (final r in rosters) {
        final rMap = r as Map<String, dynamic>;
        final teamId = (rMap['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
        final homeAway = homeAwayByTeamId[teamId];
        final entries = (rMap['roster'] as List<dynamic>?) ?? [];

        for (final e in entries) {
          final eMap = e as Map<String, dynamic>;
          final ath = (eMap['athlete'] as Map<String, dynamic>?) ?? {};
          final playerId = (ath['id'] as String?) ?? '';
          if (playerId.isEmpty) continue;
          final stats = (eMap['stats'] as List<dynamic>?) ?? const [];
          final avg = _statDisplay(stats, 'AVG');
          final hits = _statDisplay(stats, 'H');
          final pitches = _statDisplay(stats, 'P');
          final era = _statDisplay(stats, 'ERA');
          if (avg.isNotEmpty) batterAvgByPlayerId[playerId] = avg;
          if (hits.isNotEmpty) batterHitsByPlayerId[playerId] = hits;
          if (pitches.isNotEmpty) pitcherPitchesByPlayerId[playerId] = pitches;
          if (era.isNotEmpty) pitcherEraByPlayerId[playerId] = era;
        }

        final starters = entries
            .where((e) => (e as Map<String, dynamic>)['starter'] == true)
            .map((e) {
          final eMap = e as Map<String, dynamic>;
          final ath = (eMap['athlete'] as Map<String, dynamic>?) ?? {};
          final playerId = ath['id'] as String? ?? '';
          final stats = (eMap['stats'] as List<dynamic>?) ?? const [];
          return BaseballPlayer(
            name: ath['displayName'] as String? ?? '',
            playerId: playerId,
            position: (ath['position'] as Map<String, dynamic>?)?[
                    'abbreviation'] as String? ??
                '',
            batOrder: (eMap['batOrder'] as int?) ?? 0,
            battingAvg: _statDisplay(stats, 'AVG'),
            hitsToday: _statDisplay(stats, 'H'),
            atBatsToday: _statDisplay(stats, 'AB'),
            homeRuns: _statDisplay(stats, 'HR'),
            rbis: _statDisplay(stats, 'RBI'),
          );
        }).toList()
          ..sort((a, b) => a.batOrder.compareTo(b.batOrder));
        if (homeAway == 'home') {
          homeLineup = starters;
        } else {
          awayLineup = starters;
        }
        // fallback: if homeAway not present, use ESPN common order: first=home, second=away
        if (homeAway == null) {
          if (rosters.indexOf(r) == 0) {
            homeLineup = starters;
          } else {
            awayLineup = starters;
          }
        }
      }

      // ── Boxscore pitching（投手今日數據）──────────────────────────
      final boxscorePlayers = (data['boxscore'] as Map<String, dynamic>?)?['players']
              as List<dynamic>? ??
          const [];
      for (final team in boxscorePlayers) {
        if (team is! Map<String, dynamic>) continue;
        final statistics = (team['statistics'] as List<dynamic>?) ?? const [];
        for (final statGroup in statistics) {
          if (statGroup is! Map<String, dynamic>) continue;
          if ((statGroup['type'] as String?) != 'pitching') continue;
          final keys = (statGroup['keys'] as List<dynamic>?)?.cast<String>() ?? const [];
          final athletes = (statGroup['athletes'] as List<dynamic>?) ?? const [];
          for (final athleteEntry in athletes) {
            if (athleteEntry is! Map<String, dynamic>) continue;
            final athlete = athleteEntry['athlete'] as Map<String, dynamic>?;
            final playerId = athlete?['id'] as String? ?? '';
            final values = (athleteEntry['stats'] as List<dynamic>?) ?? const [];
            if (playerId.isEmpty || values.isEmpty) continue;
            String valueFor(String key) {
              final index = keys.indexOf(key);
              if (index < 0 || index >= values.length) return '';
              return values[index]?.toString() ?? '';
            }
            final pitchesStrikes = valueFor('pitches-strikes');
            String pitches = valueFor('pitches');
            String strikes = '';
            String balls = '';
            if (pitchesStrikes.contains('-')) {
              final parts = pitchesStrikes.split('-');
              if (parts.length == 2) {
                pitches = parts[0];
                strikes = parts[1];
                final p = int.tryParse(parts[0]) ?? 0;
                final s = int.tryParse(parts[1]) ?? 0;
                balls = (p - s).toString();
              }
            }
            final era = valueFor('ERA');
            if (pitches.isNotEmpty) pitcherPitchesByPlayerId[playerId] = pitches;
            if (era.isNotEmpty) pitcherEraByPlayerId[playerId] = era;
            pitcherGameStatsByPlayerId[playerId] = BaseballPitcherGameStats(
              innings: valueFor('fullInnings.partInnings'),
              hits: valueFor('hits'),
              runs: valueFor('runs'),
              earnedRuns: valueFor('earnedRuns'),
              walks: valueFor('walks'),
              strikeouts: valueFor('strikeouts'),
              pitches: pitches,
              strikes: strikes,
              balls: balls,
              era: era,
            );
          }
        }
      }

      // ── Injuries（傷兵名單）──────────────────────────────────────
      final injuriesRaw = (data['injuries'] as List<dynamic>?) ?? [];
      final injuries = <BaseballInjury>[];
      for (final injTeam in injuriesRaw) {
        final itMap = injTeam as Map<String, dynamic>;
        final teamName =
            _translateTeam(
                (itMap['team'] as Map<String, dynamic>?)?['displayName']
                    as String? ??
                    '', '美職棒');
        for (final inj in (itMap['injuries'] as List<dynamic>?) ?? []) {
          final injMap = inj as Map<String, dynamic>;
          final ath = (injMap['athlete'] as Map<String, dynamic>?) ?? {};
          final typeMap =
              (injMap['type'] as Map<String, dynamic>?) ?? {};
          injuries.add(BaseballInjury(
            playerName: ath['displayName'] as String? ?? '',
            team: teamName,
            status: injMap['status'] as String? ?? '',
            description: typeMap['description'] as String? ?? '',
          ));
        }
      }

      return BaseballGameDetail(
        overUnder: overUnder,
        overOdds: overOdds,
        underOdds: underOdds,
        homeLineScores: homeLineScores,
        awayLineScores: awayLineScores,
        homeHits: homeHits,
        awayHits: awayHits,
        homeErrors: homeErrors,
        awayErrors: awayErrors,
        homeRecord: homeRecord,
        awayRecord: awayRecord,
        homeStreak: homeStreak,
        awayStreak: awayStreak,
        homeLast10: homeLast10,
        awayLast10: awayLast10,
        homeHomeRecord: homeHomeRecord,
        awayHomeRecord: awayHomeRecord,
        homeRoadRecord: homeRoadRecord,
        awayRoadRecord: awayRoadRecord,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
        injuries: injuries,
        batterAvgByPlayerId: batterAvgByPlayerId,
        batterHitsByPlayerId: batterHitsByPlayerId,
        pitcherPitchesByPlayerId: pitcherPitchesByPlayerId,
        pitcherEraByPlayerId: pitcherEraByPlayerId,
        pitcherGameStatsByPlayerId: pitcherGameStatsByPlayerId,
      );
    } catch (e) {
      // Keep app resilient in production; parsing failures should not crash UI.
      return null;
    }
  }

  /// 抓取籃球賽事 summary（先發名單 + 傷兵 + 大小盤）
  static Future<BasketballGameDetail?> fetchBasketballSummary(
      String espnEventId) async {
    try {
      final url =
          'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=$espnEventId';
      final response = await _httpGetWithRetry(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // ── Over/Under ────────────────────────────────────────────────
      double? overUnder;
      double? overOdds;
      double? underOdds;
      final pickcenter = (data['pickcenter'] as List<dynamic>?) ?? [];
      if (pickcenter.isNotEmpty) {
        final pc = pickcenter.first as Map<String, dynamic>;
        overUnder = (pc['overUnder'] as num?)?.toDouble();
        overOdds = (pc['overOdds'] as num?)?.toDouble();
        underOdds = (pc['underOdds'] as num?)?.toDouble();
      }

      // ── Team records + streaks from header.competitions ───────────
      final competitors = (data['header'] as Map<String, dynamic>?)?['competitions']
              as List<dynamic>? ??
          const [];
      final firstComp =
          competitors.isNotEmpty ? competitors.first as Map<String, dynamic> : <String, dynamic>{};
      final compTeams = (firstComp['competitors'] as List<dynamic>?) ?? const [];
      final homeAwayByTeamId = <String, String>{};

      String homeRecord = '', awayRecord = '';
      String homeStreak = '', awayStreak = '';
      String homeLast10 = '', awayLast10 = '';
      String homeHomeRecord = '', awayHomeRecord = '';
      String homeRoadRecord = '', awayRoadRecord = '';
      List<BasketballLineScore> homeLineScores = [];
      List<BasketballLineScore> awayLineScores = [];

      for (final c in compTeams) {
        if (c is! Map<String, dynamic>) continue;
        final team = c['team'];
        if (team is! Map<String, dynamic>) continue;
        final id = team['id'] as String? ?? '';
        final homeAway = c['homeAway'] as String? ?? '';
        if (id.isNotEmpty && homeAway.isNotEmpty) homeAwayByTeamId[id] = homeAway;

        final records = (c['records'] as List<dynamic>?) ?? const [];
        final linescores = (c['linescores'] as List<dynamic>?) ?? const [];
        final streakMap = c['streak'] as Map<String, dynamic>?;
        final streak = _translateStreak(streakMap?['shortDisplayName'] as String? ?? '');

        final parsedLines = linescores.asMap().entries.map((entry) {
          final i = entry.key;
          final ls = entry.value as Map<String, dynamic>;
          final periodNum = (ls['period'] as num?)?.toInt() ??
              (ls['periodNumber'] as num?)?.toInt() ??
              (i + 1);
          return BasketballLineScore(
            period: periodNum,
            points: (ls['displayValue'] ?? ls['value'] ?? '').toString(),
          );
        }).toList();

        String record = '', last10 = '', homeRec = '', roadRec = '';
        for (final rec in records) {
          final recMap = rec as Map<String, dynamic>;
          final type = recMap['type'] as String? ?? '';
          final summary = recMap['summary'] as String? ?? '';
          if (type == 'total' && record.isEmpty) record = summary;
          if (type == 'home' || type == 'homeAndAway') homeRec = summary;
          if (type == 'road') roadRec = summary;
          if ((type == 'lastTen' || type == 'vsown') && last10.isEmpty) last10 = summary;
        }
        if (record.isEmpty && records.isNotEmpty) {
          record = (records.first as Map<String, dynamic>)['summary'] as String? ?? '';
        }

        if (homeAway == 'home') {
          homeRecord = record; homeStreak = streak;
          homeLast10 = last10; homeHomeRecord = homeRec; homeRoadRecord = roadRec;
          homeLineScores = parsedLines;
        } else if (homeAway == 'away') {
          awayRecord = record; awayStreak = streak;
          awayLast10 = last10; awayHomeRecord = homeRec; awayRoadRecord = roadRec;
          awayLineScores = parsedLines;
        }
      }

      // ── Rosters（先發名單 + 場均數據）────────────────────────────
      final rosters = (data['rosters'] as List<dynamic>?) ?? [];
      List<BasketballPlayer> homeLineup = [];
      List<BasketballPlayer> awayLineup = [];
      final playerAvgPointsById = <String, String>{};
      final playerPointsTodayById = <String, String>{};

      double homeTeamPER = 0.0; // 新增：計算球隊總 PER
      double awayTeamPER = 0.0; // 新增：計算球隊總 PER
      for (final r in rosters) {
        final rMap = r as Map<String, dynamic>;
        final teamId = (rMap['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
        final homeAway = homeAwayByTeamId[teamId];
        final entries = (rMap['roster'] as List<dynamic>?) ?? [];

        for (final e in entries) {
          final eMap = e as Map<String, dynamic>;
          final ath = (eMap['athlete'] as Map<String, dynamic>?) ?? {};
          final playerId = ath['id'] as String? ?? '';
          if (playerId.isEmpty) continue;
          final stats = (eMap['stats'] as List<dynamic>?) ?? const [];
          String ppg = _statDisplay(stats, 'PPG');
          if (ppg.isEmpty) ppg = _statDisplay(stats, 'PTS');
          String per = _statDisplay(stats, 'PER'); // 假設 ESPN 有 PER
          if (per.isNotEmpty) playerAvgPointsById['${playerId}_PER'] = per; // 暫存 PER

          if (ppg.isNotEmpty) playerAvgPointsById[playerId] = ppg;
        }

        final starters = entries
            .where((e) => (e as Map<String, dynamic>)['starter'] == true)
            .map((e) {
          final eMap = e as Map<String, dynamic>;
          final ath = (eMap['athlete'] as Map<String, dynamic>?) ?? {};
          final playerId = ath['id'] as String? ?? '';
          final stats = (eMap['stats'] as List<dynamic>?) ?? const [];
          String ppg = _statDisplay(stats, 'PPG');
          if (ppg.isEmpty) ppg = _statDisplay(stats, 'PTS');
          String rpg = _statDisplay(stats, 'RPG');
          if (rpg.isEmpty) rpg = _statDisplay(stats, 'REB');
          String apg = _statDisplay(stats, 'APG');
          if (apg.isEmpty) apg = _statDisplay(stats, 'AST');
          return BasketballPlayer(
            name: ath['displayName'] as String? ?? '',
            playerId: playerId,
            position: (ath['position'] as Map<String, dynamic>?)?['abbreviation'] as String? ?? '',
            jerseyNumber: ath['jersey'] as String? ?? '',
            avgPoints: ppg,
            avgRebounds: rpg,
            avgAssists: apg,
            pointsToday: '',
          );
        }).toList();

        // 計算球隊總 PER (只算先發球員)
        final teamPER = starters.map((p) => double.tryParse(playerAvgPointsById['${p.playerId}_PER'] ?? '0.0') ?? 0.0).reduce((a, b) => a + b);

        if (homeAway == 'home') {
          homeLineup = starters;
          homeTeamPER = teamPER;
        } else if (homeAway == 'away') {
          awayLineup = starters;
          awayTeamPER = teamPER;
        } else if (homeAway == null) {
          if (rosters.indexOf(r) == 0) {
            homeLineup = starters;
          } else {
            awayLineup = starters;
          }
        }
      }

      // ── Boxscore（今日得分）──────────────────────────────────────
      final boxscorePlayers = (data['boxscore'] as Map<String, dynamic>?)?['players']
              as List<dynamic>? ??
          const [];
      for (final team in boxscorePlayers) {
        if (team is! Map<String, dynamic>) continue;
        final statistics = (team['statistics'] as List<dynamic>?) ?? const [];
        for (final statGroup in statistics) {
          if (statGroup is! Map<String, dynamic>) continue;
          final keys = (statGroup['keys'] as List<dynamic>?)?.cast<String>() ?? const [];
          final athletes = (statGroup['athletes'] as List<dynamic>?) ?? const [];
          for (final athleteEntry in athletes) {
            if (athleteEntry is! Map<String, dynamic>) continue;
            final athlete = athleteEntry['athlete'] as Map<String, dynamic>?;
            final playerId = athlete?['id'] as String? ?? '';
            final values = (athleteEntry['stats'] as List<dynamic>?) ?? const [];
            if (playerId.isEmpty || values.isEmpty) continue;
            String valueFor(String key) {
              final index = keys.indexOf(key);
              if (index < 0 || index >= values.length) return '';
              return values[index]?.toString() ?? '';
            }
            final pts = valueFor('pts');
            if (pts.isNotEmpty && pts != '0') playerPointsTodayById[playerId] = pts;
          }
        }
      }

      // Update lineup with today's points
      BasketballPlayer withPoints(BasketballPlayer p) {
        final pts = playerPointsTodayById[p.playerId] ?? '';
        return BasketballPlayer(
          name: p.name, playerId: p.playerId, position: p.position,
          jerseyNumber: p.jerseyNumber, avgPoints: p.avgPoints,
          avgRebounds: p.avgRebounds, avgAssists: p.avgAssists,
          pointsToday: pts,
        );
      }
      homeLineup = homeLineup.map(withPoints).toList();
      awayLineup = awayLineup.map(withPoints).toList();

      // ── Boxscore team stats（球隊比賽統計）───────────────────────
      final boxscoreTeamsRaw =
          (data['boxscore'] as Map<String, dynamic>?)?['teams']
              as List<dynamic>? ??
          const [];
      Map<String, String> homeTeamStats = {};
      Map<String, String> awayTeamStats = {};
      for (final td in boxscoreTeamsRaw) {
        if (td is! Map<String, dynamic>) continue;
        final teamId =
            (td['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
        final ha = homeAwayByTeamId[teamId];
        final statistics = (td['statistics'] as List<dynamic>?) ?? const [];
        final stats = <String, String>{};
        for (final s in statistics) {
          if (s is! Map<String, dynamic>) continue;
          final abbr =
              s['abbreviation'] as String? ?? s['name'] as String? ?? '';
          final val = s['displayValue'] as String? ?? '';
          if (abbr.isNotEmpty && val.isNotEmpty) stats[abbr] = val;
        }
        if (ha == 'home') {
          homeTeamStats = stats;
        } else if (ha == 'away') {
          awayTeamStats = stats;
        }
      }

      // ── Injuries（傷兵名單）──────────────────────────────────────
      final injuriesRaw = (data['injuries'] as List<dynamic>?) ?? [];
      final injuries = <BaseballInjury>[];
      for (final injTeam in injuriesRaw) {
        final itMap = injTeam as Map<String, dynamic>;
        final teamName =
            _translateTeam((itMap['team'] as Map<String, dynamic>?)?['displayName'] as String? ?? '', 'NBA');
        for (final inj in (itMap['injuries'] as List<dynamic>?) ?? []) {
          final injMap = inj as Map<String, dynamic>;
          final ath = (injMap['athlete'] as Map<String, dynamic>?) ?? {};
          final typeMap = (injMap['type'] as Map<String, dynamic>?) ?? {};
          injuries.add(BaseballInjury(
            playerName: ath['displayName'] as String? ?? '',
            team: teamName,
            status: injMap['status'] as String? ?? '',
            description: typeMap['description'] as String? ?? '',
          ));
        }
      }

      return BasketballGameDetail(
        overUnder: overUnder,
        overOdds: overOdds,
        underOdds: underOdds,
        homeRecord: homeRecord,
        awayRecord: awayRecord,
        homeStreak: homeStreak,
        awayStreak: awayStreak,
        homeLast10: homeLast10,
        awayLast10: awayLast10,
        homeHomeRecord: homeHomeRecord,
        awayHomeRecord: awayHomeRecord,
        homeRoadRecord: homeRoadRecord,
        awayRoadRecord: awayRoadRecord,
        homeLineScores: homeLineScores,
        awayLineScores: awayLineScores,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
        injuries: injuries,
        playerAvgPointsById: playerAvgPointsById,
        playerPointsTodayById: playerPointsTodayById,
        homeTeamStats: homeTeamStats,
        awayTeamStats: awayTeamStats,
        homePlayerEfficiencyRating: homeTeamPER / homeLineup.length.clamp(1, 5), // 平均 PER
        awayPlayerEfficiencyRating: awayTeamPER / awayLineup.length.clamp(1, 5), // 平均 PER
      );
    } catch (e) {
      return null;
    }
  }

  /// 從 ESPN competitor 資料解析 TeamForm
  static Future<TeamForm> _parseTeamForm(
    Map<String, dynamic> comp,
    String teamName,
    SportType sport,
    String league,
  ) async {
    // 解析勝敗記錄
    // 足球格式：勝-平-負 (e.g. "7-8-16")
    // 棒球/籃球格式：勝-負 (e.g. "51-29")
    final records = (comp['records'] as List<dynamic>?) ?? [];
    int wins = 0;
    int draws = 0;
    int losses = 0;
    int homeWins = 0;
    int homeLosses = 0;
    for (final r in records) {
      final rec = r as Map<String, dynamic>;
      final summary = rec['summary'] as String? ?? '';
      final parts = summary.split('-');
      if (rec['type'] == 'total') {
        if (parts.length == 3) {
          // 足球 W-D-L 格式
          wins = int.tryParse(parts[0]) ?? 0;
          draws = int.tryParse(parts[1]) ?? 0;
          losses = int.tryParse(parts[2]) ?? 0;
        } else if (parts.length >= 2) {
          wins = int.tryParse(parts[0]) ?? 0;
          losses = int.tryParse(parts[1]) ?? 0;
        }
      }
      if (rec['type'] == 'home' && parts.length >= 2) {
        homeWins = int.tryParse(parts[0]) ?? 0;
        homeLosses = int.tryParse(parts[1]) ?? 0;
      }
    }

    final totalGames = wins + draws + losses;
    // 足球用積分制勝率（勝=1分，平=0.5分），棒球/籃球用純勝率
    final double winRate;
    if (totalGames > 0) {
      winRate = sport == SportType.football
          ? (wins + draws * 0.5) / totalGames
          : wins / totalGames;
    } else {
      winRate = 0.5;
    }

    // 解析統計數據
    final stats = <String, double>{};
    for (final s in (comp['statistics'] as List<dynamic>?) ?? []) {
      final stat = s as Map<String, dynamic>;
      final name = stat['name'] as String? ?? '';
      final val = double.tryParse(stat['displayValue'] as String? ?? '') ?? 0.0;
      if (val != 0.0) stats[name] = val; // 只存非零值，避免蓋掉預設
    }

    double avgScored = 0;
    double avgConceded = 0;
    double momentum = 0;
    double playerEfficiencyRating = 0.0; // 新增 PER
    double pitcherK9 = 0.0; // 新增 K/9

    // 利用勝率做出大幅差異化：不同隊伍 winRate 差異大時分數明顯不同
    final recBoost = winRate - 0.5; // 範圍約 -0.5 ~ +0.5

    // 球隊名稱 hash → 各隊固定但不同的攻守特性偏差
    // 使每隊在相近勝率下仍有明顯不同的得失分期望值
    final nameHash = teamName.codeUnits.fold(0, (sum, c) => sum + c);
    final nameIndex = (nameHash % 17) - 8; // -8 ~ +8

    bool hasRealStats;
    switch (sport) {
      case SportType.basketball:
        // nameBias ±10 pts（現實範圍：各隊場均得分差可達 ±15 pts）
        final nameBias = nameIndex * 10.0 / 8.0; // ±10
        final hasAvgPts = stats.containsKey('avgPoints') && stats['avgPoints']! > 80;
        avgScored = hasAvgPts ? stats['avgPoints']! : 113.0 + recBoost * 30.0 + nameBias;
        final hasAvgPtsAllowed = stats.containsKey('avgPointsAllowed') && stats['avgPointsAllowed']! > 80;
        avgConceded = hasAvgPtsAllowed
            ? stats['avgPointsAllowed']!
            : 226.0 - avgScored - recBoost * 8.0 - nameBias * 0.6;
        // ORTG: offensive rating per 100 possessions (ESPN field names vary)
        final ortg = stats['offRating'] ?? stats['offensiveRating'] ?? stats['ORTG'] ?? 0.0;
        playerEfficiencyRating = ortg > 80 ? ortg
            : stats.containsKey('PER') ? stats['PER']!
            : 15.0 + recBoost * 10.0;
        momentum = recBoost * 20;
        hasRealStats = hasAvgPts || hasAvgPtsAllowed;
        break;

      case SportType.baseball:
        // nameBias ±1.0 runs（現實範圍：各隊場均得分差可達 ±2 runs）
        final nameBias = nameIndex * 1.0 / 8.0; // ±1.0
        final hasAvg = stats.containsKey('avg') && stats['avg']! > 0.1;
        final hasEra = stats.containsKey('ERA') && stats['ERA']! > 0.5;
        avgScored = (hasAvg ? 4.3 + (stats['avg']! - 0.260) * 50 : 4.3)
            + recBoost * 6.0 + nameBias;
        avgConceded = hasEra
            ? (stats['ERA']! * 0.85).clamp(2.0, 7.0)
            : (4.3 - recBoost * 6.0 - nameBias).clamp(2.0, 7.0);
        final homeGames = homeWins + homeLosses;
        final homeRate = homeGames > 0 ? homeWins / homeGames : 0.5;
        momentum = (homeRate - 0.5) * 18 + recBoost * 12;
        pitcherK9 = stats.containsKey('K/9') ? stats['K/9']! : 8.0 + recBoost * 2.0;
        hasRealStats = hasEra; // 有真實 ERA 才算有效數據
        break;

      case SportType.football:
        final nameBias = nameIndex * 0.20 / 8.0;
        final standingsEntry = _soccerStandingsCache[league]?[teamName];
        if (standingsEntry != null && standingsEntry.gamesPlayed > 0) {
          avgScored = standingsEntry.goalsFor / standingsEntry.gamesPlayed;
          avgConceded = standingsEntry.goalsAgainst / standingsEntry.gamesPlayed;
          hasRealStats = true;
        } else {
          avgScored = 1.35 + recBoost * 2.5 + nameBias;
          avgConceded = 1.35 - recBoost * 1.8 - nameBias * 0.7;
          hasRealStats = false;
        }
        momentum = recBoost * 18;
        break;
    }

    final recentCount = sport == SportType.football ? 5 : 10;
    final List<String> recentResults;
    if (sport == SportType.football) {
      // ESPN 在足球 competitor 物件中直接提供 form 字串（如 "WLDWL"）
      final espnForm = comp['form'] as String? ?? '';
      final parsed = _parseEspnFormString(espnForm, allowDraw: true);
      recentResults = parsed.isNotEmpty ? parsed : _simulateRecentResults(winRate, sport, recentCount);
    } else {
      // NBA/MLB：從球隊賽程 API 取得最近完賽結果（session 快取）
      final teamId = (comp['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
      final fetched = teamId.isNotEmpty
          ? await _fetchTeamRecentForm(teamId, sport, recentCount)
          : null;
      recentResults = fetched ?? _simulateRecentResults(winRate, sport, recentCount);
    }

    // 滾動視窗統計（NBA / MLB / 足球）
    double? last3AvgScored;
    double? last3AvgConceded;
    double? last10AvgScored;
    double? last10AvgConceded;
    bool isB2B = false;
    int restDays = 2;
    List<String> recentScores = [];
    if (sport == SportType.basketball || sport == SportType.baseball) {
      final teamId = (comp['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
      if (teamId.isNotEmpty) {
        final rolling = await _fetchTeamRollingStats(teamId, sport);
        if (rolling != null) {
          last3AvgScored = rolling.last3Avg;
          last3AvgConceded = rolling.last3Conceded;
          last10AvgScored = rolling.last10Avg;
          last10AvgConceded = rolling.last10Conceded;
          isB2B = rolling.isB2B;
          restDays = rolling.restDays;
          recentScores = rolling.recentScores;
        }
      }
    } else if (sport == SportType.football) {
      final teamId = (comp['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
      final slug = _soccerSlugFromLeague(league);
      if (teamId.isNotEmpty && slug != null) {
        final rolling = await _fetchFootballTeamRollingStats(teamId, slug);
        if (rolling != null) {
          last3AvgScored = rolling.last3Avg;
          last3AvgConceded = rolling.last3Conceded;
          // 用近 5 場數據取代賽季平均（更能反映近況）
          if (rolling.last5Avg != null) {
            avgScored = rolling.last5Avg!;
            hasRealStats = true;
          }
          if (rolling.last5Conceded != null) {
            avgConceded = rolling.last5Conceded!;
          }
          last10AvgScored = rolling.last5Avg;
          last10AvgConceded = rolling.last5Conceded;
          recentScores = rolling.recentScores;
        }
      }
    }

    final seasonRecord = sport == SportType.football && draws > 0
        ? '$wins-$draws-$losses'
        : (wins > 0 || losses > 0)
            ? '$wins-$losses'
            : '';

    // ESPN scoreboard competitor 物件中的連勝/連敗（如 "W3", "L2"）
    final streakMap = comp['streak'] as Map<String, dynamic>?;
    final streakDisplay = _translateStreak(streakMap?['shortDisplayName'] as String? ?? '');

    final teamIdForForm = (comp['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
    return TeamForm(
      teamName: teamName,
      teamId: teamIdForForm,
      lastFiveResults: recentResults,
      averageScored: avgScored.clamp(0, 200),
      averageConceded: avgConceded.clamp(0, 200),
      injuries: 0,
      momentumScore: momentum.clamp(-10, 10),
      playerEfficiencyRating: sport == SportType.baseball ? pitcherK9 : playerEfficiencyRating,
      seasonRecord: seasonRecord,
      hasRealStats: hasRealStats,
      streakDisplay: streakDisplay,
      last3AvgScored: last3AvgScored,
      last3AvgConceded: last3AvgConceded,
      last10AvgScored: last10AvgScored,
      last10AvgConceded: last10AvgConceded,
      isB2B: isB2B,
      restDays: restDays,
      recentScores: recentScores,
    );
  }

  /// 將 ESPN form 字串（如 "WLDWL"）轉為中文陣列（最近→最舊）
  static List<String> _parseEspnFormString(String form, {bool allowDraw = false}) {
    if (form.isEmpty) return [];
    return form.toUpperCase().split('').map((c) {
      if (c == 'W') return '勝';
      if (c == 'L') return '負';
      if (c == 'D' && allowDraw) return '平';
      return '';
    }).where((s) => s.isNotEmpty).toList();
  }

  /// 從 ESPN 球隊賽程 API 取得最近 [count] 場完賽結果（session 快取）
  static Future<List<String>?> _fetchTeamRecentForm(
    String teamId,
    SportType sport,
    int count,
  ) async {
    final cacheKey = '${sport.name}:$teamId';
    if (_teamFormCache.containsKey(cacheKey)) return _teamFormCache[cacheKey];

    try {
      final sportPath = sport == SportType.basketball ? 'basketball/nba' : 'baseball/mlb';
      final url = '$_base/$sportPath/teams/$teamId/schedule?limit=20';
      final resp = await _httpGetWithRetry(Uri.parse(url), timeout: const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final events = (data['events'] as List<dynamic>?) ?? [];

      final results = <String>[];
      for (final raw in events.reversed) {
        final e = raw as Map<String, dynamic>;
        final comps = ((e['competitions'] as List?)?.first as Map<String, dynamic>?)?['competitors'] as List?;
        final state = (((e['competitions'] as List?)?.first as Map<String, dynamic>?)?['status'] as Map<String, dynamic>?)?['type']?['state'] as String? ?? '';
        if (state != 'post') continue;
        for (final c in (comps ?? [])) {
          final cm = c as Map<String, dynamic>;
          if ((cm['team'] as Map<String, dynamic>?)?['id'] == teamId) {
            results.add(cm['winner'] == true ? '勝' : '負');
            break;
          }
        }
        if (results.length >= count) break;
      }

      final out = results.reversed.take(count).toList();
      _teamFormCache[cacheKey] = out;
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// 從 ESPN 球隊賽程 API 取得滾動視窗統計（得分/失分/B2B/休息天數）
  /// 回傳記錄型別包含：results, recentScores, last3Avg, last10Avg, last3Conceded, last10Conceded, isB2B, restDays
  static Future<({
    List<String> results,
    List<String> recentScores,
    double? last3Avg,
    double? last10Avg,
    double? last3Conceded,
    double? last10Conceded,
    bool isB2B,
    int restDays,
  })?> _fetchTeamRollingStats(String teamId, SportType sport) async {
    final cacheKey = 'rolling:${sport.name}:$teamId';
    if (_rollingCache.containsKey(cacheKey)) {
      return _rollingCache[cacheKey] as ({
        List<String> results,
        List<String> recentScores,
        double? last3Avg,
        double? last10Avg,
        double? last3Conceded,
        double? last10Conceded,
        bool isB2B,
        int restDays,
      })?;
    }

    try {
      final sportPath = sport == SportType.basketball ? 'basketball/nba' : 'baseball/mlb';
      final teamMap = sport == SportType.basketball ? _nbaTeams : _mlbTeams;
      final url = '$_base/$sportPath/teams/$teamId/schedule?limit=20';
      final resp = await _httpGetWithRetry(Uri.parse(url), timeout: const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final events = (data['events'] as List<dynamic>?) ?? [];

      final teamScores = <double>[];   // 本隊得分（最近→最舊）
      final oppScores = <double>[];    // 對手得分（最近→最舊）
      final resultFlags = <String>[];  // '勝'/'負'
      final scoreStrings = <String>[]; // "112-105 湖人"
      DateTime? mostRecentGameDate;

      // 由新到舊掃描完賽
      for (final raw in events.reversed) {
        final e = raw as Map<String, dynamic>;
        final comp = (e['competitions'] as List?)?.first as Map<String, dynamic>?;
        if (comp == null) continue;
        final state = ((comp['status'] as Map<String, dynamic>?)?['type'] as Map<String, dynamic>?)?['state'] as String? ?? '';
        if (state != 'post') continue;

        final competitors = (comp['competitors'] as List?) ?? [];
        double? myScore;
        double? opponentScore;
        String opponentName = '';
        bool isWinner = false;
        for (final c in competitors) {
          final cm = c as Map<String, dynamic>;
          final rawS = cm['score'];
          final score = rawS is num ? rawS.toDouble() : double.tryParse(rawS?.toString() ?? '');
          final teamObj = cm['team'] as Map<String, dynamic>?;
          if (teamObj?['id'] == teamId) {
            myScore = score;
            isWinner = cm['winner'] == true;
          } else {
            opponentScore = score;
            final rawName = teamObj?['displayName'] as String? ?? teamObj?['abbreviation'] as String? ?? '';
            opponentName = teamMap[rawName] ?? rawName;
          }
        }
        if (myScore == null || opponentScore == null) continue;

        teamScores.add(myScore);
        oppScores.add(opponentScore);
        resultFlags.add(isWinner ? '勝' : '負');
        final ms = myScore.toInt();
        final os = opponentScore.toInt();
        scoreStrings.add(opponentName.isNotEmpty ? '$ms-$os $opponentName' : '$ms-$os');

        // 記錄最近一場完賽日期
        if (mostRecentGameDate == null) {
          final dateStr = e['date'] as String?;
          if (dateStr != null) {
            mostRecentGameDate = DateTime.tryParse(dateStr);
          }
        }
      }

      // 計算滾動均值（最近場次排在前面）
      double? last3Avg;
      double? last10Avg;
      double? last3Conceded;
      double? last10Conceded;
      if (teamScores.length >= 3) {
        last3Avg = teamScores.take(3).reduce((a, b) => a + b) / 3;
        last3Conceded = oppScores.take(3).reduce((a, b) => a + b) / 3;
      }
      if (teamScores.length >= 10) {
        last10Avg = teamScores.take(10).reduce((a, b) => a + b) / 10;
        last10Conceded = oppScores.take(10).reduce((a, b) => a + b) / 10;
      }

      // 計算 B2B 與休息天數
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      bool isB2B = false;
      int restDays = 2; // 預設正常休息
      if (mostRecentGameDate != null) {
        final gameDate = DateTime(mostRecentGameDate.year, mostRecentGameDate.month, mostRecentGameDate.day);
        final diff = todayDate.difference(gameDate).inDays;
        restDays = diff.clamp(0, 7);
        isB2B = diff == 1;
      }

      final result = (
        results: resultFlags,
        recentScores: scoreStrings,
        last3Avg: last3Avg,
        last10Avg: last10Avg,
        last3Conceded: last3Conceded,
        last10Conceded: last10Conceded,
        isB2B: isB2B,
        restDays: restDays,
      );
      _rollingCache[cacheKey] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 從 _standingsSlugs 取得足球 ESPN slug（如 'eng.1'），不含 'soccer/' 前綴
  static String? _soccerSlugFromLeague(String league) {
    final full = _standingsSlugs[league]; // e.g. 'soccer/eng.1'
    if (full == null || !full.startsWith('soccer/')) return null;
    return full.substring('soccer/'.length);
  }

  /// 從 ESPN 足球球隊賽程 API 取得近 5-10 場進失球滾動統計
  static Future<({
    double? last3Avg,
    double? last5Avg,
    double? last3Conceded,
    double? last5Conceded,
    List<String> recentScores,
  })?> _fetchFootballTeamRollingStats(String teamId, String leagueSlug) async {
    final cacheKey = 'football_rolling:$leagueSlug:$teamId';
    if (_rollingCache.containsKey(cacheKey)) {
      return _rollingCache[cacheKey] as ({
        double? last3Avg,
        double? last5Avg,
        double? last3Conceded,
        double? last5Conceded,
        List<String> recentScores,
      })?;
    }

    try {
      final url = '$_base/soccer/$leagueSlug/teams/$teamId/schedule?limit=15';
      final resp = await _httpGetWithRetry(Uri.parse(url), timeout: const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        _rollingCache[cacheKey] = null;
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final events = (data['events'] as List<dynamic>?) ?? [];

      final teamScores = <double>[];
      final oppScores = <double>[];
      final scoreStrings = <String>[];

      for (final raw in events.reversed) {
        final e = raw as Map<String, dynamic>;
        final comp = (e['competitions'] as List?)?.first as Map<String, dynamic>?;
        if (comp == null) continue;
        final state = ((comp['status'] as Map<String, dynamic>?)?['type'] as Map<String, dynamic>?)?['state'] as String? ?? '';
        if (state != 'post') continue;

        final competitors = (comp['competitors'] as List?) ?? [];
        double? myScore;
        double? opponentScore;
        String opponentName = '';
        for (final c in competitors) {
          final cm = c as Map<String, dynamic>;
          final rawS = cm['score'];
          final score = rawS is num ? rawS.toDouble() : double.tryParse(rawS?.toString() ?? '');
          final teamObj = cm['team'] as Map<String, dynamic>?;
          if (teamObj?['id'] == teamId) {
            myScore = score;
          } else {
            opponentScore = score;
            final rawName = teamObj?['displayName'] as String? ?? teamObj?['name'] as String? ?? '';
            opponentName = _translateTeamBySlug(rawName, leagueSlug);
          }
        }
        if (myScore == null || opponentScore == null) continue;

        teamScores.add(myScore);
        oppScores.add(opponentScore);
        final ms = myScore.toInt();
        final os = opponentScore.toInt();
        scoreStrings.add(opponentName.isNotEmpty ? '$ms-$os $opponentName' : '$ms-$os');
        if (teamScores.length >= 10) break;
      }

      if (teamScores.isEmpty) {
        _rollingCache[cacheKey] = null;
        return null;
      }

      double? last3Avg;
      double? last5Avg;
      double? last3Conceded;
      double? last5Conceded;

      if (teamScores.length >= 3) {
        last3Avg = teamScores.take(3).reduce((a, b) => a + b) / 3;
        last3Conceded = oppScores.take(3).reduce((a, b) => a + b) / 3;
      }
      if (teamScores.length >= 5) {
        last5Avg = teamScores.take(5).reduce((a, b) => a + b) / 5;
        last5Conceded = oppScores.take(5).reduce((a, b) => a + b) / 5;
      }

      final result = (
        last3Avg: last3Avg,
        last5Avg: last5Avg,
        last3Conceded: last3Conceded,
        last5Conceded: last5Conceded,
        recentScores: scoreStrings,
      );
      _rollingCache[cacheKey] = result;
      return result;
    } catch (_) {
      _rollingCache[cacheKey] = null;
      return null;
    }
  }

  /// 從 ESPN event summary API 抓取 H2H 對戰記錄與 ESPN 預測主隊勝率
  /// 回傳 (homeWins, awayWins, draws, avgGoals, espnHomePct)，失敗時回傳全零
  static Future<(int, int, int, double, double)> _fetchEventSummary(
    String eventId, SportType sport, String leagueSlug,
  ) async {
    if (_summaryCache.containsKey(eventId)) return _summaryCache[eventId]!;

    try {
      final String url;
      switch (sport) {
        case SportType.football:
          url = '$_base/soccer/$leagueSlug/summary?event=$eventId';
          break;
        case SportType.basketball:
          url = '$_base/basketball/nba/summary?event=$eventId';
          break;
        case SportType.baseball:
          url = '$_base/baseball/mlb/summary?event=$eventId';
          break;
      }

      final resp = await _httpGetWithRetry(
        Uri.parse(url),
        timeout: const Duration(seconds: 8),
      );
      if (resp.statusCode != 200) {
        _summaryCache[eventId] = (0, 0, 0, 0.0, 0.0);
        return (0, 0, 0, 0.0, 0.0);
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      // H2H 對戰記錄
      int homeWins = 0;
      int awayWins = 0;
      int draws = 0;
      final h2h = data['headToHead'] as Map<String, dynamic>?;
      if (h2h != null) {
        homeWins = (h2h['homeWins'] as num?)?.toInt() ?? 0;
        awayWins = (h2h['awayWins'] as num?)?.toInt() ?? 0;
        draws = (h2h['ties'] as num?)?.toInt() ??
                (h2h['draws'] as num?)?.toInt() ?? 0;
      }

      // ESPN Predictor 主隊勝率
      double espnHomePct = 0.0;
      final predictor = data['predictor'] as Map<String, dynamic>?;
      if (predictor != null) {
        final homeTeamPred = predictor['homeTeam'] as Map<String, dynamic>?;
        final projStr = homeTeamPred?['gameProjection'] as String?;
        if (projStr != null) {
          final proj = double.tryParse(projStr) ?? 0.0;
          espnHomePct = (proj / 100.0).clamp(0.0, 1.0);
        }
      }

      // avgGoals：足球時從 H2H 比賽記錄計算，其他運動為 0.0
      double avgGoals = 0.0;
      if (sport == SportType.football && h2h != null) {
        final matches = h2h['competitions'] as List<dynamic>?;
        if (matches != null && matches.isNotEmpty) {
          double totalGoals = 0.0;
          int count = 0;
          for (final m in matches) {
            if (m is! Map<String, dynamic>) continue;
            final comps = (m['competitors'] as List<dynamic>?) ?? const [];
            double gameGoals = 0.0;
            for (final c in comps) {
              if (c is! Map<String, dynamic>) continue;
              final rawG = c['score'];
              final goals = rawG is num ? rawG.toDouble()
                  : rawG is Map ? (rawG['value'] as num?)?.toDouble() ?? 0
                  : double.tryParse(rawG?.toString() ?? '') ?? 0;
              gameGoals += goals;
            }
            totalGoals += gameGoals;
            count++;
          }
          if (count > 0) avgGoals = totalGoals / count;
        }
      }

      final result = (homeWins, awayWins, draws, avgGoals, espnHomePct);
      _summaryCache[eventId] = result;
      return result;
    } catch (_) {
      _summaryCache[eventId] = (0, 0, 0, 0.0, 0.0);
      return (0, 0, 0, 0.0, 0.0);
    }
  }

  // ── 公開分析方法（供 MatchAnalysisScreen 使用）──────────────────────

  /// 取得球隊延伸統計（控球率/射門/角球/黃紅牌等），失敗時回傳空 Map
  static Future<Map<String, double>> fetchTeamExtendedStats(
    String teamId,
    SportType sport,
    String leagueSlug,
  ) async {
    if (teamId.isEmpty) return {};
    final cacheKey = 'ext:${sport.name}:$leagueSlug:$teamId';
    if (_rollingCache.containsKey(cacheKey)) {
      return (_rollingCache[cacheKey] as Map<String, double>?) ?? {};
    }
    try {
      final String path;
      switch (sport) {
        case SportType.football:
          if (leagueSlug.isEmpty) { _rollingCache[cacheKey] = <String, double>{}; return {}; }
          path = 'soccer/$leagueSlug/teams/$teamId/statistics';
          break;
        case SportType.basketball:
          path = 'basketball/nba/teams/$teamId/statistics';
          break;
        case SportType.baseball:
          path = 'baseball/mlb/teams/$teamId/statistics';
          break;
      }
      final resp = await _httpGetWithRetry(
        Uri.parse('$_base/$path'),
        timeout: const Duration(seconds: 6),
      );
      if (resp.statusCode != 200) { _rollingCache[cacheKey] = <String, double>{}; return {}; }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final stats = <String, double>{};
      // ESPN splits.categories[].stats[]
      final splits = data['splits'] as Map<String, dynamic>?;
      final categories = (splits?['categories'] as List<dynamic>?) ?? [];
      for (final cat in categories) {
        if (cat is! Map<String, dynamic>) continue;
        for (final s in (cat['stats'] as List<dynamic>?) ?? []) {
          if (s is! Map<String, dynamic>) continue;
          final name = s['name'] as String? ?? s['abbreviation'] as String? ?? '';
          final val = (s['value'] as num?)?.toDouble()
              ?? double.tryParse(s['displayValue']?.toString() ?? '');
          if (name.isNotEmpty && val != null) stats[name] = val;
        }
      }
      // Also check top-level results array
      for (final r in (data['results'] as List<dynamic>?) ?? []) {
        if (r is! Map<String, dynamic>) continue;
        final name = r['abbreviation'] as String? ?? r['name'] as String? ?? '';
        final val = (r['value'] as num?)?.toDouble()
            ?? double.tryParse(r['summary']?.toString() ?? '');
        if (name.isNotEmpty && val != null) stats[name] = val;
      }
      _rollingCache[cacheKey] = stats;
      return stats;
    } catch (_) {
      _rollingCache[cacheKey] = <String, double>{};
      return {};
    }
  }

  /// 取得球隊近期比賽詳情（對手名稱 + 比分 + 日期）
  /// 回傳列表：每項為 {opponent, teamScore, oppScore, isHome, date, result}
  static Future<List<Map<String, dynamic>>> fetchTeamRecentMatchDetails(
    String teamId,
    SportType sport,
    String leagueSlug, {
    int limit = 5,
  }) async {
    if (teamId.isEmpty) return [];
    final cacheKey = 'recent_detail:${sport.name}:$leagueSlug:$teamId';
    if (_rollingCache.containsKey(cacheKey)) {
      return (_rollingCache[cacheKey] as List<Map<String, dynamic>>?) ?? [];
    }
    try {
      final String path;
      switch (sport) {
        case SportType.football:
          if (leagueSlug.isEmpty) { _rollingCache[cacheKey] = <Map<String, dynamic>>[]; return []; }
          path = 'soccer/$leagueSlug/teams/$teamId/schedule?limit=15';
          break;
        case SportType.basketball:
          path = 'basketball/nba/teams/$teamId/schedule?limit=15';
          break;
        case SportType.baseball:
          path = 'baseball/mlb/teams/$teamId/schedule?limit=15';
          break;
      }
      final resp = await _httpGetWithRetry(
        Uri.parse('$_base/$path'),
        timeout: const Duration(seconds: 6),
      );
      if (resp.statusCode != 200) { _rollingCache[cacheKey] = <Map<String, dynamic>>[]; return []; }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final events = (data['events'] as List<dynamic>?) ?? [];
      final results = <Map<String, dynamic>>[];
      for (final raw in events.reversed) {
        final e = raw as Map<String, dynamic>;
        final comp = (e['competitions'] as List?)?.first as Map<String, dynamic>?;
        if (comp == null) continue;
        final state = ((comp['status'] as Map<String, dynamic>?)?['type'] as Map<String, dynamic>?)?['state'] as String? ?? '';
        if (state != 'post') continue;
        final competitors = (comp['competitors'] as List?) ?? [];
        String opponent = '';
        int? teamScore;
        int? oppScore;
        bool isHome = false;
        String result = '';
        for (final c in competitors) {
          final cm = c as Map<String, dynamic>;
          final teamObj = cm['team'] as Map<String, dynamic>?;
          final id = teamObj?['id'] as String? ?? '';
          final name = teamObj?['displayName'] as String? ?? teamObj?['shortDisplayName'] as String? ?? '';
          final rawScore = cm['score'];
          final int? score;
          if (rawScore is num) {
            score = rawScore.toInt();
          } else if (rawScore is Map<String, dynamic>) {
            score = (rawScore['value'] as num?)?.toInt();
          } else {
            score = double.tryParse(rawScore?.toString() ?? '')?.toInt();
          }
          if (id == teamId) {
            teamScore = score;
            isHome = cm['homeAway'] == 'home';
            result = cm['winner'] == true ? '勝' : (sport == SportType.football ? '平' : '負');
          } else {
            opponent = name;
            oppScore = score;
          }
        }
        if (opponent.isEmpty || teamScore == null || oppScore == null) continue;
        // Draw in football: same score
        if (sport == SportType.football && teamScore != oppScore) {
          result = teamScore > oppScore ? '勝' : '負';
        } else if (sport == SportType.football && teamScore == oppScore) {
          result = '平';
        }
        // Date
        final dateStr = e['date'] as String? ?? '';
        String displayDate = '';
        if (dateStr.isNotEmpty) {
          final dt = DateTime.tryParse(dateStr);
          if (dt != null) {
            final local = dt.toLocal();
            displayDate = '${local.month}/${local.day}';
          }
        }
        results.add({
          'opponent': opponent,
          'teamScore': teamScore,
          'oppScore': oppScore,
          'isHome': isHome,
          'date': displayDate,
          'result': result,
        });
        if (results.length >= limit) break;
      }
      _rollingCache[cacheKey] = results;
      return results;
    } catch (_) {
      _rollingCache[cacheKey] = <Map<String, dynamic>>[];
      return [];
    }
  }

  /// 從 ESPN summary 取得 H2H 對戰詳情（主客隊名、比分、日期）
  static Future<List<Map<String, dynamic>>> fetchH2HMatchDetails(
    String eventId,
    SportType sport,
    String leagueSlug,
  ) async {
    if (eventId.isEmpty) return [];
    final cacheKey = 'h2h_detail:$eventId';
    if (_rollingCache.containsKey(cacheKey)) {
      return (_rollingCache[cacheKey] as List<Map<String, dynamic>>?) ?? [];
    }
    try {
      final String url;
      switch (sport) {
        case SportType.football:
          if (leagueSlug.isEmpty) { _rollingCache[cacheKey] = <Map<String, dynamic>>[]; return []; }
          url = '$_base/soccer/$leagueSlug/summary?event=$eventId';
          break;
        case SportType.basketball:
          url = '$_base/basketball/nba/summary?event=$eventId';
          break;
        case SportType.baseball:
          url = '$_base/baseball/mlb/summary?event=$eventId';
          break;
      }
      final resp = await _httpGetWithRetry(Uri.parse(url), timeout: const Duration(seconds: 8));
      if (resp.statusCode != 200) { _rollingCache[cacheKey] = <Map<String, dynamic>>[]; return []; }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final h2h = data['headToHead'] as Map<String, dynamic>?;
      if (h2h == null) { _rollingCache[cacheKey] = <Map<String, dynamic>>[]; return []; }
      final matches = (h2h['competitions'] as List<dynamic>?) ?? [];
      final results = <Map<String, dynamic>>[];
      for (final m in matches) {
        if (m is! Map<String, dynamic>) continue;
        final competitors = (m['competitors'] as List<dynamic>?) ?? [];
        String home = '', away = '';
        int homeScore = 0, awayScore = 0;
        for (final c in competitors) {
          if (c is! Map<String, dynamic>) continue;
          final teamObj = c['team'] as Map<String, dynamic>?;
          final name = teamObj?['displayName'] as String? ?? teamObj?['shortDisplayName'] as String? ?? '';
          final rawC = c['score'];
          final score = rawC is num ? rawC.toInt()
              : rawC is Map ? (rawC['value'] as num?)?.toInt() ?? 0
              : double.tryParse(rawC?.toString() ?? '')?.toInt() ?? 0;
          if (c['homeAway'] == 'home') { home = name; homeScore = score; }
          else { away = name; awayScore = score; }
        }
        final dateStr = m['date'] as String? ?? '';
        String displayDate = '';
        if (dateStr.isNotEmpty) {
          final dt = DateTime.tryParse(dateStr);
          if (dt != null) displayDate = '${dt.year}/${dt.month}/${dt.day}';
        }
        if (home.isNotEmpty) results.add({'home': home, 'away': away, 'homeScore': homeScore, 'awayScore': awayScore, 'date': displayDate});
        if (results.length >= 5) break;
      }
      _rollingCache[cacheKey] = results;
      return results;
    } catch (_) {
      _rollingCache[cacheKey] = <Map<String, dynamic>>[];
      return [];
    }
  }

  /// 透過掃描主隊賽程找出兩隊 H2H 歷史對戰（當 ESPN summary 無 headToHead 時的備援方案）
  /// 回傳列表：{home, away, homeScore, awayScore, date, fixtureHomeWon (bool)}
  static Future<List<Map<String, dynamic>>> fetchH2HFromSchedules(
    String homeTeamId,
    String awayTeamId,
    SportType sport,
    String leagueSlug,
  ) async {
    if (homeTeamId.isEmpty || awayTeamId.isEmpty) return [];
    final cacheKey = 'h2h_sched:${sport.name}:$homeTeamId:$awayTeamId';
    if (_rollingCache.containsKey(cacheKey)) {
      return (_rollingCache[cacheKey] as List<Map<String, dynamic>>?) ?? [];
    }
    try {
      final String path;
      switch (sport) {
        case SportType.football:
          if (leagueSlug.isEmpty) { _rollingCache[cacheKey] = <Map<String, dynamic>>[]; return []; }
          path = 'soccer/$leagueSlug/teams/$homeTeamId/schedule?limit=40';
          break;
        case SportType.basketball:
          path = 'basketball/nba/teams/$homeTeamId/schedule?limit=40';
          break;
        case SportType.baseball:
          path = 'baseball/mlb/teams/$homeTeamId/schedule?limit=40';
          break;
      }
      final resp = await _httpGetWithRetry(
        Uri.parse('$_base/$path'),
        timeout: const Duration(seconds: 8),
      );
      if (resp.statusCode != 200) { _rollingCache[cacheKey] = <Map<String, dynamic>>[]; return []; }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final events = (data['events'] as List<dynamic>?) ?? [];
      final results = <Map<String, dynamic>>[];

      for (final raw in events.reversed) {
        final e = raw as Map<String, dynamic>;
        final comp = (e['competitions'] as List?)?.first as Map<String, dynamic>?;
        if (comp == null) continue;
        final state = ((comp['status'] as Map<String, dynamic>?)?['type'] as Map<String, dynamic>?)?['state'] as String? ?? '';
        if (state != 'post') continue;

        final competitors = (comp['competitors'] as List?) ?? [];
        if (competitors.length < 2) continue;

        bool hasHome = false, hasAway = false;
        String homeName = '', awayName = '';
        int homeScore = 0, awayScore = 0;
        bool fixtureHomeTeamWasHome = false;

        for (final c in competitors) {
          final cm = c as Map<String, dynamic>;
          final teamObj = cm['team'] as Map<String, dynamic>?;
          final id = teamObj?['id'] as String? ?? '';
          final name = teamObj?['displayName'] as String? ?? teamObj?['shortDisplayName'] as String? ?? '';
          final rawScore = cm['score'];
          final score = rawScore is num
              ? rawScore.toInt()
              : (double.tryParse(rawScore?.toString() ?? '')?.toInt() ?? 0);
          final isHomeInGame = cm['homeAway'] == 'home';

          if (id == homeTeamId) {
            hasHome = true;
            fixtureHomeTeamWasHome = isHomeInGame;
            if (isHomeInGame) { homeName = name; homeScore = score; }
            else { awayName = name; awayScore = score; }
          } else if (id == awayTeamId) {
            hasAway = true;
            if (isHomeInGame) { homeName = name; homeScore = score; }
            else { awayName = name; awayScore = score; }
          }
        }

        if (!hasHome || !hasAway) continue;

        // Determine winner from fixture perspective
        final String result;
        if (homeScore == awayScore) {
          result = '平';
        } else {
          final fixtureHomeScored = fixtureHomeTeamWasHome ? homeScore : awayScore;
          final fixtureAwaySored = fixtureHomeTeamWasHome ? awayScore : homeScore;
          result = fixtureHomeScored > fixtureAwaySored ? '主勝' : '客勝';
        }

        final dateStr = e['date'] as String? ?? '';
        String displayDate = '';
        if (dateStr.isNotEmpty) {
          final dt = DateTime.tryParse(dateStr);
          if (dt != null) displayDate = '${dt.year}/${dt.month}/${dt.day}';
        }

        results.add({
          'home': homeName,
          'away': awayName,
          'homeScore': homeScore,
          'awayScore': awayScore,
          'date': displayDate,
          'fixtureHomeWon': result == '主勝',
          'result': result,
        });
        if (results.length >= 5) break;
      }

      _rollingCache[cacheKey] = results;
      return results;
    } catch (_) {
      _rollingCache[cacheKey] = <Map<String, dynamic>>[];
      return [];
    }
  }

  /// 取得足球聯賽 ESPN API slug（供分析畫面傳入 fetchTeamExtendedStats）
  static String? soccerSlugFromLeague(String league) => _soccerSlugFromLeague(league);

  /// 根據 MatchFixture 組成的 ESPN event ID（去掉 "espn_" 前綴）
  static String eventIdFromFixture(String fixtureId) =>
      fixtureId.startsWith('espn_') ? fixtureId.substring(5) : fixtureId;

  /// 根據真實勝敗平數計算近 N 場 W/D/L
  /// 邏輯：依照近期實際趨勢分配，若連勝則顯示連勝，若連敗則顯示連敗
  static List<String> _simulateRecentResults(
    double winRate,
    SportType sport,
    int sampleCount,
  ) {
    final allowDraw = sport == SportType.football;
    final results = <String>[];

    // 用 winRate 決定近 N 場的勝平負分布
    // 高勝率 (>0.7) → 多勝；低勝率 (<0.3) → 多敗；中間 → 混合
    final wins = (winRate * sampleCount).round().clamp(0, sampleCount);
    final losses = sampleCount - wins;

    if (allowDraw) {
      // 足球：有平局可能
      final drawCount = sampleCount >= 4 && wins > 0 && losses > 0 ? 1 : 0;
      final wCount = wins - (drawCount > 0 && wins > losses ? 1 : 0);
      final lCount = sampleCount - wCount - drawCount;
      final raw = [
        ...List.filled(wCount.clamp(0, sampleCount), '勝'),
        ...List.filled(drawCount, '平'),
        ...List.filled(lCount.clamp(0, sampleCount), '負'),
      ];
      // 按趨勢排列：近期靠前（若高勝率，好結果放前面；低勝率，差結果放前面）
      if (winRate >= 0.5) {
        results.addAll(raw.reversed);
      } else {
        results.addAll(raw);
      }
    } else {
      // 棒球/籃球：只有 W/L
      final raw = [
        ...List.filled(wins, '勝'),
        ...List.filled(losses, '負'),
      ];
      if (winRate >= 0.5) {
        results.addAll(raw.reversed); // 最近的勝場放前面
      } else {
        results.addAll(raw);
      }
    }

    return results.take(sampleCount).toList();
  }

  /// 從 seasonRecord (格式如 "7-8-11") 提取歷史和局率
  static double _getHistoricalDrawRate(String record) {
    if (record.isEmpty) return 0.26; // 足球平均和局率預設值
    final parts = record.split('-');
    if (parts.length < 3) return 0.26;
    
    final w = double.tryParse(parts[0]) ?? 0;
    final d = double.tryParse(parts[1]) ?? 0;
    final l = double.tryParse(parts[2]) ?? 0;
    final total = w + d + l;
    return total > 5 ? (d / total).clamp(0.15, 0.40) : 0.26;
  }

  /// 美式賠率字串 → 歐式小數賠率（例："-145" → 1.69，"+390" → 4.90）
  static double _usOddsToDecimal(String? s) {
    if (s == null || s.isEmpty) return 0.0;
    final ml = int.tryParse(s.replaceAll('+', ''));
    if (ml == null || ml == 0) return 0.0;
    final dec = ml < 0 ? 1.0 + 100.0 / ml.abs() : 1.0 + ml / 100.0;
    return double.parse(dec.toStringAsFixed(2));
  }

  static OddsSnapshot _parseOdds(
    Map<String, dynamic> competition,
    TeamForm homeForm,
    TeamForm awayForm,
    SportType sport,
  ) {
    // ── 優先讀取 ESPN competition['odds']（DraftKings 真實盤口）──────
    final oddsList = (competition['odds'] as List<dynamic>?) ?? [];
    if (oddsList.isNotEmpty) {
      final o = oddsList.first as Map<String, dynamic>;
      final ml     = (o['moneyline']    as Map<String, dynamic>?) ?? {};
      final total  = (o['total']        as Map<String, dynamic>?) ?? {};
      final spd    = (o['pointSpread']  as Map<String, dynamic>?) ?? {};
      final drawOm = o['drawOdds']      as Map<String, dynamic>?;
      final provider = ((o['provider'] as Map<String, dynamic>?)?['name'] as String?) ?? 'ESPN';

      String? closeOdds(Map<String, dynamic> side, String key) =>
          ((side[key] as Map<String, dynamic>?)?['close'] as Map<String, dynamic>?)?['odds'] as String?;
      String? closeLine(Map<String, dynamic> side, String key) =>
          ((side[key] as Map<String, dynamic>?)?['close'] as Map<String, dynamic>?)?['line'] as String?;
      String? openOdds(Map<String, dynamic> side, String key) =>
          ((side[key] as Map<String, dynamic>?)?['open'] as Map<String, dynamic>?)?['odds'] as String?;

      final homeWin = _usOddsToDecimal(closeOdds(ml, 'home'));
      final awayWin = _usOddsToDecimal(closeOdds(ml, 'away'));

      if (homeWin > 1.0 && awayWin > 1.0) {
        // 足球和局賠率
        final drawML  = (drawOm?['moneyLine'] as num?)?.toInt();
        final drawDec = drawML != null
            ? _usOddsToDecimal(drawML > 0 ? '+$drawML' : '$drawML')
            : (sport == SportType.football ? 3.30 : 99.0);

        // 讓分盤：ESPN home spread 負=主場讓分(主場優)，我們的約定正=主場讓分 → 乘 -1
        final homeSpreadLineStr = closeLine(spd, 'home');
        final espnSpread = homeSpreadLineStr != null
            ? (double.tryParse(homeSpreadLineStr.replaceAll('+', '')) ?? 0.0)
            : 0.0;
        final ourSpread       = -espnSpread;
        final homeSpreadOdds  = _usOddsToDecimal(closeOdds(spd, 'home'));
        final awaySpreadOdds  = _usOddsToDecimal(closeOdds(spd, 'away'));

        // 大小分
        final overLine  = (o['overUnder'] as num?)?.toDouble() ?? 0.0;
        final overOdds  = _usOddsToDecimal(
            ((total['over']  as Map?)?['close'] as Map?)?['odds'] as String?);
        final underOdds = _usOddsToDecimal(
            ((total['under'] as Map?)?['close'] as Map?)?['odds'] as String?);

        // 初盤（用於市場移動偵測）
        final openHome = _usOddsToDecimal(openOdds(ml, 'home'));
        final openAway = _usOddsToDecimal(openOdds(ml, 'away'));

        return OddsSnapshot(
          homeWin: homeWin,
          draw: drawDec,
          awayWin: awayWin,
          overLine: overLine,
          overOdds: overOdds > 1.0 ? overOdds : 1.91,
          underOdds: underOdds > 1.0 ? underOdds : 1.91,
          bookmakerName: provider,
          spread: ourSpread,
          homeSpreadOdds: homeSpreadOdds > 1.0 ? homeSpreadOdds : 1.91,
          awaySpreadOdds: awaySpreadOdds > 1.0 ? awaySpreadOdds : 1.91,
          isFromBookmaker: true,
          openingHomeWin: openHome > 1.0 ? openHome : 0.0,
          openingDraw: 0.0,
          openingAwayWin: openAway > 1.0 ? openAway : 0.0,
        );
      }
    }

    // ── 備援：模型推算（無真實盤口時）──────────────────────────────
    final homeWR = (homeForm.momentumScore / 20.0 + 0.5).clamp(0.20, 0.80);
    final awayWR = (awayForm.momentumScore / 20.0 + 0.5).clamp(0.20, 0.80);

    double drawProb = 0.0;
    if (sport == SportType.football) {
      final historicalRate = (_getHistoricalDrawRate(homeForm.seasonRecord) +
                             _getHistoricalDrawRate(awayForm.seasonRecord)) / 2;
      final parityFactor = (0.35 - (homeWR - awayWR).abs() * 0.45).clamp(0.12, 0.38);
      drawProb = (historicalRate * 0.4 + parityFactor * 0.6).clamp(0.15, 0.45);
    }

    final homeAdv = sport == SportType.baseball ? 0.035
        : sport == SportType.basketball ? 0.030
        : 0.040;
    final remainingProb = 1.0 - drawProb;
    final strengthRatio = homeWR / (homeWR + awayWR);
    final homeWinProb = (strengthRatio * remainingProb + homeAdv).clamp(0.05, 0.90);
    final awayWinProb = (remainingProb - (homeWinProb - homeAdv)).clamp(0.05, 0.90);

    return OddsSnapshot(
      homeWin: double.parse((1.0 / homeWinProb).toStringAsFixed(2)),
      draw: sport == SportType.football
          ? double.parse((1.0 / drawProb).toStringAsFixed(2))
          : 99.0,
      awayWin: double.parse((1.0 / awayWinProb).toStringAsFixed(2)),
      overLine: 0.0,
      overOdds: 1.91,
      underOdds: 1.91,
      bookmakerName: '模型推算',
      spread: 0.0,
      homeSpreadOdds: 1.91,
      awaySpreadOdds: 1.91,
      isFromBookmaker: false,
    );
  }

  static MatchStatus _parseStatus(String statusName, [String state = '']) {
    // ESPN state 是最可靠的指標：'in' = 進行中，'post' = 已完賽，'pre' = 未開始
    if (state == 'in') return MatchStatus.live;
    if (state == 'post') return MatchStatus.completed;
    // 備援：用 name 字串判斷（state 欄位缺失時）
    switch (statusName) {
      case 'STATUS_IN_PROGRESS':
      case 'STATUS_HALFTIME':
      case 'STATUS_EXTRA_TIME':
      case 'STATUS_PENALTY':
      case 'STATUS_END_PERIOD':
      case 'STATUS_OT':
      case 'STATUS_2ND_OT':
        return MatchStatus.live;
      case 'STATUS_FINAL':
      case 'STATUS_FULL_TIME':
      case 'STATUS_FINAL_OT':
      case 'STATUS_FINAL_PEN':
        return MatchStatus.completed;
      case 'STATUS_POSTPONED':
      case 'STATUS_CANCELED':
      case 'STATUS_SUSPENDED':
        return MatchStatus.postponed;
      default:
        return MatchStatus.scheduled;
    }
  }

  static SportType _sportFromLeague(String league) {
    if (league == '美職棒') return SportType.baseball;
    if (league == 'NBA') return SportType.basketball;
    return SportType.football;
  }

  static String _statDisplay(List<dynamic> stats, String abbr) {
    for (final s in stats) {
      final m = s as Map<String, dynamic>;
      if ((m['abbreviation'] as String?) == abbr) {
        return (m['displayValue'] as String?) ?? '';
      }
    }
    return '';
  }

  /// 將 UTC 時間轉換為台灣中原標準時間（UTC+8）
  static DateTime? _toTaiwanTime(DateTime? utc) {
    if (utc == null) return null;
    final utcTime = utc.isUtc ? utc : utc.toUtc();
    return utcTime.add(const Duration(hours: 8));
  }

  // ── 足球聯賽 slug 對照 ────────────────────────────────────────
  static const _soccerLeagueSlugs = {
    '英超': 'eng.1',
    '西甲': 'esp.1',
    '德甲': 'ger.1',
    '意甲': 'ita.1',
    '法甲': 'fra.1',
    '日職': 'jpn.1',
    '葡超': 'por.1',
    '荷甲': 'ned.1',
    '澳超': 'aus.1',
    '歐冠': 'uefa.champions',
    '世界盃': 'fifa.world',
    '世預歐洲': 'fifa.worldq.uefa',
    '世預南美': 'fifa.worldq.conmebol',
    '世預亞洲': 'fifa.worldq.afc',
    '世預北美': 'fifa.worldq.concacaf',
    '世預非洲': 'fifa.worldq.caf',
  };

  static String? soccerSlugForLeague(String league) =>
      _soccerLeagueSlugs[league];

  /// ── 備用回退方法：ESPN 查不到資料時的最小化 Soccer 詳情 ──
  /// 返回空名單 + 傷兵清空，模型會自動應用 8% 備用缺席削減
  static SoccerGameDetail _buildFallbackSoccerDetail() => SoccerGameDetail(
    homeRecord: 'N/A',
    awayRecord: 'N/A',
    homeStreak: '',
    awayStreak: '',
    homeFirstHalf: -1,
    awayFirstHalf: -1,
    homeSecondHalf: -1,
    awaySecondHalf: -1,
    homeLineup: const [],  // 空先發 → 觸發 8% 缺席削減
    awayLineup: const [],
    injuries: const [],
    suspensions: const [],
    homeTeamStats: const {},
    awayTeamStats: const {},
    situationDescription: '',
    situationTeam: '',
    events: const [],
  );

  /// 從 ESPN 名單端點抓取完整名單，對比本場出賽名單，找出缺席球員
  static Future<List<BaseballInjury>> _fetchAbsentPlayers(
      String leagueSlug,
      String teamId,
      String teamName,
      Set<String> matchSquadIds) async {
    if (matchSquadIds.isEmpty) return const []; // 名單尚未公布
    try {
      final url = '$_base/soccer/$leagueSlug/teams/$teamId/roster';
      final resp = await _httpGetWithRetry(Uri.parse(url));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final athletes = (data['athletes'] as List<dynamic>?) ?? const [];
      final results = <BaseballInjury>[];
      for (final p in athletes) {
        if (p is! Map<String, dynamic>) continue;
        final id = p['id']?.toString() ?? '';
        final name = p['displayName'] as String? ?? p['fullName'] as String? ?? '';
        if (name.isEmpty || id.isEmpty) continue;
        if (matchSquadIds.contains(id)) continue; // 已在比賽名單
        final pos = (p['position'] as Map<String, dynamic>?)?['abbreviation'] as String? ?? '';
        // 取得球員 injuries / status
        final injList = (p['injuries'] as List<dynamic>?) ?? const [];
        final status = (p['status'] as Map<String, dynamic>?);
        final statusType = status?['type'] as String? ?? 'active';
        String injDesc = '';
        String injStatus = '未入選';
        if (injList.isNotEmpty) {
          final inj0 = injList.first as Map<String, dynamic>? ?? {};
          final typeMap = inj0['type'] as Map<String, dynamic>? ?? {};
          injDesc = typeMap['description'] as String? ?? inj0['longComment'] as String? ?? '';
          injStatus = inj0['status'] as String? ?? '傷兵';
        } else if (statusType != 'active') {
          injStatus = statusType == 'day-to-day' ? '每日觀察' : statusType;
        }
        results.add(BaseballInjury(
          playerName: '$name${pos.isNotEmpty ? " ($pos)" : ""}',
          team: teamName,
          status: injStatus,
          description: injDesc.isNotEmpty ? injDesc : '未入選本場比賽名單',
        ));
      }
      return results;
    } catch (e) {
      return const [];
    }
  }

  /// 抓取足球賽事 summary（先發名單 + 傷兵 + 即時數據）
  /// 若 ESPN 查不到 → 嘗試備用快取或簡化估計
  static Future<SoccerGameDetail?> fetchSoccerSummary(
      String espnEventId, String leagueSlug) async {
    try {
      final url =
          '$_base/soccer/$leagueSlug/summary?event=$espnEventId';
      final response = await _httpGetWithRetry(Uri.parse(url), timeout: const Duration(seconds: 12));

      if (response.statusCode != 200) {
        // ── ESPN 查不到時的備用："缺先發數據" → 返回輕度警示，但不崩潰 ──
        return _buildFallbackSoccerDetail();
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // ── Team records + half-time scores from header ──────────────
      final headerComp =
          ((data['header'] as Map<String, dynamic>?)?['competitions']
                  as List<dynamic>?)
              ?.firstOrNull;
      final compTeams =
          (headerComp as Map<String, dynamic>?)?['competitors']
              as List<dynamic>? ??
          const [];

      final homeAwayByTeamId = <String, String>{};
      final teamNameById = <String, String>{};
      String homeRecord = '', awayRecord = '';
      String homeStreak = '', awayStreak = '';
      int homeFirstHalf = -1, awayFirstHalf = -1;
      int homeSecondHalf = -1, awaySecondHalf = -1;
      String homeTeamName = '', awayTeamName = '';

      for (final c in compTeams) {
        if (c is! Map<String, dynamic>) continue;
        final team = c['team'] as Map<String, dynamic>? ?? {};
        final id = team['id'] as String? ?? '';
        final displayName = _translateTeamBySlug(
            team['displayName'] as String? ?? '', leagueSlug);
        final homeAway = c['homeAway'] as String? ?? '';
        if (id.isNotEmpty) {
          homeAwayByTeamId[id] = homeAway;
          teamNameById[id] = displayName;
        }

        final records = (c['records'] as List<dynamic>?) ?? const [];
        String record = '';
        for (final r in records) {
          final rMap = r as Map<String, dynamic>;
          if (rMap['type'] == 'total') record = rMap['summary'] as String? ?? '';
        }
        final streak = _translateStreak(
            (c['streak'] as Map<String, dynamic>?)?['shortDisplayName']
                as String? ?? '');
        final linescores = (c['linescores'] as List<dynamic>?) ?? const [];

        if (homeAway == 'home') {
          homeRecord = record;
          homeStreak = streak;
          homeTeamName = displayName;
          if (linescores.isNotEmpty) {
            homeFirstHalf = int.tryParse(
                    linescores[0]['displayValue']?.toString() ?? '') ??
                -1;
          }
          if (linescores.length > 1) {
            homeSecondHalf = int.tryParse(
                    linescores[1]['displayValue']?.toString() ?? '') ??
                -1;
          }
        } else if (homeAway == 'away') {
          awayRecord = record;
          awayStreak = streak;
          awayTeamName = displayName;
          if (linescores.isNotEmpty) {
            awayFirstHalf = int.tryParse(
                    linescores[0]['displayValue']?.toString() ?? '') ??
                -1;
          }
          if (linescores.length > 1) {
            awaySecondHalf = int.tryParse(
                    linescores[1]['displayValue']?.toString() ?? '') ??
                -1;
          }
        }
      }

      // ── Situation（即時進攻方）─────────────────────────────────
      String situationDescription = '';
      String situationTeam = ''; // 'home', 'away', or ''
      final situation = data['situation'] as Map<String, dynamic>?;
      if (situation != null) {
        situationDescription = situation['description'] as String? ?? '';
        final posTeam =
            situation['possession'] as Map<String, dynamic>?;
        final posTeamId = posTeam?['id'] as String? ?? '';
        if (posTeamId.isNotEmpty) {
          situationTeam = homeAwayByTeamId[posTeamId] ?? '';
        }
        // Fallback: parse description for team name
        if (situationTeam.isEmpty && situationDescription.isNotEmpty) {
          situationTeam = 'unknown';
        }
      }

      // ── Rosters（先發名單）────────────────────────────────────
      final rosters = (data['rosters'] as List<dynamic>?) ?? const [];
      List<SoccerPlayer> homeLineup = [];
      List<SoccerPlayer> awayLineup = [];

      for (final r in rosters) {
        if (r is! Map<String, dynamic>) continue;
        final teamId =
            (r['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
        final homeAway = homeAwayByTeamId[teamId];
        final entries = (r['roster'] as List<dynamic>?) ?? const [];
        final starters = <SoccerPlayer>[];
        final subs = <SoccerPlayer>[];

        for (final e in entries) {
          if (e is! Map<String, dynamic>) continue;
          final ath = e['athlete'] as Map<String, dynamic>? ?? {};
          final statsRaw = (e['stats'] as List<dynamic>?) ?? const [];
          String goals = '', assists = '';
          for (final s in statsRaw) {
            if (s is! Map<String, dynamic>) continue;
            final abbr = s['abbreviation'] as String? ?? s['name'] as String? ?? '';
            final val = s['displayValue']?.toString() ??
                s['value']?.toString() ?? '';
            if (abbr == 'G' || abbr == 'GLS') goals = val;
            if (abbr == 'A' || abbr == 'AST') assists = val;
          }
          final player = SoccerPlayer(
            name: ath['displayName'] as String? ?? ath['lastName'] as String? ?? '',
            playerId: ath['id'] as String? ?? '',
            position: (ath['position'] as Map<String, dynamic>?)?['abbreviation'] as String? ?? '',
            jerseyNumber: ath['jersey'] as String? ?? '',
            goals: goals,
            assists: assists,
            isStarter: e['starter'] == true,
          );
          if (player.isStarter) {
            starters.add(player);
          } else {
            subs.add(player);
          }
        }

        // Use all entries as lineup (starters first) if no starters flagged
        final lineup = starters.isNotEmpty ? starters : subs;
        if (homeAway == 'home') {
          homeLineup = lineup;
        } else if (homeAway == 'away') {
          awayLineup = lineup;
        } else {
          // Fallback by order
          if (homeLineup.isEmpty) {
            homeLineup = lineup;
          } else {
            awayLineup = lineup;
          }
        }
      }

      // ── Boxscore team stats ──────────────────────────────────
      final boxTeams = ((data['boxscore'] as Map<String, dynamic>?)?['teams']
              as List<dynamic>?) ??
          const [];
      Map<String, String> homeTeamStats = {};
      Map<String, String> awayTeamStats = {};
      for (final td in boxTeams) {
        if (td is! Map<String, dynamic>) continue;
        final teamId =
            (td['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
        final ha = homeAwayByTeamId[teamId];
        final statistics = (td['statistics'] as List<dynamic>?) ?? const [];
        final stats = <String, String>{};
        for (final s in statistics) {
          if (s is! Map<String, dynamic>) continue;
          final name = s['name'] as String? ?? s['abbreviation'] as String? ?? '';
          final val = s['displayValue'] as String? ?? '';
          if (name.isNotEmpty && val.isNotEmpty) stats[name] = val;
        }
        if (ha == 'home') {
          homeTeamStats = stats;
        } else if (ha == 'away') {
          awayTeamStats = stats;
        }
      }

      // ── Injuries ──────────────────────────────────────────────
      final injuriesRaw = (data['injuries'] as List<dynamic>?) ?? const [];
      final injuries = <BaseballInjury>[];
      for (final injTeam in injuriesRaw) {
        if (injTeam is! Map<String, dynamic>) continue;
        final teamName =
            (injTeam['team'] as Map<String, dynamic>?)?['displayName']
                as String? ?? '';
        for (final inj
            in (injTeam['injuries'] as List<dynamic>?) ?? const []) {
          if (inj is! Map<String, dynamic>) continue;
          final ath = inj['athlete'] as Map<String, dynamic>? ?? {};
          final typeMap = inj['type'] as Map<String, dynamic>? ?? {};
          injuries.add(BaseballInjury(
            playerName: ath['displayName'] as String? ?? '',
            team: teamName,
            status: inj['status'] as String? ?? '',
            description: typeMap['description'] as String? ?? '',
          ));
        }
      }

      // ── 如果 summary 沒有傷兵資料，從名單對比找出缺席球員 ──────
      if (injuries.isEmpty && (homeLineup.isNotEmpty || awayLineup.isNotEmpty)) {
        // 收集本場出賽球員 IDs（先發 + 替補）
        final homeSquadIds = <String>{};
        final awaySquadIds = <String>{};
        for (final r in rosters) {
          if (r is! Map<String, dynamic>) continue;
          final teamId =
              (r['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
          final ha = homeAwayByTeamId[teamId];
          final entries = (r['roster'] as List<dynamic>?) ?? const [];
          for (final e in entries) {
            if (e is! Map<String, dynamic>) continue;
            final athId = (e['athlete'] as Map<String, dynamic>?)?['id'] as String? ?? '';
            if (athId.isEmpty) continue;
            if (ha == 'home') {
              homeSquadIds.add(athId);
            } else if (ha == 'away') {
              awaySquadIds.add(athId);
            }
          }
        }
        // 同時查詢兩隊名單，找出缺席球員
        final teamIds = homeAwayByTeamId.keys.toList();
        final futures = <Future<List<BaseballInjury>>>[];
        for (final tid in teamIds) {
          final tName = teamNameById[tid] ?? '';
          final ha = homeAwayByTeamId[tid] ?? '';
          final squadIds = ha == 'home' ? homeSquadIds : awaySquadIds;
          futures.add(_fetchAbsentPlayers(leagueSlug, tid, tName, squadIds));
        }
        final results = await Future.wait(futures);
        for (final r in results) {
          injuries.addAll(r);
        }
      }

      // ── Match events from commentary ──────────────────────────
      final commentary = (data['commentary'] as List<dynamic>?) ?? const [];
      final events = <SoccerMatchEvent>[];
      const keyTypes = {'goal', 'yellowcard', 'yellow-card', 'redcard',
          'red-card', 'substitution', 'sub', 'score'};
      for (final c in commentary) {
        if (c is! Map<String, dynamic>) continue;
        final typeId =
            ((c['type'] as Map<String, dynamic>?)?['id'] as String? ?? '')
                .toLowerCase();
        if (!keyTypes.contains(typeId)) continue;
        final clock =
            (c['clock'] as Map<String, dynamic>?)?['displayValue'] as String? ?? '';
        final text = c['text'] as String? ?? '';
        final period =
            (c['period'] as Map<String, dynamic>?)?['number'] as int? ?? 1;
        final athletes = (c['athletesInvolved'] as List<dynamic>?) ?? const [];
        String teamId = '';
        String playerName = '';
        if (athletes.isNotEmpty) {
          final a = athletes.first as Map<String, dynamic>? ?? {};
          teamId = (a['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
          playerName = a['displayName'] as String? ?? '';
        }
        events.add(SoccerMatchEvent(
          clock: clock,
          type: typeId,
          teamSide: homeAwayByTeamId[teamId] ?? '',
          playerName: playerName,
          description: text,
          period: period,
        ));
      }
      // Most recent events first
      final reversedEvents = events.reversed.toList();

      // ── Suspensions from red cards in this match ───────────────
      // 吃紅牌球員下場比賽禁賽；從 commentary 紅牌事件和 keyEvents 提取
      final suspensions = <SoccerSuspension>[];
      final seenSuspensions = <String>{};
      // 從 commentary 事件中找紅牌
      for (final ev in events) {
        final t = ev.type;
        if ((t == 'redcard' || t == 'red-card') && ev.playerName.isNotEmpty) {
          final key = '${ev.playerName}_${ev.teamSide}';
          if (seenSuspensions.add(key)) {
            suspensions.add(SoccerSuspension(
              playerName: ev.playerName,
              teamName: ev.teamSide == 'home' ? homeTeamName : ev.teamSide == 'away' ? awayTeamName : '',
              teamSide: ev.teamSide,
              reason: '紅牌禁賽（${ev.clock}）',
            ));
          }
        }
      }
      // 也從 keyEvents 補充（ESPN 有時只記錄在 keyEvents 裡）
      final keyEventsRaw = (data['keyEvents'] as List<dynamic>?) ?? const [];
      for (final ke in keyEventsRaw) {
        if (ke is! Map<String, dynamic>) continue;
        final typeId = ((ke['type'] as Map<String, dynamic>?)?['id'] as String? ?? '').toLowerCase();
        if (typeId != 'redcard' && typeId != 'red-card') continue;
        final clock = (ke['clock'] as Map<String, dynamic>?)?['displayValue'] as String? ?? '';
        final athletes = (ke['athletesInvolved'] as List<dynamic>?) ?? const [];
        for (final a in athletes) {
          if (a is! Map<String, dynamic>) continue;
          final pName = a['displayName'] as String? ?? '';
          final teamId = (a['team'] as Map<String, dynamic>?)?['id'] as String? ?? '';
          final side = homeAwayByTeamId[teamId] ?? '';
          final key = '${pName}_$side';
          if (pName.isNotEmpty && seenSuspensions.add(key)) {
            suspensions.add(SoccerSuspension(
              playerName: pName,
              teamName: teamNameById[teamId] ?? '',
              teamSide: side,
              reason: '紅牌禁賽${clock.isNotEmpty ? "（$clock）" : ""}',
            ));
          }
        }
      }

      return SoccerGameDetail(
        homeRecord: homeRecord,
        awayRecord: awayRecord,
        homeStreak: homeStreak,
        awayStreak: awayStreak,
        homeFirstHalf: homeFirstHalf,
        awayFirstHalf: awayFirstHalf,
        homeSecondHalf: homeSecondHalf,
        awaySecondHalf: awaySecondHalf,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
        injuries: injuries,
        suspensions: suspensions,
        homeTeamStats: homeTeamStats,
        awayTeamStats: awayTeamStats,
        situationDescription: situationDescription,
        situationTeam: situationTeam,
        events: reversedEvents,
      );
    } catch (e) {
      return null;
    }
  }
}

// ── 棒球 summary 資料模型 ─────────────────────────────────────────

class BaseballGameDetail {
  final double? overUnder;
  final double? overOdds;
  final double? underOdds;
  final List<BaseballLineScore> homeLineScores;
  final List<BaseballLineScore> awayLineScores;
  final String homeHits;
  final String awayHits;
  final String homeErrors;
  final String awayErrors;
  final String homeRecord;
  final String awayRecord;
  final String homeStreak;
  final String awayStreak;
  final String homeLast10;
  final String awayLast10;
  final String homeHomeRecord;
  final String awayHomeRecord;
  final String homeRoadRecord;
  final String awayRoadRecord;
  final List<BaseballPlayer> homeLineup;
  final List<BaseballPlayer> awayLineup;
  final List<BaseballInjury> injuries;
  final Map<String, String> batterAvgByPlayerId;
  final Map<String, String> batterHitsByPlayerId;
  final Map<String, String> pitcherPitchesByPlayerId;
  final Map<String, String> pitcherEraByPlayerId;
  final Map<String, BaseballPitcherGameStats> pitcherGameStatsByPlayerId;

  const BaseballGameDetail({
    required this.overUnder,
    required this.overOdds,
    required this.underOdds,
    required this.homeLineScores,
    required this.awayLineScores,
    required this.homeHits,
    required this.awayHits,
    required this.homeErrors,
    required this.awayErrors,
    required this.homeRecord,
    required this.awayRecord,
    required this.homeStreak,
    required this.awayStreak,
    required this.homeLast10,
    required this.awayLast10,
    required this.homeHomeRecord,
    required this.awayHomeRecord,
    required this.homeRoadRecord,
    required this.awayRoadRecord,
    required this.homeLineup,
    required this.awayLineup,
    required this.injuries,
    required this.batterAvgByPlayerId,
    required this.batterHitsByPlayerId,
    required this.pitcherPitchesByPlayerId,
    required this.pitcherEraByPlayerId,
    required this.pitcherGameStatsByPlayerId,
  });
}

class BaseballLineScore {
  final String runs;
  final String hits;
  final String errors;

  const BaseballLineScore({
    required this.runs,
    required this.hits,
    required this.errors,
  });
}

class BaseballPitcherGameStats {
  final String innings;
  final String hits;
  final String runs;
  final String earnedRuns;
  final String walks;
  final String strikeouts;
  final String pitches;
  final String strikes;
  final String balls;
  final String era;

  const BaseballPitcherGameStats({
    required this.innings,
    required this.hits,
    required this.runs,
    required this.earnedRuns,
    required this.walks,
    required this.strikeouts,
    required this.pitches,
    required this.strikes,
    required this.balls,
    required this.era,
  });
}

class BaseballPlayer {
  final String name;
  final String playerId;
  final String position;
  final int batOrder;
  final String battingAvg;
  final String hitsToday;
  final String atBatsToday;
  final String homeRuns;
  final String rbis;
  const BaseballPlayer({
    required this.name,
    required this.playerId,
    required this.position,
    required this.batOrder,
    required this.battingAvg,
    required this.hitsToday,
    required this.atBatsToday,
    required this.homeRuns,
    required this.rbis,
  });
}

class BaseballInjury {
  final String playerName;
  final String team;
  final String status;
  final String description;
  const BaseballInjury({
    required this.playerName,
    required this.team,
    required this.status,
    required this.description,
  });
}

// ── 籃球 summary 資料模型 ─────────────────────────────────────────

class BasketballPlayer {
  final String name;
  final String playerId;
  final String position;
  final String jerseyNumber;
  final String avgPoints;
  final String avgRebounds;
  final String avgAssists;
  final String pointsToday;
  const BasketballPlayer({
    required this.name,
    required this.playerId,
    required this.position,
    required this.jerseyNumber,
    required this.avgPoints,
    required this.avgRebounds,
    required this.avgAssists,
    required this.pointsToday,
  });
}

class BasketballLineScore {
  final int period;
  final String points;
  const BasketballLineScore({
    required this.period,
    required this.points,
  });
}

class BasketballGameDetail {
  final double? overUnder;
  final double? overOdds;
  final double? underOdds;
  final String homeRecord;
  final String awayRecord;
  final String homeStreak;
  final String awayStreak;
  final String homeLast10;
  final String awayLast10;
  final String homeHomeRecord;
  final String awayHomeRecord;
  final String homeRoadRecord;
  final String awayRoadRecord;
  final List<BasketballLineScore> homeLineScores;
  final List<BasketballLineScore> awayLineScores;
  final List<BasketballPlayer> homeLineup;
  final List<BasketballPlayer> awayLineup;
  final List<BaseballInjury> injuries;
  final Map<String, String> playerAvgPointsById;
  final Map<String, String> playerPointsTodayById;
  final Map<String, String> homeTeamStats;
  final Map<String, String> awayTeamStats;
  final double homePlayerEfficiencyRating;
  final double awayPlayerEfficiencyRating;

  const BasketballGameDetail({
    required this.overUnder,
    required this.overOdds,
    required this.underOdds,
    required this.homeRecord,
    required this.awayRecord,
    required this.homeStreak,
    required this.awayStreak,
    required this.homeLast10,
    required this.awayLast10,
    required this.homeHomeRecord,
    required this.awayHomeRecord,
    required this.homeRoadRecord,
    required this.awayRoadRecord,
    required this.homeLineScores,
    required this.awayLineScores,
    required this.homeLineup,
    required this.awayLineup,
    required this.injuries,
    required this.playerAvgPointsById,
    required this.playerPointsTodayById,
    required this.homeTeamStats,
    required this.awayTeamStats,
    required this.homePlayerEfficiencyRating,
    required this.awayPlayerEfficiencyRating,
  });
}

// ── 足球 summary 資料模型 ─────────────────────────────────────────

class SoccerPlayer {
  final String name;
  final String playerId;
  final String position;
  final String jerseyNumber;
  final String goals;
  final String assists;
  final bool isStarter;
  const SoccerPlayer({
    required this.name,
    required this.playerId,
    required this.position,
    required this.jerseyNumber,
    required this.goals,
    required this.assists,
    required this.isStarter,
  });
}

class SoccerMatchEvent {
  final String clock;       // e.g. "45:01"
  final String type;        // "goal", "yellowcard", "redcard", "substitution"
  final String teamSide;    // 'home', 'away', or ''
  final String playerName;
  final String description;
  final int period;         // 1 = 上半場, 2 = 下半場
  const SoccerMatchEvent({
    required this.clock,
    required this.type,
    required this.teamSide,
    required this.playerName,
    required this.description,
    required this.period,
  });
}

class SoccerSuspension {
  final String playerName;
  final String teamName;
  final String teamSide; // 'home', 'away', or ''
  final String reason;  // e.g. '紅牌禁賽（67'）' or '累積黃牌'
  const SoccerSuspension({
    required this.playerName,
    required this.teamName,
    required this.teamSide,
    required this.reason,
  });
}

class SoccerGameDetail {
  final String homeRecord;
  final String awayRecord;
  final String homeStreak;
  final String awayStreak;
  final int homeFirstHalf;    // -1 = 未知
  final int awayFirstHalf;
  final int homeSecondHalf;
  final int awaySecondHalf;
  final List<SoccerPlayer> homeLineup;
  final List<SoccerPlayer> awayLineup;
  final List<BaseballInjury> injuries;
  final List<SoccerSuspension> suspensions;
  final Map<String, String> homeTeamStats;
  final Map<String, String> awayTeamStats;
  final String situationDescription; // e.g. "Monaco Attacking"
  final String situationTeam;        // 'home', 'away', 'unknown', or ''
  final List<SoccerMatchEvent> events;

  const SoccerGameDetail({
    required this.homeRecord,
    required this.awayRecord,
    required this.homeStreak,
    required this.awayStreak,
    required this.homeFirstHalf,
    required this.awayFirstHalf,
    required this.homeSecondHalf,
    required this.awaySecondHalf,
    required this.homeLineup,
    required this.awayLineup,
    required this.injuries,
    this.suspensions = const [],
    required this.homeTeamStats,
    required this.awayTeamStats,
    required this.situationDescription,
    required this.situationTeam,
    required this.events,
  });
}

// ── 聯賽排行榜條目 ────────────────────────────────────────────────
class LeagueStandingEntry {
  final String teamName;
  final String teamNameEn;
  final String teamAbbr;
  final String group;    // 分組/分區名稱（MLB: AL/NL, NBA: East/West, 足球: 空）
  final int rank;
  final int gamesPlayed;
  final int wins;
  final int draws;
  final int losses;
  final int points;      // 足球積分
  final int goalsFor;
  final int goalsAgainst;
  final String goalDifference;
  final String winPct;   // 棒球/籃球勝率
  const LeagueStandingEntry({
    required this.teamName,
    required this.teamNameEn,
    required this.teamAbbr,
    required this.group,
    required this.rank,
    required this.gamesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.points,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDifference,
    required this.winPct,
  });
}
