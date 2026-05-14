import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _register() async {
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (_passCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await api.register(_nameCtrl.text.trim(), _emailCtrl.text.trim(), _passCtrl.text);
      final ok = await context.read<AuthProvider>().login(_emailCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        setState(() => _error = 'Registration succeeded but login failed. Try logging in.');
      }
    } catch (e) {
      setState(() => _error = e.toString().contains('already') ? 'Email already registered.' : 'Registration failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF1a3323), Color(0xFF2d6b3a)],
          ),
        ),
        child: SafeArea(child: Column(children: [
          // Header
          Expanded(flex: 2, child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.park, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('TreeTrace', style: TextStyle(color: Colors.white,
                        fontSize: 22, fontWeight: FontWeight.w700)),
                    Text('Geo-Spatial Inventory',
                        style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
                  ]),
                ]),
                const SizedBox(height: 28),
                const Text('Join TreeTrace', style: TextStyle(color: Colors.white,
                    fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Create your citizen account',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
              ],
            ),
          )),

          // Form
          Expanded(flex: 4, child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: kBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Container(margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: kPoor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kPoor.withOpacity(0.3))),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: kPoor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: kPoor, fontSize: 13))),
                    ])),

                const Text('Full Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kForeground)),
                const SizedBox(height: 6),
                TextFormField(controller: _nameCtrl,
                  decoration: const InputDecoration(hintText: 'Juan dela Cruz',
                    prefixIcon: Icon(Icons.person_outline, size: 18, color: kMutedFg))),
                const SizedBox(height: 16),

                const Text('Email', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kForeground)),
                const SizedBox(height: 6),
                TextFormField(controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.email_outlined, size: 18, color: kMutedFg))),
                const SizedBox(height: 16),

                const Text('Password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kForeground)),
                const SizedBox(height: 6),
                TextFormField(controller: _passCtrl, obscureText: _obscure,
                  decoration: InputDecoration(hintText: 'Min. 8 characters',
                    prefixIcon: const Icon(Icons.lock_outline, size: 18, color: kMutedFg),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 18, color: kMutedFg),
                      onPressed: () => setState(() => _obscure = !_obscure)))),
                const SizedBox(height: 24),

                // Free tier notice
                Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kPrimary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPrimary.withOpacity(0.2))),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: kPrimary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Free account: maps and QR are unlimited, 10 AI scans/day',
                        style: TextStyle(color: kPrimary, fontSize: 12))),
                  ])),
                const SizedBox(height: 16),

                SizedBox(height: 46, child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Create Account'),
                )),
                const SizedBox(height: 16),

                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Already have an account? ', style: TextStyle(color: kMutedFg, fontSize: 13)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Sign In', style: TextStyle(color: kPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
              ],
            )),
          )),
        ])),
      ),
    );
  }
}
