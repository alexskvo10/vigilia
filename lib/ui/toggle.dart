import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'pressable.dart';

/// Строка-переключатель: подпись слева, трек 44×24 справа.
/// Ручка 18×18 едет 200ms OutBack(1.2); кликабельна вся строка.
class Toggle extends StatelessWidget {
  const Toggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.hint,
    this.hintWidget,
    this.warn = false,
  });

  final String label;
  final String? hint; // мелкая подпись под названием
  final Widget? hintWidget; // или виджет вместо неё (например, сочетание клавиш)
  final bool warn; // подпись — предупреждение
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return Pressable(
      radius: BorderRadius.circular(8),
      pop: 1.015,
      flash: 0.08,
      pressScale: 0.99,
      toggled: value,
      semanticLabel: label,
      onTap: () => onChanged(!value),
      builder: (context, hovered, _) => AnimatedContainer(
        duration: D.color,
        height: hintWidget == null ? 40 : 50,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: hovered ? C.text.withValues(alpha: 0.05) : C.text.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              AnimatedSwitcher(
                duration: D.color,
                child: Icon(icon, key: ValueKey(value), size: 16, color: value ? C.accent : C.overlay0),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(12, color: value ? C.text : C.subtext0),
                  ),
                  if (hintWidget != null) Padding(padding: const EdgeInsets.only(top: 3), child: hintWidget),
                  if (hint != null)
                    Text(
                      hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(9.5, weight: FontWeight.w500, color: warn ? C.warning : C.overlay0),
                    ),
                ],
              ),
            ),
            AnimatedScale(
              scale: hovered && !still ? 1.04 : 1,
              duration: D.base,
              curve: Curves.easeOutQuint,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 24,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? C.accent : (hovered ? lighter(C.base, 1.2) : C.base),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedAlign(
                  duration: still ? Duration.zero : const Duration(milliseconds: 200),
                  curve: const OutBack(1.2),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: D.color,
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(color: value ? C.onAccent : C.text, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
