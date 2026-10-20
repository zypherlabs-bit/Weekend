import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/weekend_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/weekend_design_system.dart';
import '../../widgets/weekend_empty_state.dart';

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weekendProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Weekend Plans',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showCreatePlanDialog(context, ref),
            icon: const Icon(Icons.add_rounded),
            color: theme.colorScheme.primary,
            tooltip: 'Create plan',
          ),
        ],
      ),
      body: state.plans.isEmpty
          ? WeekendEmptyState(
              icon: Icons.calendar_today_rounded,
              title: 'No Plans Yet',
              subtitle:
                  'Create your first weekend plan and invite people to join!',
              actionLabel: 'Create Plan',
              onAction: () => _showCreatePlanDialog(context, ref),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(WeekendSpacing.lg),
              itemCount: state.plans.length,
              itemBuilder: (context, index) {
                final plan = state.plans[index];
                return _PlanCard(plan: plan);
              },
            ),
    );
  }

  void _showCreatePlanDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final venueController = TextEditingController();
    final timeController = TextEditingController();
    final descriptionController = TextEditingController();
    String category = 'Coffee';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          return WeekendGlassDialog(
            title: 'Create Weekend Plan',
            icon: Icons.calendar_today_rounded,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WeekendGlassTextField(
                  controller: titleController,
                  label: 'Title',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  dropdownColor: theme.colorScheme.surface,
                  items:
                      [
                            'Coffee',
                            'Dinner',
                            'Hiking',
                            'Concert',
                            'Movies',
                            'Travel',
                            'Sports',
                            'Art',
                            'Gaming',
                            'Events',
                          ]
                          .map(
                            (cat) =>
                                DropdownMenuItem(value: cat, child: Text(cat)),
                          )
                          .toList(),
                  onChanged: (value) => setState(() => category = value!),
                ),
                const SizedBox(height: 12),
                WeekendGlassTextField(
                  controller: venueController,
                  label: 'Venue',
                ),
                const SizedBox(height: 12),
                WeekendGlassTextField(
                  controller: timeController,
                  label: 'Time',
                ),
                const SizedBox(height: 12),
                WeekendGlassTextField(
                  controller: descriptionController,
                  label: 'Description',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              WeekendGlassButton(
                label: 'Create',
                expanded: false,
                onPressed: () {
                  if (titleController.text.trim().isEmpty) return;
                  ref
                      .read(weekendProvider.notifier)
                      .createPlan(
                        titleController.text.trim(),
                        category,
                        venueController.text.trim(),
                        timeController.text.trim(),
                        descriptionController.text.trim(),
                      );
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final WeekendPlan plan;

  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: WeekendSpacing.md),
      child: WeekendGlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plan.creatorPhoto.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(WeekendRadius.xl),
                ),
                child: Image.network(
                  plan.creatorPhoto,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(WeekendSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          plan.category,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (plan.isJoined)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.onlineGreen.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Joined',
                            style: TextStyle(
                              color: AppTheme.onlineGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    plan.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PlanMeta(
                    icon: Icons.location_on_rounded,
                    text: plan.venue,
                  ),
                  const SizedBox(height: 4),
                  _PlanMeta(
                    icon: Icons.access_time_rounded,
                    text: plan.time,
                  ),
                  if (plan.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      plan.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.person_rounded, size: 16, color: secondary),
                      const SizedBox(width: 8),
                      Text(
                        'by ${plan.creatorName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                      const Spacer(),
                      if (plan.participants.isNotEmpty)
                        Text(
                          '${plan.participants.length} joined',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: Consumer(
                      builder: (context, ref, _) => ElevatedButton(
                        onPressed: () => ref
                            .read(weekendProvider.notifier)
                            .togglePlanJoin(plan.id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: plan.isJoined
                              ? theme.colorScheme.surfaceContainerHighest
                              : theme.colorScheme.primary,
                          foregroundColor: plan.isJoined
                              ? theme.colorScheme.onSurface
                              : Colors.white,
                        ),
                        child: Text(plan.isJoined ? 'Leave Plan' : 'Join Plan'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PlanMeta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
