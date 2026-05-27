import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// ════════════════════════════════════════════════════════════════
/// 自我学习系统 - 隐藏的后台学习引擎
/// 
/// 功能：
/// • 记录用户预测与实际结果
/// • 动态调整预测权重
/// • 分析各种特征的预测准确率
/// • 自动提交学习成果到Github
/// ════════════════════════════════════════════════════════════════

class PredictionRecord {
  final String id;
  final String type; // 'lottery_539', 'bingo', 'football', 'baseball', 'basketball'
  final DateTime predictionDate;
  final DateTime resultDate;
  final List<int> predictedNumbers; // 预测的号码/比数
  final List<int> actualNumbers; // 实际开出的号码/比数
  final int confidence; // 预测时的信心度
  final bool isCorrect; // 是否正确
  final double accuracy; // 准确度 (0.0-1.0)
  final Map<String, dynamic> metadata; // 其他数据

  PredictionRecord({
    required this.id,
    required this.type,
    required this.predictionDate,
    required this.resultDate,
    required this.predictedNumbers,
    required this.actualNumbers,
    required this.confidence,
    required this.isCorrect,
    required this.accuracy,
    required this.metadata,
  });

  factory PredictionRecord.fromJson(Map<String, dynamic> json) {
    return PredictionRecord(
      id: json['id'] as String,
      type: json['type'] as String,
      predictionDate: DateTime.parse(json['predictionDate'] as String),
      resultDate: DateTime.parse(json['resultDate'] as String),
      predictedNumbers: List<int>.from(json['predictedNumbers'] as List),
      actualNumbers: List<int>.from(json['actualNumbers'] as List),
      confidence: json['confidence'] as int,
      isCorrect: json['isCorrect'] as bool,
      accuracy: (json['accuracy'] as num).toDouble(),
      metadata: json['metadata'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'predictionDate': predictionDate.toIso8601String(),
    'resultDate': resultDate.toIso8601String(),
    'predictedNumbers': predictedNumbers,
    'actualNumbers': actualNumbers,
    'confidence': confidence,
    'isCorrect': isCorrect,
    'accuracy': accuracy,
    'metadata': metadata,
  };
}

class PredictionWeights {
  // 特征权重 (动态调整)
  Map<String, double> featureWeights = {
    'frequency': 0.25,
    'recency': 0.20,
    'pairing': 0.20,
    'cycles': 0.15,
    'market_odds': 0.20, // 体育用
  };

  // 各预测类型的基础准确率
  Map<String, double> baseAccuracy = {
    'lottery_539': 0.15, // 539原始随机率
    'bingo': 0.13,
    'football': 0.45,
    'baseball': 0.42,
    'basketball': 0.48,
  };

  // 各特征的转换系数
  Map<String, Map<String, double>> featureCoefficients = {
    'frequency': {'hot': 1.5, 'warm': 1.0, 'cold': 0.5},
    'recency': {'recent': 1.3, 'medium': 1.0, 'old': 0.7},
    'market_odds': {'favorite': 1.2, 'even': 1.0, 'underdog': 0.8},
  };

  PredictionWeights();

  factory PredictionWeights.defaults() => PredictionWeights();

  factory PredictionWeights.fromJson(Map<String, dynamic> json) {
    final weights = PredictionWeights.defaults();
    weights.featureWeights = Map<String, double>.from(
      (json['featureWeights'] as Map).cast<String, double>(),
    );
    weights.baseAccuracy = Map<String, double>.from(
      (json['baseAccuracy'] as Map).cast<String, double>(),
    );
    return weights;
  }

  Map<String, dynamic> toJson() => {
    'featureWeights': featureWeights,
    'baseAccuracy': baseAccuracy,
  };
}

class SelfLearningEngine {
  static const _recordsKey = 'prediction_records_v1';
  static const _weightsKey = 'prediction_weights_v1';

  final List<PredictionRecord> allRecords = [];
  late PredictionWeights currentWeights;

  SelfLearningEngine() {
    currentWeights = PredictionWeights.defaults();
  }

  /// 记录一次预测
  Future<void> recordPrediction(
    String type,
    List<int> predicted, {
    required int confidence,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final record = PredictionRecord(
        id: '${type}_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        predictionDate: DateTime.now(),
        resultDate: DateTime.now().add(const Duration(days: 1)), // 待计算
        predictedNumbers: predicted,
        actualNumbers: [], // 待更新
        confidence: confidence,
        isCorrect: false, // 待更新
        accuracy: 0.0, // 待计算
        metadata: metadata,
      );

      allRecords.add(record);
      await _saveRecords();
    } catch (e) {
      print('记录预测失败: $e');
    }
  }

  /// 对答案 - 当结果公布后调用
  Future<void> recordResult(
    String recordId,
    List<int> actualNumbers,
  ) async {
    try {
      final idx = allRecords.indexWhere((r) => r.id == recordId);
      if (idx == -1) return;

      final oldRecord = allRecords[idx];
      final accuracy = _calculateAccuracy(
        oldRecord.predictedNumbers,
        actualNumbers,
        oldRecord.type,
      );

      final updatedRecord = PredictionRecord(
        id: oldRecord.id,
        type: oldRecord.type,
        predictionDate: oldRecord.predictionDate,
        resultDate: DateTime.now(),
        predictedNumbers: oldRecord.predictedNumbers,
        actualNumbers: actualNumbers,
        confidence: oldRecord.confidence,
        isCorrect: accuracy >= 0.7, // >= 70% 算正确
        accuracy: accuracy,
        metadata: oldRecord.metadata,
      );

      allRecords[idx] = updatedRecord;

      // 触发权重调整
      await _updateWeights(updatedRecord);
      await _saveRecords();

      print('✅ 预测已对答：${recordId} (准确率: ${(accuracy * 100).toStringAsFixed(1)}%)');
    } catch (e) {
      print('对答案失败: $e');
    }
  }

  /// 计算准确率
  double _calculateAccuracy(
    List<int> predicted,
    List<int> actual,
    String type,
  ) {
    if (type == 'lottery_539') {
      // 539: 中几个号码
      final matches = predicted.where((p) => actual.contains(p)).length;
      return matches / 5; // 最多中5个
    } else if (type == 'bingo') {
      // 宾果: 中几个号码
      final matches = predicted.where((p) => actual.contains(p)).length;
      return matches / predicted.length;
    } else if (type == 'football') {
      // 足球: 比数或胜负
      if (predicted[0] == actual[0]) return 0.5; // 胜负正确
      if (predicted.length >= 3 &&
          predicted[1] == actual[1] &&
          predicted[2] == actual[2]) return 1.0; // 比数完全正确
      return 0.0;
    } else if (type == 'baseball' || type == 'basketball') {
      // 棒球/篮球: 让分、胜负、大小分
      int matches = 0;
      int total = min(3, predicted.length);
      if (predicted[0] == actual[0]) matches++; // 胜负
      if (predicted.length > 1 && predicted[1] == actual[1]) matches++; // 让分
      if (predicted.length > 2 && predicted[2] == actual[2]) matches++; // 大小分
      return matches / total;
    }
    return 0.0;
  }

  /// 动态调整权重
  Future<void> _updateWeights(PredictionRecord record) async {
    try {
      // 如果预测准确，增加该特征的权重
      final metadata = record.metadata;
      final dominantFeature = metadata['dominant_feature'] as String?;

      if (record.isCorrect && dominantFeature != null) {
        // 该特征预测正确，增加其权重
        final adjustment = 0.02 * (record.accuracy - 0.5); // 基于超额准确率调整
        currentWeights.featureWeights[dominantFeature] =
            (currentWeights.featureWeights[dominantFeature] ?? 0.2) + adjustment;
      }

      // 归一化权重 (保持总和为1)
      _normalizeWeights();
      await _saveWeights();
    } catch (e) {
      print('权重更新失败: $e');
    }
  }

  /// 归一化权重
  void _normalizeWeights() {
    final sum = currentWeights.featureWeights.values.reduce((a, b) => a + b);
    currentWeights.featureWeights.forEach((key, value) {
      currentWeights.featureWeights[key] = value / sum;
    });
  }

  /// 获取加权预测
  double getWeightedConfidence(
    Map<String, double> featureScores,
    String type,
  ) {
    double weighted = 0;
    featureScores.forEach((feature, score) {
      final weight = currentWeights.featureWeights[feature] ?? 0.2;
      weighted += weight * score;
    });

    // 基础准确率影响
    final baseAcc = currentWeights.baseAccuracy[type] ?? 0.3;
    return (weighted * 0.7) + (baseAcc * 0.3);
  }

  /// 生成学习报告
  String generateLearningReport() {
    final sb = StringBuffer();
    sb.writeln('═══ 自我学习系统报告 ═══\n');

    // 统计信息
    final total = allRecords.length;
    final correct = allRecords.where((r) => r.isCorrect).length;
    final avgAccuracy =
        allRecords.isEmpty ? 0 : allRecords.map((r) => r.accuracy).reduce((a, b) => a + b) / total;

    sb.writeln('📊 总体表现:');
    sb.writeln('  • 总预测数: $total');
    sb.writeln('  • 正确数: $correct (${((correct / total) * 100).toStringAsFixed(1)}%)');
    sb.writeln('  • 平均准确率: ${(avgAccuracy * 100).toStringAsFixed(1)}%\n');

    // 按类型分类
    sb.writeln('📈 按类型分析:');
    final types = {'lottery_539', 'bingo', 'football', 'baseball', 'basketball'};
    for (final type in types) {
      final typeRecords = allRecords.where((r) => r.type == type).toList();
      if (typeRecords.isEmpty) continue;

      final typeCorrect = typeRecords.where((r) => r.isCorrect).length;
      final typeAvgAcc = typeRecords.map((r) => r.accuracy).reduce((a, b) => a + b) / typeRecords.length;

      sb.writeln('  $type:');
      sb.writeln('    - 数量: ${typeRecords.length}');
      sb.writeln('    - 准确率: ${((typeCorrect / typeRecords.length) * 100).toStringAsFixed(1)}%');
      sb.writeln('    - 平均精准度: ${(typeAvgAcc * 100).toStringAsFixed(1)}%');
    }

    sb.writeln('\n⚙️ 当前权重:');
    currentWeights.featureWeights.forEach((feature, weight) {
      sb.writeln('  • $feature: ${(weight * 100).toStringAsFixed(1)}%');
    });

    return sb.toString();
  }

  /// 保存记录到本地
  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = allRecords.map((r) => r.toJson()).toList();
      await prefs.setString(_recordsKey, jsonEncode(data));
    } catch (e) {
      print('保存记录失败: $e');
    }
  }

  /// 加载记录
  Future<void> loadRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_recordsKey);
      if (data == null) return;

      final list = jsonDecode(data) as List;
      allRecords.clear();
      allRecords.addAll(
        list.map((e) => PredictionRecord.fromJson(e as Map<String, dynamic>)),
      );
    } catch (e) {
      print('加载记录失败: $e');
    }
  }

  /// 保存权重
  Future<void> _saveWeights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_weightsKey, jsonEncode(currentWeights.toJson()));
    } catch (e) {
      print('保存权重失败: $e');
    }
  }

  /// 加载权重
  Future<void> loadWeights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_weightsKey);
      if (data == null) return;
      currentWeights = PredictionWeights.fromJson(jsonDecode(data) as Map<String, dynamic>);
    } catch (e) {
      print('加载权重失败: $e');
    }
  }

  /// 导出Github
  Future<void> exportToGithub() async {
    try {
      final report = generateLearningReport();
      // 实际应连接到Github API
      print('📤 正在导出学习成果到Github...\n$report');
    } catch (e) {
      print('导出失败: $e');
    }
  }
}

