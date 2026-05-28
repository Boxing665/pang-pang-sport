import 'package:flutter/material.dart';
import '../models/lottery_model.dart';
import '../services/lottery_analysis_service.dart';

/// 彩票数据分析面板
class LotteryAnalysisPanel extends StatelessWidget {
  final List<DrawRecord> records;

  const LotteryAnalysisPanel({
    super.key,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
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

    final stats = LotteryAnalysisService.computeComprehensiveStats(records);
    final hotNumbers = LotteryAnalysisService.getHotNumbers(records, limit: 8);
    final coldNumbers = LotteryAnalysisService.getColdNumbers(records, limit: 8);
    final consecutive = LotteryAnalysisService.computeConsecutiveNumbers(records);
    final recentDraws = LotteryAnalysisService.getRecentDraws(records, limit: 10);

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

          // 连号分析
          if (consecutive['consecutive2']!.isNotEmpty)
            _buildConsecutiveCard(consecutive),
          if (consecutive['consecutive2']!.isNotEmpty)
            const SizedBox(height: 16),

          // 最近开奖记录
          _buildRecentDrawsCard(recentDraws),
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
              _buildStatItem(
                '单',
                stats['oddCount'].toString(),
                '${stats['oddPercent']}%',
                const Color(0xFF4CAF50),
              ),
              _buildStatItem(
                '双',
                stats['evenCount'].toString(),
                '${stats['evenPercent']}%',
                const Color(0xFFE91E63),
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

  Widget _buildConsecutiveCard(Map<String, dynamic> consecutive) {
    final cons2 = consecutive['consecutive2'] as List<List<int>>;
    final cons3 = consecutive['consecutive3'] as List<List<int>>;

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
              Icon(Icons.link, color: Color(0xFF9C27B0), size: 20),
              SizedBox(width: 8),
              Text(
                '连号分析',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (cons2.isNotEmpty) ...[
            const Text(
              '热门2连',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cons2.map((pair) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9C27B0).withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF9C27B0).withAlpha(100),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${pair[0]}-${pair[1]}',
                    style: const TextStyle(
                      color: Color(0xFF9C27B0),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (cons3.isNotEmpty) ...[
            const Text(
              '热门3连',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cons3.map((triple) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B9D).withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFF6B9D).withAlpha(100),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${triple[0]}-${triple[1]}-${triple[2]}',
                    style: const TextStyle(
                      color: Color(0xFFFF6B9D),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentDrawsCard(List<DrawRecord> recentDraws) {
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
              Icon(Icons.history, color: Color(0xFF00BCD4), size: 20),
              SizedBox(width: 8),
              Text(
                '最近开奖记录',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentDraws.length,
            separatorBuilder: (_, __) => Divider(
              color: Colors.white.withAlpha(20),
              height: 12,
            ),
            itemBuilder: (_, index) {
              final draw = recentDraws[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          draw.date,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: draw.numbers.map((num) {
                            return Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF00BCD4).withAlpha(40),
                              ),
                              child: Center(
                                child: Text(
                                  num.toString().padLeft(2, '0'),
                                  style: const TextStyle(
                                    color: Color(0xFF00BCD4),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
