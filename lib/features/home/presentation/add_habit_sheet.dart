import 'package:flutter/material.dart';

import '../domain/habit.dart';
import '../domain/habit_icons.dart';
import '../domain/scheduled_time.dart';

final _iconOptions = habitIconOptions.values.toList();

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class AddHabitSheet extends StatefulWidget {
  final Habit? initialHabit;

  /// When non-null, the user must select exactly this many specific weekdays.
  /// The SegmentedButton is hidden and save is blocked until the count matches.
  final int? requiredDaysPerWeek;

  const AddHabitSheet({super.key, this.initialHabit, this.requiredDaysPerWeek});

  @override
  State<AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<AddHabitSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late TimeOfDay _selectedTime;
  late IconData _selectedIcon;
  late bool _everyDay;
  late Set<int> _selectedWeekdays;
  bool _weekdayError = false;

  bool get _isEditing => widget.initialHabit != null;

  @override
  void initState() {
    super.initState();
    final initialHabit = widget.initialHabit;
    _titleController = TextEditingController(text: initialHabit?.title ?? '');
    _selectedTime = initialHabit != null
        ? (parseScheduledTime(initialHabit.scheduledTime) ?? TimeOfDay.now())
        : TimeOfDay.now();
    _selectedIcon = initialHabit?.icon ?? _iconOptions.first;

    final wd = initialHabit?.weekdays ?? const [1, 2, 3, 4, 5, 6, 7];
    _selectedWeekdays = Set<int>.of(wd);
    _everyDay =
        widget.requiredDaysPerWeek == null &&
        _selectedWeekdays.length == 7 &&
        _selectedWeekdays.containsAll([1, 2, 3, 4, 5, 6, 7]);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  String get _weekdayErrorText {
    final req = widget.requiredDaysPerWeek;
    if (req != null) {
      return 'Select exactly $req ${req == 1 ? "day" : "days"}';
    }
    return 'Select at least one day';
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final req = widget.requiredDaysPerWeek;
    if (!_everyDay &&
        (_selectedWeekdays.isEmpty ||
            (req != null && _selectedWeekdays.length != req))) {
      setState(() => _weekdayError = true);
      return;
    }

    final weekdays = _everyDay
        ? const [1, 2, 3, 4, 5, 6, 7]
        : (_selectedWeekdays.toList()..sort());

    final initialHabit = widget.initialHabit;
    final habit = Habit(
      id: initialHabit?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      scheduledTime: _formatTime(_selectedTime),
      icon: _selectedIcon,
      completedDates: initialHabit?.completedDates ?? const {},
      weekdays: weekdays,
    );
    Navigator.of(context).pop(habit);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Edit habit' : 'Add habit',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Habit title'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Title cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Scheduled time'),
                  subtitle: Text(_formatTime(_selectedTime)),
                  trailing: const Icon(Icons.access_time),
                  onTap: _pickTime,
                ),
                const SizedBox(height: 8),
                Text('Icon', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final icon in _iconOptions)
                      _IconChoice(
                        icon: icon,
                        selected: icon == _selectedIcon,
                        onTap: () => setState(() => _selectedIcon = icon),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Repeat', style: theme.textTheme.titleSmall),
                if (widget.requiredDaysPerWeek != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Select exactly ${widget.requiredDaysPerWeek} '
                    '${widget.requiredDaysPerWeek == 1 ? "day" : "days"}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (widget.requiredDaysPerWeek == null) ...[
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Every day')),
                      ButtonSegment(value: false, label: Text('Specific days')),
                    ],
                    selected: {_everyDay},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _everyDay = selection.first;
                        _weekdayError = false;
                      });
                    },
                  ),
                ],
                if (!_everyDay) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 1; i <= 7; i++)
                        FilterChip(
                          label: Text(_weekdayLabels[i - 1]),
                          selected: _selectedWeekdays.contains(i),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedWeekdays.add(i);
                              } else {
                                _selectedWeekdays.remove(i);
                              }
                              _weekdayError = false;
                            });
                          },
                        ),
                    ],
                  ),
                  if (_weekdayError)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _weekdayErrorText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _save, child: const Text('Save')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: CircleAvatar(
        backgroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          icon,
          color: selected
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
