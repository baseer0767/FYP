import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/workout_catalog.dart';
import '../theme/gym_theme.dart';
import 'main_interface.dart';

class ExerciseTutorialScreen extends StatefulWidget {
  const ExerciseTutorialScreen({super.key, required this.exercise});

  final WorkoutExercise exercise;

  @override
  State<ExerciseTutorialScreen> createState() => _ExerciseTutorialScreenState();
}

class _ExerciseTutorialScreenState extends State<ExerciseTutorialScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  WorkoutExercise get exercise => widget.exercise;

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

  Widget _backButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _modelPreview(WorkoutBodyPart bodyPart) {
    final baseColor = exercise.color;

    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [baseColor, baseColor.withOpacity(0.60)],
                    ),
                  ),
                  child: const Icon(
                    Icons.view_in_ar_rounded,
                    color: Colors.black,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '3D model guide',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Rotate the visual and match the working body part: ${bodyPart.label.toLowerCase()}.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.68),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            AspectRatio(
              aspectRatio: 1.35,
              child: AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  final t = _rotationController.value * math.pi * 2;
                  final angleY = math.sin(t) * 0.18;
                  final angleX = -0.12 + math.cos(t * 0.7) * 0.03;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0018)
                      ..rotateX(angleX)
                      ..rotateY(angleY),
                    child: child,
                  );
                },
                child: _ExerciseModelStage(
                  exercise: exercise,
                  bodyPart: bodyPart,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This view gives you a visual form reference before you start the steps.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    final bodyPart = bodyPartForId(exercise.bodyPartId);

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
            320,
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
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _glassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            children: [
                              _backButton(context),
                              const SizedBox(width: 14),
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      exercise.color,
                                      exercise.color.withOpacity(0.60),
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  exercise.icon,
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
                                      exercise.label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      exercise.description,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.70),
                                        height: 1.4,
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
                      _modelPreview(bodyPart),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _pill('Body part: ${bodyPart.label}', exercise.color),
                          _pill(
                            'Equipment: ${exercise.equipment}',
                            GymColors.accentSoft,
                          ),
                          _pill(
                            'Duration: ${exercise.duration}',
                            GymColors.accentCool,
                          ),
                          _pill(
                            exercise.supported
                                ? 'Supported by FitPose'
                                : 'Coming soon',
                            exercise.supported ? GymColors.accent : Colors.grey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _glassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'How to perform it',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...exercise.tutorialSteps.asMap().entries.map((
                                entry,
                              ) {
                                final index = entry.key + 1;
                                final step = entry.value;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.08),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: exercise.color.withOpacity(
                                              0.16,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '$index',
                                            style: TextStyle(
                                              color: exercise.color,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            step,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.92,
                                              ),
                                              height: 1.45,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _glassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tips',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...exercise.tips.map(
                                (tip) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.bolt_rounded,
                                        color: exercise.color,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          tip,
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.82,
                                            ),
                                            height: 1.4,
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
                      const SizedBox(height: 18),
                      if (exercise.supported)
                        _glassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Ready when you are',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'FitPose supports this exercise, so you can jump into the camera training screen now.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.72),
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              MainInterfaceScreen(
                                                initialExerciseLabel:
                                                    exercise.label,
                                                initialExerciseApi:
                                                    exercise.apiName,
                                              ),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      'Start Training',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        _glassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  color: exercise.color,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'This exercise is not supported yet. The tutorial is ready, but the training button stays hidden for now.',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.75),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextButton.icon(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  label: const Text('Back to exercises'),
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

class _ExerciseModelStage extends StatelessWidget {
  const _ExerciseModelStage({required this.exercise, required this.bodyPart});

  final WorkoutExercise exercise;
  final WorkoutBodyPart bodyPart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101722), Color(0xFF0B1018)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _StageGridPainter(bodyPart.color.withOpacity(0.10)),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildModel(),
                  const SizedBox(height: 18),
                  Text(
                    exercise.label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.96),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Target area: ${bodyPart.label}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModel() {
    switch (exercise.bodyPartId) {
      case 'core':
        return _PoseModel(highlight: bodyPart.color, pose: _PoseType.plank);
      case 'back':
        return _PoseModel(highlight: bodyPart.color, pose: _PoseType.deadlift);
      case 'arms':
        return _PoseModel(highlight: bodyPart.color, pose: _PoseType.bicepCurl);
      case 'chest':
      default:
        return _PoseModel(highlight: bodyPart.color, pose: _PoseType.pushUp);
    }
  }
}

class _StageGridPainter extends CustomPainter {
  const _StageGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final background = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.24), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, background);

    for (int i = 1; i < 6; i++) {
      final dy = size.height * (i / 6);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }

    for (int i = 1; i < 6; i++) {
      final dx = size.width * (i / 6);
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StageGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

enum _PoseType { plank, deadlift, bicepCurl, pushUp }

class _PoseModel extends StatelessWidget {
  const _PoseModel({required this.highlight, required this.pose});

  final Color highlight;
  final _PoseType pose;

  @override
  Widget build(BuildContext context) {
    switch (pose) {
      case _PoseType.plank:
        return _buildHorizontalPose(bodyLine: 0.0, armAngle: -0.35);
      case _PoseType.pushUp:
        return _buildHorizontalPose(bodyLine: 0.05, armAngle: -0.45);
      case _PoseType.deadlift:
        return _buildDeadliftPose();
      case _PoseType.bicepCurl:
        return _buildBicepPose();
    }
  }

  Widget _baseStage({required Widget child}) {
    return AspectRatio(
      aspectRatio: 1.1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 16,
            child: Container(
              width: 230,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    highlight.withOpacity(0.14),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildHorizontalPose({
    required double bodyLine,
    required double armAngle,
  }) {
    return _baseStage(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 44,
            right: 44,
            top: 120,
            child: Container(
              height: 18,
              decoration: BoxDecoration(
                color: highlight.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(left: 92, top: 104, child: _sphere(highlight, 28, false)),
          Positioned(
            left: 112,
            right: 90,
            top: 118,
            child: Transform.rotate(
              angle: bodyLine,
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      highlight.withOpacity(0.92),
                      highlight.withOpacity(0.42),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.20),
                      blurRadius: 16,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 62,
            top: 110,
            child: Transform.rotate(
              angle: armAngle,
              child: Container(
                width: 88,
                height: 16,
                decoration: BoxDecoration(
                  color: highlight.withOpacity(0.56),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Positioned(
            right: 58,
            top: 110,
            child: Transform.rotate(
              angle: -armAngle,
              child: Container(
                width: 88,
                height: 16,
                decoration: BoxDecoration(
                  color: highlight.withOpacity(0.56),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadliftPose() {
    return _baseStage(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 84,
            child: Container(
              width: 250,
              height: 14,
              decoration: BoxDecoration(
                color: highlight.withOpacity(0.20),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(top: 96, left: 60, child: _sphere(highlight, 26, false)),
          Positioned(
            top: 108,
            left: 96,
            right: 96,
            child: Transform.rotate(
              angle: -0.34,
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      highlight.withOpacity(0.92),
                      highlight.withOpacity(0.40),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Positioned(
            top: 150,
            left: 122,
            child: Transform.rotate(
              angle: 0.60,
              child: Container(
                width: 96,
                height: 16,
                decoration: BoxDecoration(
                  color: highlight.withOpacity(0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Positioned(
            top: 180,
            left: 168,
            child: Transform.rotate(
              angle: -0.95,
              child: Container(
                width: 94,
                height: 16,
                decoration: BoxDecoration(
                  color: highlight.withOpacity(0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _dumbbellPlate(highlight),
                Container(
                  width: 90,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        highlight.withOpacity(0.90),
                        highlight.withOpacity(0.42),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                _dumbbellPlate(highlight),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBicepPose() {
    return _baseStage(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 64, child: _sphere(highlight, 26, false)),
          Positioned(
            top: 102,
            child: Container(
              width: 34,
              height: 108,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    highlight.withOpacity(0.92),
                    highlight.withOpacity(0.38),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            left: 70,
            top: 140,
            child: Transform.rotate(
              angle: -0.72,
              child: Container(
                width: 92,
                height: 16,
                decoration: BoxDecoration(
                  color: highlight.withOpacity(0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Positioned(
            right: 70,
            top: 140,
            child: Transform.rotate(
              angle: 0.72,
              child: Container(
                width: 92,
                height: 16,
                decoration: BoxDecoration(
                  color: highlight.withOpacity(0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            child: Row(
              children: [
                _dumbbellPlate(highlight),
                Container(
                  width: 78,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        highlight.withOpacity(0.90),
                        highlight.withOpacity(0.42),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                _dumbbellPlate(highlight),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sphere(Color color, double size, bool innerShadow) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(0.98), color.withOpacity(0.42)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(innerShadow ? 0.24 : 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
    );
  }

  Widget _dumbbellPlate(Color color) {
    return Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(0.95), color.withOpacity(0.45)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );
  }
}
