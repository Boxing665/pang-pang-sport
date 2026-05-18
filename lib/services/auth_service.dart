import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firebase 身分驗證服務
///
/// 封裝 Firebase Authentication 的所有操作。
/// 提供電子郵件登入、Google 登入、登出及用戶狀態監聽。
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── 當前用戶 ──────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;

  bool get isLoggedIn => _auth.currentUser != null;

  /// 監聽登入狀態變化的 Stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── 電子郵件 / 密碼 ───────────────────────────────────────────

  /// 用電子郵件和密碼建立新帳戶
  Future<AuthResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user!;

      // 更新顯示名稱
      if (displayName != null && displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }

      // 在 Firestore 建立用戶資料（預設為一般用戶，非 VIP）
      await _createUserDocument(user, displayName: displayName);

      return AuthResult.success(user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.code));
    }
  }

  /// 用電子郵件和密碼登入
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return AuthResult.success(credential.user!);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.code));
    }
  }

  /// 登出
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// 寄送重設密碼郵件
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult.success(null);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.code));
    }
  }

  // ── Firestore 用戶資料 ────────────────────────────────────────

  /// 讀取當前用戶的 VIP 狀態
  Future<bool> isVipUser() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      return doc.data()?['isVIP'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 讀取用戶 Firestore 文件（以 Stream 持續監聽）
  Stream<DocumentSnapshot<Map<String, dynamic>>>? userDocumentStream() {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _firestore.collection('users').doc(user.uid).snapshots();
  }

  // ── 私有輔助方法 ──────────────────────────────────────────────

  Future<void> _createUserDocument(User user, {String? displayName}) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final snapshot = await docRef.get();

    // 若文件已存在則不覆蓋（避免重複建立時清空資料）
    if (!snapshot.exists) {
      await docRef.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': displayName ?? user.displayName ?? '',
        'isVIP': false,       // 預設非 VIP，由管理員手動升級
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } else {
      // 僅更新最後登入時間
      await docRef.update({'lastLoginAt': FieldValue.serverTimestamp()});
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return '此電子郵件已被使用，請直接登入或使用其他信箱。';
      case 'invalid-email':
        return '電子郵件格式不正確。';
      case 'weak-password':
        return '密碼強度不足，請使用至少 6 位字元。';
      case 'user-not-found':
        return '找不到此帳戶，請確認電子郵件或先行註冊。';
      case 'wrong-password':
      case 'invalid-credential':
        return '電子郵件或密碼錯誤，請重新輸入。';
      case 'user-disabled':
        return '此帳戶已被停用，請聯絡客服。';
      case 'too-many-requests':
        return '登入嘗試次數過多，請稍後再試。';
      case 'network-request-failed':
        return '網路連線失敗，請檢查你的網路。';
      default:
        return '發生未知錯誤（$code），請稍後再試。';
    }
  }
}

/// 封裝 Auth 操作結果，避免讓 UI 直接處理 Firebase 例外
class AuthResult {
  final bool isSuccess;
  final User? user;
  final String? errorMessage;

  const AuthResult._({
    required this.isSuccess,
    this.user,
    this.errorMessage,
  });

  factory AuthResult.success(User? user) =>
      AuthResult._(isSuccess: true, user: user);

  factory AuthResult.failure(String message) =>
      AuthResult._(isSuccess: false, errorMessage: message);
}
