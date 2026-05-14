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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSidebarBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kSidebarBg, kSidebarBg, kPrimary],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: Colors.white,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.asset(
                            'assets/landing/logo.png',
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TreeTrace',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Geo-Spatial Inventory',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.62),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Sign in to TreeTrace',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Access your dashboard, tree map, QR scanner, and AI tools.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.68),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: kBackground,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) _ErrorBox(message: _error!),
                        const _FieldLabel('Email'),
                        const SizedBox(height: 7),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'you@example.com',
                            prefixIcon: Icon(Icons.email_outlined,
                                size: 18, color: kMutedFg),
                          ),
                          onFieldSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 15),
                        const _FieldLabel('Password'),
                        const SizedBox(height: 7),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline,
                                size: 18, color: kMutedFg),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18,
                                color: kMutedFg,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          onFieldSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Log In',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: const [
                            Expanded(child: Divider(color: kBorder)),
                            SizedBox(width: 12),
                            Text('or',
                                style:
                                    TextStyle(color: kMutedFg, fontSize: 12)),
                            SizedBox(width: 12),
                            Expanded(child: Divider(color: kBorder)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen()),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kPrimary,
                              side: const BorderSide(color: kBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Create Citizen Account',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Center(
                          child: Text(
                            'TreeTrace - Panabo City',
                            style: TextStyle(color: kMutedFg, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: kMutedFg,
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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPoor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPoor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: kPoor, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: kPoor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
