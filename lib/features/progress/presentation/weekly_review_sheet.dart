import 'package:flutter/material.dart';
import 'package:smart_habit_coach/features/coach/presentation/adaptive_coach_card.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../../coach/data/adaptive_coach_service.dart';
import '../../coach/domain/adaptive_apply_eligibility.dart';
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

  /// Called immediately after a habit is successfully persisted here
  /// (direct Apply or a successful Adjust-manually edit), so the caller
  /// (e.g. ProgressScreen) can update its own in-memory habit list without
  /// requiring the screen to be recreated.
  final ValueChanged<Habit>? onHabitUpdated;

  const WeeklyReviewSheet({
    super.key,
    required this.localReview,
    required this.metrics,
    this.habits = const [],
    this.service,
    this.coachService,
    this.habitStorage,
    this.onHabitUpdated,
  });

  @override
  State<WeeklyReviewSheet> createState() => _WeeklyReviewSheetState();
}

class _WeeklyReviewSheetState extends State<WeeklyReviewSheet> {
  late final AiWeeklyReviewSource _service =
      widget.service ?? AiWeeklyReviewService();
  late final AdaptiveCoachService _coachService =
      widget.coachService ?? AdaptiveCoachService(habitStorage: _habitStorage);
  late final HabitStorage _habitStorage = widget.habitStorage ?? HabitStorage();

  _ReviewStatus _status = _ReviewStatus.loading;
  AiWeeklyReview? _aiReview;
  String _fallbackNotice = _defaultFallbackNotice;
  bool _isFetching = false;

  PendingCoachSuggestion? _coachSuggestion;
  bool _isApplying = false;

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

    final stamped = await _persistHabit(updatedHabit);
    await _coachService.setStatus(
      current.suggestion,
      AdaptiveSuggestionStatus.adjusted,
    );
    if (!mounted) return;
    widget.onHabitUpdated?.call(stamped);
    setState(() => _coachSuggestion = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Habit plan updated')));
  }

  Future<void> _applySuggestion() async {
    if (_isApplying) return;
    final current = _coachSuggestion;
    if (current == null) return;

    setState(() => _isApplying = true);
    final outcome = await _coachService.applySuggestion(
      suggestion: current.suggestion,
      currentHabit: current.habit,
    );
    if (!mounted) return;

    switch (outcome.result) {
      case AdaptiveApplyResult.applied:
        widget.onHabitUpdated?.call(outcome.habit!);
        setState(() {
          _coachSuggestion = null;
          _isApplying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suggested target applied')),
        );
      case AdaptiveApplyResult.habitSaveFailed:
        setState(() => _isApplying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't update the habit. Try again."),
          ),
        );
      case AdaptiveApplyResult.suggestionSaveFailed:
        // Partial success: the habit was saved (so its target already
        // equals the proposal), but the suggestion status write failed.
        // Reflect the saved habit so eligibility re-evaluates Apply away,
        // preventing a duplicate write, while keeping the card visible.
        final updatedHabit = outcome.habit!;
        widget.onHabitUpdated?.call(updatedHabit);
        setState(() {
          _coachSuggestion = (
            suggestion: current.suggestion,
            habit: updatedHabit,
          );
          _isApplying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "The habit was updated, but the suggestion status couldn't "
              'be saved.',
            ),
          ),
        );
      case AdaptiveApplyResult.stale:
      case AdaptiveApplyResult.unsupported:
        setState(() => _isApplying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This suggestion needs review because the habit has changed.',
            ),
          ),
        );
    }
  }

  Future<Habit> _persistHabit(Habit habit) {
    return _habitStorage.upsertHabit(habit);
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: AppRadii.pillRadius,
                ),
              ),
            ),
            Text(
              'Weekly Review',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
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
            onApply:
                !_isApplying &&
                    isApplyEligible(
                      suggestion: _coachSuggestion!.suggestion,
                      habit: _coachSuggestion!.habit,
                    )
                ? _applySuggestion
                : null,
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

  IconData get _icon => switch (title) {
    'What went well' => Icons.check_circle_outline,
    'Partial progress' => Icons.trending_up,
    'Patterns noticed' => Icons.insights_outlined,
    'Focus for next week' => Icons.flag_outlined,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = items.isEmpty ? const ['No data available.'] : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final item in visibleItems) ...[
          Text(item, style: theme.textTheme.bodyMedium),
          if (item != visibleItems.last) const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}
