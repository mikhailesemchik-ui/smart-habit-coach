import 'package:flutter/material.dart';

class OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;

  const OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

const onboardingPages = [
  OnboardingPageData(
    icon: Icons.self_improvement,
    title: 'Build better habits',
    description: 'Create simple daily habits and stay consistent with ease.',
  ),
  OnboardingPageData(
    icon: Icons.bar_chart,
    title: 'Track your progress',
    description: 'See your streaks and weekly completion rate at a glance.',
  ),
  OnboardingPageData(
    icon: Icons.auto_awesome,
    title: 'Get smart suggestions',
    description: 'Describe a goal and get a ready-made habit to start with.',
  ),
];
