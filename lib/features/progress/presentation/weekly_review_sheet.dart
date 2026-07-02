import 'package:flutter/material.dart';
import 'package:smart_habit_coach/features/coach/presentation/adaptive_coach_card.dart';

import '../../coach/data/adaptive_coach_service.dart';
import '../../coach/domain/adaptive_suggestion.dart';
import '../../home/domain/habit.dart';
import '../../home/data/habit_storage.dart';
import '../../home/presentation/add_habit_sheet.dart';
import '../data/ai_weekly_review_service.dart';
import '../domain/ai_weekly_review.dart';
import '../domain/ai_weekly_review_exception.dart';
import '../domain/ai_weekly_review_source.dart';
import '../domain/weekly_review.dart';

enum _ReviewStatus { loading, success, error }

const _defaultFallbackNotice =
    "Showing your local weekly review - AI insights aren't available right now.";

class WeeklyReviewSheet extends StatefulWidget {
  final WeeklyReview localReview;
  final WeeklyReviewMetrics metrics;
  final List<Habit> habits;
  final AiWeeklyReviewSource? service;
  final AdaptiveCoachService? coachService;
  final HabitStorage? habitStorage;

  const WeeklyReviewSheet({
    super.key,
    required this.localReview,
    required this.metrics,
    this.habits = const [],
    this.service,
    this.coachService,
    this.habitStorage,
  });

  @override
  State<WeeklyReviewSheet> createState() => _WeeklyReviewSheetState();
}

class _WeeklyReviewSheetState extends State<WeeklyReviewSheet> {
  late final AiWeeklyReviewSource _service =
      widget.service ?? AiWeeklyReviewService();
  late final AdaptiveCoachService _coachService =
      widget.coachService ?? AdaptiveCoachService();
  late final HabitStorage _habitStorage = widget.habitStorage ?? HabitStorage();

  _ReviewStatus _status = _ReviewStatus.loading;
  AiWeeklyReview? _aiReview;
  String _fallbackNotice = _defaultFallbackNotice;
  bool _isFetching = false;

  PendingCoachSuggestion? _coachSuggestion;

  @override
  void initState() {
    super.initState();
    _loadAiReview();
    _loadCoachSuggestion();
  }

  // Runs independently of the AI review: a coach load/storage failure must
  // never trigger the AI fallback message, and vice versa.
  Future<void> _loadCoachSuggestion() async {
    final result = await _coachService.resolvePendingSuggestion(
      habits: widget.habits,
      now: DateTime.now(),
    );
    if (!mounted) return;
    setState(() => _coachSuggestion = result);
  }

  Future<void> _keepCurrentPlan() async {
    final current = _coachSuggestion;
    if (current == null) return;
    await _coachService.setStatus(
      current.suggestion,
      AdaptiveSuggestionStatus.kept,
    );
    if (!mounted) return;
    setState(() => _coachSuggestion = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Current plan kept')));
  }

  Future<void> _adjustManually() async {
    final current = _coachSuggestion;
    if (current == null) return;
    final updatedHabit = await showModalBottomSheet<Habit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddHabitSheet(initialHabit: current.habit),
    );
    if (updatedHabit == null || !mounted) return;

    await _persistHabit(updatedHabit);
    await _coachService.setStatus(
      current.suggestion,
      AdaptiveSuggestionStatus.adjusted,
    );
    if (!mounted) return;
    setState(() => _coachSuggestion = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Habit plan updated')));
  }

  Future<void> _persistHabit(Habit habit) async {
    final all = await _habitStorage.loadHabits() ?? [];
    final index = all.indexWhere((h) => h.id == habit.id);
    if (index >= 0) {
      all[index] = habit;
    } else {
      all.add(habit);
    }
    await _habitStorage.saveHabits(all);
  }

  Future<void> _loadAiReview() async {
    if (_isFetching) return;
    _isFetching = true;
    setState(() => _status = _ReviewStatus.loading);

    try {
      final aiReview = await _service.generateReview(widget.metrics);
      if (!mounted) return;
      setState(() {
        _aiReview = aiReview;
        _status = _ReviewStatus.success;
      });
    } on AiWeeklyReviewException catch (e) {
      if (!mounted) return;
      setState(() {
        _aiReview = null;
        _fallbackNotice = e.isQuotaExceeded
            ? e.message
            : _defaultFallbackNotice;
        _status = _ReviewStatus.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiReview = null;
        _fallbackNotice = _defaultFallbackNotice;
        _status = _ReviewStatus.error;
      });
    } finally {
      _isFetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weekly Review', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildBody(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_status == _ReviewStatus.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final aiReview = _aiReview;
    final isSuccess = _status == _ReviewStatus.success && aiReview != null;
    final whatWentWell = isSuccess
        ? aiReview.whatWentWell
        : widget.localReview.whatWentWell;
    final partialProgress = isSuccess
        ? aiReview.partialProgress
        : widget.localReview.partialProgress;
    final patterns = isSuccess
        ? aiReview.patterns
        : widget.localReview.patterns;
    final focusNextWeek = isSuccess
        ? aiReview.focusNextWeek
        : widget.localReview.focusNextWeek;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReviewSection(title: 'What went well', items: whatWentWell),
        const SizedBox(height: 16),
        _ReviewSection(title: 'Partial progress', items: partialProgress),
        const SizedBox(height: 16),
        _ReviewSection(title: 'Patterns noticed', items: patterns),
        const SizedBox(height: 16),
        _ReviewSection(title: 'Focus for next week', items: [focusNextWeek]),
        if (!isSuccess) ...[
          const SizedBox(height: 16),
          Text(
            _fallbackNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
        if (_coachSuggestion != null) ...[
          const SizedBox(height: 16),
          AdaptiveCoachCard(
            suggestion: _coachSuggestion!.suggestion,
            habit: _coachSuggestion!.habit,
            onKeep: _keepCurrentPlan,
            onAdjust: _adjustManually,
          ),
        ],
        const SizedBox(height: 24),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            if (!isSuccess)
              TextButton(onPressed: _loadAiReview, child: const Text('Retry')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final List<String> items;

  const _ReviewSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = items.isEmpty ? const ['No data available.'] : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final item in visibleItems) ...[
          Text(item, style: theme.textTheme.bodyMedium),
          if (item != visibleItems.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}
