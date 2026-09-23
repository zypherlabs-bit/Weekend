import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide AsyncValue;
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.startOnSignUp = false});

  /// Opens on the "Create Account" form. The welcome flow uses this so a
  /// visitor who tapped "Get Started" is not shown the sign-in form first.
  final bool startOnSignUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  late bool _isLogin = !widget.startOnSignUp;
  bool _obscurePassword = true;
  
  // Passkey flow controllers
  final _passkeyEmailController = TextEditingController();
  final _passkeyNameController = TextEditingController();
  bool _showPasskeyForm = false;
  bool _isPasskeySignUp = false;
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _passkeyEmailController.dispose();
    _passkeyNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    try {
      if (_isLogin) {
        await ref
            .read(authStateProvider.notifier)
            .signInWithEmail(email, password);
      } else {
        final name = _nameController.text.trim();
        await ref
            .read(authStateProvider.notifier)
            .signUpWithEmail(email, password, name);
      }
      if (!mounted) return;
      final authState = ref.read(authStateProvider);
      if (authState.needsMfaChallenge) {
        context.go('/mfa-challenge');
      } else if (authState.awaitingEmailConfirmation) {
        // Supabase created the account but issued no session: email
        // confirmation is required by the live project. Continue on the
        // dedicated step instead of leaving the user on this form.
        context.go('/confirm-email');
      } else if (authState.isAuthenticated) {
        // Session reused: first-time accounts go to Personal Details, an
        // existing complete profile goes home.
        context.go(
          authState.needsProfileSetup ? '/edit-profile' : '/home',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handlePasskeySignUp() async {
    final email = _passkeyEmailController.text.trim();
    final name = _passkeyNameController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Please enter a valid email');
      return;
    }
    if (name.isEmpty) {
      _showError('Please enter your name');
      return;
    }
    setState(() => _showPasskeyForm = false);
    await ref
        .read(authStateProvider.notifier)
        .signUpWithPasskey(email: email, fullName: name);
    if (!mounted) return;
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated) {
      context.go(
        authState.needsProfileSetup ? '/edit-profile' : '/home',
      );
    } else if (authState.error != null) {
      _showError(authState.error!);
    }
  }

  Future<void> _handlePasskeySignIn() async {
    await ref.read(authStateProvider.notifier).signInWithPasskey();
    if (!mounted) return;
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated) {
      context.go(
        authState.needsProfileSetup ? '/edit-profile' : '/home',
      );
    } else if (authState.error != null) {
      _showError(authState.error!);
    }
  }

  void _showPasskeySignUpForm() {
    setState(() {
      _isPasskeySignUp = true;
      _showPasskeyForm = true;
      _passkeyEmailController.clear();
      _passkeyNameController.clear();
    });
  }

  void _showPasskeySignInForm() {
    setState(() {
      _isPasskeySignUp = false;
      _showPasskeyForm = true;
    });
  }

  void _hidePasskeyForm() {
    setState(() => _showPasskeyForm = false);
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF4B72), Color(0xFFFF9966)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.weekend_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isLogin ? 'Welcome Back' : 'Create Account',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin
                      ? 'Sign in to continue your journey'
                      : 'Join Weekend and meet people nearby',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Passkey form (shown when user taps "Continue with Passkey")
                if (_showPasskeyForm) ...[
                  if (_isPasskeySignUp) ...[
                    TextFormField(
                      controller: _passkeyNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        'Full Name',
                        Icons.person_outline,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _passkeyEmailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('Email', Icons.email_outlined),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: authState.isLoading
                          ? null
                          : (_isPasskeySignUp ? _handlePasskeySignUp : _handlePasskeySignIn),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4B72),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      child: authState.isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _isPasskeySignUp
                                  ? 'Create Account with Passkey'
                                  : 'Sign In with Passkey',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _hidePasskeyForm,
                    child: const Text(
                      'Back',
                      style: TextStyle(color: Color(0xFFFF9966), fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 24),
                ],
                
                if (!_isLogin) ...[
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      'Full Name',
                      Icons.person_outline,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Email', Icons.email_outlined),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    'Password',
                    Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white60,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                if (authState.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      authState.error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: authState.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4B72),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 0,
                    ),
                    child: authState.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _isLogin ? 'Sign In' : 'Create Account',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _showPasskeyForm = false;
                    });
                    // A stale error from the previous form must not follow the
                    // user across the switch.
                    ref.read(authStateProvider.notifier).dismissError();
                  },
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Sign up"
                        : 'Already have an account? Sign in',
                    style: TextStyle(
                      color: const Color(0xFFFF9966),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Passkey buttons
                TextButton.icon(
                  onPressed: authState.isLoading
                      ? null
                      : (_isLogin ? _showPasskeySignInForm : _showPasskeySignUpForm),
                  icon: const Icon(Icons.fingerprint, color: Color(0xFFFF9966)),
                  label: Text(
                    _isLogin
                        ? 'Continue with Passkey'
                        : 'Sign Up with Passkey',
                    style: const TextStyle(
                      color: Color(0xFFFF9966),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFFF9966)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(authStateProvider.notifier)
                        .signInAnonymously();
                    if (!context.mounted) return;
                    if (ref.read(authStateProvider).isAuthenticated) {
                      context.go('/home');
                    }
                  },
                  icon: const Icon(Icons.explore, color: Color(0xFFFF9966)),
                  label: const Text(
                    'Explore as Guest',
                    style: TextStyle(color: Color(0xFFFF9966)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      prefixIcon: Icon(icon, color: Colors.white60),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF1C162E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF4B72)),
      ),
    );
  }
}
