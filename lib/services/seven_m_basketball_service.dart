import 'package:http/http.dart' as http;

/// 7m.hk NBA 排行榜服務
///
/// 資料來源：https://px-bdata.7mdt.com/basketball_match_data/3/big/rank.js
/// 提供東西岸各隊實時勝率，用於提升 NBA 比賽預測精準度
class SevenMBasketballService {
  static const _rankUrl =
      'https://px-bdata.7mdt.com/basketball_match_data/3/big/rank.js';
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://www.7m.hk/basketball/',
  };

  // 7m 球隊短名 → ESPN 中文全名對照
  // （兩邊用詞不同，需顯式對應）
  static const _sevenMToEspn = <String, String>{
    '老鷹':   '亞特蘭大老鷹',
    '塞爾特人': '波士頓塞爾提克',
    '籃網':   '布魯克林籃網',
    '黃蜂':   '夏洛特黃蜂',
    '公牛':   '芝加哥公牛',
    '騎士':   '克里夫蘭騎士',
    '獨行俠':  '達拉斯獨行俠',
    '金塊':   '丹佛金塊',
    '活塞':   '底特律活塞',
    '勇士':   '金州勇士',
    '火箭':   '休士頓火箭',
    '溜馬':   '印第安那溜馬',
    '快艇':   '洛杉磯快艇',
    '湖人':   '洛杉磯湖人',
    '灰熊':   '曼菲斯灰熊',
    '熱火':   '邁阿密熱火',
    '公鹿':   '密爾瓦基公鹿',
    '木狼':   '明尼蘇達灰狼',
    '鹈鹕':   '紐奧良鵜鶘',
    '紐約人':  '紐約尼克',
    '雷霆':   '奧克拉荷馬雷霆',
    '魔術':   '奧蘭多魔術',
    '76人':   '費城76人',
    '太陽':   '鳳凰城太陽',
    '拓荒者':  '波特蘭拓荒者',
    '帝王':   '沙加緬度國王',
    '馬刺':   '聖安東尼奧馬刺',
    '速龍':   '多倫多暴龍',
    '爵士':   '猶他爵士',
    '巫師':   '華盛頓巫師',
  };

  /// 抓取 NBA 各隊勝率，回傳 `Map<ESPN中文名, 勝率>` (0.0–1.0)
  Future<Map<String, double>> fetchNBAWinRates() async {
    try {
      final resp = await http
          .get(Uri.parse(_rankUrl), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return {};
      return _parseRankJs(resp.body);
    } catch (_) {
      return {};
    }
  }

  Map<String, double> _parseRankJs(String js) {
    final result = <String, double>{};
    // 格式：var e_rank = [ [id,'短名',勝率,落後場數], ... ];
    final entryRe = RegExp(r"\[(\d+),'([^']+)',([\d.]+),(\d+)\]");
    for (final varName in ['e_rank', 'w_rank']) {
      final block = RegExp(
        r'var ' + varName + r'\s*=\s*\[(.*?)\];',
        dotAll: true,
      ).firstMatch(js);
      if (block == null) continue;
      for (final m in entryRe.allMatches(block.group(1)!)) {
        final shortName = m.group(2)!;
        final winRate = double.tryParse(m.group(3)!) ?? 0.0;
        final espnName = _sevenMToEspn[shortName];
        if (espnName != null) result[espnName] = winRate;
      }
    }
    return result;
  }
}
