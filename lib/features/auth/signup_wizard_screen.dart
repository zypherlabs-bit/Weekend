import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncValue;
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';

/// Tinder-style sign-up wizard: one question per screen across six steps,
/// ending in account creation. Answers ride along in the signup metadata and
/// are written to `profiles` by the auth notifier once a session exists.
class SignupWizardScreen extends ConsumerStatefulWidget {
  const SignupWizardScreen({super.key, this.returnTo = '/onboarding'});

  /// Where the back arrow on step one returns (onboarding or sign-in).
  final String returnTo;

  @override
  ConsumerState<SignupWizardScreen> createState() => _SignupWizardScreenState();
}

class _SignupWizardScreenState extends ConsumerState<SignupWizardScreen> {
  static const int _stepCount = 6;

  // Option lists must match the CHECK constraints on `profiles`
  // (migration 001, typo corrected by migration 015).
  static const List<String> _genders = [
    'Man',
    'Woman',
    'Non-binary',
    'Prefer not to say',
  ];
  static const List<String> _goals = [
    'Dating',
    'Long-term relationship',
    'New people & Friendships',
    'Dating & Weekend Plans',
  ];

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  int _step = 0;
  bool _obscurePassword = true;
  bool _submitting = false;
  DateTime? _birthday;
  String? _gender;
  String? _goal;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _isLastStep => _step == _stepCount - 1;

  String get _question => switch (_step) {
        0 => "What's your email?",
        1 => 'Create a password',
        2 => "What's your name?",
        3 => "When's your birthday?",
        4 => 'How do you identify?',
        _ => 'What brings you here?',
      };

  String? _validateStep() {
    switch (_step) {
      case 0:
        final email = _emailController.text.trim();
        if (email.isEmpty) return 'Please enter your email';
        if (!email.contains('@')) return 'Please enter a valid email';
        return null;
      case 1:
        final password = _passwordController.text;
        if (password.isEmpty) return 'Please create a password';
        if (password.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      case 2:
        if (_nameController.text.trim().isEmpty) {
          return 'Please enter your name';
        }
        return null;
      case 3:
        final birthday = _birthday;
        if (birthday == null) return 'Pick your date of birth';
        final years = DateTime.now().difference(birthday).inDays ~/ 365;
        if (years < 18) return 'You must be at least 18 to join Weekend';
        return null;
      case 4:
        if (_gender == null) return 'Pick an option to continue';
        return null;
      default:
        if (_goal == null) return 'Pick an option to continue';
        return null;
    }
  }

  void _showProblem(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _advance() {
    final problem = _validateStep();
    if (problem != null) {
      _showProblem(problem);
      return;
    }
    ref.read(authStateProvider.notifier).dismissError();
    setState(() => _step += 1);
  }

  void _back() {
    ref.read(authStateProvider.notifier).dismissError();
    if (_step == 0) {
      context.go(widget.returnTo);
      return;
    }
    setState(() => _step -= 1);
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    // The picker's lastDate enforces the 18+ rule at selection time.
    final latest = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? latest,
      firstDate: DateTime(now.year - 100),
      lastDate: latest,
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Future<void> _submit() async {
    final problem = _validateStep();
    if (problem != null) {
      _showProblem(problem);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(authStateProvider.notifier).signUpWithEmail(
            _emailController.text.trim(),
            _passwordController.text,
            _nameController.text.trim(),
            dateOfBirth: _birthday,
            gender: _gender,
            relationshipIntent: _goal,
          );
      if (!mounted) return;
      final authState = ref.read(authStateProvider);
      if (authState.awaitingEmailConfirmation) {
        context.go('/confirm-email');
      } else if (authState.isAuthenticated) {
        context.go(
          authState.needsProfileSetup ? '/edit-profile' : '/home',
        );
      }
      // On failure the wizard stays put: the inline error box shows why.
      // Navigating here on failure was the old "pushed back" defect.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed:
                        (authState.isLoading || _submitting) ? null : _back,
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Step ${_step + 1} of $_stepCount',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_step + 1) / _stepCount,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFFF4B72),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _question,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(child: _buildStepBody()),
              if (authState.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
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
              ],
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: (authState.isLoading || _submitting)
                      ? null
                      : (_isLastStep ? _submit : _advance),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4B72),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isLastStep ? 'Create Account' : 'Next',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return TextFormField(
          controller: _emailController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.emailAddress,
          decoration: _inputDecoration('Email', Icons.email_outlined),
        );
      case 1:
        return TextFormField(
          controller: _passwordController,
          autofocus: true,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            'Password',
            Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.white60,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        );
      case 2:
        return TextFormField(
          controller: _nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Full name', Icons.person_outline),
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _pickBirthday,
              borderRadius: BorderRadius.circular(16),
              child: InputDecorator(
                decoration: _inputDecoration(
                  'Birthday',
                  Icons.cake_outlined,
                ).copyWith(
                  suffixIcon: const Icon(
                    Icons.calendar_today,
                    color: Colors.white60,
                  ),
                ),
                child: Text(
                  _birthday == null
                      ? 'Tap to pick your date of birth'
                      : '${_birthday!.day.toString().padLeft(2, '0')}/'
                          '${_birthday!.month.toString().padLeft(2, '0')}/'
                          '${_birthday!.year}',
                  style: TextStyle(
                    color: _birthday == null ? Colors.white38 : Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You must be 18 or older to join.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        );
      case 4:
        return _ChoiceList(
          options: _genders,
          selected: _gender,
          onSelected: (value) => setState(() => _gender = value),
        );
      default:
        return _ChoiceList(
          options: _goals,
          selected: _goal,
          onSelected: (value) => setState(() => _goal = value),
        );
    }
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

/// Full-width selectable option rows (gender / goal steps).
class _ChoiceList extends StatelessWidget {
  const _ChoiceList({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelected(option),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C162E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected == option
                          ? const Color(0xFFFF4B72)
                          : Colors.white.withValues(alpha: 0.1),
                      width: selected == option ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    option,
                    style: TextStyle(
                      color: selected == option ? Colors.white : Colors.white70,
                      fontSize: 16,
                      fontWeight: selected == option
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
