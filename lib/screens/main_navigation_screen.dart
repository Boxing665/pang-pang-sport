import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'latest_matches_screen.dart';
import 'lottery_screen.dart';
import 'bingo_screen.dart';
import 'unified_prediction_screen.dart';
import '../services/google_auth_service.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final _authService = GoogleAuthService();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const LatestMatchesScreen(),
      const HomeScreen(),
      const LotteryScreen(),
      const BingoScreen(),
      const UnifiedPredictionScreen(),
    ];
    _authService.restoreSession();
  }

  void _handleGoogleSignIn() async {
    if (_authService.isLoggedIn) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('用户信息'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('邮箱: ${_authService.currentUser?.email}'),
              Text('用户: ${_authService.currentUser?.displayName}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await _authService.signOut();
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('登出', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 登入成功: ${user.email}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎰 胖胖體育'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: _handleGoogleSignIn,
              child: _authService.isLoggedIn
                  ? Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        child: Text(_authService.currentUser?.displayName?.substring(0, 1) ?? 'U'),
                      ),
                      const SizedBox(width: 8),
                      Text(_authService.currentUser?.displayName ?? 'User'),
                    ],
                  )
                  : const Row(
                    children: [
                      Icon(Icons.login),
                      SizedBox(width: 4),
                      Text('登入'),
                    ],
                  ),
            ),
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: const Color(0xFF3DDC97),
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.shifting,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.new_releases),
            label: '所有比賽',
            backgroundColor: Color(0xFF1E1E1E),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_basketball),
            label: '體育',
            backgroundColor: Color(0xFF1E1E1E),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.confirmation_number_rounded),
            label: '樂透',
            backgroundColor: Color(0xFF1E1E1E),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.casino_outlined),
            label: '台灣賓果',
            backgroundColor: Color(0xFF1E1E1E),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: '統合預測',
            backgroundColor: Color(0xFF1E1E1E),
          ),
        ],
      ),
    );
  }
}
