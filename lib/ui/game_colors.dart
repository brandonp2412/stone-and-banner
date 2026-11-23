import 'package:flutter/material.dart';

/// Theme counterparts for the game's illustrated dark palette. Map surfaces and
/// their inks together; board art, resource art and player pieces keep their
/// original colors. Unlisted art colors and every dark-mode color pass through.
Color gameColor(BuildContext context, Color darkColor) {
  if (Theme.of(context).brightness == Brightness.dark) return darkColor;
  final light = _lightGameColors[darkColor.toARGB32() & 0x00ffffff];
  return light?.withValues(alpha: darkColor.a) ?? darkColor;
}

final Map<int, Color> _lightGameColors = {
  // Light canvas and panels
  for (final rgb in const [
    0x0a131a,
    0x101d29,
    0x101e25,
    0x111d2c,
    0x14242b,
    0x17242b,
    0x172a33,
    0x172b33,
    0x182a31,
    0x182b32,
    0x182c34,
    0x192b32,
    0x192e38,
    0x1c2830,
    0x1c2e35,
    0x1e343d,
    0x20313a,
    0x20323a,
    0x222b32,
    0x28271e,
  ])
    rgb: const Color(0xfffffaf2),
  // Success panels
  for (final rgb in const [0x153e36, 0x183931, 0x294c43, 0x315248])
    rgb: const Color(0xffe0eee5),
  // Finale panels
  for (final rgb in const [0x1b101b, 0x3b304e]) rgb: const Color(0xffefe6f5),
  // Raised panels
  for (final rgb in const [
    0x202b3c,
    0x20343c,
    0x20363e,
    0x223b41,
    0x243b43,
    0x2b4249,
    0x2c4145,
    0x354b50,
    0x354e4b,
  ])
    rgb: const Color(0xffeee9df),
  // Success and green player ink
  for (final rgb in const [
    0x2c8063,
    0x40d5b4,
    0x67dbbf,
    0x6de0ae,
    0x6f9e79,
    0x70d8bf,
    0x73d9c0,
    0x7fe4b8,
    0x9cbd95,
    0xbde7d4,
    0xeafff5,
  ])
    rgb: const Color(0xff14634d),
  // Danger panels
  for (final rgb in const [0x2e181c, 0x3c0715]) rgb: const Color(0xfffbe8e6),
  // Outlines
  for (final rgb in const [
    0x30434a,
    0x34464a,
    0x365159,
    0x37515a,
    0x38535b,
    0x3a4c53,
    0x40565b,
    0x425963,
    0x45616a,
    0x61716a,
    0x63737a,
    0x786039,
  ])
    rgb: const Color(0xff78817e),
  // Information and blue player ink
  for (final rgb in const [0x4279b9, 0x8ebdff, 0xa1b1c4, 0xa7c8ff, 0xe4eff0])
    rgb: const Color(0xff285c8e),
  // Warning panels
  for (final rgb in const [0x584322, 0x60451d]) rgb: const Color(0xfff5e8cb),
  // Secondary text
  for (final rgb in const [
    0x6b939a,
    0x8fa9ac,
    0xa6b6ba,
    0xa8b9bd,
    0xa8bfc0,
    0xabbfc2,
    0xacc4c9,
    0xadbdc1,
    0xadc4c6,
    0xaebfc0,
    0xaec2c6,
    0xaec5c9,
    0xafc6c8,
    0xb5c9c8,
    0xb7c9ce,
    0xbac9cc,
    0xbac9cc,
    0xc2d2d2,
    0xc6d7d9,
    0xc7d8d9,
  ])
    rgb: const Color(0xff4c5f63),
  // Gold accents and action fills
  for (final rgb in const [
    0xad8121,
    0xd6bd80,
    0xd7b968,
    0xe3d8b7,
    0xe4c976,
    0xe4df75,
    0xe5c183,
    0xeac587,
    0xefd6a3,
    0xf4ce80,
    0xf4eee2,
    0xf5ead3,
    0xf9db9a,
    0xffc477,
    0xffd08a,
    0xffd449,
    0xffd680,
    0xffd6a3,
    0xffdb7d,
    0xffde93,
    0xffe092,
  ])
    rgb: const Color(0xff755018),
  // Purple player and finale ink
  for (final rgb in const [0xbd9dca, 0xcba4f6, 0xd1b2f5, 0xd5a6f7])
    rgb: const Color(0xff69418a),
  // Primary text
  for (final rgb in const [0xdce8e9, 0xffffff]) rgb: const Color(0xff24383d),
  // Danger and red player ink
  for (final rgb in const [
    0xc78369,
    0xff6555,
    0xff6c43,
    0xff756e,
    0xff8299,
    0xff8861,
    0xff8c83,
    0xff977f,
    0xffa28e,
    0xffb8aa,
  ])
    rgb: const Color(0xffa32c30),
};
