import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';

/// PR #64 verification — `LiquidGlassContainer` glass renders short when its
/// frame reaches into the bottom safe area.
///
/// PR: https://github.com/gunumdogdu/cupertino_native_better/pull/64
/// Reported by @fbernack.
///
/// ### The claim
///
/// `LiquidGlassContainerPlatformView` hosts the SwiftUI glass in a
/// `UIHostingController`. `UIHostingController` propagates the screen's safe
/// area into its SwiftUI content, so when the platform view's frame overlaps
/// the home-indicator inset, the hosted `GeometryReader`/shape gets inset by
/// the overlap and the glass fills only the reduced size. Reported as up to
/// **22 pt** short on an iPhone 17 Pro (iOS 26.4).
///
/// Proposed fix: `self.hostingController.safeAreaRegions = []`.
///
/// ### How this screen proves it
///
/// The native glass is drawn as a platform view. On top of the *same rect*
/// this screen draws a **magenta outline in Flutter** — Flutter always lays
/// that out correctly, so it marks where the frame truly is. It also draws a
/// **cyan dashed line at the safe-area boundary** (`viewPadding.bottom`).
///
///  * **Bug present:** the glass stops short of the magenta outline's bottom
///    edge — and it stops *at the cyan line*, which is the tell that the safe
///    area is what's insetting it.
///  * **Bug fixed:** the glass fills the magenta outline completely and
///    crosses the cyan line.
///
/// Drag the **bottom offset** slider to watch the glass detach from the frame
/// as the panel crosses into the inset. Above the cyan line both builds look
/// identical; below it, only the fixed build keeps the glass attached.
class Pr64LiquidGlassSafeAreaTestPage extends StatefulWidget {
  const Pr64LiquidGlassSafeAreaTestPage({super.key});

  @override
  State<Pr64LiquidGlassSafeAreaTestPage> createState() =>
      _Pr64LiquidGlassSafeAreaTestPageState();
}

class _Pr64LiquidGlassSafeAreaTestPageState
    extends State<Pr64LiquidGlassSafeAreaTestPage> {
  /// Distance from the bottom of the screen to the bottom of the glass panel.
  /// The reporter's repro uses 12pt, which is inside the ~34pt home-indicator
  /// inset on modern iPhones.
  double _bottomOffset = 12;

  double _panelHeight = 140;
  CNGlassEffectShape _shape = CNGlassEffectShape.rect;

  static const _magenta = Color(0xFFFF2D95);
  static const _cyan = Color(0xFF00E5FF);

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.of(context).viewPadding;
    final safeBottom = viewPadding.bottom;
    final intrudes = _bottomOffset < safeBottom;
    final overlap = (safeBottom - _bottomOffset).clamp(0.0, double.infinity);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('PR #64: glass safe-area'),
      ),
      child: Stack(
        children: [
          // High-contrast striped backdrop so the glass edge is easy to see.
          Positioned.fill(child: CustomPaint(painter: _StripesPainter())),

          // Controls + readout.
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _readout(
                            'Device safe-area inset (bottom)',
                            '${safeBottom.toStringAsFixed(1)} pt',
                          ),
                          _readout(
                            'Panel bottom offset',
                            '${_bottomOffset.toStringAsFixed(1)} pt',
                          ),
                          _readout(
                            'Intrudes into safe area?',
                            intrudes
                                ? 'YES — by ${overlap.toStringAsFixed(1)} pt'
                                : 'no',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'What to look for',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'The RED strip at the bottom is exactly the '
                            'safe-area inset — the zone the bug would leave '
                            'uncovered. The MAGENTA outline is the panel\'s '
                            'true frame (drawn by Flutter, always correct). '
                            'The CYAN dashed line is the safe-area boundary.\n\n'
                            'BUG PRESENT → red stays raw and saturated inside '
                            'the magenta outline below the cyan line; glass '
                            'stops at the cyan line.\n'
                            'BUG FIXED → the whitened glass covers the red all '
                            'the way down to the magenta bottom edge.\n\n'
                            'Slide "bottom offset" 60 → 0 and watch whether '
                            'the glass keeps covering the red as the frame '
                            'descends past the cyan line.',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bottom offset: '
                            '${_bottomOffset.toStringAsFixed(0)} pt',
                          ),
                          CupertinoSlider(
                            value: _bottomOffset,
                            min: 0,
                            max: 60,
                            onChanged: (v) => setState(() => _bottomOffset = v),
                          ),
                          Text(
                            'Panel height: '
                            '${_panelHeight.toStringAsFixed(0)} pt',
                          ),
                          CupertinoSlider(
                            value: _panelHeight,
                            min: 80,
                            max: 260,
                            onChanged: (v) => setState(() => _panelHeight = v),
                          ),
                          const SizedBox(height: 8),
                          CupertinoSegmentedControl<CNGlassEffectShape>(
                            groupValue: _shape,
                            children: const {
                              CNGlassEffectShape.rect: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text('rect'),
                              ),
                              CNGlassEffectShape.capsule: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text('capsule'),
                              ),
                              CNGlassEffectShape.circle: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text('circle'),
                              ),
                            },
                            onValueChanged: (v) => setState(() => _shape = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── THE TEST ZONE ────────────────────────────────────────────────
          // Solid red fills exactly the safe-area strip. This is the region
          // the bug would leave uncovered. Painted UNDER the panel, so:
          //   glass short  → red shows through raw and saturated
          //   glass correct→ red is visibly washed/refracted by the glass
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: safeBottom,
            child: IgnorePointer(
              child: CustomPaint(painter: _RulerPainter(safeBottom)),
            ),
          ),

          // ── The panel under test ─────────────────────────────────────────
          Positioned(
            left: 12,
            right: 12,
            bottom: _bottomOffset,
            height: _panelHeight,
            child: Stack(
              children: [
                // The native glass.
                Positioned.fill(
                  child: LiquidGlassContainer(
                    config: LiquidGlassConfig(
                      effect: CNGlassEffect.regular,
                      shape: _shape,
                      cornerRadius: 40,
                      // Strong tint: the glass's own bounds must be
                      // unmistakable, not a subtle refraction.
                      tint: CupertinoColors.white.withValues(alpha: 0.55),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                // Flutter-drawn frame marker at the SAME rect. Flutter lays
                // this out correctly regardless of the native bug, so any
                // gap between the glass and this outline is the bug.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: _magenta, width: 2),
                        borderRadius: BorderRadius.circular(
                          _shape == CNGlassEffectShape.rect ? 40 : 999,
                        ),
                      ),
                    ),
                  ),
                ),
                // Label pinned to the frame's true bottom edge.
                Positioned(
                  left: 8,
                  bottom: 2,
                  child: IgnorePointer(child: _tag('frame bottom', _magenta)),
                ),
              ],
            ),
          ),

          // ── Safe-area boundary marker — drawn LAST so it stays visible
          // ON TOP of the glass panel. This is the reference that matters:
          // if the glass bottom edge lands exactly on this line while the
          // magenta frame continues below it, the safe area is the culprit.
          Positioned(
            left: 0,
            right: 0,
            bottom: safeBottom,
            child: IgnorePointer(
              child: SizedBox(
                height: 2,
                child: CustomPaint(painter: _DashedLinePainter(_cyan)),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: safeBottom + 3,
            child: IgnorePointer(
              child: _tag(
                'safe area  ${safeBottom.toStringAsFixed(0)}pt',
                _cyan,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground
            .resolveFrom(context)
            .withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _readout(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: CupertinoColors.black,
        ),
      ),
    );
  }
}

/// Diagonal stripes so the glass's refraction (and therefore its exact
/// bottom edge) is easy to see against the backdrop.
class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF10243A),
    );
    final paint = Paint()
      ..color = const Color(0xFFFF7A00).withValues(alpha: 0.85)
      ..strokeWidth = 14;
    for (double x = -size.height; x < size.width + size.height; x += 34) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fills the safe-area strip with saturated red plus 10pt ruler bands.
/// This is the zone the bug would leave uncovered, so it doubles as both
/// a high-contrast backdrop and a measuring stick.
class _RulerPainter extends CustomPainter {
  _RulerPainter(this.inset);
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE01B2E),
    );
    // 10pt alternating bands, measured up from the bottom.
    final band = Paint()..color = const Color(0xFF7A0714);
    for (double y = size.height - 10; y > -10; y -= 20) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 10), band);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.inset != inset;
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 8.0;
    const gap = 5.0;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
