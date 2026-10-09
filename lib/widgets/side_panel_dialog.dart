import 'package:flauncher/actions.dart';
import 'package:flutter/material.dart';

class SidePanelDialog extends StatelessWidget {
  final Widget child;
  final double width;

  const SidePanelDialog({
    super.key,
    required this.child,
    this.width = 250,
  });

  @override
  Widget build(BuildContext context) {
    // On the start side: the left, or the right in a right-to-left language
    final borderRadius =
        const BorderRadiusDirectional.horizontal(end: Radius.circular(24)).resolve(Directionality.of(context));

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        color: const Color(0xFF0F0F0F),
        elevation: 24,
        shadowColor: Colors.black,
        borderRadius: borderRadius,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Actions(
            actions: { BackIntent: BackAction(context) },
            child: child,
          ),
        ),
      ),
    );
  }
}
