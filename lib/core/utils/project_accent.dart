import 'package:flutter/material.dart';

/// Deterministic accent colours for work-log cards.
///
/// The same project always maps to the same colour, so a project that
/// appears several times in a list is traceable by eye. Nothing is stored:
/// the colour is derived from the project id, which keeps the database (and
/// the export) untouched.
class ProjectAccent {
  ProjectAccent._();

  /// Chosen to stay apart from each other on the light card surface.
  static const List<Color> light = <Color>[
    Color(0xFF1565C0),
    Color(0xFF00B8D4),
    Color(0xFF2E7D32),
    Color(0xFFE59400),
    Color(0xFF6A4FBF),
    Color(0xFFC62828),
    Color(0xFF3949AB),
    Color(0xFF8D6E63),
  ];

  /// The same hues, lifted so they read on a dark surface.
  static const List<Color> dark = <Color>[
    Color(0xFF7CB4FF),
    Color(0xFF4DD0E1),
    Color(0xFF66BB6A),
    Color(0xFFFFB74D),
    Color(0xFFB39DDB),
    Color(0xFFEF9A9A),
    Color(0xFF9FA8DA),
    Color(0xFFBCAAA4),
  ];

  /// The accent for [projectId] on the given theme brightness.
  ///
  /// Ids are taken modulo the palette length, and a missing id falls back to
  /// the first colour, so a row is never left without one.
  static Color of(int? projectId, Brightness brightness) {
    final palette = brightness == Brightness.dark ? dark : light;
    if (projectId == null) return palette.first;
    return palette[projectId.abs() % palette.length];
  }
}
