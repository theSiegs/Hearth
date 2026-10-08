import 'package:flauncher/models/tv_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TvInputType typeOf(int? type) => TvInput.fromMap({'id': 'input', 'label': 'Input', 'type': type}).type;

  test("maps Android's input types to tuner, HDMI, AV and other", () {
    expect(typeOf(0), TvInputType.tuner);
    expect(typeOf(2), TvInputType.tuner);
    expect(typeOf(3), TvInputType.tuner);
    expect(typeOf(1007), TvInputType.hdmi);
    expect([1001, 1002, 1003, 1004].map(typeOf), everyElement(TvInputType.av));
    expect(typeOf(1005), TvInputType.other);
    expect(typeOf(null), TvInputType.other);
  });
}
