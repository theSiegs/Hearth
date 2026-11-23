# Hardened components

Change them in place, never rewrite them.

The parts below were reviewed, attacked with probe tests, fixed, and covered by regression tests (2026-11). Each one
handles edge cases that aren't obvious from a quick read. Change them with small edits that keep their tests passing.
Don't replace one with a "cleaner" version: if a redesign is truly needed, port every edge case and its test first,
and say so in the change. When another part gets the same review-probe-fix-test treatment, add it here.

| File | What it handles (tests in `ha_tests/`) |
|---|---|
| `counting.py` `merge` | A live "now playing" reading next to itemized readings counts as a total only, so one play isn't counted twice (`test_counting`) |
| `household.py` totals sources | Keeps the day's highest count across restarts. A drop of 5 min or less is accepted; a bigger drop counts as the source's new day before 6 AM and is ignored after. The count is capped at the time since midnight (`test_sources`) |
| `household.py` startup | A limit reached today stays held for 90 s after Home Assistant starts, but not on a reload. `group_packages` is cached once per recompute (`test_qc_fixes`) |
| `enforce.py` | A shared Switch keeps its real limit when it passes from one kid to another. Family Safety locks are applied again past midnight, and a pause locks platforms. The held set is updated as each platform's call succeeds. Hearth's own Family Link bonus isn't counted twice against a parent's. Extra time that has ended is ignored. A Family Link app pause is a parent's change only once it was seen intact (`pauses_intact`); one never shown is said and retried with a doubling wait (`pauses_not_taken`); apps of a pause call that failed part-way stay possibly held (`maybe_paused`) so letting go resumes them. A family pause locks a Family Link child's devices whole. `essential()` is the explicit system list (`SYSTEM_PARTS`, no `com.android.*` prefix: Chrome is held). A call that failed because the integration hadn't loaded yet is retried in 30 s (`_not_loaded_yet`) (`test_enforce`, `test_native_sync`, `test_seams_probes`) |
| `native_sync.py` | A parent's Family Link bonus grant lasts while their share is left; extra time Hearth couldn't cancel stays known as Hearth's (`test_native_sync`) |
| `unlimited.py` | A total's minutes of a window reported after the settle are left out by each source's growth beyond the time since (ratchet, last window only). Unlimited started again while a window settles reopens it (`test_seams_probes`) |
| `pause.py` | Pauses are saved and survive a restart. Family Safety's downtime sensors are a bedtime by `downtime_start`/`downtime_end` (`test_qc_fixes`, `test_pause`) |
| `backstop.py` | A whole-device hold is remembered across a restart |
| `api.py` | Parent PIN guesses are checked one at a time past the free tries. Deeply nested JSON gets a 400 (`test_parent_pin`) |
| `switch_approval.py` | Only an adult can answer, and the persistent notification never carries the request id (`test_switch_approval`) |
| `hub.py` | Tells a moved clock from a time zone (`utc_offset_minutes`). A day's counts never go down. A pairing ticket never takes over a device of another kind (`test_qc_fixes`, `test_tickets`) |
| `schedule.py` | Days off in a row, a day off ended early, and `off_now` for days that are over (`test_schedule`, `test_places`) |
| `weekly.py` | Half days when School is split by a break, and "until 00:00" (`test_weekly`, `test_qc_fixes`) |
| `todos.py` | An undone reward stays undone. Editing an every-N-days task keeps its start date (`test_chores`) |
| `places.py` | A Family Link move needs two location fixes. A reading too rough to place someone at home doesn't jump to a big zone (`test_places`) |
| `presence.py` + `presence_rules.py` | The kid's fix is set against an adult's track at its own time, not their latest position (a car together isn't apart). Unsure and unknown change nothing; nothing is confirmed while settling; a restored adult position keeps its stored age; no coordinate is stored, fired or logged. Messages when away opens on 5 minutes apart, goes back after 10 with an adult or at home, never flaps within 15, goes off after 6 hours unknown, and lifts time limits only; `Household.open_apps` keeps the device lock when a lock, pause, block, the schedule or School time holds the app (`test_presence`, `test_away_messages`, `test_invariants` D) |
| `fs_site_list.py` | Refuses a web page or a list that looks like a wrong download (`test_fs_site_list`) |
| `app_blocks.py` | A block call that timed out is still Hearth's to lift. Launchers and keyboards are never blocked; Chrome (`com.android.chrome`) is blockable (`test_app_blocks`) |
| `client_settings.py` | Hearth's own documents are exempt from the limits. Each device scope is capped at 256 KB (`test_qc_fixes`) |
| `glint_api.py` | Who may forget a phone. The start-screen options come from adults' phones only (`test_glint_agent`) |
| `entity.py` | Removes the entities of pools that no longer exist, only for keys that setup made (`test_qc_fixes`) |
| `media.py` | Rooms whose players have no name (`test_media`) |
| Settings (`panel.py` `hearth/config/set`, services) | Probed with 34 schema-valid odd values (built-in pool ids, missing entities, ghost people, cycles): none stops the household; keep new option consumers tolerant of missing targets |
| TV `Allowance.java` (`timeUpGroup`, `heldApps`, `lockedNow`) | A lock holds every app however it's opened; a next lock whose time has come holds without Home Assistant (`HeldAppsTest`) |
| TV `LauncherAccessibilityService.java` `holdRunningApp` | The app in front is re-checked periodically with Home Assistant too, so apps already open, or relaunched past the hold cap, go home |
| TV `HaStatusReporter.java` + `hub.py` `_tell_failing_tv_checks` | The TV reports its accessibility service; 5 minutes off is told to the adults once, cleared when back (`test_qc_fixes`) |
| TV `HaAllowance.java` `staleCountdown` | With no word from Home Assistant for 10 minutes, each group's minutes are counted down by the time in front since its last word. HearthTube's time counts against daily time, and HearthTube's minutes come down with what other apps take of a group holding it (`HaStaleCountdownTest`, `SeamsStaleCountdownTest`) |
| TV `HaAllowance.java` `profilesFromDocument`, `carriedOver`, `valuesOf` | HearthTube isn't held by daily time when its `except` lists it. Past midnight a lock with no end and a next lock the TV started itself still hold (with when Home Assistant last spoke). A lifted bedtime's end is the next lock, ending at the schedule's wake time. HearthTube is locked exactly when other apps are (`lockedNow`). Minutes used come from the document's `time` (`SeamsDocumentTest`, `SeamsOfflineLocksTest`, `HaAllowanceCarryTest`, `LockInForceTest`) |
| State document seam (TV and Home Assistant) | One fixture, `ha_tests/contract_fixtures/tv_state_document.json`, at five moments (evening, bedtime, bedtime lifted, a pause, YouTube allowed): Home Assistant must still send what it says (`test_client_contract`) and the TV must read it as a family expects (`TvStateDocumentFixtureTest`). Change both sides with the fixture |
| `ha_tests/test_invariants.py` | Never-break rules over random cases: left values, whole minutes, counting, day scenarios. Keep it green; add a rule when you harden something |
| `household.py` `document_for` parent PINs, `client.py` `device_contract` | A contract-4 TV (the higher of its pairing's and its status's contract) is never sent the adults' PIN hashes, only their version; a post naming an older contract can't get them back. Staged: TVs below 4 still get them until the next release. Each adult's version comes by a key that names nobody (`parent_pins_versions`) (`test_parent_pin`, `test_client_contract`) |
| `frontend/hearth-panel.js` | Every interpolation of device-supplied text goes through `esc()`. Keep it that way |

Run `ha_tests` before every push and read the result first.
