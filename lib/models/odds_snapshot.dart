import 'dart:math';

class OddsSnapshot {
  const OddsSnapshot({
    required this.homeWin,
    required this.draw,
    required this.awayWin,
    required this.overLine,
    required this.overOdds,
    required this.underOdds,
    this.bookmakerName = '',
    this.spread = 0.0,
    this.homeSpreadOdds = 1.91,
    this.awaySpreadOdds = 1.91,
    this.isFromBookmaker = false,
    this.openingHomeWin = 0.0,
    this.openingDraw = 0.0,
    this.openingAwayWin = 0.0,
  });

  // 勝負賠率（歐式小數盤口）
  final double homeWin;
  final double draw;
  final double awayWin;

  // 大小分
  final double overLine;
  final double overOdds;
  final double underOdds;

  // 讓分盤口
  final double spread;         // 正數→主場讓分，負數→主場受讓
  final double homeSpreadOdds; // 主場讓分賠率（歐式）
  final double awaySpreadOdds; // 客場讓分賠率（歐式）

  // 來源資訊
  final String bookmakerName;    // e.g. "Pinnacle"
  final bool isFromBookmaker;    // true = 真實賭盤數據

  // 初盤賠率（0.0 = 未提供）：用於偵測市場盲目跟風引起的賠率漂移
  final double openingHomeWin;
  final double openingDraw;
  final double openingAwayWin;

  /// 賠率波動幅度（0.0 = 完全不動、1.0 = 極端波動）
  ///
  /// 計算初盤與即時盤之間的隱含機率向量 Euclidean 距離。
  /// > 0.05 : 輕微波動（過濾開始介入）
  /// > 0.15 : 顯著波動（可能含大量跟風資金）
  /// > 0.30 : 異常波動（模型主動衰減市場信號）
  double get errorMargin {
    if (openingHomeWin <= 0 || openingAwayWin <= 0) return 0.0;
    // --- 初盤隱含機率 ---
    final oh = 1 / openingHomeWin;
    final od = openingDraw > 0 ? 1 / openingDraw : 0.0;
    final oa = 1 / openingAwayWin;
    final ot = oh + od + oa;
    final opH = oh / ot;
    final opD = od / ot;
    final opA = oa / ot;
    // --- 即時盤隱含機率 ---
    final ch = 1 / homeWin;
    final cd = draw > 0 ? 1 / draw : 0.0;
    final ca = 1 / awayWin;
    final ct = ch + cd + ca;
    final cuH = ch / ct;
    final cuD = cd / ct;
    final cuA = ca / ct;
    // Euclidean 距離
    return sqrt(
      pow(cuH - opH, 2) + pow(cuD - opD, 2) + pow(cuA - opA, 2),
    ).clamp(0.0, 1.0);
  }

  // ── 特徵工程（Feature Engineering）─────────────────────────────

  /// 博彩公司抽水百分比（Overround / Vig）
  /// 三向市場總隱含機率 − 100%（例：105% → 5% 抽水）
  double get overround {
    final sum = (homeWin > 0 ? 1 / homeWin : 0.0)
              + (draw > 0 ? 1 / draw : 0.0)
              + (awayWin > 0 ? 1 / awayWin : 0.0);
    return (sum - 1.0).clamp(0.0, 1.0);
  }

  /// 去除抽水後的公平隱含機率（Fair Probability）
  /// P_fair = (1/Odds) / Σ(1/Odds) → 所有機率和恰好 = 100%
  double get fairHomeProb {
    final raw = homeWin > 0 ? 1 / homeWin : 0.0;
    final sum = raw + (draw > 0 ? 1 / draw : 0.0) + (awayWin > 0 ? 1 / awayWin : 0.0);
    return sum > 0 ? raw / sum : 0.0;
  }
  double get fairDrawProb {
    final raw = draw > 0 ? 1 / draw : 0.0;
    final sum = (homeWin > 0 ? 1 / homeWin : 0.0) + raw + (awayWin > 0 ? 1 / awayWin : 0.0);
    return sum > 0 ? raw / sum : 0.0;
  }
  double get fairAwayProb {
    final raw = awayWin > 0 ? 1 / awayWin : 0.0;
    final sum = (homeWin > 0 ? 1 / homeWin : 0.0) + (draw > 0 ? 1 / draw : 0.0) + raw;
    return sum > 0 ? raw / sum : 0.0;
  }

  /// 盤口變動方向（Market Movement）
  /// 正值 = 即時盤比初盤更看好主隊；負值 = 即時盤比初盤更看好客隊
  /// 值域 [-1, 1]，|值| > 0.03 = 有意義的變動
  double get marketMovement {
    if (openingHomeWin <= 0 || openingAwayWin <= 0) return 0.0;
    final openH = 1 / openingHomeWin;
    final openA = 1 / openingAwayWin;
    final openT = openH + (openingDraw > 0 ? 1 / openingDraw : 0.0) + openA;
    final liveH = 1 / homeWin;
    final liveA = 1 / awayWin;
    final liveT = liveH + (draw > 0 ? 1 / draw : 0.0) + liveA;
    return ((liveH / liveT) - (openH / openT)).clamp(-1.0, 1.0);
  }

  /// 是否偵測到逆向盤口（Reverse Line Movement / Smart Money Signal）
  /// 當盤口移動方向與初盤看好方相反時為 true → 可能是聰明錢訊號
  bool get hasReverseLineMovement {
    if (openingHomeWin <= 0 || openingAwayWin <= 0) return false;
    final openFavHome = 1 / openingHomeWin > 1 / openingAwayWin;
    return openFavHome ? marketMovement < -0.03 : marketMovement > 0.03;
  }

  Map<String, dynamic> toJson() => {
    'homeWin': homeWin,
    'draw': draw,
    'awayWin': awayWin,
    'overLine': overLine,
    'overOdds': overOdds,
    'underOdds': underOdds,
    'bookmakerName': bookmakerName,
    'spread': spread,
    'homeSpreadOdds': homeSpreadOdds,
    'awaySpreadOdds': awaySpreadOdds,
    'isFromBookmaker': isFromBookmaker,
    'openingHomeWin': openingHomeWin,
    'openingDraw': openingDraw,
    'openingAwayWin': openingAwayWin,
  };

  factory OddsSnapshot.fromJson(Map<String, dynamic> json) {
    return OddsSnapshot(
      homeWin: (json['homeWin'] as num?)?.toDouble() ?? 1.91,
      draw: (json['draw'] as num?)?.toDouble() ?? 3.3,
      awayWin: (json['awayWin'] as num?)?.toDouble() ?? 1.91,
      overLine: (json['overLine'] as num?)?.toDouble() ?? 2.5,
      overOdds: (json['overOdds'] as num?)?.toDouble() ?? 1.91,
      underOdds: (json['underOdds'] as num?)?.toDouble() ?? 1.91,
      bookmakerName: json['bookmakerName'] as String? ?? '',
      spread: (json['spread'] as num?)?.toDouble() ?? 0.0,
      homeSpreadOdds: (json['homeSpreadOdds'] as num?)?.toDouble() ?? 1.91,
      awaySpreadOdds: (json['awaySpreadOdds'] as num?)?.toDouble() ?? 1.91,
      isFromBookmaker: json['isFromBookmaker'] as bool? ?? false,
      openingHomeWin: (json['openingHomeWin'] as num?)?.toDouble() ?? 0.0,
      openingDraw: (json['openingDraw'] as num?)?.toDouble() ?? 0.0,
      openingAwayWin: (json['openingAwayWin'] as num?)?.toDouble() ?? 0.0,
    );
  }
}