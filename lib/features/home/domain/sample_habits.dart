import 'package:flutter/material.dart';

import 'habit.dart';

List<Habit> sampleHabits() => [
  const Habit(
    id: '1',
    title: 'Drink water',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink_outlined,
  ),
  const Habit(
    id: '2',
    title: 'Read 20 minutes',
    scheduledTime: '01:00 PM',
    icon: Icons.menu_book_outlined,
  ),
  const Habit(
    id: '3',
    title: 'Evening walk',
    scheduledTime: '07:00 PM',
    icon: Icons.directions_walk_outlined,
  ),
];
