import 'dart:math';

/// New matches use an independent, positive seed saved in their replay.
int randomWorldSeed() => Random.secure().nextInt(0x7fffffff) + 1;
