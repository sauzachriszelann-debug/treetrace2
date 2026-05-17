import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import '../services/theme.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await context
        .read<AuthProvider>()
        .login(_emailCtrl.text.trim(), _passCtrl.text);

    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      final message = context.read<AuthProvider>().lastError;
      setState(() => _error = message ?? 'Invalid email or password.');
    }
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: kMutedFg, fontSize: 14),
      prefixIcon: Icon(prefixIcon, size: 20, color: kMutedFg),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: kMutedFg.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: kBorder.withOpacity(0.5), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kPrimary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: kPoor.withOpacity(0.5), width: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AuthShell(
      title: 'Welcome Back',
      subtitle: 'Access your tree map, QR scanner, dashboard, and AI tools.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Animated error box for smooth appearance
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _error != null
                ? Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ErrorBox(message: _error!),
            )
                : const SizedBox.shrink(),
          ),

          const _FieldLabel('Email Address'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontWeight: FontWeight.w500),
            decoration: _buildInputDecoration(
              hintText: 'you@example.com',
              prefixIcon: Icons.email_outlined,
            ),
          ),

          const SizedBox(height: 20),

          const _FieldLabel('Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontWeight: FontWeight.w500),
            decoration: _buildInputDecoration(
              hintText: '••••••••',
              prefixIcon: Icons.lock_outline,
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: kMutedFg,
                  ),
                  splashRadius: 24,
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            onFieldSubmitted: (_) => _login(),
          ),

          const SizedBox(height: 32),

          // Main action button with subtle shadow
          Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: kPrimary.withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _loading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
                  : const Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: Divider(color: kBorder.withOpacity(0.5))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'or',
                  style: TextStyle(
                    color: kMutedFg,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Divider(color: kBorder.withOpacity(0.5))),
            ],
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterScreen()),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kBorder, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Create Citizen Account',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          const Center(
            child: Text(
              'TreeTrace • Panabo City',
              style: TextStyle(
                color: kMutedFg,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _AuthShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSidebarBg,
      body: Stack(
        children: [
          // Background Gradient Base
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kSidebarBg, kPrimary],
                stops: [0.3, 1.0],
              ),
            ),
          ),

          // Decorative Top Right Circle
          Positioned(
            top: -40,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),

          // Decorative Middle Left Circle
          Positioned(
            top: 150,
            left: -80,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back Button and Tag inline
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            color: Colors.white,
                            iconSize: 20,
                            splashRadius: 24,
                            padding: const EdgeInsets.all(8),
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.12),
                              ),
                            ),
                            child: const Text(
                              'TreeTrace Account',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Headers
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 15,
                            height: 1.4,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Sheet Container
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: kBackground,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 20,
                          offset: Offset(0, -5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 36, 28, 36),
                        physics: const BouncingScrollPhysics(),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: kSidebarBg,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kPoor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPoor.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: kPoor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: kPoor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}