import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';

/// Overlays drawn over glass — [CNGlassOcclusion] / [CNOccludesGlass].
///
/// A CN widget is a native view composited above Flutter's content, so an
/// `OverlayEntry` that crosses one doesn't cover it, it tears through it.
/// Modal routes are handled by the package; an overlay pushes no route, so
/// the app has to declare it.
///
/// Procedure:
///  1. Tap "Drop a banner (unwrapped)" and watch the controls behind it.
///     On iOS 26 the glass smears through the banner as it slides over.
///  2. Tap "Drop a banner (CNOccludesGlass)". Same banner, but the
///     controls hand themselves over to their Flutter fallbacks for as
///     long as it is up, and take the glass back when it leaves.
///
/// The row of controls is the same in both cases; only the banner differs.
class GlassOcclusionDemoPage extends StatefulWidget {
  const GlassOcclusionDemoPage({super.key});

  @override
  State<GlassOcclusionDemoPage> createState() => _GlassOcclusionDemoPageState();
}

class _GlassOcclusionDemoPageState extends State<GlassOcclusionDemoPage> {
  OverlayEntry? _entry;
  double _slider = 0.4;
  bool _switched = true;
  int _segment = 0;

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  /// Drops a banner from the top for two seconds.
  ///
  /// [occluding] is the whole point of the demo: the same banner, wrapped
  /// or not.
  void _drop({required bool occluding}) {
    _entry?.remove();

    final banner = _Banner(
      title: occluding ? 'Wrapped in CNOccludesGlass' : 'Plain overlay',
      subtitle: occluding
          ? 'Controls below are on their fallbacks'
          : 'Controls below are still glass',
    );

    final entry = OverlayEntry(
      builder: (_) => occluding ? CNOccludesGlass(child: banner) : banner,
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _entry != entry) return;
      entry.remove();
      _entry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Glass occlusion'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Watch the controls, not the banner. Without the wrapper the '
              'glass tears through it; with it, every control drops to the '
              'same fallback it would use on a device with no Liquid Glass.',
            ),
            const SizedBox(height: 20),

            // The controls under the banner. Nothing here opts in — the
            // package gates each one on the occlusion count itself.
            CNButton(
              onPressed: () {},
              label: 'A glass button',
              config: const CNButtonConfig(shrinkWrap: true),
            ),
            const SizedBox(height: 16),
            CNSegmentedControl(
              labels: const ['One', 'Two', 'Three'],
              selectedIndex: _segment,
              onValueChanged: (i) => setState(() => _segment = i),
            ),
            const SizedBox(height: 16),
            CNSlider(
              value: _slider,
              onChanged: (v) => setState(() => _slider = v),
            ),
            const SizedBox(height: 16),
            CNSwitch(
              value: _switched,
              onChanged: (v) => setState(() => _switched = v),
            ),

            const SizedBox(height: 32),
            CupertinoButton.filled(
              onPressed: () => _drop(occluding: false),
              child: const Text('Drop a banner (unwrapped)'),
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: () => _drop(occluding: true),
              child: const Text('Drop a banner (CNOccludesGlass)'),
            ),

            const SizedBox(height: 24),
            // Proof the count is shared: anything can watch it.
            ValueListenableBuilder<int>(
              valueListenable: CNGlassOcclusion.depth,
              builder: (context, depth, _) => Text(
                'CNGlassOcclusion.depth: $depth',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The thing that comes down over the controls.
class _Banner extends StatelessWidget {
  const _Banner({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
