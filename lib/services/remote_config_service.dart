import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

/// 負責處理 Firebase Remote Config 的動態權重更新
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  FirebaseRemoteConfig? _remoteConfigInstance;

  // 確保只有在真正需要且 Firebase 已初始化時才存取 instance
  FirebaseRemoteConfig? get _remoteConfig {
    try {
      _remoteConfigInstance ??= FirebaseRemoteConfig.instance;
      return _remoteConfigInstance;
    } catch (_) {
      return null;
    }
  }

  // 使用 ValueNotifier 讓 UI 或分析引擎能訂閱權重的變化
  final ValueNotifier<Map<String, double>> soccerWeightsNotifier = ValueNotifier({
    "elo_diff": 0.42,
    "avg_goals_combined": 0.35,
    "draw_rate_combined": 0.23,
    "base_rate": 0.25
  });

  static const String _weightsKey = 'soccer_draw_weights';

  Future<void> initialize() async {
    final config = _remoteConfig;
    if (config == null) return;

    // 1. 設定抓取間隔（iOS 模擬器/Debug 模式設為 0，確保即時同步）
    await config.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: kDebugMode ? Duration.zero : const Duration(hours: 1),
    ));

    // 2. 設定本地預設權重，防止網路不穩時解析失敗
    try {
      await config.setDefaults({
        _weightsKey: jsonEncode({
          "elo_diff": 0.42,
          "avg_goals_combined": 0.35,
          "draw_rate_combined": 0.23,
          "base_rate": 0.25
        }),
      });
    } catch (e) {
      debugPrint('Remote Config setDefaults 失敗: $e');
    }

    // 3. 初次抓取並激活
    try {
      await config.fetchAndActivate();
    } catch (e) {
      debugPrint('Remote Config 抓取失敗: $e');
    }
    _updateLocalWeights();

    // 4. 自動監聽雲端更新 (Real-time Config)
    // 當你在 Firebase Console 點擊「發佈」時，此流會立即觸發
    config.onConfigUpdated.listen((event) async {
      await config.activate();
      _updateLocalWeights();
      debugPrint('Firebase Remote Config 已自動同步最新權重');
    });

  }

  /// 解析 JSON 並更新通知器
  void _updateLocalWeights() {
    if (_remoteConfigInstance == null) return;
    final jsonString = _remoteConfigInstance!.getString(_weightsKey);
    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      soccerWeightsNotifier.value = data.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (e) {
      debugPrint('Remote Config JSON 解析錯誤: $e');
    }
  }
}