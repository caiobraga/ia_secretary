import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'debug_log.dart';
import 'stored_credentials.dart';

/// Email + password sign-in (no verification). Sign up or sign in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _error = '';
  bool _loading = false;
  bool _isSignUp = false;

  @override
  void initState() {
    super.initState();
    _loadLastEmail();
  }

  Future<void> _loadLastEmail() async {
    final email = await getLastEmail();
    if (mounted && email != null && email.isNotEmpty) {
      _emailController.text = email;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter email and password');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (_isSignUp) {
        await AuthService.signUpWithEmail(email: email, password: password);
      } else {
        await AuthService.signInWithEmail(email: email, password: password);
      }
      if (mounted) {
        debugLog('Auth', _isSignUp ? 'signUp success' : 'signIn success');
        await saveLastEmail(email);
        widget.onSignedIn();
      }
    } catch (e) {
      if (mounted) {
        debugLog('Auth', 'error: $e');
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'IA Secretary',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isSignUp ? 'Create account' : 'Sign in to start listening',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_error.isNotEmpty) ...[
                Text(_error, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isSignUp ? 'Sign up' : 'Sign in'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading
                    ? null
                    : () {
                        setState(() {
                          _isSignUp = !_isSignUp;
                          _error = '';
                        });
                      },
                child: Text(_isSignUp ? 'Already have an account? Sign in' : 'No account? Sign up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
