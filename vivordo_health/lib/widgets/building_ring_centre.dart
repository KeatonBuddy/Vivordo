import 'package:flutter/material.dart';

/// "6/14" over "DAYS" inside a ring that's still building, scaled down to
/// fit [width] (the ring's inside) whatever the text size.
class BuildingRingCentre extends StatelessWidget {
  const BuildingRingCentre(this.building, {super.key, required this.width});

  final (int done, int of, String unit) building;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${building.$1}/${building.$2}',
            style: const TextStyle(
              fontSize: 22,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            building.$3,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    ),
  );
}
