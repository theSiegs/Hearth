/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flauncher/widgets/settings/setup_checklist_page.dart';
import 'package:flauncher/widgets/title_pill.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'setup_flow_launcher.dart';
import 'setup_flow_page.dart';
import 'setup_snapshot.dart';

/// The top bar's "Finish setting up · 3 left", "Home button needs a fix", or after an update that added a card
/// "New in Hearth: Smart home": what the setup flow left undone or has new, one press from carrying on. Not shown in
/// kids' profiles, before the flow has ever run (it shows itself then), when nothing is left, or after holding OK
/// on it and choosing to hide it (until something new comes).
class SetupChip extends StatefulWidget {
  final FocusNode? focusNode;

  const SetupChip({super.key, this.focusNode});

  @override
  State<SetupChip> createState() => _SetupChipState();
}

class _SetupChipState extends State<SetupChip> with WidgetsBindingObserver {
  SetupFlowService? _flow;
  int _left = 0;
  bool _fix = false;

  /// Cards added since the owner last went through the flow.
  List<SetupCard> _new = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flow = context.read<SetupFlowService?>();
    _flow?.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flow?.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Something may have been turned on (or off) in Android's settings meanwhile
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final flow = _flow;
    if (flow == null) return;
    try {
      final channel = context.read<FLauncherChannel>();
      final status = await channel.getHomeButtonFixStatus();
      final homeApp = await channel.isDefaultLauncher();
      final homeButtonOn = status["enabled"] == true;
      if (!mounted) return;
      final cardsOn = await SetupSnapshot.loadCardsOn(channel,
          showContinueWatching: context.read<SettingsService?>()?.showContinueWatching ?? false,
          hasParentPin: context.read<SettingsService?>()?.hasParentPin ?? false,
          kidsProtected: flow.kidsProtected);
      final newKidsProfile = await SetupSnapshot.loadNewKidsProfile(channel, kidsProtected: flow.kidsProtected);
      if (!mounted) return;
      setState(() {
        _left = flow.remaining(
            homeButtonOn: homeButtonOn,
            homeAppOn: homeApp,
            cardOn: cardsOn,
            newKidsProfile: newKidsProfile);
        _new = flow.newCards(cardOn: cardsOn);
        _fix = flow.homeButtonNeedsFix(
            homeButtonOn: homeButtonOn, homeButtonSeenBefore: status["seenBefore"] == true);
      });
    } catch (_) {
      // No Android side (tests): nothing to say
    }
  }

  void _open() {
    final flow = _flow;
    if (flow == null || flow.showing) return;
    if (_fix) {
      SetupFlowLauncher.openFlow(context, mode: SetupMode.rerun, startAt: "homeButton");
      return;
    }
    if (_new.isNotEmpty) {
      // What's new, from its card on
      final first = _new.first;
      flow.markNewSeen();
      SetupFlowLauncher.openFlow(context, mode: SetupMode.rerun, startAt: SetupFlowPage.cardStart(first));
      return;
    }
    final resume = flow.resume;
    SetupFlowLauncher.openFlow(context, mode: resume?.mode ?? SetupMode.rerun, startAt: resume?.screen);
  }

  Future<void> _askToHide() async {
    final l = AppLocalizations.of(context)!;
    final hide = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.setupChipHideTitle),
        content: Text(l.setupChipHideBody(SetupChecklistPage.breadcrumb(l))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(l.setupChipHide)),
        ],
      ),
    );
    if (hide != true) return;
    // Dismissing news hides only the news; the chip comes back for the next
    if (_new.isNotEmpty) await _flow?.markNewSeen();
    await _flow?.hideChip();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<SetupFlowService?>();
    // Without the flow's state (a test's home) there's nothing to say
    if (flow == null) return const SizedBox.shrink();
    final kids = context.select<ProfileService?, bool>((profiles) => profiles?.isKidsProfile ?? false);
    final news = _new.isNotEmpty && !_fix;
    if (!flow.chipAllowed(kids: kids, news: news) || (!_fix && _left == 0)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final label = _fix
        ? l.setupChipFix
        : !news
            ? l.setupChipLeft(_left)
            : _new.length == 1
                ? l.setupChipNewOne(SetupFlowPage.cardTitle(l, _new.first))
                : l.setupChipNewMany(_new.length);
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: FocusKeyboardListener(
        onPressed: (key) {
          if (!AppCardKeys.validationKeys.contains(key)) return KeyEventResult.ignored;
          _open();
          return KeyEventResult.handled;
        },
        onLongPress: (key) {
          _askToHide();
          return KeyEventResult.handled;
        },
        builder: (context) => FocusableTap(
          key: const Key("setup_chip"),
          focusNode: widget.focusNode,
          onPressed: _open,
          builder: (context, focused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: focused ? accent : Colors.black.withOpacity(TitlePill.opacityOf(context)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: focused ? Colors.white : Colors.white.withOpacity(0.12), width: focused ? 2 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_fix ? Icons.warning_amber_rounded : (news ? Icons.auto_awesome : Icons.settings_suggest_outlined),
                  size: 18, color: _fix && !focused ? Colors.amber : Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}
