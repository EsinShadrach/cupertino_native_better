import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for a CN widget: watches occlusion the way [GlassOcclusionMixin]
/// makes a real one watch it, and says which face it is wearing.
class _Watcher extends StatefulWidget {
  const _Watcher(this.name);

  final String name;

  @override
  State<_Watcher> createState() => _WatcherState();
}

class _WatcherState extends State<_Watcher> with GlassOcclusionMixin<_Watcher> {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: Text(
      '${widget.name}:${isGlassOccluded ? 'fallback' : 'glass'}',
      textDirection: TextDirection.ltr,
    ),
  );
}

/// A page with a widget pinned to the top and another pinned to the bottom,
/// so "did the right one stand down" is answerable.
Widget _page({required List<OverlayEntry> extra}) {
  return MaterialApp(
    home: Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => const Column(
            children: [_Watcher('top'), Spacer(), _Watcher('bottom')],
          ),
        ),
        ...extra,
      ],
    ),
  );
}

void main() {
  group('CNGlassOcclusion', () {
    tearDown(() {
      expect(
        CNGlassOcclusion.isOccluded,
        isFalse,
        reason: 'a leaked claim would poison the next test',
      );
    });

    test('covers() is geometric, and a rectless claim covers everything', () {
      const top = Rect.fromLTWH(0, 0, 400, 100);
      const bottom = Rect.fromLTWH(0, 700, 400, 100);

      expect(CNGlassOcclusion.covers(top), isFalse);

      final banner = CNGlassOcclusion.retain(
        rect: const Rect.fromLTWH(0, 0, 400, 80),
      );
      expect(CNGlassOcclusion.covers(top), isTrue);
      expect(CNGlassOcclusion.covers(bottom), isFalse);

      // A caller that cannot measure itself is covered, on the safe side.
      expect(CNGlassOcclusion.covers(null), isTrue);

      final scrim = CNGlassOcclusion.retain();
      expect(CNGlassOcclusion.covers(bottom), isTrue);

      CNGlassOcclusion.release(scrim);
      expect(CNGlassOcclusion.covers(bottom), isFalse);
      expect(CNGlassOcclusion.covers(top), isTrue);

      CNGlassOcclusion.release(banner);
      expect(CNGlassOcclusion.covers(top), isFalse);

      // Idempotent, and a dead token can't be resurrected.
      CNGlassOcclusion.release(banner);
      CNGlassOcclusion.update(banner, top);
      expect(CNGlassOcclusion.isOccluded, isFalse);
    });

    testWidgets('a banner at the top leaves the bottom bar alone', (
      tester,
    ) async {
      final entry = OverlayEntry(
        builder: (_) => const Align(
          alignment: Alignment.topCenter,
          child: CNOccludesGlass(child: SizedBox(height: 80, width: 300)),
        ),
      );

      await tester.pumpWidget(_page(extra: [entry]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // This is the regression the whole rewrite is for: the bar at the
      // bottom was standing down for a banner that never touched it.
      expect(find.text('top:fallback'), findsOneWidget);
      expect(find.text('bottom:glass'), findsOneWidget);

      entry.remove();
      await tester.pumpAndSettle();
      expect(find.text('top:glass'), findsOneWidget);
    });

    testWidgets('a full-screen scrim takes everything down', (tester) async {
      final entry = OverlayEntry(
        builder: (_) => const CNOccludesGlass(child: SizedBox.expand()),
      );

      await tester.pumpWidget(_page(extra: [entry]));
      await tester.pumpAndSettle();

      expect(find.text('top:fallback'), findsOneWidget);
      expect(find.text('bottom:fallback'), findsOneWidget);

      entry.remove();
      await tester.pumpAndSettle();
      expect(find.text('top:glass'), findsOneWidget);
      expect(find.text('bottom:glass'), findsOneWidget);
    });

    testWidgets('claiming from inside a build does not throw', (tester) async {
      // The retain runs in initState — mid-build, with the page underneath
      // already built this frame. Writing the notifier there is a
      // markNeedsBuild on an already-built element.
      final entry = OverlayEntry(
        builder: (_) => const CNOccludesGlass(child: SizedBox.expand()),
      );

      await tester.pumpWidget(_page(extra: [entry]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('top:fallback'), findsOneWidget);

      entry.remove();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the claim follows the wrapper, enabled or not', (
      tester,
    ) async {
      await tester.pumpWidget(
        const CNOccludesGlass(enabled: false, child: SizedBox()),
      );
      expect(CNGlassOcclusion.isOccluded, isFalse);

      await tester.pumpWidget(const CNOccludesGlass(child: SizedBox()));
      expect(CNGlassOcclusion.isOccluded, isTrue);

      // Unmounting releases, so no path out can leak a claim.
      await tester.pumpWidget(const SizedBox());
      expect(CNGlassOcclusion.isOccluded, isFalse);
    });
  });
}
