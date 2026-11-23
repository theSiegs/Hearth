# Hearth TV's documentation

**For families using Hearth**
- [User guide](user-guide.md): setup and every feature
- [Home Assistant](home-assistant.md): what Hearth TV and Home Assistant give each other, and how to set each part up
- [Privacy](privacy.md): what Hearth TV sends where, and why it asks for each Android permission

**For contributors and apps that work with Hearth TV**
- [Development](development.md): building, testing and releasing
- [Hearth TV contract](contracts/hearth-tv.md): every call between Hearth TV and the Hearth integration, and what
  each does without the other. A change to the Hearth TV contract needs contracts/hearth-tv.md and both contract tests (ha_tests here, the fixture test in HearthTV) updated together.
- [Home Assistant integration](home-assistant-integration.md): design draft for a Hearth integration that replaces the webhook, helpers and tokens
- [Message hub](message-hub.md): design and task list for keeping the household's SMS, RCS and other messages in
  one store the household runs, checked by a local model, with alerts to adults through Hearth
- [Household sync](household-sync.md): design draft for keeping profiles, PINs, looks and Continue Watching in step across TVs
- [PIN recipes](pin-recipes.md): how Hearth TV recognises and types into each streaming app's PIN screen, and how to fix a recipe without a release
- [Provider contract](provider-contract.md): what HearthTube (or another app) can read from Hearth TV, and
  [wallpaper sync](wallpaper-sync.md), how HearthTube shows Hearth TV's wallpaper with it
