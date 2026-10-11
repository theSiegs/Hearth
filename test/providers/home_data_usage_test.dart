import 'package:flauncher/providers/home_data_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("it opens on the top bar's period each time, and OK goes today, this week, this month, today", () {
    final home = HomeDataUsage();
    var notified = 0;
    home.addListener(() => notified++);

    home.setShowing(true, period: "weekly");
    expect(home.showing, isTrue);
    expect(home.period, "weekly");
    home.nextPeriod();
    expect(home.period, "monthly");
    home.nextPeriod();
    expect(home.period, "daily");
    home.nextPeriod();
    expect(home.period, "weekly");

    home.setShowing(false);
    expect(home.showing, isFalse);
    home.setShowing(true, period: "monthly");
    expect(home.period, "monthly");
    expect(notified, 6);
  });

  test("an unknown period opens on today; showing again changes nothing", () {
    final home = HomeDataUsage();
    home.setShowing(true, period: "yearly");
    expect(home.period, "daily");
    var notified = 0;
    home.addListener(() => notified++);
    home.setShowing(true, period: "monthly");
    expect(home.period, "daily");
    expect(notified, 0);
  });
}
