import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// App-declared occlusion: "this rect is drawn over your glass right now".
///
/// **The bug.** A CN widget is a real `UIView` composited *above* Flutter's
/// own content, not a layer inside it. Anything Flutter paints over one
/// therefore doesn't cover it — it tears through it. A toast sliding down
/// over a header, a full-screen loader, a tutorial spotlight: each of them
/// leaves the glass underneath smearing through the thing that is supposed
/// to be on top of it.
///
/// **Why this isn't `ModalHideMixin`'s job.** That one watches the
/// *navigator* and catches modal routes and sheets. These push no route at
/// all — they are `OverlayEntry`s, invisible to any route observer — so
/// nothing in the package can notice them on its own. The app has to say
/// so.
///
/// **The fix.** A CN widget whose own rect is covered renders the same
/// Flutter fallback it would use on a platform with no Liquid Glass at
/// all. No platform view, nothing to tear — and, unlike a hide, the
/// control keeps its shape: still there, still the same size, still where
/// the finger expects it. It just isn't glass for those few seconds.
///
/// **Position-aware**, exactly as `ModalHideMixin` is for sheets: a banner
/// across the top of the screen has no business dropping the tab bar at
/// the bottom out of glass. A claim with no rect is the safe fallback — it
/// covers everything.
///
/// **Usage.** Prefer [CNOccludesGlass], which pairs itself and publishes
/// its own geometry every frame. Wrap the thing that is actually visible,
/// not the full-screen shell it is positioned inside, or its rect is the
/// whole screen and every CN widget stands down:
///
/// ```dart
/// // in the toast's own build, around the card itself
/// CNOccludesGlass(child: MyToastCard())
/// ```
///
/// Or claim by hand, for something that isn't a widget you build. Hold on
/// to the token — it is how the claim is updated and withdrawn:
///
/// ```dart
/// final claim = CNGlassOcclusion.retain(rect: someRect);
/// CNGlassOcclusion.update(claim, movedRect);
/// CNGlassOcclusion.release(claim);
/// ```
abstract final class CNGlassOcclusion {
  /// Live claims: token to the rect it covers, in global coordinates. A
  /// null rect means "geometry unknown", which [covers] treats as the
  /// whole screen.
  static final Map<Object, Rect?> _claims = <Object, Rect?>{};

  /// Bumped whenever a claim is added, moved or withdrawn.
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// Ticks on every change to the set of claims. The value carries no
  /// meaning beyond "something moved" — ask [covers] what it means for a
  /// particular widget.
  static ValueListenable<int> get revision => _revision;

  /// Whether anything at all is currently covering part of the screen.
  ///
  /// Coarse, and rarely what you want: ask [covers] whether a *particular*
  /// widget is affected.
  static bool get isOccluded => _claims.isNotEmpty;

  /// Declares that something now covers [rect], and returns the token that
  /// identifies the claim.
  ///
  /// Leave [rect] null when the geometry isn't known — a full-screen scrim,
  /// say — and every CN widget stands down. Safe to call from anywhere,
  /// `initState` included; see [_bump].
  static Object retain({Rect? rect}) {
    final token = Object();
    _claims[token] = rect;
    _bump();
    return token;
  }

  /// Moves an existing claim. A no-op once [release] has been called for
  /// [token], so a late frame callback can't resurrect a dead claim.
  static void update(Object token, Rect? rect) {
    if (!_claims.containsKey(token) || _claims[token] == rect) return;
    _claims[token] = rect;
    _bump();
  }

  /// Withdraws a claim. Idempotent.
  static void release(Object token) {
    if (_claims.remove(token) == null) return;
    _bump();
  }

  /// Whether [rect] — a widget's own bounds, in global coordinates — is
  /// covered by anything currently claiming occlusion.
  ///
  /// A null [rect] means the caller couldn't measure itself (an early
  /// frame, a detached render object). That resolves to true for the same
  /// reason `ModalHideMixin` hides when it can't measure: standing down
  /// unnecessarily costs a fallback for a frame, and the alternative is the
  /// artifact this whole thing exists to prevent.
  static bool covers(Rect? rect) {
    if (_claims.isEmpty) return false;
    if (rect == null) return true;
    for (final claim in _claims.values) {
      if (claim == null || claim.overlaps(rect)) return true;
    }
    return false;
  }

  static bool _bumpScheduled = false;

  /// Announces a change, waiting for the end of the frame if we are inside
  /// one.
  ///
  /// The natural place to claim occlusion is the `initState` of the thing
  /// doing the covering — which runs *during the build phase*, and the
  /// widgets that would have to swap were built earlier in that same
  /// frame. Notifying there is a `markNeedsBuild` on an already-built
  /// element: Flutter refuses, and the swap silently never happens.
  ///
  /// Only the notification waits. [_claims] is mutated immediately, so
  /// [covers] and [isOccluded] never disagree with what has been asked for,
  /// and claims can't land out of order.
  static void _bump() {
    if (_bumpScheduled) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final midFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!midFrame) {
      _revision.value++;
      return;
    }

    _bumpScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _bumpScheduled = false;
      _revision.value++;
    });
  }
}

/// Declares that its child covers the glass underneath it, for as long as
/// it is in the tree.
///
/// The pairing-free way to use [CNGlassOcclusion]: the claim follows the
/// widget's own lifetime, so there is no release to forget on a path you
/// didn't think about. Its rect is republished every frame, so a toast
/// keeps its claim honest as it slides in and out.
///
/// **Wrap what is actually visible.** A card centred inside a
/// `Positioned.fill` shell measures as the whole screen if you wrap the
/// shell, and then every CN widget on the page stands down instead of just
/// the ones behind the card. Put this around the card.
///
/// It adds no layout of its own; [child] is returned as-is.
class CNOccludesGlass extends StatefulWidget {
  /// Creates a wrapper that claims the glass under [child] while mounted.
  const CNOccludesGlass({super.key, required this.child, this.enabled = true});

  /// The thing being drawn over the page. Returned as-is.
  final Widget child;

  /// Set false to mount without claiming anything — for a wrapper that is
  /// always in the tree and only sometimes covering something.
  final bool enabled;

  @override
  State<CNOccludesGlass> createState() => _CNOccludesGlassState();
}

class _CNOccludesGlassState extends State<CNOccludesGlass> {
  Object? _claim;
  Rect? _published;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant CNOccludesGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  @override
  void dispose() {
    _releaseClaim();
    super.dispose();
  }

  /// Brings the claim in line with [CNOccludesGlass.enabled].
  ///
  /// The first frame has no geometry yet, so the claim starts rectless —
  /// covering everything — and narrows to the measured rect a frame later.
  /// Erring wide for one frame is the right way round; the alternative is a
  /// frame of the artifact.
  void _sync() {
    if (widget.enabled == (_claim != null)) return;
    if (widget.enabled) {
      _claim = CNGlassOcclusion.retain();
      _published = null;
      _scheduleMeasure();
    } else {
      _releaseClaim();
    }
  }

  void _releaseClaim() {
    final claim = _claim;
    if (claim == null) return;
    _claim = null;
    _published = null;
    CNGlassOcclusion.release(claim);
  }

  /// Re-arms every frame, the way `CNSheetGeometryProbe` does, so a rect
  /// that moves — a toast sliding in, a card being dragged away — stays
  /// current rather than pinning the claim where it started.
  void _scheduleMeasure() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _claim == null) return;
      _measure();
      _scheduleMeasure();
    });
  }

  void _measure() {
    final claim = _claim;
    if (claim == null) return;

    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return;
    final rect = ro.localToGlobal(Offset.zero) & ro.size;
    if (rect == _published) return;

    _published = rect;
    CNGlassOcclusion.update(claim, rect);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Tells a CN widget whether something is currently drawn over *it*, and
/// rebuilds it when that changes.
///
/// **Usage.** Mix in, then `&&` [isGlassOccluded] into the widget's
/// existing native/fallback decision:
///
/// ```dart
/// class _CNButtonState extends State<CNButton>
///     with GlassOcclusionMixin<CNButton> {
///   Widget build(BuildContext context) {
///     final shouldUseNative =
///         isIOSOrMacOS &&
///         PlatformVersion.shouldUseNativeGlass &&
///         !isGlassOccluded;
///     ...
/// ```
///
/// The widget's own fallback is what shows, so this costs nothing to a
/// consumer who never claims occlusion — the flag is false for the whole
/// life of the app until something says otherwise.
mixin GlassOcclusionMixin<T extends StatefulWidget> on State<T> {
  bool _occluded = false;
  bool _tracking = false;

  /// True while something the app has declared covers this widget's own
  /// rect. Position-aware: a banner at the top of the screen doesn't drop a
  /// tab bar at the bottom out of glass.
  bool get isGlassOccluded => _occluded;

  @override
  void initState() {
    super.initState();
    CNGlassOcclusion.revision.addListener(_onOcclusionChanged);
    // Something may already be up when this mounts — a widget scrolled into
    // view under a toast that is still on screen.
    if (CNGlassOcclusion.isOccluded) _startTracking();
  }

  @override
  void dispose() {
    CNGlassOcclusion.revision.removeListener(_onOcclusionChanged);
    super.dispose();
  }

  void _onOcclusionChanged() {
    if (!mounted) return;
    if (CNGlassOcclusion.isOccluded) {
      _startTracking();
    } else if (_occluded) {
      // Nothing left to be under, and no rect it could overlap — so skip
      // the measure and take the glass straight back.
      setState(() => _occluded = false);
    }
  }

  /// Re-measures every frame while anything is claiming occlusion.
  ///
  /// Watching [CNGlassOcclusion.revision] alone isn't enough: a *stationary*
  /// banner over a *scrolling* page changes which widgets it covers without
  /// any claim moving. The loop only runs while something is up, which is
  /// the couple of seconds a toast is on screen.
  void _startTracking() {
    if (_tracking) return;
    _tracking = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _tracking = false;
      if (!mounted) return;
      _recompute();
      if (CNGlassOcclusion.isOccluded) _startTracking();
    });
  }

  void _recompute() {
    final ro = context.findRenderObject();
    Rect? myRect;
    if (ro is RenderBox && ro.hasSize && ro.attached) {
      myRect = ro.localToGlobal(Offset.zero) & ro.size;
    }

    final next = CNGlassOcclusion.covers(myRect);
    if (next != _occluded) setState(() => _occluded = next);
  }
}
