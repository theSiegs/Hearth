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

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../flauncher_channel.dart';
import '../../providers/search_service.dart';

/// The apps a card offers, best first: those that can open the title's own page (Wikidata links it) before those
/// that can only search for it.
List<ProviderApp> appsFor(TitleMatch match, {bool rentOrBuy = false}) {
  final apps = [...(rentOrBuy ? match.availability.rentOrBuy : match.availability.included)];
  bool linked(ProviderApp app) => match.result.offers.any((o) => o.service.packageName == app.packageName);
  apps.sort((a, b) => (linked(a) ? 0 : 1) - (linked(b) ? 0 : 1));
  return apps;
}

/// Opens [match] in [app]: its page there when Wikidata links one, else the app's own search for the title, else
/// Google TV's page for it.
Future<bool> openIn(TitleMatch match, ProviderApp app, {FLauncherChannel? channel}) async {
  final c = channel ?? FLauncherChannel();
  final offer = match.result.offers.firstWhereOrNull((o) => o.service.packageName == app.packageName);
  if (offer != null && await c.openLinkInApp(app.packageName, offer.link)) return true;
  if (await c.searchInApp(app.packageName, match.result.title)) return true;
  return openOnGoogleTv(match, channel: c);
}

/// Google TV's page for the title (every way to watch it), or its search when there's no Google id.
Future<bool> openOnGoogleTv(TitleMatch match, {FLauncherChannel? channel}) {
  final c = channel ?? FLauncherChannel();
  return match.result.googleTvLink != null
      ? c.openGoogleTv(link: match.result.googleTvLink)
      : c.openGoogleTv(query: match.result.title);
}

/// What pressing a card does: straight into the one app that has it, or a short "Watch on" choice when several
/// do (and "More ways to watch" for Google TV's page). True when something opened.
Future<bool> openTitle(BuildContext context, TitleMatch match, {bool rentOrBuy = false}) async {
  final apps = appsFor(match, rentOrBuy: rentOrBuy);
  if (apps.length == 1) return openIn(match, apps.first);
  final choice = await showDialog<Object>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(match.result.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, app) in apps.indexed)
            TextButton.icon(
              autofocus: i == 0,
              style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(14)),
              icon: Icon(rentOrBuy ? Icons.shopping_bag_outlined : Icons.play_arrow_rounded),
              label: Text(rentOrBuy ? "Rent or buy on ${app.name}" : "Watch on ${app.name}"),
              onPressed: () => Navigator.of(context).pop(app),
            ),
          TextButton.icon(
            autofocus: apps.isEmpty,
            style: TextButton.styleFrom(
                alignment: Alignment.centerLeft, padding: const EdgeInsets.all(14), foregroundColor: Colors.white70),
            icon: const Icon(Icons.info_outline),
            label: const Text("More ways to watch (Google TV)"),
            onPressed: () => Navigator.of(context).pop("google"),
          ),
        ],
      ),
    ),
  );
  if (choice is ProviderApp) return openIn(match, choice);
  if (choice == "google") return openOnGoogleTv(match);
  return false;
}
