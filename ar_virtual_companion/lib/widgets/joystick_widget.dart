import 'package:flutter/material.dart';

/// 搖桿方向資訊：dx/dy 各在 −1..1，magnitude 在 0..1
class JoystickDirection {
  final double dx;
  final double dy;
  final double magnitude;

  const JoystickDirection(this.dx, this.dy, this.magnitude);

  static const zero = JoystickDirection(0, 0, 0);
}

/// 王者榮耀式浮現搖桿。
///
/// 使用方式：放在 Stack 裡某個觸控區域，手指按下時搖桿就地浮現，
/// 鬆手後消失。[onDirectionChanged] 持續回報方向（包含死區=zero）；
/// [onReleased] 只在手指真正離開螢幕時觸發，用於停止移動邏輯。
class FloatingJoystick extends StatefulWidget {
  final void Function(JoystickDirection dir) onDirectionChanged;

  /// 手指真正離開螢幕時觸發（與 onDirectionChanged(zero) 有別：
  /// 後者在死區內也會觸發，onReleased 只在 pointer up/cancel 時觸發）
  final VoidCallback? onReleased;

  /// 基座圓半徑（邏輯像素）
  final double baseRadius;

  /// 小圓鈕半徑（邏輯像素）
  final double knobRadius;

  const FloatingJoystick({
    super.key,
    required this.onDirectionChanged,
    this.onReleased,
    this.baseRadius = 60.0,
    this.knobRadius = 26.0,
  });

  @override
  State<FloatingJoystick> createState() => _FloatingJoystickState();
}

class _FloatingJoystickState extends State<FloatingJoystick> {
  Offset? _baseCenter;
  Offset _knobOffset = Offset.zero;
  int? _activePointer;

  void _onPointerDown(PointerDownEvent e) {
    if (_activePointer != null) return;
    _activePointer = e.pointer;
    setState(() {
      _baseCenter = e.localPosition;
      _knobOffset = Offset.zero;
    });
    widget.onDirectionChanged(JoystickDirection.zero);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer) return;
    final center = _baseCenter!;
    final delta = e.localPosition - center;
    final dist = delta.distance;
    final maxDist = widget.baseRadius - widget.knobRadius;

    // Dead zone: below 12px = no direction
    const deadZone = 12.0;
    if (dist < deadZone) {
      setState(() => _knobOffset = Offset.zero);
      widget.onDirectionChanged(JoystickDirection.zero);
      return;
    }

    // Snap to nearest cardinal direction (4-way)
    final Offset snapDir;
    if (delta.dx.abs() >= delta.dy.abs()) {
      snapDir = Offset(delta.dx > 0 ? 1.0 : -1.0, 0.0);
    } else {
      snapDir = Offset(0.0, delta.dy > 0 ? 1.0 : -1.0);
    }

    // Knob always sits at maxDist in the snapped direction
    setState(() => _knobOffset = snapDir * maxDist);

    widget.onDirectionChanged(JoystickDirection(snapDir.dx, snapDir.dy, 1.0));
  }

  void _release(int pointer) {
    if (pointer != _activePointer) return;
    _activePointer = null;
    setState(() {
      _baseCenter = null;
      _knobOffset = Offset.zero;
    });
    widget.onDirectionChanged(JoystickDirection.zero);
    // 手指真正離開才通知 onReleased，與死區 zero 有別
    widget.onReleased?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (e) => _release(e.pointer),
      onPointerCancel: (e) => _release(e.pointer),
      child: SizedBox.expand(
        child: _baseCenter == null
            ? const SizedBox.shrink()
            : CustomPaint(
                painter: _JoystickPainter(
                  baseCenter: _baseCenter!,
                  knobOffset: _knobOffset,
                  baseRadius: widget.baseRadius,
                  knobRadius: widget.knobRadius,
                ),
              ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset baseCenter;
  final Offset knobOffset;
  final double baseRadius;
  final double knobRadius;

  const _JoystickPainter({
    required this.baseCenter,
    required this.knobOffset,
    required this.baseRadius,
    required this.knobRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 基座外圓（半透明填充）
    canvas.drawCircle(
      baseCenter,
      baseRadius,
      Paint()..color = Colors.white.withOpacity(0.18),
    );
    // 基座外圓（邊框）
    canvas.drawCircle(
      baseCenter,
      baseRadius,
      Paint()
        ..color = Colors.white.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // 小圓鈕
    canvas.drawCircle(
      baseCenter + knobOffset,
      knobRadius,
      Paint()..color = Colors.white.withOpacity(0.65),
    );
    // 小圓鈕邊框
    canvas.drawCircle(
      baseCenter + knobOffset,
      knobRadius,
      Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.baseCenter != baseCenter || old.knobOffset != knobOffset;
}
