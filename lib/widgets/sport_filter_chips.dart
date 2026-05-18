import 'package:flutter/material.dart';

import '../models/sport_type.dart';

class SportFilterChips extends StatelessWidget {
  const SportFilterChips({
    super.key,
    required this.selectedSport,
    required this.onChanged,
  });

  final SportType? selectedSport;
  final ValueChanged<SportType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ChoiceChip(
          label: const Text('全部'),
          selected: selectedSport == null,
          onSelected: (_) => onChanged(null),
          avatar: const Icon(Icons.grid_view_rounded, size: 18),
          labelStyle: _labelStyle(theme, selectedSport == null),
        ),
        for (final sport in SportType.values)
          ChoiceChip(
            label: Text(_labelForSport(sport)),
            selected: selectedSport == sport,
            onSelected: (_) => onChanged(sport),
            avatar: Icon(_iconForSport(sport), size: 18),
            labelStyle: _labelStyle(theme, selectedSport == sport),
          ),
      ],
    );
  }

  TextStyle _labelStyle(ThemeData theme, bool isSelected) {
    return (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: isSelected ? theme.colorScheme.primary : Colors.white,
      fontWeight: FontWeight.w700,
    );
  }

  String _labelForSport(SportType sport) {
    switch (sport) {
      case SportType.football:
        return '足球';
      case SportType.baseball:
        return '棒球';
      case SportType.basketball:
        return '籃球';
    }
  }

  IconData _iconForSport(SportType sport) {
    switch (sport) {
      case SportType.football:
        return Icons.sports_soccer_rounded;
      case SportType.baseball:
        return Icons.sports_baseball_rounded;
      case SportType.basketball:
        return Icons.sports_basketball_rounded;
    }
  }
}