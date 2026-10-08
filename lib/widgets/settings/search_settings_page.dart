import 'package:flauncher/providers/search_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';

/// Search settings (under Remote & search): where search results come from, and an optional TMDB key of the user's
/// own for posters.
class SearchSettingsPage extends StatelessWidget {
  static const String routeName = "search_settings";

  const SearchSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final settings = context.watch<SettingsService>();
    final ownKey = settings.tmdbApiKey.isNotEmpty;
    final builtIn = TmdbClient().enabled;
    final status = ownKey
        ? "Your key"
        : builtIn
            ? "Built in"
            : "Off";

    return Column(
      children: [
        Text("Search", style: textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                FocusableSettingsTile(
                  autofocus: true,
                  leading: const Icon(Icons.image_outlined),
                  title: Text("Posters (TMDB key)", style: textTheme.bodyMedium),
                  trailing: Text(status,
                      style: textTheme.bodySmall?.copyWith(color: ownKey || builtIn ? Colors.green : Colors.white54)),
                  onPressed: () => _editKey(context, settings),
                ),
                if (ownKey)
                  FocusableSettingsTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(builtIn ? "Use the built-in key instead" : "Remove my key",
                        style: textTheme.bodyMedium),
                    onPressed: () => settings.setTmdbApiKey(""),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Search finds films and shows in Wikidata (open data; only your search text is sent). With a TMDB "
                    "key, results also show posters and where they're streaming in the US. Get a free key at "
                    "themoviedb.org (Settings → API). Your key stays on this TV and isn't included in backups.",
                    style: textTheme.bodySmall?.copyWith(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editKey(BuildContext context, SettingsService settings) async {
    final controller = TextEditingController(text: settings.tmdbApiKey);
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Your TMDB API key"),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: "API key (v3)"),
            onSubmitted: (text) => Navigator.of(context).pop(text),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text("Save")),
        ],
      ),
    );
    if (key != null) await settings.setTmdbApiKey(key);
  }
}
