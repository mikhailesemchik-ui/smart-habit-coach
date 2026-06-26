import 'package:flutter/material.dart';

import '../data/ai_weekly_review_service.dart';
import '../domain/ai_weekly_review.dart';
import '../domain/ai_weekly_review_exception.dart';
import '../domain/ai_weekly_review_source.dart';
import '../domain/weekly_review.dart';

enum _ReviewStatus { loading, success, error }

const _defaultFallbackNotice =
    "Showing your local weekly review — AI insights aren't available right now.";

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
            Text('Weekly review', style: theme.textTheme.titleLarge),
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
    final metrics = widget.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isSuccess ? aiReview.summary : widget.localReview.summary,
          style: theme.textTheme.bodyLarge,
        ),
        if (metrics.strongestDay != null) ...[
          const SizedBox(height: 16),
          Text('Strongest day', style: theme.textTheme.titleSmall),
          Text(metrics.strongestDay!, style: theme.textTheme.bodyLarge),
          if (isSuccess) ...[
            const SizedBox(height: 4),
            Text(aiReview.strongestInsight, style: theme.textTheme.bodyMedium),
          ],
        ],
        if (metrics.weakestDay != null) ...[
          const SizedBox(height: 16),
          Text('Weakest day', style: theme.textTheme.titleSmall),
          Text(metrics.weakestDay!, style: theme.textTheme.bodyLarge),
          if (isSuccess) ...[
            const SizedBox(height: 4),
            Text(aiReview.weakestInsight, style: theme.textTheme.bodyMedium),
          ],
        ],
        const SizedBox(height: 16),
        Text('Recommendation', style: theme.textTheme.titleSmall),
        Text(
          isSuccess
              ? aiReview.recommendation
              : widget.localReview.recommendation,
          style: theme.textTheme.bodyLarge,
        ),
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
