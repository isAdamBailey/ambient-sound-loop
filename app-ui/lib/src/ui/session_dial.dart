/// The length dial: the session's clock and its length in one round face.
///
/// Stopped, the arc is the chosen length on a 12-hour face and can be dragged
/// round in 5-minute steps. Running or paused, it is locked and the arc is the
/// time left, shrinking toward 12. Past 12 hours the whole ring turns to the
/// secondary tone, the same for any longer length; Until I stop is a full ring
/// with no handle.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../session/length.dart';
import '../session/session_controller.dart';
import 'theme.dart';

const _faceSeconds = 12 * 3600;
const _step = 300; // 5 minutes
const _semanticStep = 900; // 15 minutes per assistive increase/decrease

class SessionDial extends StatefulWidget {
  const SessionDial({super.key, required this.controller, required this.size, required this.onExact});

  final SessionController controller;
  final double size;
  final VoidCallback onExact;

  @override
  State<SessionDial> createState() => _SessionDialState();
}

class _SessionDialState extends State<SessionDial> {
  Timer? _minute; // redraws "ends" at each minute while stopped
  double? _dragSeconds; // unsnapped, while a drag is under way
  double _lastAngle = 0;

  SessionController get c => widget.controller;

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  static final _maxSnapped = maxSessionLength.inSeconds ~/ _step * _step;

  static int _snap(num seconds) => ((seconds / _step).round() * _step).clamp(_step, _maxSnapped);

  int? get _dragSnapped => _dragSeconds == null ? null : _snap(_dragSeconds!);

  /// The length the face shows while stopped (a drag in progress wins).
  SessionLength get _chosen {
    final drag = _dragSnapped;
    return drag != null ? SessionLength.timed(Duration(seconds: drag)) : c.settings.length;
  }

  /// A drag turns the dial only when it starts on the ring band, so brushing
  /// the center (or scrolling past it) never changes the length.
  bool _onRing(Offset local) {
    final r = widget.size / 2 - 14;
    final d = (local - Offset(widget.size / 2, widget.size / 2)).distance;
    return d > r - 36 && d < r + 20;
  }

  double _angleOf(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    return math.atan2(local.dy - center.dy, local.dx - center.dx);
  }

  void _panStart(DragStartDetails d) {
    _lastAngle = _angleOf(d.localPosition);
    setState(() => _dragSeconds = (c.settings.length.duration?.inSeconds ?? 0).toDouble());
  }

  void _panUpdate(DragUpdateDetails d) {
    final a = _angleOf(d.localPosition);
    var delta = a - _lastAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _lastAngle = a;
    final before = _dragSnapped;
    setState(() {
      _dragSeconds = (_dragSeconds! + delta / (2 * math.pi) * _faceSeconds).clamp(
        0,
        maxSessionLength.inSeconds.toDouble(),
      );
    });
    final after = _dragSnapped;
    if (before != null && after != null && before ~/ 3600 != after ~/ 3600) HapticFeedback.selectionClick();
  }

  void _panEnd([DragEndDetails? _]) {
    final snapped = _dragSnapped;
    setState(() => _dragSeconds = null);
    if (snapped != null) c.setLength(SessionLength.timed(Duration(seconds: snapped)));
  }

  void _nudge(int seconds) {
    final now = c.settings.length.duration?.inSeconds ?? 0;
    c.setLength(SessionLength.timed(Duration(seconds: _snap(now + seconds))));
  }

  /// What the face draws: the time left while locked, else the chosen length.
  _Face _face() {
    if (c.lengthLocked) {
      return c.shownLength is UntilStop ? const _Face.untilStop() : _Face.timed(c.clockSeconds, handle: false);
    }
    final length = _chosen;
    return length is UntilStop ? const _Face.untilStop() : _Face.timed(length.duration!.inSeconds, handle: true);
  }

  @override
  void initState() {
    super.initState();
    _keepEndCurrent();
  }

  @override
  void didUpdateWidget(SessionDial old) {
    super.didUpdateWidget(old);
    _keepEndCurrent(); // the screen rebuilds the dial on every controller change
  }

  /// While stopped with a timed length, "ends" moves on with the wall clock:
  /// redraw at the next minute. Running, the controller's ticks redraw it.
  void _keepEndCurrent() {
    final needed = !c.lengthLocked && c.settings.length is! UntilStop;
    if (!needed) {
      _minute?.cancel();
      _minute = null;
    } else if (_minute?.isActive != true) {
      _minute = Timer(Duration(seconds: 60 - DateTime.now().second), () {
        if (!mounted) return;
        setState(() {});
        _keepEndCurrent();
      });
    }
  }

  String _endText(BuildContext context, DateTime end) {
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(end), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
    final now = DateTime.now();
    final sameDay = end.year == now.year && end.month == now.month && end.day == now.day;
    if (sameDay) return time;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[end.weekday - 1]} $time';
  }

  @override
  Widget build(BuildContext context) {
    final locked = c.lengthLocked;
    final paused = c.phase == SessionPhase.paused;
    final size = widget.size;

    final face = _face();
    final clockText = !locked && _dragSnapped != null ? formatClock(_dragSnapped!) : c.clockText;
    final endText = face.untilStop ? null : _endText(context, DateTime.now().add(Duration(seconds: face.seconds)));
    final clockSize = (size * 0.17).clamp(30.0, 52.0);

    final ring = RepaintBoundary(
      child: CustomPaint(size: Size.square(size), painter: _DialPainter(face)),
    );

    final dial = locked
        ? ExcludeSemantics(child: ring)
        : Semantics(
            slider: true,
            label: 'Session length',
            value: _chosen.tileText,
            increasedValue: _chosen is UntilStop ? null : 'longer by 15 minutes',
            decreasedValue: _chosen is UntilStop ? null : 'shorter by 15 minutes',
            onIncrease: _chosen is UntilStop ? null : () => _nudge(_semanticStep),
            onDecrease: _chosen is UntilStop ? null : () => _nudge(-_semanticStep),
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _RingPanRecognizer: GestureRecognizerFactoryWithHandlers<_RingPanRecognizer>(
                  () => _RingPanRecognizer(_onRing),
                  (r) => r
                    ..onStart = _panStart
                    ..onUpdate = _panUpdate
                    ..onEnd = _panEnd
                    ..onCancel = _panEnd,
                ),
              },
              child: ExcludeSemantics(child: ring),
            ),
          );

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          dial,
          SizedBox(
            width: size * 0.7,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Flutter has no timer role; the clock is labelled and never
                // announced as it ticks (no live region).
                IgnorePointer(
                  child: Semantics(
                    label: 'Clock, ${c.clockCaption}',
                    value: clockText,
                    excludeSemantics: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(clockText, maxLines: 1, style: SessionText.clock(clockSize, dimmed: paused)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                IgnorePointer(
                  child: ExcludeSemantics(child: Text(c.clockCaption, style: SessionText.note.copyWith(height: 1.2))),
                ),
                if (endText != null)
                  IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'ends '),
                            TextSpan(text: endText, style: SessionText.figures(14)),
                          ],
                        ),
                        style: SessionText.note.copyWith(height: 1.3),
                        maxLines: 1,
                      ),
                    ),
                  ),
                if (!locked)
                  TextButton(
                    onPressed: widget.onExact,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 44),
                      foregroundColor: SessionColors.ink,
                      overlayColor: SessionColors.seaDeep,
                    ),
                    child: Text(
                      'Exact',
                      style: SessionText.weight(
                        14,
                        500,
                      ).copyWith(decoration: TextDecoration.underline, decorationColor: SessionColors.dim),
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

/// What the ring shows.
class _Face {
  const _Face.timed(this.seconds, {required this.handle}) : untilStop = false;
  const _Face.untilStop() : seconds = 0, handle = false, untilStop = true;

  final int seconds;
  final bool handle;
  final bool untilStop;

  bool get pastFace => !untilStop && seconds > _faceSeconds;
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.face);
  final _Face face;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const stroke = _stroke;
    final radius = size.width / 2 - 14; // room for the handle
    final rect = Rect.fromCircle(center: center, radius: radius);
    const top = -math.pi / 2;

    canvas.drawCircle(center, radius, _track);

    // Hour ticks just inside the ring; the quarters a little longer.
    for (var h = 0; h < 12; h++) {
      final a = top + h / 12 * 2 * math.pi;
      final inner = radius - stroke / 2 - (h % 3 == 0 ? 12 : 7);
      final outer = radius - stroke / 2 - 3;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * inner,
        center + Offset(math.cos(a), math.sin(a)) * outer,
        _tick,
      );
    }

    final arc = face.pastFace ? _arcPast : _arc;

    if (face.untilStop || face.pastFace) {
      canvas.drawCircle(center, radius, arc);
    } else if (face.seconds > 0) {
      canvas.drawArc(rect, top, face.seconds / _faceSeconds * 2 * math.pi, false, arc);
    }

    if (face.handle) {
      final turn = (face.seconds % _faceSeconds) / _faceSeconds;
      final a = top + turn * 2 * math.pi;
      final at = center + Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawCircle(at, 11, _handle);
      canvas.drawCircle(at, 3, _handleDot);
    }
  }

  static const _stroke = 10.0;
  static Paint _ring(Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _stroke
    ..color = color;
  static final _track = _ring(SessionColors.rule);
  static final _arc = _ring(SessionColors.sea);
  static final _arcPast = _ring(SessionColors.dim);
  static final _tick = Paint()
    ..color = const Color(0xFF2A343C)
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  static final _handle = Paint()..color = SessionColors.ink;
  static final _handleDot = Paint()..color = SessionColors.ground;

  /// While the clock runs down a second is 1/43200 of a turn, so the locked
  /// ring redraws once a minute rather than on every tick.
  @override
  bool shouldRepaint(_DialPainter old) =>
      old.face.handle != face.handle ||
      old.face.untilStop != face.untilStop ||
      old.face.pastFace != face.pastFace ||
      (face.handle ? old.face.seconds != face.seconds : old.face.seconds ~/ 60 != face.seconds ~/ 60);
}

/// A pan that claims the pointer as soon as it lands on the ring, so an
/// enclosing scroll view cannot take a vertical turn of the dial.
class _RingPanRecognizer extends PanGestureRecognizer {
  _RingPanRecognizer(this.onRing);
  final bool Function(Offset local) onRing;

  @override
  bool isPointerAllowed(PointerEvent event) => onRing(event.localPosition) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
