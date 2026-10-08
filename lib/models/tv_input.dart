enum TvInputType {
  tuner,
  hdmi,
  av,
  other
}

class TvInput {
  // TvInputInfo.getType() values
  static const int _typeTuner = 0;
  static const int _typeOther = 1000;
  static const int _typeComposite = 1001; // composite, S-Video, SCART and component run 1001-1004
  static const int _typeComponent = 1004;
  static const int _typeHdmi = 1007;

  /// Counted as tuners too, though TvInputInfo defines no such types.
  static const Set<int> _otherTunerTypes = {2, 3};

  final String id;
  final String label;
  final TvInputType type;

  TvInput({
    required this.id,
    required this.label,
    required this.type,
  });

  factory TvInput.fromMap(Map<dynamic, dynamic> map) {
    final int typeInt = map['type'] as int? ?? _typeOther;
    TvInputType type;
    if (typeInt == _typeHdmi) {
      type = TvInputType.hdmi;
    } else if (typeInt == _typeTuner || _otherTunerTypes.contains(typeInt)) {
      type = TvInputType.tuner;
    } else if (typeInt >= _typeComposite && typeInt <= _typeComponent) {
      type = TvInputType.av;
    } else {
      type = TvInputType.other;
    }

    return TvInput(
      id: map['id'] as String? ?? '',
      label: map['label'] as String? ?? '',
      type: type,
    );
  }
}
