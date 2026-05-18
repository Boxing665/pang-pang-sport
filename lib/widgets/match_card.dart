import 'package:flutter/material.dart';

import '../models/match_fixture.dart';
import '../models/match_prediction.dart';
import '../models/sport_type.dart';
import '../theme/app_theme.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.fixture,
    required this.prediction,
    this.onTap,
  });

  final MatchFixture fixture;
  final MatchPrediction prediction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(
                icon: _sportIcon(fixture.sport),
                label: _sportLabel(fixture.sport),
                color: _sportColor(fixture.sport),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fixture.league,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatStartTime(fixture.startTime),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TeamColumn(
                  alignment: CrossAxisAlignment.start,
                  teamName: fixture.homeTeam,
                  formText: _formText(fixture.homeForm.lastFiveResults),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '對',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppTheme.highlight,
                  ),
                ),
              ),
              Expanded(
                child: _TeamColumn(
                  alignment: CrossAxisAlignment.end,
                  teamName: fixture.awayTeam,
                  formText: _formText(fixture.awayForm.lastFiveResults),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── 盤口賠率 ──────────────────────────────────────────────
          _OddsRow(fixture: fixture),
          const SizedBox(height: 10),
          Row(
            children: [
              if (fixture.sport == SportType.football) ...[
                // ── 足球：盤口推算比分 ─────────────────────────────────
                Expanded(
                  child: _InfoTile(
                    label: '盤口推算比分',
                    value: _footballScoreLabel(fixture, prediction),
                    accentColor: AppTheme.highlight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoTile(
                    label: '大小分',
                    value: _overUnderLabel(fixture, prediction),
                    accentColor: AppTheme.secondaryAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoTile(
                    label: '勝負預測',
                    value: _winnerLabel(fixture, prediction),
                    accentColor: AppTheme.primaryAccent,
                  ),
                ),
              ] else ...[
                // ── 籃球 / 棒球：移除預測比分，改用賭盤分布 ──────────
                Expanded(
                  child: _InfoTile(
                    label: '賭盤看好',
                    value: _winnerLabel(fixture, prediction),
                    accentColor: AppTheme.highlight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoTile(
                    label: '勝分差',
                    value: _spreadLabel(fixture, prediction),
                    accentColor: Colors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoTile(
                    label: '大小分',
                    value: _overUnderLabel(fixture, prediction),
                    accentColor: AppTheme.secondaryAccent,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x12000000),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prediction.summary,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (fixture.analystNote.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '分析備註：${fixture.analystNote}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: content,
      ),
    );
  }

  String _formatStartTime(DateTime dateTime) {
    final month = dateTime.month.toString();
    final day = dateTime.day.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  String _formText(List<String> results) {
    if (results.isEmpty) {
      return '近況資料不足';
    }
    return '近${results.length}場 ${results.join('-')}';
  }

  String _sportLabel(SportType sport) {
    switch (sport) {
      case SportType.football:
        return '足球';
      case SportType.baseball:
        return '棒球';
      case SportType.basketball:
        return '籃球';
    }
  }

  IconData _sportIcon(SportType sport) {
    switch (sport) {
      case SportType.football:
        return Icons.sports_soccer_rounded;
      case SportType.baseball:
        return Icons.sports_baseball_rounded;
      case SportType.basketball:
        return Icons.sports_basketball_rounded;
    }
  }

  Color _sportColor(SportType sport) {
    switch (sport) {
      case SportType.football:
        return AppTheme.primaryAccent;
      case SportType.baseball:
        return AppTheme.secondaryAccent;
      case SportType.basketball:
        return AppTheme.highlight;
    }
  }

  /// 大/小分推薦標籤（三種運動通用）
  String _overUnderLabel(MatchFixture f, MatchPrediction p) {
    final odds = f.odds;
    final unit = f.sport == SportType.football ? '球' : '分';
    final aiTotal = p.predictedHomeScore + p.predictedAwayScore;

    if (odds.overLine > 0 && odds.bookmakerName != '模型推算') {
      // ── 有真實賭盤線 ──────────────────────────────────────────
      final line = odds.overLine % 1 == 0
          ? odds.overLine.toInt().toString()
          : odds.overLine.toStringAsFixed(1);
      if (odds.overOdds < odds.underOdds) {
        return '大$line$unit (${odds.overOdds.toStringAsFixed(2)})';
      } else if (odds.underOdds < odds.overOdds) {
        return '小$line$unit (${odds.underOdds.toStringAsFixed(2)})';
      }
      // 賠率相同 → AI 預估方向
      if (aiTotal > odds.overLine) return '大$line$unit';
      if (aiTotal < odds.overLine) return '小$line$unit';
      return '$line$unit';
    }

    // ── 無真實賭盤線 ──────────────────────────────────────────────
    // 棒球 / 籃球：盤口不存在時不顯示 AI 估算（僅參考賭盤）
    if (f.sport == SportType.baseball || f.sport == SportType.basketball) return '暫無盤口';
    if (aiTotal <= 0) return '—';
    final aiLine = aiTotal % 1 == 0
        ? aiTotal.toInt().toString()
        : aiTotal.toStringAsFixed(1);
    final baseline = f.homeForm.averageScored + f.awayForm.averageScored;
    if (aiTotal > baseline) return 'AI大$aiLine$unit';
    if (aiTotal < baseline) return 'AI小$aiLine$unit';
    return 'AI $aiLine$unit';
  }

  /// 足球盤口推算比分：以莊家 spread + overLine 反推主客預期進球
  String _footballScoreLabel(MatchFixture f, MatchPrediction p) {
    // 有真實莊家盤口時，直接用 marketHomeExp / marketAwayExp（已由 spread+overLine 解出）
    if (p.marketHomeExp > 0 && p.marketAwayExp > 0 &&
        f.odds.bookmakerName != '模型推算') {
      return '${p.marketHomeExp.round()} : ${p.marketAwayExp.round()}';
    }
    // 無真實賭盤時退回 AI 融合預測
    return '${p.predictedHomeScore} : ${p.predictedAwayScore}';
  }

  /// 賭盤看好方向：優先用賠率直接比較，退回公平隱含機率 / ensemble 機率
  String _winnerLabel(MatchFixture f, MatchPrediction p) {
    final odds = f.odds;

    // 足球：直接用賠率判斷和局（賠率最低 = 莊家最看好該結果）
    // 比 fairDrawProb 更可靠，因為不受 overround 計算方式影響
    if (f.sport == SportType.football &&
        odds.draw > 0 && odds.draw < 99 &&
        odds.draw <= odds.homeWin && odds.draw <= odds.awayWin) {
      final drawPct = (odds.fairDrawProb * 100).round().clamp(20, 65);
      return '看好平局 $drawPct%';
    }

    final homeP = odds.fairHomeProb > 0.05 ? odds.fairHomeProb : p.ensembleHomeWinPct;
    final drawP = f.sport == SportType.football
        ? (odds.fairDrawProb > 0.05 ? odds.fairDrawProb : p.ensembleDrawPct)
        : 0.0;
    final awayP = odds.fairAwayProb > 0.05 ? odds.fairAwayProb : p.ensembleAwayWinPct;

    String shorten(String name) =>
        name.length > 5 ? '${name.substring(0, 5)}..' : name;

    if (drawP > homeP && drawP > awayP) {
      return '看好平局 ${(drawP * 100).round().clamp(20, 65)}%';
    } else if (homeP >= awayP) {
      return '${shorten(f.homeTeam)} ${(homeP * 100).round().clamp(40, 99)}%';
    } else {
      return '${shorten(f.awayTeam)} ${(awayP * 100).round().clamp(40, 99)}%';
    }
  }

  /// 勝分差標籤（籃球 / 棒球）：仿照運彩格式顯示預測勝方及分差區間
  String _spreadLabel(MatchFixture f, MatchPrediction p) {
    final odds = f.odds;
    final homeP = odds.fairHomeProb > 0.05 ? odds.fairHomeProb : p.ensembleHomeWinPct;
    final awayP = odds.fairAwayProb > 0.05 ? odds.fairAwayProb : p.ensembleAwayWinPct;
    final homeLeads = homeP >= awayP;
    final winner = homeLeads ? f.homeTeam : f.awayTeam;
    final short = winner.length > 4 ? '${winner.substring(0, 4)}..' : winner;
    final winnerP = homeLeads ? homeP : awayP;
    final spreadAbs = odds.spread.abs();
    final hasRealSpread = odds.spread != 0.0 && odds.bookmakerName != '模型推算';

    if (f.sport == SportType.basketball) {
      // 籃球：讓分值 → 映射到運彩勝分差區間（1-5、6-10、11-15、16-20、>20）
      if (!hasRealSpread) return homeLeads ? '主場看好' : '客場看好';
      final String range;
      if (spreadAbs <= 5.5) {
        range = '1-5分';
      } else if (spreadAbs <= 10.5) {
        range = '6-10分';
      } else if (spreadAbs <= 15.5) {
        range = '11-15分';
      } else if (spreadAbs <= 20.5) {
        range = '16-20分';
      } else {
        range = '>20分';
      }
      return '$short $range';
    } else {
      // 棒球：讓分值 + 勝率 → 映射到運彩勝分差區間（1分、2分、>2分）
      if (!hasRealSpread) return homeLeads ? '主場看好' : '客場看好';
      final String range;
      if (spreadAbs >= 2.5 || winnerP >= 0.65) {
        range = '>2分';
      } else if (spreadAbs >= 1.5 || winnerP >= 0.57) {
        range = '2分';
      } else {
        range = '1分';
      }
      return '$short $range';
    }
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.alignment,
    required this.teamName,
    required this.formText,
  });

  final CrossAxisAlignment alignment;
  final String teamName;
  final String formText;

  @override
  Widget build(BuildContext context) {
    final textAlign =
        alignment == CrossAxisAlignment.end ? TextAlign.end : TextAlign.start;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          teamName,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          formText,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// 盤口賠率列（主勝 / 和局 / 客勝 + 盤口來源）
class _OddsRow extends StatelessWidget {
  const _OddsRow({required this.fixture});
  final MatchFixture fixture;

  @override
  Widget build(BuildContext context) {
    final odds = fixture.odds;
    final isSoccer = fixture.sport == SportType.football;
    final source = odds.isFromBookmaker
        ? (odds.bookmakerName.isNotEmpty ? odds.bookmakerName : 'Bet365')
        : 'ESPN';
    final sourceColor =
        odds.isFromBookmaker ? Colors.green.shade400 : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x0CFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _OddsCell(
                label: '主勝',
                value: odds.homeWin.toStringAsFixed(2),
                highlight: odds.fairHomeProb >= odds.fairAwayProb &&
                    odds.fairHomeProb >= odds.fairDrawProb,
              ),
              if (isSoccer)
                _OddsCell(
                  label: '和局',
                  value: odds.draw < 99 ? odds.draw.toStringAsFixed(2) : '—',
                  highlight: false,
                ),
              _OddsCell(
                label: '客勝',
                value: odds.awayWin.toStringAsFixed(2),
                highlight: odds.fairAwayProb > odds.fairHomeProb &&
                    odds.fairAwayProb >= odds.fairDrawProb,
              ),
              if (isSoccer && odds.overLine > 0) ...[
                const SizedBox(width: 6),
                _OddsCell(
                  label: '大${_lineStr(odds.overLine)}',
                  value: odds.overOdds.toStringAsFixed(2),
                  highlight: odds.overOdds <= odds.underOdds,
                  color: Colors.amber.shade300,
                ),
                _OddsCell(
                  label: '小${_lineStr(odds.overLine)}',
                  value: odds.underOdds.toStringAsFixed(2),
                  highlight: odds.underOdds < odds.overOdds,
                  color: Colors.cyan.shade300,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (_hasSmartMoney) ...[
                _SmartMoneyBadge(fixture: fixture),
                const Spacer(),
              ] else
                const Spacer(),
              Icon(Icons.circle, size: 7, color: sourceColor),
              const SizedBox(width: 4),
              Text(
                source,
                style: TextStyle(fontSize: 10, color: sourceColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasSmartMoney =>
      fixture.odds.hasReverseLineMovement && fixture.odds.errorMargin > 0.03;

  String _lineStr(double line) =>
      line % 1 == 0 ? line.toInt().toString() : line.toStringAsFixed(1);
}

class _SmartMoneyBadge extends StatelessWidget {
  const _SmartMoneyBadge({required this.fixture});
  final MatchFixture fixture;

  @override
  Widget build(BuildContext context) {
    final mm = fixture.odds.marketMovement;
    final side = mm > 0 ? fixture.homeTeam : fixture.awayTeam;
    final shortSide = side.length > 5 ? '${side.substring(0, 5)}..' : side;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFD700).withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, size: 11, color: Color(0xFFFFD700)),
          const SizedBox(width: 3),
          Text(
            '聰明錢→$shortSide',
            style: const TextStyle(fontSize: 9, color: Color(0xFFFFD700), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _OddsCell extends StatelessWidget {
  const _OddsCell({
    required this.label,
    required this.value,
    required this.highlight,
    this.color,
  });
  final String label;
  final String value;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (highlight ? Colors.white : Colors.white54);
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: fg.withAlpha(180))),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}