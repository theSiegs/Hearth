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
import 'package:flauncher/models/parent_channel.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'remote_text_field.dart';
import 'settings_page.dart';

/// What a kid's HearthTube has told Hearth (provider contract 8): the videos they started, newest first, for a parent to
/// read without Home Assistant. A row opens Block this video / Block this channel, which [KidBlocksPage] lists.
class KidWatchLogPage extends StatefulWidget {
  static const String routeName = "kid_watch_log";

  /// The kid's profile key ("user:11").
  final String profileKey;

  const KidWatchLogPage({super.key, required this.profileKey});

  @override
  State<KidWatchLogPage> createState() => _KidWatchLogPageState();
}

class _KidWatchLogPageState extends State<KidWatchLogPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  List<StartedVideo>? _entries;
  Set<String> _blocked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await _channel.getStartedLog(widget.profileKey);
      final blocks = ParentBlocks.fromMap(await _channel.getParentBlocks(widget.profileKey));
      if (mounted) {
        setState(() {
          _entries = entries;
          _blocked = blocks.blockedIds;
        });
      }
    } catch (err) {
      noteFailure('kid_watch_log', err);
      if (mounted) setState(() => _entries = []);
    }
  }

  Future<void> _block(StartedVideo entry) async {
    final l = AppLocalizations.of(context)!;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(entry.title.isEmpty ? entry.videoId : entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        children: [
          SimpleDialogOption(
            child: TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop("video"),
              child: Align(alignment: Alignment.centerLeft, child: Text(l.kidBlockVideo)),
            ),
          ),
          if (entry.channelId.isNotEmpty)
            SimpleDialogOption(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop("channel"),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(entry.channel.isEmpty ? l.kidBlockChannel : l.kidBlockChannelNamed(entry.channel))),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final isChannel = picked == "channel";
    await _channel.setParentBlock(
      profileKey: widget.profileKey,
      kind: picked,
      id: isChannel ? entry.channelId : entry.videoId,
      label: isChannel ? entry.channel : entry.title,
      on: true,
    );
    await _load();
  }

  /// 2026-10-27 14:05, in the TV's own time.
  static String _when(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, "0");
    return "${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final entries = _entries;

    return SettingsPage.custom(
      title: l.kidWatchLog,
      subtitle: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Text(l.kidWatchLogBody, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? Center(child: Text(l.kidWatchLogEmpty, style: textTheme.bodyMedium))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final blocked = _blocked.contains(e.videoId) || _blocked.contains(e.channelId);
                    return FocusableSettingsTile(
                      autofocus: i == 0,
                      leading: Icon(blocked ? Icons.block : Icons.smart_display_outlined,
                          color: blocked ? Colors.redAccent : null),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(e.title.isEmpty ? e.videoId : e.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
                          Text("${_when(e.timeMs)}${e.channel.isEmpty ? "" : "  ·  ${e.channel}"}",
                              style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
                        ],
                      ),
                      trailing: blocked ? Text(l.kidBlocksBlocked, style: textTheme.bodySmall) : null,
                      onPressed: () => _block(e),
                    );
                  },
                ),
    );
  }
}

/// What a parent blocked in a kid's HearthTube (contract 8, `parent_blocks`): words, channels and videos, set here. What
/// Home Assistant sends is listed too, and taken back there. HearthTube applies both and doesn't let the kid undo them.
/// Below, what the kid hid or blocked themselves (contract 10), which a parent can show to them again.
class KidBlocksPage extends StatefulWidget {
  static const String routeName = "kid_blocks";

  final String profileKey;

  const KidBlocksPage({super.key, required this.profileKey});

  @override
  State<KidBlocksPage> createState() => _KidBlocksPageState();
}

class _KidBlocksPageState extends State<KidBlocksPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  ParentBlocks? _blocks;
  KidOwnBlocks _kidOwn = KidOwnBlocks.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final blocks = ParentBlocks.fromMap(await _channel.getParentBlocks(widget.profileKey));
      final kidOwn = KidOwnBlocks.fromMap(await _channel.getKidOwnBlocks(widget.profileKey));
      if (mounted) {
        setState(() {
          _blocks = blocks;
          _kidOwn = kidOwn;
        });
      }
    } catch (err) {
      noteFailure('kid_blocks', err);
      if (mounted) setState(() => _blocks = ParentBlocks.empty);
    }
  }

  /// Shows one of the kid's own hides or blocks to them again: HearthTube takes it back when it next hears from Hearth.
  Future<void> _undoKidOwn(String kind, BlockedThing item) async {
    final l = AppLocalizations.of(context)!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.kidBlocksRemove(item.label)),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.remove)),
        ],
      ),
    );
    if (yes != true) return;
    await _channel.undoKidOwnBlock(profileKey: widget.profileKey, kind: kind, id: item.id);
    await _load();
  }

  List<Widget> _kidOwnSection(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final kidOwn = _kidOwn;
    if (kidOwn.isEmpty) return const [];
    Widget tile(String kind, IconData icon, BlockedThing item) => FocusableSettingsTile(
          leading: Icon(icon, color: Colors.white54),
          title: Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
          trailing: const Icon(Icons.undo, color: Colors.white54),
          onPressed: () => _undoKidOwn(kind, item),
        );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Text(l.kidOwnBlocks, style: textTheme.titleSmall),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 4),
        child: Text(l.kidOwnBlocksBody, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
      ),
      for (final item in kidOwn.words) tile("word", Icons.text_fields, item),
      for (final item in kidOwn.channels) tile("channel", Icons.person_off_outlined, item),
      for (final item in kidOwn.videos) tile("video", Icons.visibility_off_outlined, item),
    ];
  }

  Future<void> _addWord() async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final word = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.kidBlocksAddWord),
        content: RemoteTextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
          decoration: InputDecoration(labelText: l.kidBlocksWordLabel),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: Text(l.save)),
        ],
      ),
    );
    controller.dispose();
    if (word == null || word.trim().isEmpty) return;
    await _channel.setParentBlock(profileKey: widget.profileKey, kind: "word", id: word, label: word, on: true);
    await _load();
  }

  Future<void> _remove(String kind, String id, String label) async {
    final l = AppLocalizations.of(context)!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.kidBlocksRemove(label)),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.remove)),
        ],
      ),
    );
    if (yes != true) return;
    await _channel.setParentBlock(profileKey: widget.profileKey, kind: kind, id: id, label: label, on: false);
    await _load();
  }

  List<Widget> _section(BuildContext context, String title, String kind, List<BlockedThing> own, List<BlockedThing> ha) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final fromHome = ha.where((h) => !own.any((o) => o.id == h.id)).toList();
    if (own.isEmpty && fromHome.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        child: Text(title, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
      ),
      for (final item in own)
        FocusableSettingsTile(
          leading: const Icon(Icons.block),
          title: Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
          trailing: const Icon(Icons.delete_outline, color: Colors.white54),
          onPressed: () => _remove(kind, item.id, item.label),
        ),
      for (final item in fromHome)
        FocusableSettingsTile(
          leading: const Icon(Icons.home_outlined),
          title: Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
          trailing: Text(l.kidBlocksFromHa, style: textTheme.bodySmall),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final blocks = _blocks;

    return SettingsPage(
      title: l.kidBlocks,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Text(l.kidBlocksBody, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
        ),
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.add),
          title: Text(l.kidBlocksAddWord, style: textTheme.bodyMedium),
          onPressed: _addWord,
        ),
        if (blocks == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else ...[
          ..._section(context, l.kidBlocksWords, "word", blocks.ownWords, blocks.haWords),
          ..._section(context, l.kidBlocksChannels, "channel", blocks.ownChannels, blocks.haChannels),
          ..._section(context, l.kidBlocksVideos, "video", blocks.ownVideos, blocks.haVideos),
          if (blocks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.kidBlocksNone, style: textTheme.bodyMedium),
            ),
          ..._kidOwnSection(context),
        ],
      ],
    );
  }
}
