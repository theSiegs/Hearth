import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../flauncher_channel.dart';
import '../providers/profile_service.dart';
import '../providers/watch_next_service.dart';

/// The welcome card shown over the home while it catches up with a profile switch: the profile's photo and
/// "Hi <name>" ("Setting up this profile…" before Hearth knows its name), with a line that fills as each step
/// lands. It goes once the profile's layout is restored, its native data is in (another profile's agent has
/// reported), Continue Watching has been read for it and its first posters are in, or after [maxWait] at the
/// latest, so a slow step never keeps anyone out. Remote presses wait meanwhile.
class ProfileTransitionOverlay extends StatefulWidget {
  static const Duration maxWait = Duration(seconds: 4);

  final FLauncherChannel channel;

  const ProfileTransitionOverlay({super.key, required this.channel});

  @override
  State<ProfileTransitionOverlay> createState() => _ProfileTransitionOverlayState();
}

class _ProfileTransitionOverlayState extends State<ProfileTransitionOverlay> {
  ProfileTransition? _current;
  ProfileTransition? _ended;
  bool _dataReady = false;
  Timer? _poll;
  Timer? _deadline;
  bool _timedOut = false;
  final FocusNode _focusNode = FocusNode(debugLabel: "profile_transition");

  @override
  void dispose() {
    _poll?.cancel();
    _deadline?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _start(ProfileTransition transition) {
    _current = transition;
    _dataReady = false;
    _timedOut = false;
    _poll?.cancel();
    _deadline?.cancel();
    final remaining = ProfileTransitionOverlay.maxWait - DateTime.now().difference(transition.startedAt);
    _deadline = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (mounted && _current == transition) setState(() => _timedOut = true);
    });
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _checkData(transition));
    _checkData(transition);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _current == transition) _focusNode.requestFocus();
    });
  }

  Future<void> _checkData(ProfileTransition transition) async {
    bool ready;
    try {
      ready = await widget.channel.isProfileDataReady();
    } catch (_) {
      ready = true;
    }
    if (!mounted || _current != transition) return;
    if (ready) {
      _poll?.cancel();
      if (!_dataReady) setState(() => _dataReady = true);
    }
  }

  void _finish(ProfileService profiles, ProfileTransition transition) {
    _poll?.cancel();
    _deadline?.cancel();
    _current = null;
    _ended = transition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      profiles.endTransition(transition);
      widget.channel.setProfileReady(transition.key).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfileService?>();
    final watchNext = context.watch<WatchNextService?>();
    final transition = profiles?.transition;
    if (profiles == null) return const SizedBox.shrink();
    if (transition == null || transition == _ended) {
      // Picked in the chooser, not confirmed yet: the card shows already, its progress not started
      final incoming = profiles.incomingName;
      if (incoming == null) return const SizedBox.shrink();
      if (!_focusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && profiles.incomingName != null) _focusNode.requestFocus();
        });
      }
      return _card(context, incoming, profiles.incomingAvatar, 0);
    }
    if (transition != _current) _start(transition);

    final steps = <bool>[
      profiles.layoutReadyFor(transition.key),
      _dataReady,
      watchNext == null || watchNext.refreshedFor == transition.key,
      watchNext == null || (watchNext.refreshedFor == transition.key && watchNext.postersSettled),
    ];
    final done = steps.where((s) => s).length;
    if (done == steps.length || _timedOut) _finish(profiles, transition);

    return _card(
      context,
      profiles.activeProfileName ?? transition.pickedName,
      profiles.activeProfileAvatar ?? transition.pickedAvatar,
      done / steps.length,
    );
  }

  Widget _card(BuildContext context, String? name, Uint8List? photo, double progress) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: _focusNode,
      // The home underneath is still the last profile's: nothing moves until it's this one's
      onKeyEvent: (_, __) => KeyEventResult.handled,
      child: Container(
        color: const Color(0xF2101114),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2D2E31)),
              clipBehavior: Clip.antiAlias,
              child: photo != null
                  ? Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true)
                  : const Icon(Icons.person, size: 80, color: Colors.white70),
            ),
            const SizedBox(height: 28),
            Text(
              name != null ? "Hi, $name" : "Setting up this profile…",
              style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
