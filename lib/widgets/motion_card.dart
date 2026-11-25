import 'package:material_ui/material_ui.dart';
import 'package:motion/motion.dart';

/// Gives cards a short entrance animation and pointer/device driven tilt.
class MotionCard extends StatelessWidget {
  const MotionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 520),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, progress, child) => Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - progress)),
        child: Motion.only(child: child!),
      ),
    ),
  );
}
