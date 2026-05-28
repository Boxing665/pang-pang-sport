import '../models/lottery_model.dart';

/// 彩票数据分析服务
class LotteryAnalysisService {
  /// 计算综合统计数据
  static Map<String, dynamic> computeComprehensiveStats(List<DrawRecord> records) {
    if (records.isEmpty) {
      return {
        'largeCount': 0,
        'smallCount': 0,
        'oddCount': 0,
        'evenCount': 0,
        'largePercent': 0.0,
        'smallPercent': 0.0,
        'oddPercent': 0.0,
        'evenPercent': 0.0,
      };
    }

    int largeCount = 0;    // 20-39
    int smallCount = 0;    // 1-19
    int oddCount = 0;      // 单数
    int evenCount = 0;     // 双数
    int totalNumbers = 0;

    for (final record in records) {
      for (final num in record.numbers) {
        totalNumbers++;
        if (num >= 20) largeCount++;
        else smallCount++;
        if (num % 2 == 1) oddCount++;
        else evenCount++;
      }
    }

    final pct = totalNumbers > 0 ? 100.0 / totalNumbers : 0.0;
    return {
      'largeCount': largeCount,
      'smallCount': smallCount,
      'oddCount': oddCount,
      'evenCount': evenCount,
      'largePercent': (largeCount * pct).toStringAsFixed(1),
      'smallPercent': (smallCount * pct).toStringAsFixed(1),
      'oddPercent': (oddCount * pct).toStringAsFixed(1),
      'evenPercent': (evenCount * pct).toStringAsFixed(1),
    };
  }

  /// 计算每个号码的出现频率
  static Map<int, int> computeNumberFrequency(List<DrawRecord> records) {
    final freq = <int, int>{};
    for (int i = 1; i <= 39; i++) {
      freq[i] = 0;
    }
    for (final record in records) {
      for (final num in record.numbers) {
        freq[num] = (freq[num] ?? 0) + 1;
      }
    }
    return freq;
  }

  /// 获取热门号码 (按频率排序的前10个)
  static List<MapEntry<int, int>> getHotNumbers(List<DrawRecord> records, {int limit = 10}) {
    final freq = computeNumberFrequency(records);
    final sorted = freq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// 获取冷门号码 (最久未出的号码)
  static List<MapEntry<int, int>> getColdNumbers(List<DrawRecord> records, {int limit = 10}) {
    final lastAppearance = <int, int>{};
    for (int i = 1; i <= 39; i++) {
      lastAppearance[i] = records.length; // 默认未出现
    }

    for (int drawIdx = 0; drawIdx < records.length; drawIdx++) {
      final record = records[drawIdx];
      for (final num in record.numbers) {
        if (lastAppearance[num]! == records.length) {
          lastAppearance[num] = drawIdx;
        }
      }
    }

    // 计算每个号码未出现的期数
    final missingPeriods = <int, int>{};
    for (int i = 1; i <= 39; i++) {
      missingPeriods[i] = records.length - lastAppearance[i]!;
    }

    final sorted = missingPeriods.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// 计算连号组合 (如2连3连)
  static Map<String, List<List<int>>> computeConsecutiveNumbers(List<DrawRecord> records) {
    final consecutive2 = <List<int>>{};
    final consecutive3 = <List<int>>{};

    for (final record in records) {
      final nums = record.numbers.toList()..sort();

      // 查找2连和3连
      for (int i = 0; i < nums.length - 1; i++) {
        if (nums[i + 1] - nums[i] == 1) {
          consecutive2.add([nums[i], nums[i + 1]]);

          if (i < nums.length - 2 && nums[i + 2] - nums[i + 1] == 1) {
            consecutive3.add([nums[i], nums[i + 1], nums[i + 2]]);
          }
        }
      }
    }

    // 统计频率
    final cons2Freq = <List<int>, int>{};
    final cons3Freq = <List<int>, int>{};

    for (final pair in consecutive2) {
      cons2Freq[pair] = (cons2Freq[pair] ?? 0) + 1;
    }
    for (final triple in consecutive3) {
      cons3Freq[triple] = (cons3Freq[triple] ?? 0) + 1;
    }

    // 排序并取top5
    final top2 = cons2Freq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = cons3Freq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'consecutive2': top2.take(5).map((e) => e.key).toList(),
      'consecutive3': top3.take(5).map((e) => e.key).toList(),
    };
  }

  /// 获取最近的开奖记录
  static List<DrawRecord> getRecentDraws(List<DrawRecord> records, {int limit = 10}) {
    return records.take(limit).toList();
  }
}
