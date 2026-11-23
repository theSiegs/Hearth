# Hearth's documentation

The Home Assistant integration's documents. Hearth TV's own (its user guide, privacy, development, the TV remote API,
the provider contract HearthTube reads, household sync between TVs, PIN recipes) moved to
[theSiegs/HearthTV](https://github.com/theSiegs/HearthTV/tree/master/docs).

- [Home Assistant integration](home-assistant-integration.md): design and state of the integration
- [Hearth TV contract](contracts/hearth-tv.md): everything a Hearth TV and the integration say to each other, and what
  the TV does without Home Assistant. A change to it needs the page and the contract tests here and in HearthTV
  updated together
- [A TV's entities](contracts/tv-entities.md): which entities of a paired TV other integrations may read, and how to
  find them
- [Contracts](contracts/): the device API (`device-api.md`), the time model, client settings, panel config, app facts
- [Dashboard parity](dashboard-parity.md): Hearth's page next to the parental control integrations' dashboards
- [Messages and routing](message-routing.md): what Hearth offers a household message router (`hearth.notify` and
  the `hearth_notice` event); routing and archives are other projects' job
- [Hardened components](hardened-components.md): parts to change only in place, with their tests
