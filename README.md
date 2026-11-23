<h1 align="center">Hearth</h1>

<p align="center">
  Family screen time for Home Assistant: one set of rules for the kids' TVs, tablets, phones, Xbox and Switch.
</p>

**Hearth:** the family rules (budgets, bedtime, School time, pauses, asks and approvals, Parent PINs, chores), kept
in Home Assistant; not the TV home screen, which is [Hearth TV](https://github.com/theSiegs/HearthTV).

> [!WARNING]
> **Early development.** Expect rough edges and breaking changes between versions.

## What's here

- `custom_components/hearth`: the Home Assistant integration (domain `hearth`). It counts screen time from several
  sources, applies each kid's budgets, schedule, bedtime, pauses and blocks, and enforces them through Family Link,
  Microsoft Family Safety, Nintendo parental controls, Hearth TVs and paired phones.
- `ha_tests`: its tests (`pytest-homeassistant-custom-component`).
- `blueprints`: automation blueprints that use it.
- `pin-entry`: the streaming PIN-entry files older Hearth TV builds still read from this repository. Hearth TV now
  reads them from [HearthTV](https://github.com/theSiegs/HearthTV/tree/master/pin-entry); these copies go once every
  TV runs a build that reads from there.

## Install

With [HACS](https://hacs.xyz): add this repository as a custom repository (type Integration), install **Hearth**,
restart Home Assistant, then Settings → Devices & services → Add integration → Hearth. Details:
[docs/home-assistant-integration.md](docs/home-assistant-integration.md).

## Hearth and Hearth TV

The two live in separate repositories and are released on their own:

- **This repository** releases the integration. Its version is CalVer (`2026.12.01`), kept in
  `custom_components/hearth/manifest.json` and tagged `v<version>`; HACS installs from that tag.
- **[HearthTV](https://github.com/theSiegs/HearthTV)** releases the TV app's APKs (`com.thesiegs.hearth`), which
  installed TVs update from, and owns the APIs the TV serves (its remote API, provider contract and household sync).

The contract between the two (pairing, the state document, what the TV posts, and what the TV does without Home
Assistant) is [docs/contracts/hearth-tv.md](docs/contracts/hearth-tv.md). **A change to that contract needs the page
and the contract tests updated together:** `ha_tests/test_client_contract.py` and
`ha_tests/test_hearth_tv_contract.py` here, HearthTV's `TvStateDocumentFixtureTest` and `TvStateDocumentContractTest`,
with `ha_tests/contract_fixtures/tv_state_document.json` kept identical to HearthTV's copy
(`android/app/src/test/resources/contract_fixtures/tv_state_document.json`).

## Documentation

- [Documentation index](docs/README.md)
- [Hearth TV contract](docs/contracts/hearth-tv.md): every call between Hearth TV and the Hearth integration
- [Hardened components](docs/hardened-components.md): parts to change only in place, with their tests

## Releasing

1. Raise `version` in `custom_components/hearth/manifest.json` (`2026.12.01`; it only goes up) and add a
   `## 2026.12.01` section to [CHANGELOG.md](CHANGELOG.md).
2. Run `ha_tests` and read the result.
3. Commit, tag `v2026.12.01` (annotated), push the branch and the tag. `.github/workflows/release.yml` checks the tag
   against the manifest and publishes the release HACS offers. It needs no secrets.

## License

Hearth is free software under the [GNU General Public License v3.0](LICENSE). It is developed with AI assistance.
