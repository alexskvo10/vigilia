import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';
import 'pressable.dart';

/// Свой заголовок окна: тянется за пустое место, «—» сворачивает, «×» прячет в трей.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, required this.onHide});

  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(Icons.visibility_rounded, size: 15, color: C.accent),
                  const SizedBox(width: 8),
                  Text('VIGILIA', style: mono(12, spacing: 1.5)),
                ],
              ),
            ),
          ),
          _BarButton(icon: Icons.remove_rounded, label: 'Свернуть', onTap: windowManager.minimize),
          const SizedBox(width: 4),
          _BarButton(icon: Icons.close_rounded, label: 'Спрятать в трей', onTap: onHide, danger: true),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      radius: BorderRadius.circular(8),
      pop: 1.10,
      popUp: 110,
      popDown: 420,
      flash: 0.4,
      flashMs: 400,
      hoverScale: 1.04,
      pressScale: 1.08,
      semanticLabel: label,
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: D.color,
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: hovered ? (danger ? C.danger.withValues(alpha: 0.18) : C.surface0) : C.surface0.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: hovered ? (danger ? C.danger : C.text) : C.subtext0),
      ),
    );
  }
}
