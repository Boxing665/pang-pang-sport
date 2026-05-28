import 'package:flutter/material.dart';
import '../services/bingo_analysis_service.dart';

/// Bingo数据分析面板
class BingoAnalysisPanel extends StatelessWidget {
  final List<int> allNumbers;
  final int period;

  const BingoAnalysisPanel({
    super.key,
    required this.allNumbers,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    if (allNumbers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            '暂无数据',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      );
    }

    final stats = BingoAnalysisService.computeComprehensiveStats(allNumbers);
    final hotNumbers = BingoAnalysisService.getHotNumbers(allNumbers, limit: 8);
    final coldNumbers = BingoAnalysisService.getColdNumbers(allNumbers, limit: 8);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 综合分析面板
          _buildComprehensiveAnalysisCard(stats),
          const SizedBox(height: 16),

          // 热门号码
          _buildHotNumbersCard(hotNumbers),
          const SizedBox(height: 16),

          // 冷门号码
          _buildColdNumbersCard(coldNumbers),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildComprehensiveAnalysisCard(Map<String, dynamic> stats) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart, color: Color(0xFF7C3AED), size: 20),
              SizedBox(width: 8),
              Text(
                '综合分析',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2,
            children: [
              _buildStatItem(
                '大',
                stats['largeCount'].toString(),
                '${stats['largePercent']}%',
                const Color(0xFFFF9800),
              ),
              _buildStatItem(
                '小',
                stats['smallCount'].toString(),
                '${stats['smallPercent']}%',
                const Color(0xFF2196F3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String count, String percent, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                count,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
              Text(
                percent,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHotNumbersCard(List<MapEntry<int, int>> hotNumbers) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_fire_department, color: Color(0xFFFF6B6B), size: 20),
              SizedBox(width: 8),
              Text(
                '热门号码 (今日)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: hotNumbers.map((entry) {
              return _buildNumberBall(
                entry.key.toString().padLeft(2, '0'),
                entry.value.toString(),
                const Color(0xFFFF6B6B),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildColdNumbersCard(List<MapEntry<int, int>> coldNumbers) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(30), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.ice_skating, color: Color(0xFF4FC3F7), size: 20),
              SizedBox(width: 8),
              Text(
                '冷门号码 (未出期数)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: coldNumbers.map((entry) {
              return _buildNumberBall(
                entry.key.toString().padLeft(2, '0'),
                entry.value.toString(),
                const Color(0xFF4FC3F7),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberBall(String number, String subtitle, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(40),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
