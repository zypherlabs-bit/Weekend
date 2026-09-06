import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/weekend_provider.dart';
import '../../models/models.dart';

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weekendProvider);
    
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF130E20),
        elevation: 0,
        title: const Text(
          'Weekend Plans',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showCreatePlanDialog(context, ref),
            icon: const Icon(Icons.add_rounded, color: Color(0xFFFF4B72)),
          ),
        ],
      ),
      body: state.plans.isEmpty
          ? _EmptyState(
              icon: Icons.calendar_today_rounded,
              title: 'No Plans Yet',
              subtitle: 'Create your first weekend plan and invite people to join!',
              actionLabel: 'Create Plan',
              onAction: () => _showCreatePlanDialog(context, ref),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
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
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1C162E),
          title: const Text('Create Weekend Plan', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                  dropdownColor: const Color(0xFF2E244A),
                  style: const TextStyle(color: Colors.white),
                  items: ['Coffee', 'Dinner', 'Hiking', 'Concert', 'Movies', 'Travel', 'Sports', 'Art', 'Gaming', 'Events']
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                      .toList(),
                  onChanged: (value) => setState(() => category = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: venueController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Venue',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Time',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                ref.read(weekendProvider.notifier).createPlan(
                  titleController.text.trim(),
                  category,
                  venueController.text.trim(),
                  timeController.text.trim(),
                  descriptionController.text.trim(),
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4B72)),
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final WeekendPlan plan;

  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C162E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              image: DecorationImage(
                image: NetworkImage(plan.creatorPhoto.isNotEmpty ? plan.creatorPhoto : ''),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4B72).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        plan.category,
                        style: const TextStyle(
                          color: Color(0xFFFF9966),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (plan.isJoined)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Joined',
                          style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  plan.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFFF9966)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        plan.venue,
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFFFF9966)),
                    const SizedBox(width: 4),
                    Text(
                      plan.time,
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                    ),
                  ],
                ),
                if (plan.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    plan.description,
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.person_rounded, size: 16, color: Colors.white60),
                    const SizedBox(width: 8),
                    Text(
                      'by ${plan.creatorName}',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                    ),
                    const Spacer(),
                    if (plan.participants.isNotEmpty)
                      Text(
                        '${plan.participants.length} joined',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Toggle plan join
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: plan.isJoined
                          ? const Color(0xFF2E244A)
                          : const Color(0xFFFF4B72),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(plan.isJoined ? 'Leave Plan' : 'Join Plan'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4B72).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: const Color(0xFFFF4B72)),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4B72),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
