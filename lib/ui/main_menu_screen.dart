import 'package:flutter/material.dart';
import 'package:vale_engine/theme/brand_theme.dart';
import 'package:vale_engine/ui/fade_page_route.dart';
import 'package:vale_engine/ui/menu_background_painter.dart';

import '../app_info.dart';
import '../theme/game_palette.dart';
import 'setup_screen.dart';

/// The screen the app opens on.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Stands in for the screens the later phases add. Warm rather than
  /// technical, because it is the only copy in the build so far.
  void _notReadyYet() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('The valley is still being surveyed.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  void _openSkirmish() {
    Navigator.of(context).push(
      FadePageRoute<void>(child: const SetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) => CustomPaint(
                painter: MenuBackgroundPainter(time: _animController.value),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _Title(),
                      const SizedBox(height: 48),
                      _MenuButton(
                        label: 'Skirmish',
                        colour: GamePalette.crimson,
                        onPressed: _openSkirmish,
                      ),
                      const SizedBox(height: 12),
                      _MenuButton(
                        label: 'Daily board',
                        colour: GamePalette.cobalt,
                        onPressed: _notReadyYet,
                      ),
                      const SizedBox(height: 12),
                      _MenuButton(
                        label: 'Settings',
                        colour: Brand.inkSoft,
                        onPressed: _notReadyYet,
                      ),
                      const SizedBox(height: 40),
                      const Text(
                        'v$appVersion',
                        style: TextStyle(
                          fontFamily: 'NunitoSans',
                          fontSize: 12,
                          color: Brand.mist,
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

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'DomiVale',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 52,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: GamePalette.crownLt,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'settle · grow · rule',
          style: TextStyle(
            fontFamily: 'NunitoSans',
            fontSize: 13,
            letterSpacing: 1.2,
            color: GamePalette.crown.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

/// One menu entry.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.colour,
    required this.onPressed,
  });

  final String label;
  final Color colour;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: colour,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Brand.paper,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
