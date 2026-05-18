import 'package:flutter/material.dart';
import '../services/unified_prediction_service.dart';
import '../services/lottery_539_analyzer.dart';
import '../services/bingo_analyzer.dart' as bingo_analyzer;
import '../services/lottery_service.dart';

/// 统一预测展示屏幕
/// 展示 539、宾果、足球 的所有预测结果
class UnifiedPredictionScreen extends StatefulWidget {
  const UnifiedPredictionScreen({super.key});

  @override
  State<UnifiedPredictionScreen> createState() => _UnifiedPredictionScreenState();
}

class _UnifiedPredictionScreenState extends State<UnifiedPredictionScreen> {
  final _predictionService = UnifiedPredictionService();
  
  Lottery539Prediction? _lottery539Prediction;
  bingo_analyzer.BingoPrediction? _bingoPrediction;
  Map<String, dynamic>? _footballPrediction;
  
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPredictions();
  }

  @override
  void dispose() {
    _predictionService.dispose();
    super.dispose();
  }

  Future<void> _loadPredictions() async {
    setState(() => _isLoading = true);

    try {
      // 加载539数据
      final lottery539Records = await LotteryService.loadCached539();
      
      // 加载宾果数据 (模拟数据 - 实际应从服务读取)
      final bingoDraws = _generateSampleBingoData();

      // 并发执行所有预测
      final results = await Future.wait([
        _predictionService.predict539(
          historicalRecords: lottery539Records,
          lookbackDays: 180,
        ),
        _predictionService.predictBingo(
          historicalDraws: bingoDraws,
          lookbackDraws: 100,
        ),
      ]);

      setState(() {
        _lottery539Prediction = results[0] as Lottery539Prediction;
        _bingoPrediction = results[1] as bingo_analyzer.BingoPrediction;
        _isLoading = false;
        _errorMessage = null;
      });

      // 生成足球报告
      _generateFootballPrediction();
    } catch (e) {
      setState(() {
        _errorMessage = '加载预测失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _generateFootballPrediction() async {
    try {
      final patterns = _predictionService.getAllFootballPatterns();
      final report = _predictionService.generateFootballReport();

      setState(() {
        _footballPrediction = {
          'report': report,
          'patterns': patterns,
          'generated_at': DateTime.now().toIso8601String(),
        };
      });
    } catch (e) {
      print('足球预测生成失败: $e');
    }
  }

  List<bingo_analyzer.BingoDraw> _generateSampleBingoData() {
    return [
      bingo_analyzer.BingoDraw(
        drawNo: 1,
        drawDate: '2026-05-15',
        numbers: List.generate(20, (i) => i + 1),
        superNum: '5',
      ),
      bingo_analyzer.BingoDraw(
        drawNo: 2,
        drawDate: '2026-05-16',
        numbers: List.generate(20, (i) => (i * 4 + 1) % 80 + 1),
        superNum: '10',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎰 综合预测中心'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadPredictions,
            tooltip: '刷新预测',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : _buildPredictionTabs(),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('分析中...'),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage ?? '未知错误'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadPredictions,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionTabs() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: '539彩票', icon: Icon(Icons.local_activity)),
              Tab(text: '宾果', icon: Icon(Icons.grid_on)),
              Tab(text: '足球', icon: Icon(Icons.sports_soccer)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildLottery539Tab(),
                _buildBingoTab(),
                _buildFootballTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLottery539Tab() {
    if (_lottery539Prediction == null) {
      return const Center(child: Text('暂无数据'));
    }

    final pred = _lottery539Prediction!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 推荐号码卡片
          _buildRecommendationCard(
            title: '🎯 推荐号码',
            numbers: pred.recommendedNumbers,
            confidence: pred.confidence.toInt(),
          ),

          const SizedBox(height: 16),

          // 策略说明
          _buildStrategyCard(pred.strategy),

          const SizedBox(height: 16),

          // 详细分析
          _buildAnalysisCard('📊 详细分析', pred.analysis),

          const SizedBox(height: 16),

          // 号码统计
          if (pred.numberStats.isNotEmpty)
            _buildNumberStatsCard(pred.numberStats),
        ],
      ),
    );
  }

  Widget _buildBingoTab() {
    if (_bingoPrediction == null) {
      return const Center(child: Text('暂无数据'));
    }

    final pred = _bingoPrediction!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRecommendationCard(
            title: '🎲 推荐号码 (宾果)',
            numbers: pred.recommendedNumbers,
            confidence: pred.confidenceScore,
          ),

          const SizedBox(height: 16),

          _buildStrategyCard(pred.strategy),

          const SizedBox(height: 16),

          _buildAnalysisCard('📊 分析报告', pred.detailedAnalysis),

          const SizedBox(height: 16),

          if (pred.allStats.isNotEmpty)
            _buildBingoNumberStats(pred.allStats),
        ],
      ),
    );
  }

  Widget _buildFootballTab() {
    if (_footballPrediction == null) {
      return const Center(child: Text('暂无数据'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚽ 足球勝分差规律分析',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            _footballPrediction!['report'] as String,
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard({
    required String title,
    required List<int> numbers,
    required int confidence,
  }) {
    return Card(
      elevation: 4,
      color: const Color(0xFF1a2332),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3DDC97),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getConfidenceColor(confidence),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '信心: $confidence%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: numbers.map((num) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF3DDC97).withOpacity(0.8),
                        const Color(0xFFFFD700).withOpacity(0.6),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    num.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategyCard(String strategy) {
    return Card(
      elevation: 2,
      color: const Color(0xFF1a2332),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '💡 策略说明',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFD700),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strategy,
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisCard(String title, String analysis) {
    return Card(
      elevation: 2,
      color: const Color(0xFF1a2332),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3DDC97),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              analysis,
              style: const TextStyle(fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberStatsCard(List<Number539Stats> stats) {
    final hotNumbers = stats.where((s) => s.heatScore >= 0.6).toList();
    final coldNumbers = stats.where((s) => s.heatScore < 0.3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🔥 热号分析',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: hotNumbers.take(5).map((stat) {
            return Tooltip(
              message: '频率: ${stat.frequency}次, 热度: ${(stat.heatScore * 100).toStringAsFixed(0)}%',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(
                  stat.label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text(
          '❄️ 冷号分析',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: coldNumbers.take(5).map((stat) {
            return Tooltip(
              message: '已${stat.lastDrawDaysAgo}天未出',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue),
                ),
                child: Text(
                  stat.label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBingoNumberStats(List<bingo_analyzer.BingoNumberStat> stats) {
    final hotNumbers = stats.where((s) => s.heatScore >= 0.65).toList();
    final coldNumbers = stats.where((s) => s.heatScore < 0.35).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🔥 热号分析 (Bingo)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: hotNumbers.take(8).map((stat) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                stat.label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text(
          '❄️ 冷号分析 (Bingo)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: coldNumbers.take(8).map((stat) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                stat.label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _getConfidenceColor(int confidence) {
    if (confidence >= 80) return Colors.green;
    if (confidence >= 60) return Colors.orange;
    if (confidence >= 40) return Colors.amber;
    return Colors.grey;
  }
}
