/// Bingo数据分析服务
class BingoAnalysisService {
  /// 计算综合统计数据 (1-80的区间)
  static Map<String, dynamic> computeComprehensiveStats(List<int> allNumbers) {
    if (allNumbers.isEmpty) {
      return {
        'largeCount': 0,
        'smallCount': 0,
        'largePercent': 0.0,
        'smallPercent': 0.0,
      };
    }

    int largeCount = 0;    // 41-80
    int smallCount = 0;    // 1-40

    for (final num in allNumbers) {
      if (num > 40) largeCount++;
      else smallCount++;
    }

    final total = allNumbers.length;
    final pct = 100.0 / total;

    return {
      'largeCount': largeCount,
      'smallCount': smallCount,
      'largePercent': (largeCount * pct).toStringAsFixed(1),
      'smallPercent': (smallCount * pct).toStringAsFixed(1),
    };
  }

  /// 计算每个号码的出现频率
  static Map<int, int> computeNumberFrequency(List<int> allNumbers) {
    final freq = <int, int>{};
    for (int i = 1; i <= 80; i++) {
      freq[i] = 0;
    }
    for (final num in allNumbers) {
      freq[num] = (freq[num] ?? 0) + 1;
    }
    return freq;
  }

  /// 获取热门号码
  static List<MapEntry<int, int>> getHotNumbers(List<int> allNumbers, {int limit = 10}) {
    final freq = computeNumberFrequency(allNumbers);
    final sorted = freq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.where((e) => e.value > 0).take(limit).toList();
  }

  /// 获取冷门号码 (最久未出的号码)
  static List<MapEntry<int, int>> getColdNumbers(List<int> allNumbers, {int limit = 10}) {
    final lastAppearance = <int, int>{};
    for (int i = 1; i <= 80; i++) {
      lastAppearance[i] = -1;
    }

    for (int drawIdx = 0; drawIdx < allNumbers.length; drawIdx++) {
      final num = allNumbers[drawIdx];
      lastAppearance[num] = drawIdx;
    }

    // 计算每个号码未出现的期数
    final missingPeriods = <int, int>{};
    for (int i = 1; i <= 80; i++) {
      if (lastAppearance[i]! == -1) {
        missingPeriods[i] = allNumbers.length; // 从未出现
      } else {
        missingPeriods[i] = allNumbers.length - lastAppearance[i]! - 1;
      }
    }

    final sorted = missingPeriods.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }
}
