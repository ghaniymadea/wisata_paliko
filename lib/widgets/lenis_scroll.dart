import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_web_scroll/flutter_web_scroll.dart';
import 'package:material_ui/material_ui.dart';

/// Adds Lenis-style wheel smoothing to one vertical Flutter scrollable on web.
class LenisScroll extends StatefulWidget {
  const LenisScroll({required this.child, super.key});

  final Widget child;

  @override
  State<LenisScroll> createState() => _LenisScrollState();
}

class _LenisScrollState extends State<LenisScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollable = PrimaryScrollController(
      controller: _controller,
      child: widget.child,
    );

    if (!kIsWeb) return scrollable;

    return SmoothScrollWeb(
      controller: _controller,
      config: SmoothScrollConfig.lenis(
        scrollSpeed: 1.1,
        damping: 0.1,
        enableMomentum: true,
      ),
      child: scrollable,
    );
  }
}
