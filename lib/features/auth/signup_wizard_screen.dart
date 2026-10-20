import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncValue;
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/weekend_design_system.dart';

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
  String? _problem;

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
    // Inline, not a SnackBar: validation feedback must never cover the primary
    // action at the bottom of the wizard.
    setState(() => _problem = message);
  }

  void _advance() {
    final problem = _validateStep();
    if (problem != null) {
      _showProblem(problem);
      return;
    }
    ref.read(authStateProvider.notifier).dismissError();
    setState(() {
      _problem = null;
      _step += 1;
    });
  }

  void _back() {
    ref.read(authStateProvider.notifier).dismissError();
    if (_step == 0) {
      context.go(widget.returnTo);
      return;
    }
    setState(() {
      _problem = null;
      _step -= 1;
    });
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
      await ref
          .read(authStateProvider.notifier)
          .signUpWithEmail(
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
        // A session exists, so offer the passkey / app-lock step immediately
        // after the account is created. `/security-setup` finishes into
        // `/edit-profile` or `/home` itself, so the wizard never sends the new
        // user back to the sign-in screen.
        context.go('/security-setup');
      }
      // On failure the wizard stays put: the inline error box shows why.
      // Navigating here on failure was the old "pushed back" defect.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: WeekendAtmosphere(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    WeekendGlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      semanticLabel: 'Back',
                      onPressed: (authState.isLoading || _submitting)
                          ? null
                          : _back,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Step ${_step + 1} of $_stepCount',
                      style: theme.textTheme.labelMedium,
                    ),
                    const Spacer(),
                    const WeekendLogo(size: 32, glow: false),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / _stepCount,
                    minHeight: 5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 26),
                Text(_question, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  'Your answers stay private and shape who you meet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(child: _buildStepBody()),
                if (authState.error != null || _problem != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(WeekendRadius.sm),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      authState.error ?? _problem!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                WeekendGlassButton(
                  label: _isLastStep ? 'Create Account' : 'Next',
                  icon: _isLastStep
                      ? Icons.favorite_rounded
                      : Icons.arrow_forward_rounded,
                  loading: _submitting,
                  onPressed: (authState.isLoading || _submitting)
                      ? null
                      : (_isLastStep ? _submit : _advance),
                ),
              ],
            ),
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
          keyboardType: TextInputType.emailAddress,
          decoration: _inputDecoration('Email', Icons.email_outlined),
        );
      case 1:
        return TextFormField(
          controller: _passwordController,
          autofocus: true,
          obscureText: _obscurePassword,
          decoration: _inputDecoration(
            'Password',
            Icons.lock_outline,
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
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
          decoration: _inputDecoration('Full name', Icons.person_outline),
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _pickBirthday,
              borderRadius: BorderRadius.circular(WeekendRadius.md),
              child: InputDecorator(
                decoration: _inputDecoration('Birthday', Icons.cake_outlined)
                    .copyWith(
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
                    ),
                child: Text(
                  _birthday == null
                      ? 'Tap to pick your date of birth'
                      : '${_birthday!.day.toString().padLeft(2, '0')}/'
                            '${_birthday!.month.toString().padLeft(2, '0')}/'
                            '${_birthday!.year}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _birthday == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You must be 18 or older to join.',
              style: Theme.of(context).textTheme.bodySmall,
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
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
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
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                button: true,
                selected: selected == option,
                child: InkWell(
                  borderRadius: BorderRadius.circular(WeekendRadius.md),
                  onTap: () => onSelected(option),
                  child: AnimatedContainer(
                    duration: WeekendMotion.quick,
                    curve: WeekendMotion.curve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: selected == option
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : theme.colorScheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(WeekendRadius.md),
                      border: Border.all(
                        color: selected == option
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.65,
                              ),
                        width: selected == option ? 1.6 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: selected == option
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                              fontWeight: selected == option
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (selected == option)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                      ],
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
