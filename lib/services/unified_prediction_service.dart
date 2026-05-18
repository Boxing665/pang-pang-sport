import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'lottery_539_analyzer.dart';
import 'football_spread_analyzer.dart';
import 'bingo_analyzer.dart';
import '../models/lottery_model.dart';

/// ════════════════════════════════════════════════════════════════
/// 综合体育彩票预测服务 (单例)
/// 
/// 集成所有预测引擎：
/// • 539 彩票 - 热号冷号分析
/// • 宾果(Bingo) - 20号预测  
/// • 足球勝分差 - 体育分析
/// ════════════════════════════════════════════════════════════════

class UnifiedPredictionService {
  static final UnifiedPredictionService _instance = 
      UnifiedPredictionService._internal();

  factory UnifiedPredictionService() {
    return _instance;
  }

  UnifiedPredictionService._internal();

  // 缓存的预测结果
  Lottery539Prediction? _cachedLottery539;
  BingoPrediction? _cachedBingo;
  Map<String, Map<String, dynamic>>? _cachedFootballSpreads;

  // 最后更新时间
  DateTime? _last539Update;
  DateTime? _lastBingoUpdate;
  DateTime? _lastFootballUpdate;

  // 预测结果变化流
  final _lottery539Controller = StreamController<Lottery539Prediction>.broadcast();
  final _bingoController = StreamController<BingoPrediction>.broadcast();
  final _footballController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Lottery539Prediction> get lottery539Stream => _lottery539Controller.stream;
  Stream<BingoPrediction> get bingoStream => _bingoController.stream;
  Stream<Map<String, dynamic>> get footballStream => _footballController.stream;

  void dispose() {
    _lottery539Controller.close();
    _bingoController.close();
    _footballController.close();
  }

  /// ══════════════════════════════════════════════════════════════
  /// 539 预测
  /// ══════════════════════════════════════════════════════════════

  Future<Lottery539Prediction> predict539({
    required List<DrawRecord> historicalRecords,
    int lookbackDays = 180,
    bool useCache = true,
  }) async {
    // 检查缓存有效性
    if (useCache && _cachedLottery539 != null && _last539Update != null) {
      final hoursSinceUpdate = DateTime.now().difference(_last539Update!).inHours;
      if (hoursSinceUpdate < 24) {
        return _cachedLottery539!;
      }
    }

    try {
      final analyzer = Lottery539Analyzer(
        allHistoricalRecords: historicalRecords,
        analysisDate: DateTime.now(),
      );

      final prediction = analyzer.analyze(
        lookbackDays: lookbackDays,
        recommendCount: 5,
      );

      // 保存到缓存
      _cachedLottery539 = prediction;
      _last539Update = DateTime.now();
      await analyzer.saveToCache(prediction);

      _lottery539Controller.add(prediction);
      return prediction;
    } catch (e) {
      return Lottery539Prediction.fromError('539预测失败: $e');
    }
  }

  /// ══════════════════════════════════════════════════════════════
  /// 宾果预测
  /// ══════════════════════════════════════════════════════════════

  Future<BingoPrediction> predictBingo({
    required List<BingoDraw> historicalDraws,
    int lookbackDraws = 100,
    bool useCache = true,
  }) async {
    // 检查缓存
    if (useCache && _cachedBingo != null && _lastBingoUpdate != null) {
      final hoursSinceUpdate = DateTime.now().difference(_lastBingoUpdate!).inHours;
      if (hoursSinceUpdate < 24) {
        return _cachedBingo!;
      }
    }

    try {
      final analyzer = BingoAnalyzer(
        allDraws: historicalDraws,
        analysisDate: DateTime.now(),
      );

      final prediction = analyzer.analyze(
        lookbackDraws: lookbackDraws,
        recommendCount: 8,
      );

      // 保存到缓存
      _cachedBingo = prediction;
      _lastBingoUpdate = DateTime.now();
      await analyzer.saveToCache(prediction);

      _bingoController.add(prediction);
      return prediction;
    } catch (e) {
      return BingoPrediction.fromError('宾果预测失败: $e');
    }
  }

  /// ══════════════════════════════════════════════════════════════
  /// 足球勝分差预测
  /// ══════════════════════════════════════════════════════════════

  Map<String, dynamic> predictFootballSpread({
    required String homeTeam,
    required String awayTeam,
    required String league,
    double homeStrength = 1.0,
    double awayStrength = 1.0,
    List<FootballMatch>? customMatches,
  }) {
    try {
      final predictor = FootballSpreadPredictor(
        customMatches: customMatches,
      );

      final prediction = predictor.predictMatchSpread(
        homeTeam,
        awayTeam,
        league,
        homeStrength: homeStrength,
        awayStrength: awayStrength,
      );

      return prediction;
    } catch (e) {
      return {
        'error': '足球预测失败: $e',
        'predicted_spread': 1.5,
        'confidence': 0.0,
      };
    }
  }

  /// 获取所有联赛的勝分差规律
  Map<String, SpreadPattern> getAllFootballPatterns({
    List<FootballMatch>? customMatches,
  }) {
    final predictor = FootballSpreadPredictor(
      customMatches: customMatches,
    );
    return predictor.analyzeAllLeagues();
  }

  /// 生成足球分析报告
  String generateFootballReport({
    List<FootballMatch>? customMatches,
  }) {
    final predictor = FootballSpreadPredictor(
      customMatches: customMatches,
    );
    return predictor.generateReport();
  }

  /// ══════════════════════════════════════════════════════════════
  /// 批量预测 (一键生成所有预测)
  /// ══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> generateAllPredictions({
    required List<DrawRecord> lottery539Records,
    required List<BingoDraw> bingoDraws,
    List<FootballMatch>? footballMatches,
  }) async {
    try {
      // 并发执行所有预测
      final results = await Future.wait([
        predict539(historicalRecords: lottery539Records),
        predictBingo(historicalDraws: bingoDraws),
      ]);

      final lottery539 = results[0] as Lottery539Prediction;
      final bingo = results[1] as BingoPrediction;

      final football = generateFootballReport(customMatches: footballMatches);

      return {
        'lottery_539': {
          'recommended': lottery539.recommendedNumbers,
          'strategy': lottery539.strategy,
          'analysis': lottery539.analysis,
          'confidence': lottery539.confidence,
          'signals': lottery539.signals,
        },
        'bingo': {
          'recommended': bingo.recommendedNumbers,
          'strategy': bingo.strategy,
          'analysis': bingo.detailedAnalysis,
          'confidence': bingo.confidenceScore,
          'signals': bingo.signals,
        },
        'football': {
          'report': football,
          'generated_at': DateTime.now().toIso8601String(),
        },
      };
    } catch (e) {
      return {
        'error': '批量预测失败: $e',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// ══════════════════════════════════════════════════════════════
  /// 缓存管理
  /// ══════════════════════════════════════════════════════════════

  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lottery_539_analysis_v3');
      await prefs.remove('bingo_prediction_v2');
      
      _cachedLottery539 = null;
      _cachedBingo = null;
      _cachedFootballSpreads = null;
      _last539Update = null;
      _lastBingoUpdate = null;
      _lastFootballUpdate = null;
    } catch (e) {
      print('清除缓存失败: $e');
    }
  }

  /// 获取缓存状态
  Map<String, dynamic> getCacheStatus() {
    return {
      'lottery_539': {
        'cached': _cachedLottery539 != null,
        'last_update': _last539Update?.toIso8601String(),
      },
      'bingo': {
        'cached': _cachedBingo != null,
        'last_update': _lastBingoUpdate?.toIso8601String(),
      },
      'football': {
        'cached': _cachedFootballSpreads != null,
        'last_update': _lastFootballUpdate?.toIso8601String(),
      },
    };
  }

  /// ══════════════════════════════════════════════════════════════
  /// 统计报告
  /// ══════════════════════════════════════════════════════════════

  String generateSummaryReport({
    Lottery539Prediction? lottery539,
    BingoPrediction? bingo,
    Map<String, SpreadPattern>? footballPatterns,
  }) {
    final sb = StringBuffer();

    sb.writeln('╔════════════════════════════════════════════════════╗');
    sb.writeln('║        🎰 胖胖体育 - 综合预测报告                  ║');
    sb.writeln('║        ${DateTime.now().toString()}          ║');
    sb.writeln('╚════════════════════════════════════════════════════╝\n');

    if (lottery539 != null && !lottery539.recommendedNumbers.isEmpty) {
      sb.writeln('💰 539 彩票预测');
      sb.writeln('推荐号码: ${lottery539.recommendedNumbers.map((n) => n.toString().padLeft(2, '0')).join(' ')}');
      sb.writeln('信心度: ${lottery539.confidence}%');
      sb.writeln('${lottery539.strategy}\n');
    }

    if (bingo != null && !bingo.recommendedNumbers.isEmpty) {
      sb.writeln('🎲 宾果(Bingo)预测');
      sb.writeln('推荐号码: ${bingo.recommendedNumbers.map((n) => n.toString().padLeft(2, '0')).join(' ')}');
      sb.writeln('信心度: ${bingo.confidenceScore}%');
      sb.writeln('${bingo.strategy}\n');
    }

    if (footballPatterns != null && footballPatterns.isNotEmpty) {
      sb.writeln('⚽ 足球勝分差分析');
      footballPatterns.forEach((league, pattern) {
        if (pattern.matchCount > 0) {
          sb.writeln('${pattern.summary}');
        }
      });
      sb.writeln();
    }

    sb.writeln('═' * 52);
    sb.writeln('📝 注: 所有预测仅基于统计分析，不保证准确性');

    return sb.toString();
  }
}
