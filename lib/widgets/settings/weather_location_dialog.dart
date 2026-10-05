/*
 * LTvLauncher
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../providers/open_meteo_client.dart';
import '../../providers/weather_service.dart';

/// Type a city, pick a match. Pops with the chosen place, or null.
class WeatherLocationDialog extends StatefulWidget {
  final WeatherService weatherService;

  const WeatherLocationDialog({super.key, required this.weatherService});

  @override
  State<WeatherLocationDialog> createState() => _WeatherLocationDialogState();
}

class _WeatherLocationDialogState extends State<WeatherLocationDialog> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  final FocusNode _firstResultFocus = FocusNode();
  List<WeatherPlace>? _results;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _firstResultFocus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.weatherService.searchPlaces(_query.text);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
      if (results.isNotEmpty) {
        // The TV keyboard keeps the arrow keys while open: close it and land on the first match
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        WidgetsBinding.instance.addPostFrameCallback((_) => _firstResultFocus.requestFocus());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't reach the weather service. Check the network connection.";
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return AlertDialog(
      title: const Text("Weather location"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _query,
              focusNode: _queryFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(hintText: "City or town", prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 8),
            if (_searching) const LinearProgressIndicator(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            if (results != null && results.isEmpty && !_searching) const Text("No places found"),
            if (results != null && results.isNotEmpty)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final place in results)
                      ListTile(
                        focusNode: place == results.first ? _firstResultFocus : null,
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(place.displayName),
                        onTap: () => Navigator.of(context).pop(place),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              "Weather by Open-Meteo.com: free, no account. Only the chosen place's coordinates are sent.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _search, child: const Text("Search")),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
      ],
    );
  }
}
