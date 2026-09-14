import 'package:flutter/material.dart';
import '../services/location_service.dart';

class LocationRadiusFilter extends StatelessWidget {
  final int currentRadiusKm;
  final Function(int) onRadiusChanged;
  final bool showLabel;
  const LocationRadiusFilter({
    super.key,
    required this.currentRadiusKm,
    required this.onRadiusChanged,
    this.showLabel = true,
  });
  @override
  Widget build(BuildContext context) {
    final values = LocationService.supportedRadii;
    final index = values.indexOf(currentRadiusKm.toDouble());
    final sliderIndex = index >= 0 ? index : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          const Text(
            'Discovery radius',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: values.asMap().entries.map((entry) {
            final isSelected = entry.value == currentRadiusKm.toDouble();
            final isEven = entry.key % 2 == 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEven
                      ? entry.value.toStringAsFixed(0)
                      : '${entry.value.toStringAsFixed(entry.value == 0.5 ? 1 : 0)} km',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: isSelected ? 13 : 11,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 6,
                  height: isSelected ? 6 : 0,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF4B72)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbColor: const Color(0xFFFF4B72),
            overlayColor: const Color(0xFFFF4B72).withValues(alpha: 0.2),
            activeTrackColor: const Color(0xFFFF4B72),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            trackHeight: 4,
          ),
          child: Slider(
            value: sliderIndex.toDouble(),
            min: 0,
            max: (values.length - 1).toDouble(),
            divisions: values.length - 1,
            onChanged: (value) {
              final newRadius = values[value.round()];
              onRadiusChanged(newRadius.round());
            },
          ),
        ),
        Center(
          child: Text(
            LocationService.formatDistance(currentRadiusKm.toDouble()),
            style: const TextStyle(
              color: Color(0xFFFF4B72),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
