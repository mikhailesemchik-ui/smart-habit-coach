import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/date_key.dart';
import '../domain/habit.dart';
import '../domain/habit_icons.dart';
import '../domain/scheduled_time.dart';

final _iconOptions = habitIconOptions.values.toList();

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _unitPresets = [
  'min',
  'hours',
  'steps',
  'pages',
  'times',
  'ml',
  'L',
  'km',
  'kg',
  'reps',
];
const _customPreset = 'Custom';

class AddHabitSheet extends StatefulWidget {
  final Habit? initialHabit;

  /// When non-null, the user must select exactly this many specific weekdays.
  final int? requiredDaysPerWeek;

  const AddHabitSheet({super.key, this.initialHabit, this.requiredDaysPerWeek});

  @override
  State<AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<AddHabitSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _minimumVersionController;
  late final TextEditingController _targetController;
  late final TextEditingController _customUnitController;
  late String _selectedPreset;
  late TimeOfDay _selectedTime;
  late IconData _selectedIcon;
  late bool _everyDay;
  late Set<int> _selectedWeekdays;
  late HabitTrackingType _trackingType;
  bool _weekdayError = false;

  bool get _isEditing => widget.initialHabit != null;

  @override
  void initState() {
    super.initState();
    final initialHabit = widget.initialHabit;
    _titleController = TextEditingController(text: initialHabit?.title ?? '');
    _minimumVersionController = TextEditingController(
      text: initialHabit?.minimumVersion ?? '',
    );
    _trackingType = initialHabit?.trackingType ?? HabitTrackingType.binary;
    final tv = initialHabit?.targetValue;
    _targetController = TextEditingController(
      text: tv != null ? habitProgressLabel(tv) : '',
    );
    final existingUnit = initialHabit?.unit ?? '';
    if (_unitPresets.contains(existingUnit)) {
      _selectedPreset = existingUnit;
      _customUnitController = TextEditingController();
    } else if (existingUnit.isNotEmpty) {
      _selectedPreset = _customPreset;
      _customUnitController = TextEditingController(text: existingUnit);
    } else {
      _selectedPreset = _unitPresets.first;
      _customUnitController = TextEditingController();
    }
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
    _minimumVersionController.dispose();
    _targetController.dispose();
    _customUnitController.dispose();
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

  String? _validateTarget(String? value) {
    if (_trackingType != HabitTrackingType.quantitative) return null;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Required';
    final d = double.tryParse(text);
    if (d == null || d <= 0) return 'Must be greater than 0';
    return null;
  }

  /// Lighter, less "default Material" segmented-control look: a soft
  /// tinted selected state instead of a solid filled one, and a thinner
  /// outline, while keeping selection clearly visible.
  ButtonStyle _segmentedStyle(ThemeData theme) {
    final cs = theme.colorScheme;
    return SegmentedButton.styleFrom(
      backgroundColor: cs.surface,
      selectedBackgroundColor: cs.primaryContainer,
      selectedForegroundColor: cs.primary,
      foregroundColor: cs.onSurfaceVariant,
      side: BorderSide(color: cs.outlineVariant),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final req = widget.requiredDaysPerWeek;
    if (!_everyDay &&
        (_selectedWeekdays.isEmpty ||
            (req != null && _selectedWeekdays.length != req))) {
      setState(() => _weekdayError = true);
      return;
    }

    // Ask for confirmation when tracking type changes on an existing habit
    // that already has history.
    final initialHabit = widget.initialHabit;
    if (initialHabit != null && initialHabit.trackingType != _trackingType) {
      final hasHistory =
          initialHabit.completedDates.isNotEmpty ||
          initialHabit.minimumCompletedDates.isNotEmpty ||
          initialHabit.quantitativeProgress.isNotEmpty;
      if (hasHistory) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Change tracking type?'),
            content: const Text(
              'Existing history is preserved but will be interpreted '
              'differently with the new tracking type. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Change'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
    }

    final weekdays = _everyDay
        ? const [1, 2, 3, 4, 5, 6, 7]
        : (_selectedWeekdays.toList()..sort());

    final minVersionText = _minimumVersionController.text.trim();

    var minimumDates = initialHabit?.minimumCompletedDates ?? const <String>{};
    final hadMinimumVersion = initialHabit?.hasMinimumVersion ?? false;
    if (hadMinimumVersion && minVersionText.isEmpty) {
      final today = todayKey();
      if (minimumDates.contains(today)) {
        minimumDates = Set<String>.of(minimumDates)..remove(today);
      }
    }

    double? quantTarget;
    String? quantUnit;
    if (_trackingType == HabitTrackingType.quantitative) {
      quantTarget = double.tryParse(_targetController.text.trim());
      if (_selectedPreset == _customPreset) {
        final custom = _customUnitController.text.trim();
        quantUnit = custom.isEmpty ? null : custom;
      } else {
        quantUnit = _selectedPreset;
      }
    }

    final habit = Habit(
      id: initialHabit?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      scheduledTime: _formatTime(_selectedTime),
      icon: _selectedIcon,
      completedDates: initialHabit?.completedDates ?? const {},
      minimumCompletedDates: minimumDates,
      weekdays: weekdays,
      status: initialHabit?.status ?? HabitStatus.active,
      pausedFromDate: initialHabit?.pausedFromDate,
      minimumVersion: minVersionText.isEmpty ? null : minVersionText,
      trackingType: _trackingType,
      targetValue: quantTarget,
      unit: quantUnit,
      quantitativeProgress: initialHabit?.quantitativeProgress ?? const {},
      skipReasons: initialHabit?.skipReasons ?? const {},
      skipReasonNotes: initialHabit?.skipReasonNotes ?? const {},
      partialReasons: initialHabit?.partialReasons ?? const {},
      partialReasonNotes: initialHabit?.partialReasonNotes ?? const {},
    );
    if (mounted) Navigator.of(context).pop(habit);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.92;
    // Accounts for both the on-screen keyboard (viewInsets) and the
    // permanent system gesture/navigation bar (viewPadding) — using only
    // one of the two either clips the footer behind the nav bar when the
    // keyboard is closed, or leaves it too high once the keyboard opens.
    // The Container background (matching the bottom sheet's own surface
    // color) paints all the way through that inset too, so there is no
    // mismatched strip of the screen's default background showing below
    // the footer.
    final bottomInset = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;

    return Container(
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.md,
            bottom: AppSpacing.md + bottomInset,
          ),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _DragHandle(),
                  Text(
                    _isEditing ? 'Edit habit' : 'Add habit',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FormSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Habit title',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Title cannot be empty';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _ScheduledTimeRow(
                          time: _formatTime(_selectedTime),
                          onTap: _pickTime,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _SectionLabel('Icon'),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final icon in _iconOptions)
                        _IconChoice(
                          icon: icon,
                          selected: icon == _selectedIcon,
                          onTap: () => setState(() => _selectedIcon = icon),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _SectionLabel('Tracking'),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<HabitTrackingType>(
                    style: _segmentedStyle(theme),
                    segments: const [
                      ButtonSegment(
                        value: HabitTrackingType.binary,
                        label: Text('Binary'),
                      ),
                      ButtonSegment(
                        value: HabitTrackingType.quantitative,
                        label: Text('Amount'),
                      ),
                    ],
                    selected: {_trackingType},
                    onSelectionChanged: (selection) {
                      setState(() => _trackingType = selection.first);
                    },
                  ),
                  if (_trackingType == HabitTrackingType.quantitative) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _targetController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Daily target',
                            ),
                            validator: _validateTarget,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedPreset,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                            ),
                            items: [
                              ..._unitPresets.map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              ),
                              const DropdownMenuItem(
                                value: _customPreset,
                                child: Text(_customPreset),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedPreset = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_selectedPreset == _customPreset) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _customUnitController,
                        decoration: const InputDecoration(
                          labelText: 'Custom unit',
                          hintText: 'e.g. glasses, sessions',
                        ),
                        maxLength: 20,
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              required maxLength,
                            }) => null,
                        validator: (value) {
                          if (_selectedPreset != _customPreset) return null;
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const _SectionLabel('Repeat'),
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
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<bool>(
                      style: _segmentedStyle(theme),
                      segments: const [
                        ButtonSegment(value: true, label: Text('Every day')),
                        ButtonSegment(
                          value: false,
                          label: Text('Specific days'),
                        ),
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
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
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
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          _weekdayErrorText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const _SectionLabel('Minimum version'),
                  const SizedBox(height: 2),
                  Text(
                    'An easier version for difficult days (optional)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _minimumVersionController,
                    decoration: const InputDecoration(
                      labelText: 'Minimum version (optional)',
                      hintText: '5 minutes of stretching',
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: _save,
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small centered drag handle shown at the top of a bottom sheet.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: AppRadii.pillRadius,
        ),
      ),
    );
  }
}

/// Bold, small section heading used above a form group.
class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// Rounded, softly-tinted container grouping related form fields.
class _FormSection extends StatelessWidget {
  final Widget child;

  const _FormSection({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadii.largeRadius,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: child,
    );
  }
}

/// Tappable scheduled-time row, replacing the old default ListTile.
class _ScheduledTimeRow extends StatelessWidget {
  final String time;
  final VoidCallback onTap;

  const _ScheduledTimeRow({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.mediumRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.access_time, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scheduled time', style: theme.textTheme.bodyMedium),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
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
      borderRadius: AppRadii.mediumRadius,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : null,
          borderRadius: AppRadii.mediumRadius,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
