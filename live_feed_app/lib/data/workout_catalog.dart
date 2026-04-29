import 'package:flutter/material.dart';

class WorkoutBodyPart {
  const WorkoutBodyPart({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class WorkoutExercise {
  const WorkoutExercise({
    required this.id,
    required this.bodyPartId,
    required this.label,
    required this.apiName,
    required this.description,
    required this.equipment,
    required this.duration,
    required this.icon,
    required this.color,
    required this.tutorialSteps,
    required this.tips,
    this.supported = true,
  });

  final String id;
  final String bodyPartId;
  final String label;
  final String apiName;
  final String description;
  final String equipment;
  final String duration;
  final IconData icon;
  final Color color;
  final List<String> tutorialSteps;
  final List<String> tips;
  final bool supported;
}

const List<WorkoutBodyPart> workoutBodyParts = <WorkoutBodyPart>[
  WorkoutBodyPart(
    id: 'core',
    label: 'Core',
    subtitle: 'Stability and control',
    icon: Icons.accessibility_new_rounded,
    color: Color(0xFFFF8A00),
  ),
  WorkoutBodyPart(
    id: 'back',
    label: 'Back',
    subtitle: 'Strength and hinge work',
    icon: Icons.fitness_center_rounded,
    color: Color(0xFF8BEA53),
  ),
  WorkoutBodyPart(
    id: 'arms',
    label: 'Arms',
    subtitle: 'Curl and pull power',
    icon: Icons.sports_martial_arts_rounded,
    color: Color(0xFFFF6B6B),
  ),
  WorkoutBodyPart(
    id: 'chest',
    label: 'Chest',
    subtitle: 'Pressing and push strength',
    icon: Icons.sports_gymnastics_rounded,
    color: Color(0xFF6EA8FE),
  ),
];

const List<WorkoutExercise> workoutExercises = <WorkoutExercise>[
  WorkoutExercise(
    id: 'plank',
    bodyPartId: 'core',
    label: 'Plank',
    apiName: 'plank',
    description: 'Hold a straight line from head to heels and brace your core.',
    equipment: 'Bodyweight',
    duration: '30-60 sec',
    icon: Icons.accessibility_new_rounded,
    color: Color(0xFFFFB347),
    tutorialSteps: <String>[
      'Set your forearms on the floor and keep elbows under shoulders.',
      'Brace your abs, squeeze glutes, and keep your body in one line.',
      'Breathe steadily and avoid sagging hips or a high pike.',
    ],
    tips: <String>[
      'Keep your neck neutral and eyes slightly ahead.',
      'Start with shorter holds and build up time gradually.',
    ],
  ),
  WorkoutExercise(
    id: 'deadlift',
    bodyPartId: 'back',
    label: 'Deadlift',
    apiName: 'deadlift',
    description: 'Drive the floor away and keep the bar close to your body.',
    equipment: 'Barbell or dumbbells',
    duration: '3-5 sets',
    icon: Icons.fitness_center_rounded,
    color: Color(0xFF8BEA53),
    tutorialSteps: <String>[
      'Stand tall with feet under the bar and brace your midsection.',
      'Push hips back, keep the spine neutral, and grab the weight firmly.',
      'Drive through the floor, then stand tall without overextending.',
    ],
    tips: <String>[
      'Keep the bar close to your shins.',
      'Stop if your back rounds under load.',
    ],
  ),
  WorkoutExercise(
    id: 'bicep_curl',
    bodyPartId: 'arms',
    label: 'Bicep Curl',
    apiName: 'bicep',
    description: 'Control the curl and keep your shoulders quiet.',
    equipment: 'Dumbbells',
    duration: '10-15 reps',
    icon: Icons.sports_martial_arts_rounded,
    color: Color(0xFFFF6B6B),
    tutorialSteps: <String>[
      'Stand tall with elbows pinned near your sides.',
      'Curl the dumbbells without swinging your torso.',
      'Lower slowly to keep tension on the biceps.',
    ],
    tips: <String>[
      'Use a weight you can control fully.',
      'Pause briefly at the top for a cleaner contraction.',
    ],
  ),
  WorkoutExercise(
    id: 'pushup',
    bodyPartId: 'chest',
    label: 'Push-up',
    apiName: 'pushup',
    description: 'Lower with control and press the floor away hard.',
    equipment: 'Bodyweight',
    duration: '8-20 reps',
    icon: Icons.sports_gymnastics_rounded,
    color: Color(0xFF6EA8FE),
    tutorialSteps: <String>[
      'Place hands slightly wider than shoulders and lock your plank line.',
      'Lower the chest under control until elbows reach a strong bend.',
      'Press up without letting the hips collapse.',
    ],
    tips: <String>[
      'Scale to knees or incline if needed.',
      'Keep shoulders packed and core tight.',
    ],
  ),
];

WorkoutBodyPart bodyPartForId(String id) {
  return workoutBodyParts.firstWhere((part) => part.id == id);
}

List<WorkoutExercise> exercisesForBodyPart(String bodyPartId) {
  return workoutExercises
      .where((exercise) => exercise.bodyPartId == bodyPartId)
      .toList(growable: false);
}

WorkoutExercise? exerciseForApiName(String apiName) {
  for (final exercise in workoutExercises) {
    if (exercise.apiName == apiName) {
      return exercise;
    }
  }
  return null;
}
