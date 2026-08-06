import 'package:flutter/material.dart';

/// Builds the horizontal cubic curve used by the Metrics overview chart.
Path smoothChartPath(List<Offset> points) {
  if (points.isEmpty) return Path();
  if (points.length == 1) {
    return Path()..moveTo(points.first.dx, points.first.dy);
  }

  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var index = 0; index < points.length - 1; index++) {
    final current = points[index];
    final next = points[index + 1];
    final midpointX = (current.dx + next.dx) / 2;
    path.cubicTo(midpointX, current.dy, midpointX, next.dy, next.dx, next.dy);
  }
  return path;
}
