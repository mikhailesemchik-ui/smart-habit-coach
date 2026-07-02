import 'package:flutter/material.dart';

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
  final AiWeeklyReviewSource? service;

  const WeeklyReviewSheet({
    super.key,
    required this.localReview,
    required this.metrics,
    this.service,
  });

  @override
  State<WeeklyReviewSheet> createState() => _WeeklyReviewSheetState();
}

class _WeeklyReviewSheetState extends State<WeeklyReviewSheet> {
  late final AiWeeklyReviewSource _service =
      widget.service ?? AiWeeklyReviewService();

  _ReviewStatus _status = _ReviewStatus.loading;
  AiWeeklyReview? _aiReview;
  String _fallbackNotice = _defaultFallbackNotice;
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _loadAiReview();
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
