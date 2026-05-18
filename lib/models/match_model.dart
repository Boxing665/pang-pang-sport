import 'package:flutter/material.dart';

class Match {
  final String homeTeam;
  final String awayTeam;
  final String score;
  final String status;
  final Color homeColor;
  final Color awayColor;
  
  // 新增統計數據欄位，讓詳情頁更真實
  final double possession; // 控球率 (0.0 to 1.0)
  final int homeShots;
  final int awayShots;

  Match({
    required this.homeTeam, required this.awayTeam, required this.score,
    required this.status, required this.homeColor, required this.awayColor,
    this.possession = 0.5, this.homeShots = 10, this.awayShots = 10,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      homeTeam: json['homeTeam'] ?? '未知隊伍',
      awayTeam: json['awayTeam'] ?? '未知隊伍',
      score: json['score'] ?? '0 - 0',
      status: json['status'] ?? '準備中',
      homeColor: _parseColor(json['homeColor']),
      awayColor: _parseColor(json['awayColor']),
      possession: (json['possession'] ?? 50.0) / 100.0,
      homeShots: json['homeShots'] ?? 0,
      awayShots: json['awayShots'] ?? 0,
    );
  }

  static Color _parseColor(dynamic colorValue) {
    if (colorValue == null) return Colors.grey;
    try {
      final String colorString = colorValue.toString();
      if (colorString.startsWith('0x')) {
        return Color(int.parse(colorString));
      }
      return Colors.blueGrey;
    } catch (_) {
      return Colors.blueGrey;
    }
  }
}