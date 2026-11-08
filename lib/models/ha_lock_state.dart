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

/// Why a kids profile is held, as the Hearth integration for Home Assistant says it (docs/home-assistant-integration.md,
/// Pause and locks).
enum HaLockKind { bedtime, schoolTime, pause, other }

HaLockKind _kindOf(Object? kind) => switch (kind) {
      "bedtime" => HaLockKind.bedtime,
      "school_time" => HaLockKind.schoolTime,
      "pause" => HaLockKind.pause,
      _ => HaLockKind.other,
    };

enum HaRequestStatus { pending, approved, denied, expired, unknown }

DateTime? _time(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

int? _int(Object? value) => value is int ? value : null;

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

/// A kid's latest request for more time and its answer (docs/home-assistant-integration.md, Ask for more).
class HaRequest {
  final String? id;
  final HaRequestStatus status;

  /// What an adult gave when approved, otherwise what was asked.
  final int? minutes;
  final int? askedMinutes;
  final String? group;
  final DateTime? expires;

  /// When it was answered or expired; null while pending.
  final DateTime? answered;

  const HaRequest({
    this.id,
    required this.status,
    this.minutes,
    this.askedMinutes,
    this.group,
    this.expires,
    this.answered,
  });

  factory HaRequest.fromMap(Map<dynamic, dynamic> map) => HaRequest(
        id: _text(map["id"]),
        status: switch (map["status"]) {
          "pending" => HaRequestStatus.pending,
          "approved" => HaRequestStatus.approved,
          "denied" => HaRequestStatus.denied,
          "expired" => HaRequestStatus.expired,
          _ => HaRequestStatus.unknown,
        },
        minutes: _int(map["minutes"]),
        askedMinutes: _int(map["askedMinutes"]),
        group: _text(map["group"]),
        expires: _time(map["expires"]),
        answered: _time(map["answered"]),
      );

  /// Pending, and not past its expiry by this TV's clock (the integration says expired with its next answer).
  bool isWaitingAt(DateTime now) =>
      status == HaRequestStatus.pending && (expires == null || now.isBefore(expires!));

  /// Pending but past its expiry: no adult answered in time.
  bool isExpiredAt(DateTime now) =>
      status == HaRequestStatus.expired ||
      (status == HaRequestStatus.pending && expires != null && !now.isBefore(expires!));
}

/// A group whose time is up today: its id (for asking for more of it; null from an older Hearth) and name. Or an app
/// or group an adult paused (hearth.pause with an app or group): [paused], with its plain name, reason and end; more
/// time doesn't end it, so there's no asking for it.
class HaTimeUpGroup {
  final String? id;
  final String name;
  final bool paused;
  final String? pausedName;
  final String? pauseReason;
  final DateTime? pauseUntil;

  const HaTimeUpGroup(this.id, this.name, {this.paused = false, this.pausedName, this.pauseReason, this.pauseUntil});
}

/// What the Hearth integration last said about the active profile: a family pause, the lock on now, the next bedtime
/// or school time, the latest request for more time and the groups out of time. Without Home Assistant, [none].
class HaLockState {
  /// The integration's cooldown after "not now" before the same kid may ask again (asks.py COOLDOWN).
  static const askCooldown = Duration(minutes: 10);

  /// The amounts a kid can ask for (asks.py AMOUNTS).
  static const askMinutes = [15, 30, 45, 60];

  final bool paired;
  final bool kids;
  final bool paused;
  final String? pauseReason;
  final DateTime? pauseUntil;
  final HaLockKind? lockKind;
  final DateTime? lockUntil;
  final HaLockKind? nextLockKind;
  final DateTime? nextLockAt;
  final HaRequest? request;
  final List<HaTimeUpGroup> timeUp;

  const HaLockState({
    this.paired = false,
    this.kids = false,
    this.paused = false,
    this.pauseReason,
    this.pauseUntil,
    this.lockKind,
    this.lockUntil,
    this.nextLockKind,
    this.nextLockAt,
    this.request,
    this.timeUp = const [],
  });

  static const none = HaLockState();

  /// From the Android side's getHaLockState (HaLocks.forFlutter): times are epoch ms.
  factory HaLockState.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return none;
    final pause = map["pause"];
    final lock = map["lock"];
    final next = map["nextLock"];
    final request = map["request"];
    final timeUp = map["timeUp"];
    return HaLockState(
      paired: map["paired"] == true,
      kids: map["kids"] == true,
      paused: pause is Map,
      pauseReason: pause is Map ? _text(pause["reason"]) : null,
      pauseUntil: pause is Map ? _time(pause["until"]) : null,
      lockKind: lock is Map ? _kindOf(lock["kind"]) : null,
      lockUntil: lock is Map ? _time(lock["until"]) : null,
      nextLockKind: next is Map ? _kindOf(next["kind"]) : null,
      nextLockAt: next is Map ? _time(next["at"]) : null,
      request: request is Map ? HaRequest.fromMap(request) : null,
      timeUp: [
        if (timeUp is List)
          for (final group in timeUp)
            if (group is Map && _text(group["name"]) != null)
              HaTimeUpGroup(
                _text(group["id"]),
                _text(group["name"])!,
                paused: group["paused"] is Map,
                pausedName: group["paused"] is Map ? _text(group["paused"]["name"]) : null,
                pauseReason: group["paused"] is Map ? _text(group["paused"]["reason"]) : null,
                pauseUntil: group["paused"] is Map ? _time(group["paused"]["until"]) : null,
              ),
      ],
    );
  }

  /// Whether the kid may ask for more time here at all: a kids profile on a paired TV, with time up and nothing more
  /// holding it (more time doesn't end a pause, a bedtime or a school time).
  bool get canAsk => paired && kids && !paused && lockKind == null && timeUp.any((g) => !g.paused);

  /// The adult's pause of the held group or app, when that's what holds it (by its name as the TV was told).
  HaTimeUpGroup? pauseOf(String? heldName) {
    for (final group in timeUp) {
      if (group.paused && group.name == heldName) return group;
    }
    return null;
  }

  /// The group to ask more of: the held one when it's known by name, else the first out of time (All screen time
  /// first, as it holds everything); "all" when no id is known.
  String askGroupFor(String? heldName) {
    final held = timeUp.where((g) => g.name == heldName && g.id != null && !g.paused);
    if (held.isNotEmpty) return held.first.id!;
    final all = timeUp.where((g) => g.id == "all");
    if (all.isNotEmpty) return "all";
    final withId = timeUp.where((g) => g.id != null && !g.paused);
    return withId.isNotEmpty ? withId.first.id! : "all";
  }

  /// How long until the kid may ask again after an adult's "not now" (null: they may ask).
  Duration? cooldownLeftAt(DateTime now) {
    final r = request;
    if (r == null || r.status != HaRequestStatus.denied || r.answered == null) return null;
    final left = r.answered!.add(askCooldown).difference(now);
    return left > Duration.zero ? left : null;
  }
}

/// Whole minutes in [d], rounded up (at least 1), for "in 7 min".
int minutesRoundedUp(Duration d) => d.inSeconds <= 0 ? 1 : ((d.inSeconds + 59) ~/ 60).clamp(1, 1 << 30);
