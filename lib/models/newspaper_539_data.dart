/// 539 報紙預測號碼（喜雀神卦）
///
/// 每日報紙提供：孤支、二中一、三中一、喜雀神卦、天干地支、
/// 八卦精選尾數、版路精選尾數、頭彩五連碰（兩組）
class Newspaper539Entry {
  const Newspaper539Entry({
    required this.date,
    required this.guZhi,
    required this.erZhong,
    required this.sanZhong,
    this.xique = const [],
    this.tiangan = const [],
    this.bagua = const [],
    this.banlu = const [],
    this.toucai1 = const [],
    this.toucai2 = const [],
  });

  final String date;          // "MM/DD"
  final int guZhi;            // 孤支（1 個）
  final List<int> erZhong;    // 二中一（2 個）
  final List<int> sanZhong;   // 三中一（3 個）
  final List<int> xique;      // 喜雀神卦（3 個）
  final List<int> tiangan;    // 天干地支（4 個）
  final List<int> bagua;      // 八卦精選尾數（3 個）
  final List<int> banlu;      // 版路精選尾數（3 個）
  final List<int> toucai1;    // 頭彩五連碰 組1（5 個）
  final List<int> toucai2;    // 頭彩五連碰 組2（5 個）

  /// 組合成 redHints：[孤支, 二中一×2, 三中一×3]
  List<int> get redHints => [guZhi, ...erZhong, ...sanZhong];

  /// 報紙額外號碼加成表（號碼 → 加分值）
  Map<int, double> get extraBonuses {
    final m = <int, double>{};
    for (final n in xique) {
      if (n >= 1 && n <= 39) m[n] = (m[n] ?? 0) + 55;
    }
    for (final n in tiangan) {
      if (n >= 1 && n <= 39) m[n] = (m[n] ?? 0) + 35;
    }
    for (final n in bagua) {
      if (n >= 1 && n <= 39) m[n] = (m[n] ?? 0) + 30;
    }
    for (final n in banlu) {
      if (n >= 1 && n <= 39) m[n] = (m[n] ?? 0) + 30;
    }
    for (final n in toucai1) {
      if (n >= 1 && n <= 39) m[n] = (m[n] ?? 0) + 25;
    }
    for (final n in toucai2) {
      if (n >= 1 && n <= 39) m[n] = (m[n] ?? 0) + 25;
    }
    return m;
  }

  /// 所有報紙號碼（去重）
  Set<int> get allNumbers => {
    guZhi, ...erZhong, ...sanZhong,
    ...xique, ...tiangan, ...bagua, ...banlu,
    ...toucai1, ...toucai2,
  };
}

/// 報紙預測資料庫（按日期索引）
/// key = "MM/DD"
const newspaper539Data = <String, Newspaper539Entry>{
  // ── 2026/04/13（星期一）─────────────────────────────────────
  '04/13': Newspaper539Entry(
    date: '04/13',
    guZhi: 23,
    erZhong: [12, 37],
    sanZhong: [09, 18, 21],
    xique: [04, 11, 39],
    tiangan: [06, 15, 24, 33],
    bagua: [08, 28, 38],
    banlu: [07, 17, 27],
    toucai1: [01, 10, 24, 26, 34],
    toucai2: [06, 14, 16, 29, 30],
  ),

  // ── 2026/04/14（星期二）─────────────────────────────────────
  '04/14': Newspaper539Entry(
    date: '04/14',
    guZhi: 34,
    erZhong: [21, 23],
    sanZhong: [09, 12, 32],
    xique: [10, 20, 39],
    tiangan: [07, 16, 25, 34],
    bagua: [06, 26, 36],
    banlu: [03, 13, 33],
    toucai1: [02, 15, 18, 29, 32],
    toucai2: [05, 19, 21, 30, 38],
  ),

  // ── 2026/04/15（星期三）─────────────────────────────────────
  '04/15': Newspaper539Entry(
    date: '04/15',
    guZhi: 15,
    erZhong: [28, 30],
    sanZhong: [03, 12, 37],
    xique: [02, 20, 29],
    tiangan: [08, 17, 26, 35],
    bagua: [10, 20, 30],
    banlu: [05, 25, 35],
    toucai1: [09, 14, 22, 34, 39],
    toucai2: [07, 13, 19, 23, 32],
  ),

  // ── 2026/04/16（星期四）─────────────────────────────────────
  '04/16': Newspaper539Entry(
    date: '04/16',
    guZhi: 12,
    erZhong: [24, 26],
    sanZhong: [09, 21, 30],
    xique: [13, 17, 32],
    tiangan: [09, 18, 27, 36],
    bagua: [06, 16, 36],
    banlu: [02, 22, 32],
    toucai1: [04, 15, 23, 25, 34],
    toucai2: [05, 10, 13, 29, 38],
  ),

  // ── 2026/04/17（星期五）─────────────────────────────────────
  '04/17': Newspaper539Entry(
    date: '04/17',
    guZhi: 01,
    erZhong: [12, 28],
    sanZhong: [10, 14, 39],
    xique: [06, 23, 32],
    tiangan: [01, 10, 19, 28],
    bagua: [10, 20, 30],
    banlu: [11, 21, 31],
    toucai1: [09, 16, 27, 29, 36],
    toucai2: [07, 13, 26, 33, 37],
  ),

  // ── 2026/04/18（星期六）─────────────────────────────────────
  '04/18': Newspaper539Entry(
    date: '04/18',
    guZhi: 32,
    erZhong: [25, 29],
    sanZhong: [04, 14, 23],
    xique: [16, 19, 24],
    tiangan: [02, 11, 20, 29],
    bagua: [05, 15, 35],
    banlu: [06, 26, 36],
    toucai1: [09, 10, 11, 20, 34],
    toucai2: [01, 13, 21, 30, 39],
  ),

  // ── 2026/04/20（星期一）─────────────────────────────────────
  '04/20': Newspaper539Entry(
    date: '04/20',
    guZhi: 32,
    erZhong: [13, 31],
    sanZhong: [08, 11, 23],
  ),

  // ── 2026/04/21（星期二）─────────────────────────────────────
  '04/21': Newspaper539Entry(
    date: '04/21',
    guZhi: 19,
    erZhong: [10, 12],
    sanZhong: [04, 21, 38],
  ),

  // ── 2026/04/22（星期三）─────────────────────────────────────
  '04/22': Newspaper539Entry(
    date: '04/22',
    guZhi: 33,
    erZhong: [05, 14],
    sanZhong: [10, 29, 38],
  ),

  // ── 2026/04/23（星期四）─────────────────────────────────────
  '04/23': Newspaper539Entry(
    date: '04/23',
    guZhi: 31,
    erZhong: [30, 38],
    sanZhong: [05, 13, 26],
  ),

  // ── 2026/04/24（星期五）─────────────────────────────────────
  '04/24': Newspaper539Entry(
    date: '04/24',
    guZhi: 23,
    erZhong: [34, 35],
    sanZhong: [08, 11, 29],
  ),

  // ── 2026/04/25（星期六）─────────────────────────────────────
  '04/25': Newspaper539Entry(
    date: '04/25',
    guZhi: 24,
    erZhong: [23, 33],
    sanZhong: [09, 19, 32],
  ),

  // ── 2026/04/27（星期一）─────────────────────────────────────
  '04/27': Newspaper539Entry(
    date: '04/27',
    guZhi: 25,
    erZhong: [11, 19],
    sanZhong: [08, 24, 36],
    xique: [03, 30, 34],
  ),

  // ── 2026/04/28（星期二）─────────────────────────────────────
  '04/28': Newspaper539Entry(
    date: '04/28',
    guZhi: 28,
    erZhong: [13, 31],
    sanZhong: [02, 17, 36],
    xique: [08, 23, 32],
  ),

  // ── 2026/04/29（星期三）─────────────────────────────────────
  '04/29': Newspaper539Entry(
    date: '04/29',
    guZhi: 19,
    erZhong: [25, 34],
    sanZhong: [08, 17, 29],
    xique: [06, 18, 20],
  ),

  // ── 2026/04/30（星期四）─────────────────────────────────────
  '04/30': Newspaper539Entry(
    date: '04/30',
    guZhi: 08,
    erZhong: [21, 27],
    sanZhong: [12, 23, 32],
    xique: [13, 29, 34],
  ),

  // ── 2026/05/01（星期五）─────────────────────────────────────
  '05/01': Newspaper539Entry(
    date: '05/01',
    guZhi: 11,
    erZhong: [33, 39],
    sanZhong: [08, 10, 24],
    xique: [17, 22, 35],
  ),

  // ── 2026/05/02（星期六）─────────────────────────────────────
  '05/02': Newspaper539Entry(
    date: '05/02',
    guZhi: 07,
    erZhong: [25, 35],
    sanZhong: [12, 13, 28],
    xique: [08, 10, 38],
  ),

  // ── 2026/05/04（星期一）─────────────────────────────────────
  '05/04': Newspaper539Entry(
    date: '05/04',
    guZhi: 05,
    erZhong: [34, 38],
    sanZhong: [12, 23, 27],
    xique: [17, 21, 26],
    tiangan: [09, 18, 27, 36],
    bagua: [10, 20, 30],
    banlu: [01, 11, 31],
    toucai1: [03, 16, 19, 22, 33],
    toucai2: [09, 13, 26, 29, 37],
  ),

  // ── 2026/05/05（星期二）─────────────────────────────────────
  '05/05': Newspaper539Entry(
    date: '05/05',
    guZhi: 37,
    erZhong: [29, 34],
    sanZhong: [10, 13, 31],
    xique: [15, 26, 30],
    tiangan: [01, 10, 19, 28],
    bagua: [04, 14, 24],
    banlu: [09, 19, 39],
    toucai1: [06, 11, 20, 21, 36],
    toucai2: [03, 16, 25, 33, 35],
  ),

  // ── 2026/05/06（星期三）─────────────────────────────────────
  '05/06': Newspaper539Entry(
    date: '05/06',
    guZhi: 36,
    erZhong: [13, 31],
    sanZhong: [08, 11, 22],
    xique: [14, 27, 34],
    tiangan: [02, 11, 20, 29],
    bagua: [10, 20, 30],
    banlu: [03, 23, 33],
    toucai1: [04, 17, 24, 28, 37],
    toucai2: [07, 15, 18, 25, 32],
  ),

  // ── 2026/05/08（星期五）─────────────────────────────────────
  '05/08': Newspaper539Entry(
    date: '05/08',
    guZhi: 33,
    erZhong: [17, 21],
    sanZhong: [19, 28, 36],
    xique: [29, 30, 34],
    tiangan: [04, 13, 22, 31],
    bagua: [03, 13, 23],
    banlu: [08, 18, 38],
    toucai1: [09, 14, 16, 24, 35],
    toucai2: [06, 10, 25, 26, 39],
  ),

  // ── 2026/05/09（星期六）─────────────────────────────────────
  '05/09': Newspaper539Entry(
    date: '05/09',
    guZhi: 07,
    erZhong: [31, 34],
    sanZhong: [13, 23, 32],
    xique: [09, 12, 35],
    tiangan: [05, 14, 23, 32],
    bagua: [04, 14, 24],
    banlu: [01, 11, 21],
    toucai1: [05, 16, 19, 22, 36],
    toucai2: [02, 15, 26, 29, 33],
  ),
};
