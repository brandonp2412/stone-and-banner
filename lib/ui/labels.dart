import '../engine/board.dart';

String terrainLabel(Land land) => switch (land) {
  Land.woodland => 'Woodland',
  Land.clayBeds => 'Clay Beds',
  Land.fields => 'Fields',
  Land.meadows => 'Sheep Pastures',
  Land.ridges => 'Ore Hills',
  Land.barren => 'Barren',
};

/// Human-facing label. Keep Resource.wool and its serialized name unchanged
/// so existing saves and shared game protocol remain compatible.
extension ResourceDisplayName on Resource {
  String get displayName => this == Resource.wool ? 'sheep' : name;
}
