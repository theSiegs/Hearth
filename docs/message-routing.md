# Messages and routing

Hearth doesn't route, store or read the household's messages. Keeping an archive of messages, checking them, and
deciding who hears what, on which device, is a job for other projects, such as a household message router that runs
beside Home Assistant.

What Hearth offers such a project:

- **`hearth.notify`**: a message to Hearth's devices, people or the household, on phones and on TVs that show
  notices, with an optional duration ([Home Assistant integration](home-assistant-integration.md), Pop-ups).
- **The `hearth_notice` event**: every notice Hearth shows adults, announced read-only when it's shown, updated or
  cleared, with its audience, text and button labels ([contracts/notice-event.md](contracts/notice-event.md)).

An earlier design that made Hearth the household's message directory was dropped; it's no longer kept here.
