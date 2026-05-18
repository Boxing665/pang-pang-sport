/// 應用程式配置
/// 
/// 更新此文件以添加實際的 API keys 和配置
class AppConfig {
  // ========== TheOddsAPI 配置 ==========
  // 用於獲取全球賭盤賠率數據
  // 註冊地址: https://www.theoddsapi.com/
  // 
  // 免費方案提供:
  // - 實時賠率數據
  // - 多種運動支持 (足球、籃球、棒球等)
  // - 每月 500 次請求限制
  static const String oddsApiKey = 'YOUR_ODDS_API_KEY';
  static const String oddsApiBaseUrl = 'https://api.the-odds-api.com/v4';

  // ========== OpenAI 配置 ==========
  static const String openAiApiKey = 'YOUR_OPENAI_API_KEY';
  static const String openAiBaseUrl = 'https://api.openai.com/v1/chat/completions';

  // ========== ESPN API 配置 ==========
  // 用於獲取賽事信息、球隊數據、比賽統計
  // ESPN 提供免費的公開 API (無需 API key)
  static const String espnBaseUrl = 'https://site.api.espn.com/v2/site/en/sports';

  // ========== RapidAPI 配置 ==========
  // 備選方案，提供多種體育API (需付費)
  static const String rapidApiHost = 'api-football-v1.p.rapidapi.com';
  static const String rapidApiKey = 'YOUR_RAPIDAPI_KEY';

  // ========== 數據源配置 ==========
  // 是否使用真實數據 (需要有效的 API keys)
  static const bool useRealDataByDefault = true;

  // 數據快取時間 (分鐘)
  static const int dataCacheMinutes = 30;

  // ========== 支持的聯賽 ==========
  static const List<String> supportedFootballLeagues = [
    'EPL', // 英超
    'La Liga', // 西甲
    'Serie A', // 意甲
    'Bundesliga', // 德甲
    'Ligue 1', // 法甲
    'J1 League', // 日職
    'MLS', // 美國足球大聯盟
    'Primeira Liga', // 葡超
    'Eredivisie', // 荷甲
    'A-League', // 澳超
  ];

  static const List<String> supportedBasketballLeagues = [
    'NBA',
    'EuroLeague',
  ];

  static const List<String> supportedBaseballLeagues = [
    'MLB', // 美職
    'CPBL', // 中華職棒
    'NPB', // 日職棒
  ];

  // ========== 預測引擎配置 ==========
  // 用於調整預測演算法的參數
  static const double homeAdvantageWeight = 0.15;
  static const double formWeight = 0.25;
  static const double injuriesWeight = 0.10;
  static const double headToHeadWeight = 0.20;
  static const double marketTrendWeight = 0.30;

  // ========== MLS 專用配置 ==========
  // MLS 賽事特性調整參數
  static const double mlsWeatherFactor = 0.08;     // 美國天氣多變影響大
  static const double mlsTeamDepthFactor = 0.12;   // 球隊深度差異
  static const double mlsAttackingStyleFactor = 0.18; // MLS 進攻風格突出
  static const double mlsDefensiveConsistency = 0.14; // 防線穩定性較低
  static const double mlsPlayerImpactFactor = 0.20;  // 明星球員影響力大（開球權等）
  static const double mlsHomeAdvantage = 1.15;     // MLS 主場優勢偏強（近年數據）
  static const double mlsVenueImpactFactor = 0.16;  // 場地影響（高海拔等）
  
  // ========== 高級預測特徵配置 ==========
  // 用於提升預測准確率到 90%
  static const bool enableAdvancedWeatherAnalysis = true;
  static const bool enablePlayerPerformanceTracking = true;
  static const bool enableVenueImpactAnalysis = true;
  static const bool enableLiveOddsTracking = true;
  static const bool enableMachineLearningEnsemble = true;
  static const int confidenceThresholdPercent = 90;
}

/// API 使用說明
/// 
/// 1. TheOddsAPI (建議用於賭盤數據)
///    - 訪問: https://www.theoddsapi.com/
///    - 免費註冊獲取 API Key
///    - 支持實時賠率、多個博彩商
///    - 更新至: `AppConfig.oddsApiKey`
/// 
/// 2. ESPN API (免費, 用於賽事和球隊數據)
///    - 無需 API Key
///    - 提供 NBA, NFL, MLB, Soccer 等
///    - 已在 real_data_service.dart 中使用
/// 
/// 3. 其他選擇:
///    - RapidAPI: 提供多個體育 API, 需付費
///    - SportsRadar: 企業級解決方案
///    - BetArchives: 歷史賠率數據
