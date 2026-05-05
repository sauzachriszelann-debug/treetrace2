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
    if (mounted) {
      setState(() => _loading = false);
      if (!ok) setState(() => _error = 'Invalid email or password.');
    }
  }

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
        child: SafeArea(
            child: Column(children: [
          Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.park,
                              color: Colors.white, size: 22)),
                      const SizedBox(width: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TreeTrace',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700)),
                            Text('Geo-Spatial Inventory',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 12)),
                          ]),
                    ]),
                    const SizedBox(height: 28),
                    const Text('Welcome back',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('Sign in to Panabo City Tree Inventory',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14)),
                  ],
                ),
              )),
          Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                    color: kBackground,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: SingleChildScrollView(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: kPoor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: kPoor.withOpacity(0.3))),
                          child: Row(children: [
                            const Icon(Icons.error_outline,
                                color: kPoor, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_error!,
                                    style: const TextStyle(
                                        color: kPoor, fontSize: 13))),
                          ])),
                    const Text('Email',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: kForeground)),
                    const SizedBox(height: 6),
                    TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            hintText: 'you@example.com',
                            prefixIcon: Icon(Icons.email_outlined,
                                size: 18, color: kMutedFg)),
                        onFieldSubmitted: (_) => _login()),
                    const SizedBox(height: 16),
                    const Text('Password',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: kForeground)),
                    const SizedBox(height: 6),
                    TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline,
                                size: 18, color: kMutedFg),
                            suffixIcon: IconButton(
                                icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18,
                                    color: kMutedFg),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure))),
                        onFieldSubmitted: (_) => _login()),
                    const SizedBox(height: 24),
                    SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Sign In'),
                        )),
                    const SizedBox(height: 16),
                    const Row(children: [
                      Expanded(child: Divider()),
                      SizedBox(width: 12),
                      Text('or',
                          style: TextStyle(color: kMutedFg, fontSize: 13)),
                      SizedBox(width: 12),
                      Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegisterScreen())),
                      child: const Text('Create Citizen Account'),
                    ),
                    const SizedBox(height: 20),
                    Center(
                        child: Text('TreeTrace · Panabo City',
                            style: TextStyle(color: kMutedFg, fontSize: 12))),
                  ],
                )),
              )),
        ])),
      ),
    );
  }
}
