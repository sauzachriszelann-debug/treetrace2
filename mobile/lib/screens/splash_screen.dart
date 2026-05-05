import 'package:flutter/material.dart';
import '../services/theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a3323), Color(0xFF2d6b3a), Color(0xFF3a8a4a)],
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
              ),
              child: const Icon(Icons.park, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 20),
            const Text('TreeTrace',
                style: TextStyle(color: Colors.white, fontSize: 30,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('Panabo City Tree Inventory',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
            const SizedBox(height: 48),
            SizedBox(width: 28, height: 28,
                child: CircularProgressIndicator(
                    color: Colors.white.withOpacity(0.7), strokeWidth: 2)),
          ]),
        ),
      ),
    );
  }
}
