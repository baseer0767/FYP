import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/gym_theme.dart';
import 'workout_hub_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  static const int _stepCount = 7;

  final _formKey = GlobalKey<FormState>();

  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _ageController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  int _currentStep = 0;
  bool _isLoading = false;
  String? _selectedGender;
  String? _selectedActivityLevel;
  String? _emailServerError;

  static const List<_StepMeta> _steps = <_StepMeta>[
    _StepMeta(
      title: 'Height',
      subtitle: 'Start with your height so we can shape your profile.',
      icon: Icons.height_rounded,
      accent: Color(0xFFFF8A00),
    ),
    _StepMeta(
      title: 'Weight',
      subtitle: 'Add your current weight for a better baseline.',
      icon: Icons.monitor_weight_rounded,
      accent: Color(0xFF8BEA53),
    ),
    _StepMeta(
      title: 'Age',
      subtitle: 'Age helps tailor the training experience.',
      icon: Icons.cake_rounded,
      accent: Color(0xFF6EA8FE),
    ),
    _StepMeta(
      title: 'Gender',
      subtitle: 'Pick the card that matches you best.',
      icon: Icons.groups_rounded,
      accent: Color(0xFFFF8A00),
    ),
    _StepMeta(
      title: 'Activity level',
      subtitle: 'Tell us how active you usually are.',
      icon: Icons.local_fire_department_rounded,
      accent: Color(0xFF8BEA53),
    ),
    _StepMeta(
      title: 'Profile details',
      subtitle: 'Add your name, username, and Gmail address.',
      icon: Icons.badge_rounded,
      accent: Color(0xFF6EA8FE),
    ),
    _StepMeta(
      title: 'Password',
      subtitle: 'Create your password and confirm it to finish.',
      icon: Icons.lock_rounded,
      accent: Color(0xFFFF8A00),
    ),
  ];

  static const List<_ChoiceOption> _genderOptions = <_ChoiceOption>[
    _ChoiceOption(
      label: 'Male',
      icon: Icons.male_rounded,
      color: Color(0xFFFF8A00),
      description: 'Use male profile defaults',
    ),
    _ChoiceOption(
      label: 'Female',
      icon: Icons.female_rounded,
      color: Color(0xFF6EA8FE),
      description: 'Use female profile defaults',
    ),
    _ChoiceOption(
      label: 'Non-binary',
      icon: Icons.transgender_rounded,
      color: Color(0xFF8BEA53),
      description: 'Inclusive profile setup',
    ),
    _ChoiceOption(
      label: 'Prefer not to say',
      icon: Icons.privacy_tip_rounded,
      color: Color(0xFFB9C2D0),
      description: 'Skip gender selection',
    ),
  ];

  static const List<_ChoiceOption> _activityOptions = <_ChoiceOption>[
    _ChoiceOption(
      label: 'Sedentary',
      icon: Icons.chair_rounded,
      color: Color(0xFFFF8A00),
      description: 'Mostly sitting, little movement',
    ),
    _ChoiceOption(
      label: 'Lightly active',
      icon: Icons.directions_walk_rounded,
      color: Color(0xFF6EA8FE),
      description: '1-3 workouts or active days weekly',
    ),
    _ChoiceOption(
      label: 'Moderately active',
      icon: Icons.fitness_center_rounded,
      color: Color(0xFF8BEA53),
      description: '3-5 training sessions weekly',
    ),
    _ChoiceOption(
      label: 'Very active',
      icon: Icons.sports_gymnastics_rounded,
      color: Color(0xFFFF6B6B),
      description: 'Hard training most days',
    ),
    _ChoiceOption(
      label: 'Athlete',
      icon: Icons.bolt_rounded,
      color: Color(0xFFB9C2D0),
      description: 'High-volume or performance focused',
    ),
  ];

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isFirstStep => _currentStep == 0;

  bool get _isFinalStep => _currentStep == _stepCount - 1;

  _StepMeta get _stepMeta => _steps[_currentStep];

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFF7A1D1D)
            : const Color(0xFF111827),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  void _clearEmailServerError() {
    if (_emailServerError == null) {
      return;
    }

    setState(() {
      _emailServerError = null;
    });
  }

  String? _positiveNumberValidator(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Enter your $label';
    }

    final parsed = double.tryParse(text);
    if (parsed == null || parsed <= 0) {
      return '$label must be a positive number';
    }

    return null;
  }

  String? _positiveIntegerValidator(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Enter your $label';
    }

    final parsed = int.tryParse(text);
    if (parsed == null || parsed <= 0) {
      return '$label must be a positive number';
    }

    return null;
  }

  String? _requiredTextValidator(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Enter your $label';
    }
    return null;
  }

  String? _usernameValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Enter a username';
    }
    if (text.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(text)) {
      return 'Use only letters, numbers, and underscores';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[^@\s]+@gmail\.com$', caseSensitive: false).hasMatch(text)) {
      return 'Use a Gmail address';
    }
    return _emailServerError;
  }

  String? _validatePassword(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Enter a password';
    }
    if (text.length < 6) {
      return 'Use at least 6 characters';
    }
    return null;
  }

  String? _validatePasswordConfirmation(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Confirm your password';
    }
    if (text != _passwordController.text.trim()) {
      return 'Passwords do not match';
    }
    return null;
  }

  bool _validateSelections() {
    if (_currentStep == 3 && _selectedGender == null) {
      _showSnack('Choose a gender card to continue', isError: true);
      return false;
    }

    if (_currentStep == 4 && _selectedActivityLevel == null) {
      _showSnack('Choose an activity level card to continue', isError: true);
      return false;
    }

    return true;
  }

  Future<void> _goBack() async {
    if (_isLoading) {
      return;
    }

    if (_isFirstStep) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _currentStep -= 1;
    });
  }

  Future<void> _goNext() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (!_validateSelections()) {
      return;
    }

    if (_isFinalStep) {
      await _submitSignup();
      return;
    }

    setState(() {
      _currentStep += 1;
    });
  }

  Future<void> _submitSignup() async {
    setState(() => _isLoading = true);
    _clearEmailServerError();

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text.trim(),
        data: <String, dynamic>{
          'height': double.parse(_heightController.text.trim()),
          'weight': double.parse(_weightController.text.trim()),
          'age': int.parse(_ageController.text.trim()),
          'gender': _selectedGender,
          'activity_level': _selectedActivityLevel,
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'username': _usernameController.text.trim().toLowerCase(),
        },
      );

      if (!mounted) {
        return;
      }

      if (response.session != null && response.user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const WorkoutHubScreen()),
        );
        return;
      }

      if (response.user != null) {
        _showSnack(
          'Account created. Check your email to verify it, then sign in.',
        );
        Navigator.pop(context);
        return;
      }

      _showSnack('Signup did not return a user. Try again.', isError: true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      final errorText = e.toString().toLowerCase();
      if (errorText.contains('already') ||
          errorText.contains('duplicate') ||
          errorText.contains('registered')) {
        setState(() {
          _emailServerError = 'That Gmail is already registered';
          _currentStep = 5;
        });
        _showSnack('That Gmail is already registered', isError: true);
        return;
      }

      _showSnack('Signup failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _glow(Alignment alignment, Color color, double size) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0.0)]),
        ),
      ),
    );
  }

  Widget _glassPanel({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final progressValue = (_currentStep + 1) / _stepCount;

    return _glassPanel(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [GymColors.accent, GymColors.accentSoft],
                    ),
                  ),
                  child: const Icon(
                    Icons.fitness_center_rounded,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FitPose onboarding',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.98),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'One card at a time. No clutter. Just a guided signup.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.66),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _stepMeta.accent.withOpacity(0.40),
                    ),
                  ),
                  child: Text(
                    'Step ${_currentStep + 1} of $_stepCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: 10,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(_stepMeta.accent),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: List.generate(_stepCount, (index) {
                final selected = index <= _currentStep;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: EdgeInsets.only(
                      right: index == _stepCount - 1 ? 0 : 8,
                    ),
                    height: 6,
                    decoration: BoxDecoration(
                      color: selected
                          ? (index == _currentStep
                                ? _stepMeta.accent
                                : _stepMeta.accent.withOpacity(0.38))
                          : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(fade),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(_currentStep),
        child: _glassPanel(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _stepMeta.accent,
                              _stepMeta.accent.withOpacity(0.58),
                            ],
                          ),
                        ),
                        child: Icon(
                          _stepMeta.icon,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _stepMeta.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _stepMeta.subtitle,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.70),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildCurrentStepContent(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _goBack,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.16),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              _isFirstStep ? 'Back to login' : 'Back',
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _goNext,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: _isLoading && _isFinalStep
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.black,
                                    ),
                                  )
                                : Text(
                                    _isFinalStep ? 'Create Account' : 'Next',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
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
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildNumberStep(
          controller: _heightController,
          label: 'Height',
          hint: 'Example: 178',
          unit: 'cm',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            LengthLimitingTextInputFormatter(6),
          ],
          validator: (value) => _positiveNumberValidator(value, 'height'),
          onSubmitted: (_) => _goNext(),
        );
      case 1:
        return _buildNumberStep(
          controller: _weightController,
          label: 'Weight',
          hint: 'Example: 72.5',
          unit: 'kg',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            LengthLimitingTextInputFormatter(6),
          ],
          validator: (value) => _positiveNumberValidator(value, 'weight'),
          onSubmitted: (_) => _goNext(),
        );
      case 2:
        return _buildNumberStep(
          controller: _ageController,
          label: 'Age',
          hint: 'Example: 24',
          unit: 'years',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          validator: (value) => _positiveIntegerValidator(value, 'age'),
          onSubmitted: (_) => _goNext(),
        );
      case 3:
        return _buildChoiceSection(
          options: _genderOptions,
          selectedValue: _selectedGender,
          onChanged: (value) {
            setState(() {
              _selectedGender = value;
            });
          },
          validatorMessage: 'Select a gender card',
          title: 'Pick one gender card',
          subtitle: 'This stays as a single step, not a long list on the page.',
        );
      case 4:
        return _buildChoiceSection(
          options: _activityOptions,
          selectedValue: _selectedActivityLevel,
          onChanged: (value) {
            setState(() {
              _selectedActivityLevel = value;
            });
          },
          validatorMessage: 'Select an activity level card',
          title: 'Pick your activity level',
          subtitle: 'One selection, one card, then you move on.',
        );
      case 5:
        return _buildProfileDetailsStep();
      case 6:
        return _buildPasswordStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildNumberStep({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String unit,
    required TextInputType keyboardType,
    required List<TextInputFormatter> inputFormatters,
    required String? Function(String?) validator,
    required void Function(String) onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          cursorColor: _stepMeta.accent,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            suffixText: unit,
            suffixStyle: TextStyle(
              color: Colors.white.withOpacity(0.68),
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(_stepMeta.icon, color: _stepMeta.accent),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Only one card is visible at a time. Enter, then move to the next step.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.58),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceSection({
    required List<_ChoiceOption> options,
    required String? selectedValue,
    required ValueChanged<String> onChanged,
    required String validatorMessage,
    required String title,
    required String subtitle,
  }) {
    return FormField<String>(
      initialValue: selectedValue,
      validator: (_) {
        final isSelected = selectedValue != null && selectedValue.isNotEmpty;
        return isSelected ? null : validatorMessage;
      },
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.64),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 600;
                final cardWidth = isWide
                    ? (constraints.maxWidth - 14) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: options.map((option) {
                    final selected = selectedValue == option.label;
                    return SizedBox(
                      width: cardWidth,
                      child: _buildChoiceCard(
                        option: option,
                        selected: selected,
                        onTap: () {
                          onChanged(option.label);
                          field.didChange(option.label);
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            if (field.hasError) ...[
              const SizedBox(height: 10),
              Text(
                field.errorText ?? '',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildChoiceCard({
    required _ChoiceOption option,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _isLoading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      option.color.withOpacity(0.96),
                      option.color.withOpacity(0.68),
                    ],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF101722), Color(0xFF0B1018)],
                  ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? option.color : Colors.white.withOpacity(0.10),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: option.color.withOpacity(0.26),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.black.withOpacity(0.12)
                      : option.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  option.icon,
                  color: selected ? Colors.black : option.color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      style: TextStyle(
                        color: selected
                            ? Colors.black.withOpacity(0.78)
                            : Colors.white.withOpacity(0.68),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: selected ? Colors.black : option.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDetailsStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _firstNameController,
                      label: 'First name',
                      hint: 'Jordan',
                      icon: Icons.person_rounded,
                      validator: (value) =>
                          _requiredTextValidator(value, 'first name'),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      controller: _lastNameController,
                      label: 'Last name',
                      hint: 'Smith',
                      icon: Icons.person_rounded,
                      validator: (value) =>
                          _requiredTextValidator(value, 'last name'),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                  ),
                ],
              )
            else ...[
              _buildTextField(
                controller: _firstNameController,
                label: 'First name',
                hint: 'Jordan',
                icon: Icons.person_rounded,
                validator: (value) =>
                    _requiredTextValidator(value, 'first name'),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _lastNameController,
                label: 'Last name',
                hint: 'Smith',
                icon: Icons.person_rounded,
                validator: (value) =>
                    _requiredTextValidator(value, 'last name'),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
            ],
            const SizedBox(height: 14),
            _buildTextField(
              controller: _usernameController,
              label: 'Username',
              hint: 'fitjordan',
              icon: Icons.alternate_email_rounded,
              validator: _usernameValidator,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _emailController,
              label: 'Gmail address',
              hint: 'you@gmail.com',
              icon: Icons.email_rounded,
              validator: _validateEmail,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _clearEmailServerError(),
              onSubmitted: (_) => _goNext(),
            ),
            const SizedBox(height: 12),
            Text(
              'We only accept Gmail addresses for this signup flow.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.60),
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPasswordStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;

        final passwordFields = wide
            ? Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Create a password',
                      icon: Icons.lock_rounded,
                      validator: _validatePassword,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      controller: _confirmPasswordController,
                      label: 'Confirm password',
                      hint: 'Repeat it here',
                      icon: Icons.verified_user_rounded,
                      validator: _validatePasswordConfirmation,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _goNext(),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Create a password',
                    icon: Icons.lock_rounded,
                    validator: _validatePassword,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm password',
                    hint: 'Repeat it here',
                    icon: Icons.verified_user_rounded,
                    validator: _validatePasswordConfirmation,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _goNext(),
                  ),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            passwordFields,
            const SizedBox(height: 14),
            Text(
              'Your password stays private. The wizard only uses it to create the account.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.60),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    TextInputAction textInputAction = TextInputAction.next,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onSubmitted,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: _stepMeta.accent,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _stepMeta.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.62),
              colorBlendMode: BlendMode.darken,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xF105070A),
                    Color(0xDD0D1320),
                    Color(0xF105070A),
                  ],
                ),
              ),
            ),
          ),
          _glow(
            const Alignment(-1.0, -0.95),
            GymColors.accent.withOpacity(0.35),
            340,
          ),
          _glow(
            const Alignment(1.05, -0.80),
            GymColors.accentSoft.withOpacity(0.16),
            280,
          ),
          _glow(
            const Alignment(1.05, 1.0),
            GymColors.accentCool.withOpacity(0.14),
            320,
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 18),
                      _buildStepCard(),
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

class _StepMeta {
  const _StepMeta({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
}

class _ChoiceOption {
  const _ChoiceOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.description,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String description;
}
