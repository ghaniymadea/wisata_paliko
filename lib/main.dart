import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:motion/motion.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth/auth_gate.dart';
import 'data/explorer_repository.dart';
import 'data/models.dart';
import 'pages/admin_workflow_pages.dart';
import 'pages/role_pages.dart';
import 'widgets/motion_card.dart';
import 'widgets/lenis_scroll.dart';
import 'widgets/brand_wordmark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Motion.instance.initialize();
  } catch (error, stackTrace) {
    debugPrint('Motion initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vuycmgoxepxwxemkiwpt.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_MzTtp6VZWJfn2A8xGopEVA_g08cCl9F',
  );
  final supabaseKey = supabasePublishableKey.isNotEmpty
      ? supabasePublishableKey
      : supabaseAnonKey;
  final configured = supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
  if (configured) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  }
  final preferences = await SharedPreferences.getInstance();
  final savedTheme = preferences.getString('app_theme_mode');
  final initialThemeMode = switch (savedTheme) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.light,
  };
  runApp(
    LuakExplorerApp(
      configured: configured,
      preferences: preferences,
      initialThemeMode: initialThemeMode,
    ),
  );
}

const _forest = Color(0xFF1B5E20);
const _leaf = Color(0xFF2E7D32);
const _clay = Color(0xFFC27D38);
const _ink = Color(0xFF1E293B);
const _muted = Color(0xFF718096);
const _paper = Color(0xFFF7F8F4);

Future<void> _openGoogleMaps(BuildContext context, Spot spot) async {
  final latitude = spot.latitude;
  final longitude = spot.longitude;
  final query = latitude != null && longitude != null
      ? '$latitude,$longitude'
      : '${spot.name}, ${spot.area}, Sumatera Barat';
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    _showMessage(context, 'Google Maps tidak dapat dibuka.');
  }
}

({double latitude, double longitude})? _coordinatesFromMapsLink(String value) {
  final text = Uri.decodeFull(value.trim());
  if (text.isEmpty) return null;
  final patterns = [
    RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
    RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
    RegExp(
      r'(?:[?&](?:q|query|ll)=|/search/)(-?\d+(?:\.\d+)?)[,;]\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ),
    RegExp(r'(-?\d{1,2}(?:\.\d+)?)\s*[,;]\s*(-?\d{1,3}(?:\.\d+)?)'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      final latitude = double.tryParse(match.group(1)!);
      final longitude = double.tryParse(match.group(2)!);
      if (latitude != null &&
          longitude != null &&
          latitude >= -90 &&
          latitude <= 90 &&
          longitude >= -180 &&
          longitude <= 180) {
        return (latitude: latitude, longitude: longitude);
      }
    }
  }
  return null;
}

Future<({double latitude, double longitude})?> _resolveMapsLink(
  String value,
) async {
  final local = _coordinatesFromMapsLink(value);
  if (local != null) return local;
  if (!value.trim().contains('maps.app.goo.gl') &&
      !value.trim().contains('goo.gl')) {
    return null;
  }
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'resolve-maps-link',
      body: {'url': value.trim()},
    );
    final data = asJsonMap(response.data);
    final latitude = (data?['latitude'] as num?)?.toDouble();
    final longitude = (data?['longitude'] as num?)?.toDouble();
    if (latitude != null && longitude != null) {
      return (latitude: latitude, longitude: longitude);
    }
  } on Exception {
    // Pengguna tetap bisa memakai input koordinat manual.
  }
  return null;
}

Future<void> _shareSpot(
  BuildContext context,
  Spot spot, {
  ExplorerRepository? repository,
}) async {
  final mapsQuery = spot.latitude != null && spot.longitude != null
      ? '${spot.latitude},${spot.longitude}'
      : '${spot.name}, ${spot.area}, Sumatera Barat';
  final mapsUrl = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': mapsQuery,
  });
  try {
    await repository?.recordSpotShare(spot.id);
    await SharePlus.instance.share(
      ShareParams(
        title: spot.name,
        text:
            '${spot.name}\n${spot.area}\n\n${spot.description}\n\nLokasi: $mapsUrl',
      ),
    );
  } on Exception catch (error) {
    if (context.mounted) _showMessage(context, 'Gagal membagikan spot: $error');
  }
}

Future<void> _openStoryViewer(
  BuildContext context,
  Story story,
  ExplorerRepository repository,
) async {
  try {
    await repository.recordStoryView(story.id);
  } on Exception {
    // Gagal mencatat view tidak boleh menghalangi pengguna melihat cerita.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFF101713)),
              InteractiveViewer(
                minScale: 1,
                maxScale: 3,
                child: Image.network(
                  story.image,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                  errorBuilder: (_, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.62),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      stops: const [0, 0.36, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: const LinearProgressIndicator(
                        value: 1,
                        minHeight: 3,
                        backgroundColor: Colors.white38,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.auto_stories_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            story.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          tooltip: 'Tutup cerita',
                          color: Colors.white,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'Cerita pengguna · tayang 24 jam',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    required this.configured,
    required this.onThemeModeChanged,
    super.key,
  });

  final bool configured;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _logoRotation;
  late final Animation<double> _copyFade;
  late final Animation<Offset> _copyOffset;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..forward();
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.76, curve: Curves.easeOutCubic),
    );
    _scale = Tween<double>(begin: 0.72, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.78, curve: Curves.easeOutBack),
      ),
    );
    _logoRotation = Tween<double>(begin: -0.08, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
      ),
    );
    _copyFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 1, curve: Curves.easeOut),
    );
    _copyOffset = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.22, 0.88, curve: Curves.easeOutCubic),
          ),
        );
    _timer = Timer(const Duration(milliseconds: 1700), _openApp);
  }

  void _openApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => SupabaseAuthGate(
          configured: widget.configured,
          authenticatedBuilder: (context) =>
              ExplorerShell(onThemeModeChanged: widget.onThemeModeChanged),
        ),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.035),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0B2418),
            Color(0xFF123D28),
            Color(0xFF1D6540),
            Color(0xFF3E8050),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _SplashBackdropPainter()),
          const _SplashOrb(size: 250, top: -80, right: -70),
          const _SplashOrb(size: 180, bottom: 100, left: -90),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RotationTransition(
                      turns: _logoRotation,
                      child: Container(
                        width: 122,
                        height: 122,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(38),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.42),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF06170E).withValues(alpha: 0.32),
                              blurRadius: 48,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: const _LogoImage(size: 104),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    FadeTransition(
                      opacity: _copyFade,
                      child: SlideTransition(
                        position: _copyOffset,
                        child: const Text(
                          'MENJELAJAHI RANAH LUAK',
                          style: TextStyle(
                            color: Color(0xFFC5E4C2),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    FadeTransition(
                      opacity: _copyFade,
                      child: SlideTransition(
                        position: _copyOffset,
                        child: const BrandWordmark(
                          text: 'LUAK EXPLORER',
                          fontSize: 24,
                          letterSpacing: 1.4,
                          onDarkSurface: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FadeTransition(
                      opacity: _copyFade,
                      child: SlideTransition(
                        position: _copyOffset,
                        child: const Text(
                          'Temukan cerita di setiap perjalanan',
                          style: TextStyle(
                            color: Color(0xFFD9EADB),
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFB5D8A8),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Memuat aplikasi...',
                          style: TextStyle(
                            color: Color(0xFFD9EADB),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Text(
              'PAYAKUMBUH • LIMA PULUH KOTA',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xD9FFFFFF),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SplashBackdropPainter extends CustomPainter {
  const _SplashBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final compassCenter = Offset(width * 0.84, height * 0.2);
    final compassRadius = math.min(width * 0.16, 76.0).toDouble();
    final compassPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.075)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(compassCenter, compassRadius, compassPaint);
    canvas.drawCircle(compassCenter, compassRadius * 0.82, compassPaint);
    for (var tick = 0; tick < 16; tick++) {
      final angle = tick * math.pi / 8;
      final outer = compassRadius * (tick.isEven ? 0.94 : 0.98);
      final inner = compassRadius * (tick.isEven ? 0.82 : 0.88);
      canvas.drawLine(
        compassCenter + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        compassCenter + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        compassPaint,
      );
    }

    final farHill = ui.Path()
      ..moveTo(0, height * 0.79)
      ..quadraticBezierTo(width * 0.2, height * 0.68, width * 0.39, height * 0.8)
      ..quadraticBezierTo(width * 0.61, height * 0.9, width * 0.79, height * 0.74)
      ..quadraticBezierTo(width * 0.92, height * 0.65, width, height * 0.73)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
    canvas.drawPath(
      farHill,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x332B6945), Color(0x773D8051)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );

    final nearHill = ui.Path()
      ..moveTo(0, height * 0.9)
      ..quadraticBezierTo(width * 0.24, height * 0.78, width * 0.45, height * 0.89)
      ..quadraticBezierTo(width * 0.76, height * 1.02, width, height * 0.84)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
    canvas.drawPath(
      nearHill,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x44152F22), Color(0xAA0A1D13)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashBackdropPainter oldDelegate) => false;
}

class _SplashLoadingView extends StatefulWidget {
  const _SplashLoadingView();

  @override
  State<_SplashLoadingView> createState() => _SplashLoadingViewState();
}

class _SplashLoadingViewState extends State<_SplashLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0B2418),
            Color(0xFF123D28),
            Color(0xFF1D6540),
            Color(0xFF3E8050),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _SplashBackdropPainter()),
          const _SplashOrb(size: 250, top: -80, right: -70),
          const _SplashOrb(size: 180, bottom: 100, left: -90),
          Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Transform.scale(
                scale: 0.98 + _pulse.value * 0.02,
                child: child,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 122,
                    height: 122,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(38),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.42),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF06170E).withValues(alpha: 0.32),
                          blurRadius: 48,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: const _LogoImage(size: 104),
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'MENJELAJAHI RANAH LUAK',
                    style: TextStyle(
                      color: Color(0xFFC5E4C2),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: 9),
                  const BrandWordmark(
                    text: 'LUAK EXPLORER',
                    fontSize: 24,
                    letterSpacing: 1.4,
                    onDarkSurface: true,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Temukan cerita di setiap perjalanan',
                    style: TextStyle(
                      color: Color(0xFFD9EADB),
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFB5D8A8),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Menyiapkan data...',
                        style: TextStyle(
                          color: Color(0xFFD9EADB),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Text(
              'PAYAKUMBUH  ·  LIMA PULUH KOTA',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SplashOrb extends StatefulWidget {
  const _SplashOrb({
    required this.size,
    this.top,
    this.right,
    this.bottom,
    this.left,
  });

  final double size;
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;

  @override
  State<_SplashOrb> createState() => _SplashOrbState();
}

class _SplashOrbState extends State<_SplashOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    top: widget.top,
    right: widget.right,
    bottom: widget.bottom,
    left: widget.left,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: 0.55 + _controller.value * 0.35,
        child: Transform.scale(
          scale: 0.94 + _controller.value * 0.12,
          child: child,
        ),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.04),
              blurRadius: 48,
              spreadRadius: 8,
            ),
          ],
        ),
      ),
    ),
  );
}

class LuakExplorerApp extends StatefulWidget {
  const LuakExplorerApp({
    required this.configured,
    required this.preferences,
    required this.initialThemeMode,
    super.key,
  });

  final bool configured;
  final SharedPreferences preferences;
  final ThemeMode initialThemeMode;

  @override
  State<LuakExplorerApp> createState() => _LuakExplorerAppState();
}

class _LuakExplorerAppState extends State<LuakExplorerApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;

  void _setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    widget.preferences.setString(
      'app_theme_mode',
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Luak Explorer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _forest,
        primary: _forest,
        secondary: _clay,
        surface: _paper,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: const TextStyle(
          fontFamily: 'serif',
          color: _ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        contentTextStyle: const TextStyle(
          color: _ink,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAF7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFE1E8DF), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFE1E8DF), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _forest, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFD64545)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFD64545), width: 1.5),
        ),
        labelStyle: const TextStyle(color: _muted, fontSize: 13),
        hintStyle: const TextStyle(color: Color(0xFF9AA69C), fontSize: 13),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          elevation: const WidgetStatePropertyAll(10),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAF7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFE1E8DF)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          side: const BorderSide(color: Color(0xFFB9C8BA), width: 1.2),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        backgroundColor: const Color(0xFF18311F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontFamily: 'serif',
          color: _ink,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
        titleLarge: TextStyle(
          fontFamily: 'serif',
          color: _ink,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          fontFamily: 'serif',
          color: _ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(color: _ink, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: _muted, fontSize: 12, height: 1.4),
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF101713),
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: const Color(0xFF75B977),
        primary: const Color(0xFF8BCB8B),
        secondary: const Color(0xFFE5AA6B),
        surface: const Color(0xFF18211B),
        onSurface: const Color(0xFFE6EEE7),
        onSurfaceVariant: const Color(0xFFB1BEB2),
        onSecondaryContainer: const Color(0xFFE1F0E2),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontFamily: 'serif',
          color: Color(0xFFE8F0E8),
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: TextStyle(
          fontFamily: 'serif',
          color: Color(0xFFE8F0E8),
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          fontFamily: 'serif',
          color: Color(0xFFE8F0E8),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(
          color: Color(0xFFE2EAE2),
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: Color(0xFFAAB8AB),
          fontSize: 12,
          height: 1.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF202B23),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF354438)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF354438)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF18211B),
        surfaceTintColor: const Color(0xFF18211B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    ),
    themeMode: _themeMode,
    home: SplashScreen(
      configured: widget.configured,
      onThemeModeChanged: _setThemeMode,
    ),
  );
}

class ExplorerShell extends StatefulWidget {
  const ExplorerShell({required this.onThemeModeChanged, super.key});

  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<ExplorerShell> createState() => _ExplorerShellState();
}

class _ExplorerShellState extends State<ExplorerShell>
    with SingleTickerProviderStateMixin {
  final _repository = ExplorerRepository(Supabase.instance.client);
  Timer? _railHoverTimer;
  late final AnimationController _tabTransitionController;
  bool _tabTransitioning = false;
  int _tab = 0;
  bool _railExtended = false;
  AppRole _role = AppRole.penjelajah;
  JsonMap? _profile;
  List<Spot> _spots = [];
  List<Story> _stories = [];
  List<TravelCollection> _collections = [];
  List<TravelCollection> _publicCollections = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _districts = [];
  Set<String> _saved = {};
  bool _loading = true;
  bool _hasLoaded = false;
  Object? _loadError;

  void _setRailExtended(bool extended) {
    _railHoverTimer?.cancel();
    _railHoverTimer = Timer(Duration(milliseconds: extended ? 0 : 320), () {
      if (mounted && _railExtended != extended) {
        setState(() => _railExtended = extended);
      }
    });
  }

  Future<void> _selectTab(int index) async {
    if (index == _tab || index < 0 || _tabTransitioning) return;
    _tabTransitioning = true;
    try {
      await _tabTransitionController.animateTo(
        0.35,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeInCubic,
      );
      if (!mounted) return;
      setState(() => _tab = index);
      await _tabTransitionController.animateTo(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } on TickerCanceled {
      // Navigasi dapat berakhir ketika widget ini sedang dihapus.
    } finally {
      _tabTransitioning = false;
    }
  }

  @override
  void dispose() {
    _railHoverTimer?.cancel();
    _tabTransitionController.dispose();
    super.dispose();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konfirmasi keluar'),
        content: const Text('Apakah Anda yakin mau keluar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ya, keluar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      // Saat refresh, pertahankan halaman yang sedang terlihat. Loading penuh
      // hanya dipakai pada pemuatan pertama ketika belum ada data.
      _loading = !_hasLoaded;
      _loadError = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw const AuthException(
          'Sesi login sudah berakhir. Silakan masuk kembali.',
        );
      }
      final userId = user.id;
      final profile = await _repository.getMyProfile();
      final role = appRoleFromJson(asJsonMap(profile['roles']));
      final results = await Future.wait<dynamic>([
        _repository.getApprovedSpots(),
        _repository.getBookmarkedSpotIds(userId),
        _repository.getActiveStories(),
        _repository.getMyCollections(),
        _repository.getPublicCollections(),
        _repository.getCategories(),
        _repository.getDistricts(),
      ]);
      final spots = results[0] as List<Spot>;
      final saved = results[1] as Set<String>;
      final stories = results[2] as List<Story>;
      final collections = results[3] as List<TravelCollection>;
      final publicCollections = results[4] as List<TravelCollection>;
      final categories = results[5] as List<Map<String, dynamic>>;
      final districts = results[6] as List<Map<String, dynamic>>;
      if (!mounted) return;
      setState(() {
        _role = role;
        _profile = profile;
        _spots = spots;
        _saved = saved;
        _stories = stories;
        _collections = collections;
        _publicCollections = publicCollections;
        _categories = categories;
        _districts = districts;
        _loading = false;
        _hasLoaded = true;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<bool> _toggleSaved(Spot spot) async {
    try {
      final saved = await _repository.toggleBookmark(spot.id);
      if (!mounted) return false;
      setState(() {
        if (saved) {
          _saved.add(spot.id);
        } else {
          _saved.remove(spot.id);
        }
      });
      return true;
    } on Exception catch (error) {
      if (mounted) _showMessage(context, 'Bookmark gagal disimpan: $error');
      return false;
    }
  }

  Future<void> _toggleLike(Spot spot) async {
    try {
      await _repository.toggleSpotLike(spot.id);
      await _loadData();
    } on Exception catch (error) {
      if (mounted) _showMessage(context, 'Like gagal disimpan: $error');
    }
  }

  Future<void> _refreshCollections() async {
    final collections = await _repository.getMyCollections();
    final publicCollections = await _repository.getPublicCollections();
    if (mounted) {
      setState(() {
        _collections = collections;
        _publicCollections = publicCollections;
      });
    }
  }

  void _openSpot(Spot spot) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SpotDetailPage(
          spot: spot,
          isSaved: _saved.contains(spot.id),
          role: _role,
          onSave: () => _toggleSaved(spot),
          repository: _repository,
          onCollectionChanged: _refreshCollections,
          onDataChanged: _loadData,
        ),
      ),
    );
  }

  Future<void> _createStoryFromFeed() async {
    if (_spots.isEmpty) {
      _showMessage(context, 'Belum ada spot yang bisa dipilih untuk cerita.');
      return;
    }
    final title = TextEditingController(text: 'Cerita baru');
    Spot selectedSpot = _spots.first;
    Uint8List? imageBytes;
    String? imageName;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          constraints: const BoxConstraints(maxWidth: 520),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tambah cerita',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                'Bagikan momen terbaikmu selama 24 jam.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Spot>(
                  initialValue: selectedSpot,
                  decoration: InputDecoration(
                    labelText: 'Pilih spot',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: _spots
                      .map(
                        (spot) => DropdownMenuItem(
                          value: spot,
                          child: Text(
                            spot.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (spot) {
                    if (spot != null) setDialogState(() => selectedSpot = spot);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: 'Keterangan cerita',
                    prefixIcon: const Icon(Icons.edit_note_outlined),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    counterStyle: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    final files = await FilePicker.pickFiles(
                      type: FileType.image,
                    );
                    final file = files.isEmpty ? null : files.first;
                    if (file != null) {
                      final bytes = await file.readAsBytes();
                      setDialogState(() {
                        imageBytes = bytes;
                        imageName = file.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Flexible(
                    child: Text(
                      imageName ?? 'Pilih foto dari perangkat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (imageBytes != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      imageBytes!,
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _forest.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.schedule_outlined, size: 17, color: _forest),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cerita akan tampil selama 24 jam.',
                          style: TextStyle(color: _forest, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: imageBytes == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Posting'),
            ),
          ],
        ),
      ),
    );
    if (result == true && imageBytes != null && imageName != null) {
      try {
        final url = await _repository.uploadStoryMedia(
          spotId: selectedSpot.id,
          bytes: imageBytes!,
          fileName: imageName!,
          contentType: 'image/jpeg',
        );
        await _repository.createStory(
          spotId: selectedSpot.id,
          title: title.text.trim().isEmpty ? 'Cerita baru' : title.text.trim(),
          mediaUrl: url,
          expiresAt: DateTime.now().add(const Duration(hours: 24)),
        );
        await _loadData();
        if (mounted) _showMessage(context, 'Cerita berhasil ditambahkan.');
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Cerita gagal ditambahkan: $error');
      }
    } else if (result == true && mounted) {
      _showMessage(context, 'Foto cerita wajib dipilih.');
    }
    title.dispose();
  }

  void _openCollection(TravelCollection collection) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CollectionDetailPage(
          collection: collection,
          entries: _repository.getCollectionEntries(collection.id),
          onOpenSpot: _openSpot,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _SplashLoadingView();
    }
    if (_loadError != null && !_hasLoaded) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 42, color: _forest),
                const SizedBox(height: 12),
                const Text(
                  'Data Supabase gagal dimuat',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 8),
                SelectableText('$_loadError', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadData,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final pages = [
      FeedPage(
        spots: _spots,
        districts: _districts,
        stories: _stories,
        saved: _saved,
        onSave: _toggleSaved,
        onLike: _toggleLike,
        onShare: (spot) => _shareSpot(context, spot, repository: _repository),
        onOpen: _openSpot,
        onOpenStory: (story) async {
          await _openStoryViewer(context, story, _repository);
        },
        onAddStory: _createStoryFromFeed,
        onOpenTips: (spot) =>
            _showTipsSheet(context, _repository, spot, onSubmitted: _loadData),
        onExplore: () => setState(() => _tab = 1),
        onNotifications: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NotificationsPage(repository: _repository),
          ),
        ),
      ),
      ExplorePage(
        spots: _spots,
        categories: _categories,
        districts: _districts,
        saved: _saved,
        onSave: _toggleSaved,
        onOpen: _openSpot,
        onSubmitSpot:
            ({
              required name,
              required slug,
              required summary,
              required districtId,
              required categoryId,
              latitude,
              longitude,
              imageBytes,
              imageName,
            }) async {
              final spotId = await _repository.createSpot(
                name: name,
                slug: slug,
                summary: summary,
                districtId: districtId,
                categoryId: categoryId,
                latitude: latitude,
                longitude: longitude,
              );
              if (imageBytes is Uint8List && imageName is String) {
                await _repository.uploadSpotMedia(
                  spotId: spotId,
                  bytes: imageBytes,
                  fileName: imageName,
                  contentType: 'image/*',
                  mediaTypeId: 1,
                );
              }
              await _loadData();
              if (context.mounted) {
                _showMessage(
                  context,
                  'Usulan spot terkirim dan menunggu verifikasi.',
                );
              }
            },
      ),
      NearbyPage(spots: _spots, onOpen: _openSpot),
      SavedPage(
        savedSpots: _spots.where((spot) => _saved.contains(spot.id)).toList(),
        collections: _collections,
        publicCollections: _publicCollections,
        role: _role,
        onThemeModeChanged: widget.onThemeModeChanged,
        repository: _repository,
        profileName: jsonString(_profile?['nama']).isNotEmpty
            ? jsonString(_profile?['nama'])
            : Supabase.instance.client.auth.currentUser?.email ?? 'Penjelajah',
        username: jsonString(_profile?['username']).isNotEmpty
            ? jsonString(_profile?['username'])
            : 'penjelajah',
        onOpen: _openSpot,
        onOpenCollection: _openCollection,
        onSignOut: _confirmSignOut,
        onRefresh: _loadData,
        onCreateCollection:
            ({required title, required description, required isPublic}) async {
              await _repository.createCollection(
                title: title,
                description: description,
                isPublic: isPublic,
              );
              await _loadData();
            },
      ),
      if (_role == AppRole.admin)
        AdminPage(
          repository: _repository,
          onOpenSpot: _openSpot,
          onDataChanged: _loadData,
        ),
    ];

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'Feed',
      ),
      const NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore_rounded),
        label: 'Jelajah',
      ),
      const NavigationDestination(
        icon: Icon(Icons.location_on_outlined),
        selectedIcon: Icon(Icons.location_on_rounded),
        label: 'Peta Spot',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Profil',
      ),
      if (_role == AppRole.admin)
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scheme = Theme.of(context).colorScheme;
        final wide = constraints.maxWidth >= 900;
        final content = AnimatedBuilder(
          animation: _tabTransitionController,
          builder: (context, child) {
            final progress = _tabTransitionController.value;
            return Opacity(
              opacity: 0.55 + progress * 0.45,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - progress)),
                child: Transform.scale(
                  scale: 0.985 + progress * 0.015,
                  child: child,
                ),
              ),
            );
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: IndexedStack(index: _tab, children: pages),
            ),
          ),
        );
        final adminTabHasOwnRefresh = _role == AppRole.admin && _tab == 4;
        final mobileContent = adminTabHasOwnRefresh
            ? content
            : RefreshIndicator(
                onRefresh: _loadData,
                color: scheme.primary,
                backgroundColor: scheme.surface,
                displacement: 42,
                edgeOffset: 8,
                child: content,
              );
        return Scaffold(
          body: SafeArea(
            bottom: !wide,
            child: wide
                ? Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => _setRailExtended(true),
                          onExit: (_) => _setRailExtended(false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeInOutCubic,
                            width: _railExtended ? 228 : 82,
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(color: scheme.outlineVariant),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0x180F3D24),
                                  blurRadius: _railExtended ? 32 : 22,
                                  spreadRadius: _railExtended ? 1 : 0,
                                  offset: Offset(_railExtended ? 7 : 4, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 22),
                                  child: const _BrandMark(),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    itemCount: destinations.length,
                                    itemBuilder: (context, index) {
                                      final item = destinations[index];
                                      final selected = _tab == index;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 7),
                                        child: Material(
                                          color: selected
                                              ? scheme.secondaryContainer
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(14),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(14),
                                            onTap: () => _selectTab(index),
                                            child: SizedBox(
                                              height: 52,
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 64,
                                                    child: Center(
                                                      child: IconTheme(
                                                        data: IconThemeData(
                                                          color: selected
                                                              ? scheme.primary
                                                              : scheme.onSurfaceVariant,
                                                        ),
                                                        child: selected
                                                            ? (item.selectedIcon ?? item.icon)
                                                            : item.icon,
                                                      ),
                                                    ),
                                                  ),
                                                  ClipRect(
                                                    child: AnimatedOpacity(
                                                      opacity: _railExtended ? 1 : 0,
                                                      duration: const Duration(milliseconds: 180),
                                                      child: SizedBox(
                                                        width: _railExtended ? 134 : 0,
                                                        child: Text(
                                                          item.label,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.fade,
                                                          style: TextStyle(
                                                            color: selected
                                                                ? scheme.primary
                                                                : scheme.onSurfaceVariant,
                                                            fontWeight: selected
                                                                ? FontWeight.w700
                                                                : FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: content),
                    ],
                  )
                : mobileContent,
          ),
          bottomNavigationBar: wide
              ? null
              : _AnimatedBottomNavigationBar(
                  selectedIndex: _tab,
                  destinations: destinations,
                  onDestinationSelected: _selectTab,
                ),
        );
      },
    );
  }
}

class _AnimatedBottomNavigationBar extends StatelessWidget {
  const _AnimatedBottomNavigationBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Row(
          children: [
            for (var index = 0; index < destinations.length; index++)
              Expanded(
                child: _BottomNavigationItem(
                  destination: destinations[index],
                  selected: selectedIndex == index,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _BottomNavigationItem extends StatelessWidget {
  const _BottomNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            height: 58,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutBack,
                  child: IconTheme(
                    data: IconThemeData(
                      size: 23,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    child: selected
                        ? destination.selectedIcon ?? destination.icon
                        : destination.icon,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  child: Text(destination.label, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FeedPage extends StatefulWidget {
  const FeedPage({
    required this.spots,
    required this.districts,
    required this.stories,
    required this.saved,
    required this.onSave,
    required this.onLike,
    required this.onShare,
    required this.onOpen,
    required this.onOpenStory,
    required this.onAddStory,
    required this.onOpenTips,
    required this.onExplore,
    required this.onNotifications,
    super.key,
  });

  final List<Spot> spots;
  final List<Map<String, dynamic>> districts;
  final List<Story> stories;
  final Set<String> saved;
  final ValueChanged<Spot> onSave;
  final ValueChanged<Spot> onLike;
  final ValueChanged<Spot> onShare;
  final ValueChanged<Spot> onOpen;
  final ValueChanged<Story> onOpenStory;
  final VoidCallback onAddStory;
  final ValueChanged<Spot> onOpenTips;
  final VoidCallback onExplore;
  final VoidCallback onNotifications;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  int _category = 0;
  String _selectedCity = 'Payakumbuh';

  @override
  Widget build(BuildContext context) {
    final stories = widget.stories;
    final horizontal = MediaQuery.sizeOf(context).width >= 700 ? 28.0 : 20.0;
    final cityDistricts = <String, Set<int>>{};
    for (final district in widget.districts) {
      final city = asJsonMap(district['kabupaten_kota']);
      final cityName = jsonString(city?['nama']);
      final districtId = jsonInt(district['id']);
      if (cityName.isNotEmpty && districtId != null) {
        cityDistricts.putIfAbsent(cityName, () => <int>{}).add(districtId);
      }
    }
    final cityOptions = [
      'Semua wilayah',
      ...cityDistricts.keys.map(_cityDisplayName).toSet().toList()..sort(),
    ];
    final activeCity = cityOptions.contains(_selectedCity)
        ? _selectedCity
        : cityOptions.first;
    Set<int>? activeDistrictIds;
    if (activeCity != 'Semua wilayah') {
      for (final entry in cityDistricts.entries) {
        if (_cityDisplayName(entry.key) == activeCity) {
          activeDistrictIds = entry.value;
          break;
        }
      }
    }
    final feedSpots = widget.spots.where((spot) {
      final matchesCity =
          activeDistrictIds == null ||
          (spot.districtId != null &&
              activeDistrictIds.contains(spot.districtId));
      if (!matchesCity) return false;
      if (_category == 2) {
        return spot.category.toLowerCase().contains('kuliner');
      }
      if (_category == 3) {
        return spot.category.toLowerCase().contains('alam') ||
            spot.category.toLowerCase().contains('air');
      }
      return true;
    }).toList();

    return LenisScroll(
      child: CustomScrollView(
        primary: true,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const _BrandMark(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrandWordmark(
                          text: 'Luak Explorer',
                          fontSize: 20,
                          letterSpacing: 0.1,
                        ),
                        Text(
                          'PAYAKUMBUH & 50 KOTA',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cari tempat',
                    onPressed: widget.onExplore,
                    icon: Icon(
                      Icons.search_rounded,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notifikasi',
                    onPressed: widget.onNotifications,
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
            sliver: SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Keep the region row compact on phones and narrow tablet
                  // previews so the status chip never pushes the dropdown out.
                  final compact = constraints.maxWidth < 760;
                  return Row(
                    children: [
                      Icon(
                        Icons.explore,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Menjelajah sekitar',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.only(left: 10, right: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: activeCity,
                              isDense: true,
                              borderRadius: BorderRadius.circular(16),
                              dropdownColor: Theme.of(context)
                                  .colorScheme
                                  .surface,
                              elevation: 8,
                              menuMaxHeight: 260,
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 17,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              items: cityOptions
                                  .map(
                                    (city) => DropdownMenuItem<String>(
                                      value: city,
                                      child: Container(
                                        width: 168,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 9,
                                        ),
                                        decoration: BoxDecoration(
                                          color: city == activeCity
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .secondaryContainer
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                city,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (city == activeCity)
                                              Icon(
                                                Icons.check_rounded,
                                                size: 16,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              selectedItemBuilder: (context) => cityOptions
                                  .map(
                                    (city) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        city,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (city) {
                                if (city != null)
                                  setState(() => _selectedCity = city);
                              },
                            ),
                          ),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        _tag(
                          'Sumatera Barat',
                          const Color(0xFFE8F1E8),
                          _forest,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text(
                      'Cerita di sekitar',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onExplore,
                      child: const Text('Lihat semua'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 104,
                child: ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  scrollDirection: Axis.horizontal,
                  itemCount: stories.length + 1,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 15),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _AddStoryBubble(onTap: widget.onAddStory);
                    }
                    final story = stories[index - 1];
                    return _StoryBubble(
                      title: story.title,
                      image: story.image,
                      isNew: index == 1,
                      onTap: () => widget.onOpenStory(story),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 12),
            sliver: SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('Untuk Anda', 0),
                    const SizedBox(width: 8),
                    _filterChip('Terbaru', 1),
                    const SizedBox(width: 8),
                    _filterChip('Kuliner Autentik', 2),
                    const SizedBox(width: 8),
                    _filterChip('Spot Alam', 3),
                  ],
                ),
              ),
            ),
          ),
          if (feedSpots.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text('Belum ada spot untuk kategori ini.'),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _Reveal(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _FeedPost(
                          spot: feedSpots[index],
                          isSaved: widget.saved.contains(feedSpots[index].id),
                          onSave: () => widget.onSave(feedSpots[index]),
                          onLike: () => widget.onLike(feedSpots[index]),
                          onShare: () => widget.onShare(feedSpots[index]),
                          onOpen: () => widget.onOpen(feedSpots[index]),
                          onTips: () => widget.onOpenTips(feedSpots[index]),
                        ),
                      ),
                    ),
                  ),
                ),
                childCount: feedSpots.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int index) {
    final selected = _category == index;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _category = index),
      backgroundColor: scheme.surface,
      selectedColor: _forest,
      side: BorderSide(color: selected ? _forest : scheme.outlineVariant),
      labelStyle: TextStyle(
        color: selected ? Colors.white : scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 7),
    );
  }
}

class _EngagementButton extends StatelessWidget {
  const _EngagementButton({
    required this.icon,
    required this.count,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final int count;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          icon: Icon(icon, size: 21, color: color ?? scheme.onSurface),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _FeedPost extends StatelessWidget {
  const _FeedPost({
    required this.spot,
    required this.isSaved,
    required this.onSave,
    required this.onLike,
    required this.onShare,
    required this.onOpen,
    required this.onTips,
  });

  final Spot spot;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onOpen;
  final VoidCallback onTips;

  @override
  Widget build(BuildContext context) {
    final isFood = spot.category == 'Kuliner Legendaris';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 5, 12, 5),
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              child: Icon(Icons.person, color: scheme.primary),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    spot.creatorName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.verified, color: _leaf, size: 15),
              ],
            ),
            subtitle: Text(
              '@${spot.creatorUsername} · ${spot.area}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Opsi spot',
              icon: const Icon(Icons.more_horiz_rounded),
              offset: const Offset(0, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 8,
              onSelected: (action) {
                switch (action) {
                  case 'detail':
                    onOpen();
                  case 'save':
                    onSave();
                  case 'share':
                    onShare();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'detail',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.open_in_new_rounded, size: 20),
                    title: Text('Lihat detail spot'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'save',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.bookmark_rounded,
                      size: 20,
                      color: isSaved ? _forest : null,
                    ),
                    title: Text(
                      isSaved ? 'Hapus dari tersimpan' : 'Simpan spot',
                    ),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'share',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.share_rounded, size: 20),
                    title: Text('Bagikan spot'),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onOpen,
            child: AspectRatio(
              aspectRatio: 1.18,
              child: _NetworkPhoto(image: spot.image),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _EngagementButton(
                      icon: spot.likedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: spot.likedByMe
                          ? const Color(0xFFE05252)
                          : scheme.onSurface,
                      count: spot.likeCount,
                      onPressed: onLike,
                    ),
                    _EngagementButton(
                      icon: Icons.mode_comment_outlined,
                      count: spot.tipCount,
                      onPressed: onTips,
                    ),
                    _EngagementButton(
                      icon: Icons.send_outlined,
                      count: spot.shareCount,
                      onPressed: onShare,
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onSave,
                      icon: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${spot.name} — ${spot.description}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 9),
                GestureDetector(
                  onTap: isFood ? onTips : null,
                  child: Row(
                    children: [
                      Icon(
                        isFood ? Icons.lightbulb_outline : Icons.location_on,
                        size: 14,
                        color: isFood ? _clay : _forest,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isFood ? 'Tips Warga Lokal · Tulis tips' : spot.area,
                          style: TextStyle(
                            color: isFood ? _clay : scheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _timeAgo(spot.createdAt),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({
    required this.spots,
    required this.categories,
    required this.districts,
    required this.saved,
    required this.onSave,
    required this.onOpen,
    required this.onSubmitSpot,
    super.key,
  });

  final List<Spot> spots;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> districts;
  final Set<String> saved;
  final ValueChanged<Spot> onSave;
  final ValueChanged<Spot> onOpen;
  final Future<void> Function({
    required String name,
    required String slug,
    required String summary,
    required int districtId,
    required int categoryId,
    double? latitude,
    double? longitude,
    Uint8List? imageBytes,
    String? imageName,
  })
  onSubmitSpot;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String _category = 'Semua';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories = [
      'Semua',
      ...widget.categories.map((row) => jsonString(row['nama'])),
    ];
    final filtered = widget.spots.where((spot) {
      final matchesCategory =
          _category == 'Semua' || spot.category == _category;
      final matchesQuery = '${spot.name} ${spot.area}'.toLowerCase().contains(
        _query.toLowerCase(),
      );
      return matchesCategory && matchesQuery;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 700 ? 28.0 : 20.0;
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 760
            ? 3
            : 2;
        return LenisScroll(
          child: CustomScrollView(
            primary: true,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 22, horizontal, 15),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Temukan pesona',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  'Luak Limopuluah',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _suggestSpot,
                            icon: const Icon(
                              Icons.add_location_alt_outlined,
                              size: 18,
                            ),
                            label: const Text('Usulkan Spot'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Cari tempat, kecamatan, atau kuliner',
                          prefixIcon: Icon(Icons.search, color: scheme.primary),
                          filled: true,
                          fillColor: scheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 43,
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final selected = _category == category;
                      return ChoiceChip(
                        label: Text(category),
                        selected: selected,
                        onSelected: (_) => setState(() => _category = category),
                        showCheckmark: false,
                        backgroundColor: scheme.surfaceContainerLow,
                        selectedColor: scheme.primary,
                        side: BorderSide(
                          color: selected
                              ? scheme.primary
                              : scheme.outlineVariant,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected ? scheme.onPrimary : scheme.onSurface,
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (widget.spots.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 15),
                  sliver: SliverToBoxAdapter(
                    child: _CuratedBanner(
                      image: widget.spots.first.image,
                      onTap: () => widget.onOpen(widget.spots.first),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Spot pilihan',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        '${filtered.length} tempat',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Belum ada tempat yang cocok.')),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal - 4,
                    0,
                    horizontal - 4,
                    20,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columns >= 3 ? 0.82 : 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _Reveal(
                        delay: Duration(milliseconds: index.clamp(0, 5) * 45),
                        child: _SpotCard(
                          spot: filtered[index],
                          isSaved: widget.saved.contains(filtered[index].id),
                          onSave: () => widget.onSave(filtered[index]),
                          onTap: () => widget.onOpen(filtered[index]),
                        ),
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _suggestSpot() async {
    if (widget.categories.isEmpty || widget.districts.isEmpty) {
      _showMessage(context, 'Data kategori atau kecamatan belum tersedia.');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final summary = TextEditingController();
    final latitude = TextEditingController();
    final longitude = TextEditingController();
    final googleMapsLink = TextEditingController();
    Uint8List? imageBytes;
    String? imageName;
    var showManualCoordinates = false;
    var categoryId = (widget.categories.first['id'] as num).toInt();
    var districtId = (widget.districts.first['id'] as num).toInt();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Usulkan spot wisata'),
              SizedBox(height: 5),
              Text(
                'Bantu tambahkan tempat menarik di sekitar kamu.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Nama spot'),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Nama wajib diisi'
                          : null,
                    ),
                    TextFormField(
                      controller: summary,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Ringkasan editorial',
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Ringkasan wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: () async {
                          final result = await FilePicker.pickFiles(
                            type: FileType.image,
                          );
                          final file = result.isEmpty ? null : result.first;
                          if (file != null) {
                            final bytes = await file.readAsBytes();
                            setDialogState(() {
                              imageBytes = bytes;
                              imageName = file.name;
                            });
                          }
                        },
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(imageName ?? 'Pilih gambar spot'),
                      ),
                    ),
                    if (imageBytes != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          imageBytes!,
                          width: double.infinity,
                          height: 118,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: categoryId,
                      decoration: const InputDecoration(
                        labelText: 'Kategori spot',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: widget.categories
                          .map(
                            (row) => DropdownMenuItem(
                              value: (row['id'] as num).toInt(),
                              child: Text(jsonString(row['nama'])),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => categoryId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: districtId,
                      decoration: const InputDecoration(
                        labelText: 'Kecamatan',
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                      items: widget.districts
                          .map(
                            (row) => DropdownMenuItem(
                              value: (row['id'] as num).toInt(),
                              child: Text(jsonString(row['nama'])),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => districtId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        onPressed: () async {
                          final query = name.text.trim().isEmpty
                              ? 'tempat wisata Payakumbuh Lima Puluh Kota'
                              : name.text.trim();
                          final uri = Uri.https(
                            'www.google.com',
                            '/maps/search/',
                            {'api': '1', 'query': '$query, Sumatera Barat'},
                          );
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Cari tempat di Google Maps'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: googleMapsLink,
                      decoration: const InputDecoration(
                        labelText: 'Tautan Google Maps',
                        hintText: 'Tempel tautan lokasi dari Google Maps',
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                      onChanged: (value) {
                        final coordinates = _coordinatesFromMapsLink(value);
                        if (coordinates != null) {
                          latitude.text = coordinates.latitude.toString();
                          longitude.text = coordinates.longitude.toString();
                          setDialogState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_coordinatesFromMapsLink(googleMapsLink.text) != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _forest.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: _forest,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Lokasi berhasil diambil dari tautan Google Maps.',
                                style: TextStyle(color: _forest, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 4),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      initiallyExpanded: showManualCoordinates,
                      onExpansionChanged: (expanded) => setDialogState(
                        () => showManualCoordinates = expanded,
                      ),
                      title: const Text(
                        'Lokasi belum tersedia di Google Maps?',
                      ),
                      subtitle: const Text('Masukkan koordinat secara manual'),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: latitude,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Latitude',
                                ),
                                validator: (value) =>
                                    _coordinateValidator(value, -90, 90),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: longitude,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Longitude',
                                ),
                                validator: (value) =>
                                    _coordinateValidator(value, -180, 180),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  if (latitude.text.trim().isEmpty !=
                      longitude.text.trim().isEmpty) {
                    _showMessage(
                      context,
                      'Isi latitude dan longitude bersama-sama.',
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Kirim untuk verifikasi'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      if (googleMapsLink.text.trim().isNotEmpty &&
          _coordinatesFromMapsLink(googleMapsLink.text) == null) {
        final coordinates = await _resolveMapsLink(googleMapsLink.text);
        if (coordinates != null) {
          latitude.text = coordinates.latitude.toString();
          longitude.text = coordinates.longitude.toString();
        } else if (mounted) {
          _showMessage(
            context,
            'Link Google Maps belum bisa dibaca. Gunakan link lengkap atau isi koordinat manual.',
          );
          name.dispose();
          summary.dispose();
          latitude.dispose();
          longitude.dispose();
          googleMapsLink.dispose();
          return;
        }
      }
      final spotName = name.text.trim();
      final slugBase = spotName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final slug = slugBase.isEmpty
          ? 'spot-${DateTime.now().millisecondsSinceEpoch}'
          : slugBase;
      try {
        await widget.onSubmitSpot(
          name: spotName,
          slug: slug,
          summary: summary.text.trim(),
          districtId: districtId,
          categoryId: categoryId,
          latitude: double.tryParse(latitude.text.trim()),
          longitude: double.tryParse(longitude.text.trim()),
          imageBytes: imageBytes,
          imageName: imageName,
        );
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Usulan gagal dikirim: $error');
      }
    }

    name.dispose();
    summary.dispose();
    latitude.dispose();
    longitude.dispose();
    googleMapsLink.dispose();
  }

  String? _coordinateValidator(String? value, double minimum, double maximum) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final coordinate = double.tryParse(text);
    if (coordinate == null || coordinate < minimum || coordinate > maximum) {
      return 'Koordinat tidak valid';
    }
    return null;
  }
}

class _CuratedBanner extends StatelessWidget {
  const _CuratedBanner({required this.image, required this.onTap});

  final String image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 155,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: _forest,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _NetworkPhoto(image: image),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _tag('KURASI BULAN INI', const Color(0xFFF7E4C8), _forest),
                  const SizedBox(height: 8),
                  const Text(
                    'Sudut paling estetik\nLembah Harau',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
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
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.spot,
    required this.isSaved,
    required this.onSave,
    required this.onTap,
  });

  final Spot spot;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MotionCard(
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _NetworkPhoto(image: spot.image),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: onSave,
                          icon: Icon(
                            isSaved ? Icons.bookmark : Icons.bookmark_border,
                            size: 19,
                            color: _forest,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _tag(
                        spot.category == 'Kuliner Legendaris'
                            ? 'KULINER'
                            : 'ALAM',
                        Colors.white.withValues(alpha: 0.94),
                        _forest,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            spot.area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(Icons.verified, size: 13, color: _leaf),
                        const SizedBox(width: 3),
                        Text(
                          'Terverifikasi',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
}

class NearbyPage extends StatelessWidget {
  const NearbyPage({required this.spots, required this.onOpen, super.key});

  final List<Spot> spots;
  final ValueChanged<Spot> onOpen;

  @override
  Widget build(BuildContext context) {
    return LenisScroll(
      child: CustomScrollView(
        primary: true,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 15),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Jelajahi sekitar',
                    style: TextStyle(color: _muted),
                  ),
                  Text(
                    'Peta Spot',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Container(
                height: 325,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4EBDD),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _InteractiveSpotMap(spots: spots, onOpen: onOpen),
                    if (spots.isNotEmpty)
                      Positioned(
                        left: 13,
                        top: 13,
                        child: FilledButton.icon(
                          onPressed: () =>
                              _openGoogleMaps(context, spots.first),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('Buka Google Maps'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _forest,
                          ),
                        ),
                      ),
                    if (spots.isEmpty)
                      const Center(
                        child: Text(
                          'Belum ada spot terverifikasi',
                          style: TextStyle(
                            color: _forest,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Positioned(
                      right: 13,
                      bottom: 13,
                      child: FloatingActionButton.small(
                        heroTag: 'current-location',
                        backgroundColor: Colors.white,
                        foregroundColor: _forest,
                        onPressed: () =>
                            _showMessage(context, 'Lokasi Payakumbuh dipilih'),
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                    Positioned(
                      left: 13,
                      right: 70,
                      bottom: 13,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.location_on, color: _forest, size: 18),
                            SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Payakumbuh & Lima Puluh Kota',
                                style: TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Icon(Icons.tune, color: _muted, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 23, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Spot populer dekat sini',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    'Lihat peta',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _NearbyTile(
                spot: spots[index],
                onTap: () => onOpen(spots[index]),
              ),
              childCount: spots.length < 4 ? spots.length : 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveSpotMap extends StatefulWidget {
  const _InteractiveSpotMap({required this.spots, required this.onOpen});

  final List<Spot> spots;
  final ValueChanged<Spot> onOpen;

  @override
  State<_InteractiveSpotMap> createState() => _InteractiveSpotMapState();
}

class _InteractiveSpotMapState extends State<_InteractiveSpotMap> {
  final _mapController = MapController();

  static const _defaultCenter = LatLng(-0.2299, 100.6320);

  @override
  Widget build(BuildContext context) {
    final mappedSpots = widget.spots
        .where((spot) => spot.latitude != null && spot.longitude != null)
        .toList();
    final center = mappedSpots.isNotEmpty
        ? LatLng(
            mappedSpots.map((spot) => spot.latitude!).reduce((a, b) => a + b) /
                mappedSpots.length,
            mappedSpots.map((spot) => spot.longitude!).reduce((a, b) => a + b) /
                mappedSpots.length,
          )
        : _defaultCenter;

    final zoom = mappedSpots.length > 2 ? 10.8 : 12.2;
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              maxZoom: 19,
              userAgentPackageName: 'com.luakexplorer.wisata_paliko',
            ),
            MarkerLayer(
              markers: mappedSpots
                  .map(
                    (spot) => Marker(
                      point: LatLng(spot.latitude!, spot.longitude!),
                      width: 170,
                      height: 76,
                      child: GestureDetector(
                        onTap: () => widget.onOpen(spot),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: const Color(0xFFE5ECE3),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x26000000),
                                    blurRadius: 9,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.place_rounded,
                                    color: _forest,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 5),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 120,
                                    ),
                                    child: Text(
                                      spot.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.location_on_rounded,
                              color: _forest,
                              size: 30,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 13,
          right: 13,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            elevation: 5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Perbesar peta',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                  icon: const Icon(Icons.add_rounded, color: _forest),
                ),
                const Divider(height: 1, indent: 10, endIndent: 10),
                IconButton(
                  tooltip: 'Perkecil peta',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                  icon: const Icon(Icons.remove_rounded, color: _forest),
                ),
                const Divider(height: 1, indent: 10, endIndent: 10),
                IconButton(
                  tooltip: 'Tampilkan semua spot',
                  onPressed: () => _mapController.move(center, zoom),
                  icon: const Icon(
                    Icons.center_focus_strong_rounded,
                    color: _forest,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (mappedSpots.isEmpty)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Text('Belum ada koordinat spot untuk ditampilkan.'),
              ),
            ),
          ),
      ],
    );
  }
}

class _NearbyTile extends StatelessWidget {
  const _NearbyTile({required this.spot, required this.onTap});

  final Spot spot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      iconColor: scheme.onSurfaceVariant,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 58,
          height: 58,
          child: _NetworkPhoto(image: spot.image),
        ),
      ),
      title: Text(
        spot.name,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      subtitle: Text(
        spot.area,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
    );
  }
}

class SavedPage extends StatefulWidget {
  const SavedPage({
    required this.savedSpots,
    required this.collections,
    required this.publicCollections,
    required this.role,
    required this.onThemeModeChanged,
    required this.repository,
    required this.profileName,
    required this.username,
    required this.onOpen,
    required this.onOpenCollection,
    required this.onSignOut,
    required this.onRefresh,
    required this.onCreateCollection,
    super.key,
  });

  final List<Spot> savedSpots;
  final List<TravelCollection> collections;
  final List<TravelCollection> publicCollections;
  final AppRole role;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ExplorerRepository repository;
  final String profileName;
  final String username;
  final ValueChanged<Spot> onOpen;
  final ValueChanged<TravelCollection> onOpenCollection;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onRefresh;
  final Future<void> Function({
    required String title,
    required String description,
    required bool isPublic,
  })
  onCreateCollection;

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    return LenisScroll(
      child: CustomScrollView(
        primary: true,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Profil',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Muat ulang profil',
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Keluar',
                    onPressed: widget.onSignOut,
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFFB1443C),
                      backgroundColor: const Color(0xFFFCEBE9),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF164B2A), Color(0xFF2E7D4A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x241B5E20),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 29,
                              backgroundColor: Colors.white,
                              child: Text(
                                widget.profileName.trim().isEmpty
                                    ? 'P'
                                    : widget.profileName
                                          .trim()
                                          .substring(0, 1)
                                          .toUpperCase(),
                                style: const TextStyle(
                                  color: _forest,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.profileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '@${widget.username}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFD8E9D8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            switch (widget.role) {
                              AppRole.admin => 'Administrator',
                              AppRole.kurator => 'Kurator',
                              AppRole.penjelajah => 'Penjelajah',
                            },
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    _Stat(
                      value: '${widget.savedSpots.length}',
                      label: 'Spot disimpan',
                    ),
                    Container(
                      width: 1,
                      height: 34,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    _Stat(
                      value: '${widget.collections.length}',
                      label: 'Koleksi saya',
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            sliver: SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: SwitchListTile.adaptive(
                  value: Theme.of(context).brightness == Brightness.dark,
                  onChanged: (dark) => widget.onThemeModeChanged(
                    dark ? ThemeMode.dark : ThemeMode.light,
                  ),
                  secondary: Icon(
                    Theme.of(context).brightness == Brightness.dark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Mode gelap'),
                  subtitle: const Text('Sesuaikan tampilan aplikasi'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Simpan & koleksi',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _createCollection,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Buat koleksi'),
                  ),
                ],
              ),
            ),
          ),
          if (widget.role == AppRole.penjelajah)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              sliver: SliverToBoxAdapter(
                child: CuratorApplicationCard(repository: widget.repository),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 18),
            sliver: SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _viewChip('Spot disimpan', 0),
                    const SizedBox(width: 8),
                    _viewChip('Koleksi publik', 1),
                    const SizedBox(width: 8),
                    _viewChip('Koleksi saya', 2),
                  ],
                ),
              ),
            ),
          ),
          if (_view == 0)
            if (widget.savedSpots.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('Spot tersimpan akan muncul di sini.'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _SpotCard(
                      spot: widget.savedSpots[index],
                      isSaved: true,
                      onSave: () {},
                      onTap: () => widget.onOpen(widget.savedSpots[index]),
                    ),
                    childCount: widget.savedSpots.length,
                  ),
                ),
              )
          else if (_view == 1 && widget.publicCollections.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Belum ada koleksi publik.')),
            )
          else if (_view == 1)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              sliver: SliverList.builder(
                itemCount: widget.publicCollections.length,
                itemBuilder: (context, index) => _BoardCard(
                  collection: widget.publicCollections[index],
                  onTap: () =>
                      widget.onOpenCollection(widget.publicCollections[index]),
                ),
              ),
            )
          else if (widget.collections.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('Buat koleksi perjalanan pertama Anda.'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              sliver: SliverList.builder(
                itemCount: widget.collections.length,
                itemBuilder: (context, index) => _BoardCard(
                  collection: widget.collections[index],
                  onTap: () =>
                      widget.onOpenCollection(widget.collections[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createCollection() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    var isPublic = true;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Buat koleksi'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleController,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Judul'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Judul wajib diisi'
                      : null,
                ),
                TextField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Deskripsi'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPublic,
                  title: const Text('Koleksi publik'),
                  onChanged: (value) => setDialogState(() => isPublic = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Buat'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        await widget.onCreateCollection(
          title: titleController.text.trim(),
          description: descriptionController.text.trim(),
          isPublic: isPublic,
        );
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Koleksi gagal dibuat: $error');
      }
    }
    titleController.dispose();
    descriptionController.dispose();
  }

  Widget _viewChip(String label, int index) {
    final selected = _view == index;
    final colors = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _view = index),
      showCheckmark: false,
      backgroundColor: colors.surfaceContainerLow,
      selectedColor: colors.secondaryContainer,
      side: BorderSide(
        color: selected ? colors.primary : colors.outlineVariant,
      ),
      labelStyle: TextStyle(
        color: selected ? colors.onSecondaryContainer : colors.onSurface,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class SpotDetailPage extends StatefulWidget {
  const SpotDetailPage({
    required this.spot,
    required this.isSaved,
    required this.role,
    required this.onSave,
    required this.repository,
    required this.onCollectionChanged,
    required this.onDataChanged,
    super.key,
  });

  final Spot spot;
  final bool isSaved;
  final AppRole role;
  final Future<bool> Function() onSave;
  final ExplorerRepository repository;
  final Future<void> Function() onCollectionChanged;
  final Future<void> Function() onDataChanged;

  @override
  State<SpotDetailPage> createState() => _SpotDetailPageState();
}

class _SpotDetailPageState extends State<SpotDetailPage> {
  late bool _isSaved;
  late Future<List<ExplorerTip>> _tips;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isSaved;
    _tips = widget.repository.getTips(widget.spot.id);
  }

  Future<void> _saveSpot() async {
    final success = await widget.onSave();
    if (success && mounted) setState(() => _isSaved = !_isSaved);
  }

  Future<void> _reportSpot() async {
    final reason = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Laporkan spot'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: reason,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Alasan laporan'),
            validator: (value) => (value?.trim().length ?? 0) < 5
                ? 'Alasan minimal 5 karakter'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Kirim laporan'),
          ),
        ],
      ),
    );
    if (submit == true) {
      try {
        await widget.repository.createReport(
          targetType: 'spot',
          targetId: widget.spot.id,
          reason: reason.text.trim(),
        );
        if (mounted) _showMessage(context, 'Laporan berhasil dikirim.');
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Laporan gagal dikirim: $error');
      }
    }
    reason.dispose();
  }

  Future<void> _writeTip() async {
    final contentController = TextEditingController();
    var rating = 5.0;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tulis tips warga'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: contentController,
                  maxLength: 500,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Tips pengalaman Anda',
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Tips tidak boleh kosong'
                      : null,
                ),
                Row(
                  children: [
                    const Text('Rating'),
                    const SizedBox(width: 12),
                    DropdownButton<double>(
                      value: rating,
                      items: [1, 2, 3, 4, 5]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value.toDouble(),
                              child: Text('$value bintang'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => rating = value);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      try {
        await widget.repository.addTip(
          spotId: widget.spot.id,
          content: contentController.text.trim(),
          rating: rating,
        );
        if (mounted) {
          setState(() => _tips = widget.repository.getTips(widget.spot.id));
        }
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Tips gagal dikirim: $error');
      }
    }
    contentController.dispose();
  }

  Future<void> _addToCollection() async {
    try {
      final collections = await widget.repository.getMyCollections();
      if (!mounted) return;
      if (collections.isEmpty) {
        _showMessage(
          context,
          'Buat koleksi terlebih dahulu dari halaman Profil.',
        );
        return;
      }

      String selectedId = collections.first.id;
      final noteController = TextEditingController();
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Simpan ke koleksi'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  decoration: const InputDecoration(labelText: 'Koleksi'),
                  items: collections
                      .map(
                        (collection) => DropdownMenuItem(
                          value: collection.id,
                          child: Text(collection.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedId = value);
                    }
                  },
                ),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan kurator (opsional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );
      if (result == true) {
        final curatorNote = noteController.text.trim();
        noteController.dispose();
        await widget.repository.addSpotToCollection(
          collectionId: selectedId,
          spotId: widget.spot.id,
          curatorNote: curatorNote.isEmpty ? null : curatorNote,
        );
        await widget.onCollectionChanged();
        if (mounted) _showMessage(context, 'Spot ditambahkan ke koleksi.');
      } else {
        noteController.dispose();
      }
    } on Exception catch (error) {
      if (mounted) _showMessage(context, 'Gagal menambahkan spot: $error');
    }
  }

  Future<void> _editSpot() async {
    final districts = await widget.repository.getDistricts();
    final name = TextEditingController(text: widget.spot.name);
    final summary = TextEditingController(text: widget.spot.description);
    final latitude = TextEditingController(
      text: widget.spot.latitude?.toString(),
    );
    final longitude = TextEditingController(
      text: widget.spot.longitude?.toString(),
    );
    final googleMapsLink = TextEditingController();
    var districtId =
        widget.spot.districtId ??
        (districts.isEmpty ? null : (districts.first['id'] as num).toInt());
    Uint8List? imageBytes;
    String? imageName;
    var showManualCoordinates = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit spot'),
              SizedBox(height: 5),
              Text(
                'Perbarui informasi agar spot tetap akurat.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nama spot',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: summary,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Ringkasan',
                      prefixIcon: Icon(Icons.notes_outlined),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (districts.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: districtId,
                      decoration: const InputDecoration(
                        labelText: 'Kecamatan',
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                      items: districts
                          .map(
                            (district) => DropdownMenuItem(
                              value: (district['id'] as num).toInt(),
                              child: Text(jsonString(district['nama'])),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => districtId = value),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: () async {
                        final query = name.text.trim().isEmpty
                            ? widget.spot.name
                            : name.text.trim();
                        final uri = Uri.https(
                          'www.google.com',
                          '/maps/search/',
                          {'api': '1', 'query': '$query, Sumatera Barat'},
                        );
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Cari lokasi di Google Maps'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: googleMapsLink,
                    decoration: const InputDecoration(
                      labelText: 'Tautan Google Maps',
                      hintText: 'Tempel tautan lokasi dari Google Maps',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    onChanged: (value) {
                      final coordinates = _coordinatesFromMapsLink(value);
                      if (coordinates != null) {
                        latitude.text = coordinates.latitude.toString();
                        longitude.text = coordinates.longitude.toString();
                        setDialogState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_coordinatesFromMapsLink(googleMapsLink.text) != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: _forest.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: _forest,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Lokasi berhasil diambil dari Google Maps.',
                              style: TextStyle(color: _forest, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    initiallyExpanded: showManualCoordinates,
                    onExpansionChanged: (expanded) =>
                        setDialogState(() => showManualCoordinates = expanded),
                    title: const Text('Belum ada di Google Maps?'),
                    subtitle: const Text('Isi lokasi secara manual'),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: latitude,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Latitude',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: longitude,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Longitude',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                    ),
                    onPressed: () async {
                      final picked = await FilePicker.pickFiles(
                        type: FileType.image,
                      );
                      final file = picked.isEmpty ? null : picked.first;
                      if (file != null) {
                        final bytes = await file.readAsBytes();
                        setDialogState(() {
                          imageBytes = bytes;
                          imageName = file.name;
                        });
                      }
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: Text(imageName ?? 'Ganti gambar'),
                  ),
                  if (imageBytes != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        imageBytes!,
                        width: double.infinity,
                        height: 110,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (result == true &&
        googleMapsLink.text.trim().isNotEmpty &&
        _coordinatesFromMapsLink(googleMapsLink.text) == null) {
      final coordinates = await _resolveMapsLink(googleMapsLink.text);
      if (coordinates != null) {
        latitude.text = coordinates.latitude.toString();
        longitude.text = coordinates.longitude.toString();
      } else if (mounted) {
        _showMessage(
          context,
          'Link Google Maps belum bisa dibaca. Gunakan link lengkap atau isi koordinat manual.',
        );
      }
    }
    final latitudeValue = double.tryParse(latitude.text.trim());
    final longitudeValue = double.tryParse(longitude.text.trim());
    final coordinatesValid =
        (latitude.text.trim().isEmpty && longitude.text.trim().isEmpty) ||
        (latitudeValue != null &&
            longitudeValue != null &&
            latitudeValue >= -90 &&
            latitudeValue <= 90 &&
            longitudeValue >= -180 &&
            longitudeValue <= 180);
    if (result == true &&
        name.text.trim().isNotEmpty &&
        summary.text.trim().isNotEmpty &&
        coordinatesValid) {
      try {
        await widget.repository.updateSpotBasic(
          spotId: widget.spot.id,
          name: name.text.trim(),
          summary: summary.text.trim(),
          districtId: districtId,
          latitude: latitudeValue,
          longitude: longitudeValue,
        );
        if (imageBytes != null && imageName != null) {
          await widget.repository.uploadSpotMedia(
            spotId: widget.spot.id,
            bytes: imageBytes!,
            fileName: imageName!,
            contentType: 'image/*',
            mediaTypeId: 1,
          );
        }
        if (mounted)
          _showMessage(
            context,
            'Spot diperbarui dan menunggu verifikasi ulang.',
          );
        await widget.onDataChanged();
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Edit spot gagal: $error');
      }
    } else if (result == true && mounted) {
      _showMessage(
        context,
        'Nama, ringkasan, dan koordinat harus diisi dengan benar.',
      );
    }
    name.dispose();
    summary.dispose();
    latitude.dispose();
    longitude.dispose();
    googleMapsLink.dispose();
  }

  Future<void> _createStory() async {
    final title = TextEditingController();
    Uint8List? imageBytes;
    String? imageName;
    final expiresAt = DateTime.now().add(const Duration(hours: 24));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          title: const Text('Buat cerita'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Judul cerita',
                    prefixIcon: Icon(Icons.edit_note_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                  ),
                  onPressed: () async {
                    final files = await FilePicker.pickFiles(
                      type: FileType.image,
                    );
                    final file = files.isEmpty ? null : files.first;
                    if (file != null) {
                      final bytes = await file.readAsBytes();
                      setDialogState(() {
                        imageBytes = bytes;
                        imageName = file.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(imageName ?? 'Pilih gambar cerita'),
                ),
                if (imageBytes != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      imageBytes!,
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Text('Cerita akan tampil selama 24 jam.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: imageBytes == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Posting cerita'),
            ),
          ],
        ),
      ),
    );
    if (result == true &&
        title.text.trim().isNotEmpty &&
        imageBytes != null &&
        imageName != null) {
      try {
        final url = await widget.repository.uploadStoryMedia(
          spotId: widget.spot.id,
          bytes: imageBytes!,
          fileName: imageName!,
          contentType: 'image/jpeg',
        );
        await widget.repository.createStory(
          spotId: widget.spot.id,
          title: title.text.trim(),
          mediaUrl: url,
          expiresAt: expiresAt,
        );
        await widget.onDataChanged();
        if (mounted) _showMessage(context, 'Cerita berhasil diposting.');
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Cerita gagal diposting: $error');
      }
    } else if (result == true && mounted) {
      _showMessage(context, 'Judul dan gambar cerita wajib diisi.');
    }
    title.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: LenisScroll(
        child: CustomScrollView(
          primary: true,
          slivers: [
            SliverAppBar(
              expandedHeight: 320,
              pinned: true,
              foregroundColor: Colors.white,
              backgroundColor: _forest,
              actions: [
                if (widget.spot.creatorId ==
                        Supabase.instance.client.auth.currentUser?.id ||
                    widget.role == AppRole.admin ||
                    widget.role == AppRole.kurator)
                  IconButton(
                    tooltip: 'Edit spot',
                    onPressed: _editSpot,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                IconButton(
                  tooltip: 'Laporkan spot',
                  onPressed: _reportSpot,
                  icon: const Icon(Icons.flag_outlined),
                ),
                IconButton(
                  tooltip: 'Bagikan',
                  onPressed: () => _shareSpot(
                    context,
                    widget.spot,
                    repository: widget.repository,
                  ),
                  icon: const Icon(Icons.share_outlined),
                ),
                IconButton(
                  tooltip: _isSaved ? 'Hapus dari koleksi' : 'Simpan',
                  onPressed: _saveSpot,
                  icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_border),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                title: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                    ),
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    _NetworkPhoto(image: spot.image),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0x33000000),
                            Color(0xCC000000),
                          ],
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.48, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 72,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _tag(spot.category, const Color(0xFFF7E4C8), _forest),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  spot.area,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 112),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _InfoGrid(spot: spot),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _openGoogleMaps(context, spot),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Buka lokasi di Google Maps'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (widget.role != AppRole.penjelajah) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _addToCollection,
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: const Text('Koleksi'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _createStory,
                          icon: const Icon(
                            Icons.auto_stories_outlined,
                            size: 18,
                          ),
                          label: const Text('Buat cerita'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SectionHeading(
                    icon: Icons.auto_stories,
                    title: 'Tentang ${spot.name}',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      spot.description.isEmpty
                          ? 'Belum ada ringkasan untuk spot ini.'
                          : spot.description,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.65,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _SectionHeading(
                    icon: Icons.tips_and_updates_outlined,
                    title: 'Etika & Tips Berkunjung',
                  ),
                  const SizedBox(height: 10),
                  const _TipRow(
                    icon: Icons.hiking,
                    title: 'Gunakan alas kaki anti-selip',
                    detail: 'Bebatuan di dekat air terjun dapat licin.',
                  ),
                  const _TipRow(
                    icon: Icons.volunteer_activism,
                    title: 'Hormati norma adat setempat',
                    detail: 'Berbusana sopan dan ramah kepada warga lokal.',
                  ),
                  const _TipRow(
                    icon: Icons.delete_sweep_outlined,
                    title: 'Bawa pulang sampah',
                    detail: 'Jaga kebersihan kawasan geopark.',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionHeading(
                          icon: Icons.chat_bubble_outline,
                          title: 'Catatan Penjelajah',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _writeTip,
                        icon: const Icon(Icons.edit_note, size: 18),
                        label: const Text('Tulis Tips'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<List<ExplorerTip>>(
                    future: _tips,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(
                          'Tips gagal dimuat: ${snapshot.error}',
                          style: const TextStyle(color: Color(0xFFB42318)),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final tips = snapshot.data ?? [];
                      if (tips.isEmpty) {
                        return const Text(
                          'Belum ada tips warga. Bagikan pengalaman pertama Anda.',
                          style: TextStyle(color: _muted, fontSize: 12),
                        );
                      }
                      return Column(
                        children: tips
                            .map(
                              (tip) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ReviewCard(
                                  tip: tip,
                                  onHelpful: () async {
                                    try {
                                      await widget.repository.toggleTipVote(
                                        tip.id,
                                      );
                                      if (mounted) {
                                        setState(() {
                                          _tips = widget.repository.getTips(
                                            widget.spot.id,
                                          );
                                        });
                                      }
                                    } on Exception catch (error) {
                                      if (context.mounted) {
                                        _showMessage(
                                          context,
                                          'Vote gagal disimpan: $error',
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Icon(
                _isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveSpot,
                  icon: Icon(
                    _isSaved ? Icons.bookmark_remove : Icons.bookmark_add,
                  ),
                  label: Text(_isSaved ? 'Tersimpan' : 'Simpan Spot'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _forest,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      _InfoItem(
        icon: Icons.category_outlined,
        title: 'KATEGORI',
        value: spot.category,
      ),
      _InfoItem(
        icon: Icons.location_on_outlined,
        title: 'WILAYAH',
        value: spot.area,
      ),
      _InfoItem(
        icon: Icons.near_me,
        title: 'LATITUDE',
        value: spot.latitude?.toStringAsFixed(5) ?? 'Belum tersedia',
      ),
      _InfoItem(
        icon: Icons.explore_outlined,
        title: 'LONGITUDE',
        value: spot.longitude?.toStringAsFixed(5) ?? 'Belum tersedia',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 6,
        childAspectRatio: 1.9,
        children: items,
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 19, color: scheme.primary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MotionCard(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    detail,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
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
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.tip, required this.onHelpful});

  final ExplorerTip tip;
  final Future<void> Function() onHelpful;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MotionCard(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(Icons.person, color: scheme.primary, size: 19),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tip.authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        tip.createdAt.toLocal().toString().split(' ').first,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.star, color: _clay, size: 15),
                Text(
                  ' ${tip.rating.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tip.content,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: () async => onHelpful(),
                  icon: const Icon(
                    Icons.thumb_up_outlined,
                    color: _muted,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Membantu (${tip.voteCount})',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 15),
                Icon(Icons.reply, color: scheme.onSurfaceVariant, size: 15),
                const SizedBox(width: 5),
                Text(
                  'Tanggapi',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.collection, required this.onTap});

  final TravelCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MotionCard(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.all(9),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 58,
              height: 58,
              child: _NetworkPhoto(image: collection.coverImage),
            ),
          ),
          title: Text(
            collection.title,
            style: TextStyle(
              color: colors.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '${collection.description.isEmpty ? 'Koleksi perjalanan' : collection.description}\n'
              '${collection.spotCount} spot · '
              '${collection.duration.isEmpty ? '' : '${collection.duration} · '}${collection.isPublic ? 'Publik' : 'Pribadi'}',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 10,
                height: 1.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          isThreeLine: true,
        ),
      ),
    );
  }
}

class CollectionDetailPage extends StatelessWidget {
  const CollectionDetailPage({
    required this.collection,
    required this.entries,
    required this.onOpenSpot,
    super.key,
  });

  final TravelCollection collection;
  final Future<List<CollectionEntry>> entries;
  final ValueChanged<Spot> onOpenSpot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(collection.title)),
      body: FutureBuilder<List<CollectionEntry>>(
        future: entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Isi koleksi gagal dimuat: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Text(
                'Belum ada spot di dalam koleksi ini.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: ListTile(
                  onTap: () => onOpenSpot(item.spot),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: _NetworkPhoto(image: item.spot.image),
                    ),
                  ),
                  title: Text(
                    item.spot.name,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    item.curatorNote.isEmpty
                        ? item.spot.area
                        : '${item.spot.area}\n${item.curatorNote}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  trailing: Text(
                    '${item.position}',
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _offset, child: widget.child),
  );
}

class _AddStoryBubble extends StatelessWidget {
  const _AddStoryBubble({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 68,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.add_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Tambah',
            maxLines: 1,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.title,
    required this.image,
    required this.isNew,
    required this.onTap,
  });

  final String title;
  final String image;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isNew ? _clay : const Color(0xFFD9E5D8),
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 27,
                backgroundColor: const Color(0xFFE8F1E8),
                backgroundImage: image.isEmpty ? null : NetworkImage(image),
                child: image.isEmpty ? const _LogoImage(size: 54) : null,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const _LogoImage(size: 42),
    );
  }
}

class _LogoImage extends StatelessWidget {
  const _LogoImage({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.28),
    child: SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/luak_explorer_icon.jpg',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}

class _NetworkPhoto extends StatelessWidget {
  const _NetworkPhoto({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    if (image.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFDCE8D8),
        child: const Center(child: _LogoImage(size: 42)),
      );
    }
    return Image.network(
      image,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: const Color(0xFFDCE8D8),
        alignment: Alignment.center,
        child: const _LogoImage(size: 42),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: const Color(0xFFE8F1E8),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _forest),
          ),
        );
      },
    );
  }
}

Widget _tag(String label, Color background, Color foreground) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    ),
  );
}

String _timeAgo(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime);
  if (difference.isNegative || difference.inMinutes < 1) return 'baru saja';
  if (difference.inMinutes < 60) return '${difference.inMinutes} menit lalu';
  if (difference.inHours < 24) return '${difference.inHours} jam lalu';
  if (difference.inDays < 30) return '${difference.inDays} hari lalu';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}

String _cityDisplayName(String name) {
  return name.replaceFirst(RegExp(r'^(Kota|Kabupaten)\s+'), '');
}

Future<void> _showTipsSheet(
  BuildContext context,
  ExplorerRepository repository,
  Spot spot, {
  Future<void> Function()? onSubmitted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TipsSheet(
      repository: repository,
      spot: spot,
      onSubmitted: onSubmitted,
    ),
  );
}

class _TipsSheet extends StatefulWidget {
  const _TipsSheet({
    required this.repository,
    required this.spot,
    this.onSubmitted,
  });

  final ExplorerRepository repository;
  final Spot spot;
  final Future<void> Function()? onSubmitted;

  @override
  State<_TipsSheet> createState() => _TipsSheetState();
}

class _TipsSheetState extends State<_TipsSheet> {
  late Future<List<ExplorerTip>> _tips;
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tips = widget.repository.getTips(widget.spot.id);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.repository.addTip(
        spotId: widget.spot.id,
        content: content,
        rating: 5,
      );
      _controller.clear();
      setState(() {
        _sending = false;
        _tips = widget.repository.getTips(widget.spot.id);
      });
      await widget.onSubmitted?.call();
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        _showMessage(context, 'Komentar gagal dikirim: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.42,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD3DCCF),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, color: _forest),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Komentar & tips',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    widget.spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<ExplorerTip>>(
                  future: _tips,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final tips = snapshot.data ?? [];
                    if (tips.isEmpty) {
                      return const Center(
                        child: Text(
                          'Belum ada komentar.\nJadilah yang pertama berbagi tips.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: tips.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, index) => _ReviewCard(
                        tip: tips[index],
                        onHelpful: () async {
                          await widget.repository.toggleTipVote(tips[index].id);
                          if (mounted) {
                            setState(() {
                              _tips = widget.repository.getTips(widget.spot.id);
                            });
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'Tulis komentar atau tips...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: _forest),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
