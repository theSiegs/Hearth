import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flutter/material.dart';

class RoundedSwitchListTile extends StatelessWidget {
  final bool value;
  final bool autofocus;

  /// Null shows the switch disabled, for a value that's still loading.
  final ValueChanged<bool>? onChanged;
  final Widget title;

  /// A smaller, dimmer line under [title].
  final Widget? subtitle;
  final Widget secondary;

  const RoundedSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    required this.secondary,
    this.autofocus = false
  });

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final subtitle = this.subtitle;
    return FocusableSettingsTile(
      autofocus: autofocus,
      onPressed: onChanged == null ? null : () => onChanged(!value),
      leading: secondary,
      title: subtitle == null
          ? title
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                const SizedBox(height: 2),
                DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                  child: subtitle,
                ),
              ],
            ),
      trailing: Container(
        constraints: const BoxConstraints(maxHeight: 16),
        child: Switch(
          value: value,
          onChanged: onChanged,
        )
      ),
    );
  }
}
