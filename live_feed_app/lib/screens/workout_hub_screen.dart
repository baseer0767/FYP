import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/workout_catalog.dart';
import '../theme/gym_theme.dart';
import 'exercise_tutorial_screen.dart';

class WorkoutHubScreen extends StatefulWidget {
  const WorkoutHubScreen({super.key});

  @override
  State<WorkoutHubScreen> createState() => _WorkoutHubScreenState();
}

class _WorkoutHubScreenState extends State<WorkoutHubScreen> {
  String _selectedBodyPartId = workoutBodyParts.first.id;

  WorkoutBodyPart get _selectedBodyPart => bodyPartForId(_selectedBodyPartId);

  List<WorkoutExercise> get _selectedExercises {
    return exercisesForBodyPart(_selectedBodyPartId);
  }

  WorkoutExercise get _selectedExercise => _selectedExercises.first;

  Map<String, dynamic> get _profileMetadata {
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    if (meta is Map<String, dynamic>) {
      return meta;
    }
    return <String, dynamic>{};
  }

  double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    return double.tryParse(value.toString());
  }

  int? _estimatedBmr() {
    final height = _toDouble(_profileMetadata['height']);
    final weight = _toDouble(_profileMetadata['weight']);
    final ageRaw = _profileMetadata['age'];
    final age = ageRaw == null ? null : int.tryParse(ageRaw.toString());
    final gender = (_profileMetadata['gender'] ?? '').toString().toLowerCase();

    if (height == null || weight == null || age == null) {
      return null;
    }

    final base = (10 * weight) + (6.25 * height) - (5 * age);
    final adjustment = gender.contains('male')
        ? 5
        : gender.contains('female')
        ? -161
        : 0;

    return (base + adjustment).round();
  }

  Widget _bmrCard() {
    final bmr = _estimatedBmr();
    final height = _profileMetadata['height']?.toString();
    final weight = _profileMetadata['weight']?.toString();
    final age = _profileMetadata['age']?.toString();
    final activity = (_profileMetadata['activity_level'] ?? 'moderate')
        .toString();

    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [GymColors.accent, GymColors.accentSoft],
                ),
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: Colors.black,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated BMR',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bmr == null ? 'Complete profile setup' : '$bmr kcal/day',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bmr == null
                        ? 'Add height, weight, age, and gender in your profile to unlock the estimate.'
                        : 'Height ${height ?? '-'} cm • Weight ${weight ?? '-'} kg • Age ${age ?? '-'} • Activity $activity',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.66),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _glassCard({required Widget child}) {
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

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.70), height: 1.45),
        ),
      ],
    );
  }

  Widget _bodyPartCard(WorkoutBodyPart part) {
    final selected = _selectedBodyPartId == part.id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          setState(() {
            _selectedBodyPartId = part.id;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      part.color.withOpacity(0.96),
                      part.color.withOpacity(0.70),
                    ],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF101722), Color(0xFF0B1018)],
                  ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? part.color : Colors.white.withOpacity(0.10),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.black.withOpacity(0.12)
                      : part.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  part.icon,
                  color: selected ? Colors.black : part.color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      part.label,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      part.subtitle,
                      style: TextStyle(
                        color: selected
                            ? Colors.black.withOpacity(0.78)
                            : Colors.white.withOpacity(0.66),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.38)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _exerciseCard(WorkoutExercise exercise) {
    return _glassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ExerciseTutorialScreen(exercise: exercise),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          exercise.color,
                          exercise.color.withOpacity(0.62),
                        ],
                      ),
                    ),
                    child: Icon(exercise.icon, color: Colors.black, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exercise.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          exercise.description,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.70),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _pill(
                    'Body part: ${_selectedBodyPart.label}',
                    exercise.color,
                  ),
                  _pill(
                    'Equipment: ${exercise.equipment}',
                    GymColors.accentSoft,
                  ),
                  _pill('Duration: ${exercise.duration}', GymColors.accentCool),
                  _pill(
                    exercise.supported ? 'Tutorial ready' : 'Coming soon',
                    exercise.supported ? GymColors.accent : Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ExerciseTutorialScreen(exercise: exercise),
                    ),
                  );
                },
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Open tutorial'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedExercise = _selectedExercise;

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
            GymColors.accent.withOpacity(0.34),
            330,
          ),
          _glow(
            const Alignment(1.05, -0.8),
            GymColors.accentSoft.withOpacity(0.16),
            260,
          ),
          _glow(
            const Alignment(1.05, 1.0),
            GymColors.accentCool.withOpacity(0.14),
            300,
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _glassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      GymColors.accent,
                                      GymColors.accentSoft,
                                    ],
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
                                      'Training hub',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.98),
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.8,
                                      ),
                                    ),
                                    Text(
                                      'Pick a body part, then open the exercise tutorial.',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.68),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _bmrCard(),
                      const SizedBox(height: 18),
                      _sectionTitle(
                        'Step 1: Select body part',
                        'This screen is split into separate cards, not one long page.',
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 700;
                          final cardWidth = isWide
                              ? (constraints.maxWidth - 14) / 2
                              : constraints.maxWidth;

                          return Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: workoutBodyParts
                                .map(
                                  (part) => SizedBox(
                                    width: cardWidth,
                                    child: _bodyPartCard(part),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle(
                        'Step 2: Select exercise',
                        'Tap the exercise card to open the tutorial for the selected body part.',
                      ),
                      const SizedBox(height: 14),
                      _exerciseCard(selectedExercise),
                      const SizedBox(height: 20),
                      _glassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: _selectedBodyPart.color.withOpacity(
                                    0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _selectedBodyPart.icon,
                                  color: _selectedBodyPart.color,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Selected body part: ${_selectedBodyPart.label}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
