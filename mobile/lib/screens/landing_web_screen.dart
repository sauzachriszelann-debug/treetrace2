import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';

class LandingWebScreen extends StatefulWidget {
  const LandingWebScreen({super.key});

  @override
  State<LandingWebScreen> createState() => _LandingWebScreenState();
}

class _LandingWebScreenState extends State<LandingWebScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D1F12))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.endsWith('/public') || url == '/public') {
              _showPublicPortalNotice();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'TreeTraceAuth',
        onMessageReceived: _handleAuthMessage,
      );
    _loadLanding();
  }

  Future<void> _loadLanding() async {
    final raw = await rootBundle.loadString('assets/landing/index.html');
    var html = raw
        .replaceFirst(
          '<head>',
          '<head><base href="assets/landing/">',
        )
        .replaceFirst(
          '</script>',
          '''
        function goToApp(path) {
            TreeTraceAuth.postMessage(JSON.stringify({ type: 'navigate', path: path }));
        }

        async function submitLandingLogin() {
            const button = document.getElementById('loginSubmitBtn');
            const email = document.getElementById('loginEmail').value.trim();
            const password = document.getElementById('loginPassword').value;
            if (!email || !password) {
                alert('Please enter your email and password.');
                return;
            }
            setButtonState(button, 'Signing in...', true);
            TreeTraceAuth.postMessage(JSON.stringify({
                type: 'login',
                email: email,
                password: password
            }));
        }

        async function submitLandingSignup() {
            const button = document.getElementById('signupSubmitBtn');
            const firstName = document.getElementById('signupFirstName').value.trim();
            const lastName = document.getElementById('signupLastName').value.trim();
            const email = document.getElementById('signupEmail').value.trim();
            const password = document.getElementById('signupPassword').value;
            const fullName = `\${firstName} \${lastName}`.trim();
            if (!fullName || !email || !password) {
                alert('Please complete your name, email, and password.');
                return;
            }
            setButtonState(button, 'Creating account...', true);
            TreeTraceAuth.postMessage(JSON.stringify({
                type: 'signup',
                full_name: fullName,
                email: email,
                password: password
            }));
        }
    </script>''',
        );

    final image7 = await _assetDataUrl('assets/landing/images7.png');
    final image10 = await _assetDataUrl('assets/landing/images10.png');
    final me2 = await _assetDataUrl('assets/landing/me2.png');
    final me = await _assetDataUrl('assets/landing/me.jpg', mime: 'image/jpeg');
    html = html
        .replaceAll('href="images7.png"', 'href="$image7"')
        .replaceAll('src="images7.png"', 'src="$image7"')
        .replaceAll('src="images10.png"', 'src="$image10"')
        .replaceAll('src="me2.png"', 'src="$me2"')
        .replaceAll('src="me.jpg"', 'src="$me"');

    await _controller.loadHtmlString(
      html,
      baseUrl: 'https://treetrace.local/',
    );
  }

  Future<String> _assetDataUrl(String assetPath, {String mime = 'image/png'}) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<void> _handleAuthMessage(JavaScriptMessage message) async {
    final data = jsonDecode(message.message) as Map<String, dynamic>;
    final type = data['type'] as String?;

    if (type == 'navigate') {
      final path = data['path'] as String?;
      if (path == '/public') {
        _showPublicPortalNotice();
      }
      return;
    }

    if (type == 'login') {
      final ok = await context.read<AuthProvider>().login(
            data['email'] as String,
            data['password'] as String,
          );
      if (!ok && mounted) {
        _showError('Invalid email or password.');
        await _controller.runJavaScript(
          "setButtonState(document.getElementById('loginSubmitBtn'), 'Log In →', false);",
        );
      }
      return;
    }

    if (type == 'signup') {
      try {
        await api.register(
          data['full_name'] as String,
          data['email'] as String,
          data['password'] as String,
        );
        final ok = await context.read<AuthProvider>().login(
              data['email'] as String,
              data['password'] as String,
            );
        if (!ok) throw Exception('Account created, but login failed.');
      } catch (error) {
        if (!mounted) return;
        _showError('Registration failed. Please check your details.');
        await _controller.runJavaScript(
          "setButtonState(document.getElementById('signupSubmitBtn'), 'Create Account →', false);",
        );
      }
    }
  }

  void _showPublicPortalNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Public portal opens after login in the mobile app.'),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSidebarBg,
      body: Stack(
        children: [
          SafeArea(child: WebViewWidget(controller: _controller)),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }
}
