import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// 登入 / 註冊畫面
///
/// 未登入的用戶在此輸入電子郵件和密碼，完成後 [AuthGate]（在 main.dart）
/// 會自動導向主畫面。
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _authService = AuthService();

  bool _isLogin = true;       // true = 登入模式，false = 註冊模式
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  // ── 提交表單 ───────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    AuthResult result;
    if (_isLogin) {
      result = await _authService.signInWithEmail(
        email: email,
        password: password,
      );
    } else {
      result = await _authService.registerWithEmail(
        email: email,
        password: password,
        displayName: _displayNameController.text.trim(),
      );
    }

    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.errorMessage;
      });
    }
    // 成功時 StreamBuilder 會自動切換到主畫面，不需要手動 Navigator.push
  }

  // ── 忘記密碼 ───────────────────────────────────────────────────
  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = '請先輸入你的電子郵件再點擊忘記密碼。');
      return;
    }

    final result = await _authService.sendPasswordResetEmail(email);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess ? '重設密碼郵件已寄出，請檢查你的信箱。' : result.errorMessage!,
        ),
        backgroundColor: result.isSuccess ? Colors.green : Colors.red,
      ),
    );
  }

  // ── 切換登入 / 註冊 ────────────────────────────────────────────
  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // ── Logo ───────────────────────────────────────
                  const Text(
                    '🐻',
                    style: TextStyle(fontSize: 56),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '胖胖體育',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3DDC97),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '專業體育比賽預測',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ── 標題 ───────────────────────────────────────
                  Text(
                    _isLogin ? '登入帳戶' : '建立帳戶',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),

                  // ── 顯示名稱（僅註冊時顯示）────────────────────
                  if (!_isLogin) ...[
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: '暱稱',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (!_isLogin && (v == null || v.trim().isEmpty)) {
                          return '請輸入暱稱';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 電子郵件 ───────────────────────────────────
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '電子郵件',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '請輸入電子郵件';
                      final emailRegex =
                          RegExp(r'^[\w.-]+@([\w-]+\.)+[\w-]{2,}$');
                      if (!emailRegex.hasMatch(v.trim())) return '請輸入有效的電子郵件格式';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── 密碼 ───────────────────────────────────────
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密碼',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    textInputAction:
                        _isLogin ? TextInputAction.done : TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) {
                      if (v == null || v.isEmpty) return '請輸入密碼';
                      if (!_isLogin && v.length < 6) return '密碼至少需要 6 位字元';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // ── 忘記密碼（登入模式） ───────────────────────
                  if (_isLogin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPassword,
                        child: const Text('忘記密碼？'),
                      ),
                    ),

                  // ── 錯誤訊息 ───────────────────────────────────
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade800),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── 主按鈕 ─────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isLogin ? '登入' : '建立帳戶'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 切換模式 ───────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLogin ? '還沒有帳戶？' : '已有帳戶？',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      TextButton(
                        onPressed: _toggleMode,
                        child: Text(_isLogin ? '立即註冊' : '返回登入'),
                      ),
                    ],
                  ),

                  // ── 安全說明 ───────────────────────────────────
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Text(
                        '由 Google Firebase 提供安全保護',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
