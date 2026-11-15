import '../engine/board.dart';

String terrainLabel(Land land) => switch (land) {
  Land.woodland => 'Woodland',
  Land.clayBeds => 'Clay Beds',
  Land.fields => 'Fields',
  Land.meadows => 'Meadows',
  Land.ridges => 'Ridges',
  Land.barren => 'Barren',
};
