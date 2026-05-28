import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// ════════════════════════════════════════════════════════════════
/// Google用户信息
/// ════════════════════════════════════════════════════════════════
class GoogleUser {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final DateTime loginTime;

  GoogleUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    required this.loginTime,
  });

  factory GoogleUser.fromGoogleSignInAccount(GoogleSignInAccount account) {
    return GoogleUser(
      uid: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
      loginTime: DateTime.now(),
    );
  }

  factory GoogleUser.fromJson(Map<String, dynamic> json) => GoogleUser(
    uid: json['uid'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String?,
    photoUrl: json['photoUrl'] as String?,
    loginTime: DateTime.parse(json['loginTime'] as String),
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'loginTime': loginTime.toIso8601String(),
  };
}

/// ════════════════════════════════════════════════════════════════
/// Google认证服务
/// ════════════════════════════════════════════════════════════════

class GoogleAuthService {
  static const _userKey = 'google_user_v2';
  static const _tokenKey = 'google_token_v2';

  static final GoogleAuthService _instance = GoogleAuthService._internal();

  factory GoogleAuthService() => _instance;

  GoogleAuthService._internal();

  GoogleUser? _currentUser;
  String? _authToken;

  late final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  GoogleUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// 真实Google登入
  Future<GoogleUser?> signInWithGoogle() async {
    try {
      // 初始化GoogleSignIn
      await _googleSignIn.initialize();
      
      // 执行身份验证
      final account = await _googleSignIn.authenticate();

      _currentUser = GoogleUser.fromGoogleSignInAccount(account);
      _authToken = 'authenticated'; // 简化处理

      // 保存到本地
      await _saveUser(_currentUser!);
      await _saveToken(_authToken!);

      print('✅ Google登入成功: ${_currentUser!.email}');
      return _currentUser;
    } catch (e) {
      print('❌ Google登入失败: $e');
      return null;
    }
  }

  /// 登出
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      _authToken = null;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      await prefs.remove(_tokenKey);
      
      print('✅ 已登出');
    } catch (e) {
      print('❌ 登出失败: $e');
    }
  }

  /// 恢复登录状态（应用启动时调用）
  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      final token = prefs.getString(_tokenKey);

      if (userJson != null && token != null) {
        final userMap = jsonDecode(userJson) as Map<String, dynamic>;
        _currentUser = GoogleUser.fromJson(userMap);
        _authToken = token;
        print('✅ 会话已恢复: ${_currentUser!.email}');
      } else {
        // 尝试静默登录
        await _silentSignIn();
      }
    } catch (e) {
      print('⚠️ 恢复会话失败: $e');
    }
  }

  /// 静默登录（使用之前保存的账户）
  Future<void> _silentSignIn() async {
    try {
      await _googleSignIn.initialize();
      final account = await _googleSignIn.attemptLightweightAuthentication();
      if (account != null) {
        _currentUser = GoogleUser.fromGoogleSignInAccount(account);
        _authToken = 'authenticated';
        
        await _saveUser(_currentUser!);
        await _saveToken(_authToken!);
        
        print('✅ 静默登录成功');
      }
    } catch (e) {
      print('⚠️ 静默登录失败: $e');
    }
  }

  /// 保存用户信息
  Future<void> _saveUser(GoogleUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
    } catch (e) {
      print('保存用户信息失败: $e');
    }
  }

  /// 保存令牌
  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      print('保存令牌失败: $e');
    }
  }
}
