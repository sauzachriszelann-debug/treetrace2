import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (_passCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await api.register(
        _nameCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
      final ok = await context
          .read<AuthProvider>()
          .login(_emailCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        setState(
              () => _error = 'Registration worked. Please sign in again.',
        );
      }
    } catch (e) {
      setState(
            () => _error = e.toString().contains('already')
            ? 'Email already registered.'
            : 'Registration failed. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSidebarBg,
      body: DecoratedBox(
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
                padding: const EdgeInsets.fromLTRB(18, 8, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: Colors.white,
                          padding: EdgeInsets.zero,
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
                            'Citizen access',
                            style: TextStyle(
                              color: kSidebarPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Join TreeTrace to scan QR tags, explore trees, and submit unknown species for review.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.68),
                        fontSize: 14,
                        height: 1.38,
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
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) _ErrorBox(message: _error!),
                        const _FieldLabel('Full Name'),
                        const SizedBox(height: 7),
                        TextFormField(
                          controller: _nameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Juan dela Cruz',
                            prefixIcon: Icon(
                              Icons.person_outline,
                              size: 18,
                              color: kMutedFg,
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        const _FieldLabel('Email'),
                        const SizedBox(height: 7),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'you@example.com',
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              size: 18,
                              color: kMutedFg,
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        const _FieldLabel('Password'),
                        const SizedBox(height: 7),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: 'Minimum 8 characters',
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: kMutedFg,
                            ),
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
                          onFieldSubmitted: (_) => _register(),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kPrimary.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: kPrimary.withOpacity(0.18),
                            ),
                          ),
                          child: Row(
                            children: const [
                              Icon(
                                Icons.verified_user_outlined,
                                color: kPrimary,
                                size: 18,
                              ),
                              SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Citizen accounts can scan, explore, and submit photos for review.',
                                  style: TextStyle(
                                    color: kPrimary,
                                    fontSize: 12,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _register,
                            style: ElevatedButton.styleFrom(
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
                              'Create Account',
                              style:
                              TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Already have an account? ',
                              style: TextStyle(color: kMutedFg, fontSize: 13),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: kPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
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