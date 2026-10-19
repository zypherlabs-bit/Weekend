import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../repositories/engagement_repository.dart';

/// In-app support backed by real `support_tickets` rows (migration 033).
///
/// A ticket appears in "My tickets" only after the server returned the
/// inserted row — there is no optimistic "submitted" state, so the list can
/// never show something that was not actually persisted. Safety and scam
/// reports are prioritised by the server, which the ticket's own priority
/// column then reports back.
class SupportDialog extends StatefulWidget {
  const SupportDialog({super.key});

  @override
  State<SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<SupportDialog> {
  final SupportRepository _repository = SupportRepository();

  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  static const _categories = <(String, String)>[
    ('question', 'Question about the app'),
    ('safety', 'Safety concern'),
    ('scam', 'Report a scam'),
    ('technical', 'Technical problem'),
    ('other', 'Something else'),
  ];

  String _category = 'question';

  List<SupportTicket> _tickets = const [];
  bool _loadingTickets = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    final tickets = await _repository.fetchMyTickets();
    if (!mounted) return;
    setState(() {
      _tickets = tickets;
      _loadingTickets = false;
    });
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final details = _detailsController.text.trim();
    if (subject.isEmpty || details.isEmpty) return;
    setState(() => _submitting = true);
    // Returns the persisted ticket or null; anything null means the server
    // refused and the user is told, with their text preserved for a retry.
    final ticket = await _repository.submitTicket(
      category: _category,
      subject: subject,
      details: details,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ticket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your report could not be submitted. Shorten the text and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    _subjectController.clear();
    _detailsController.clear();
    setState(() {
      _tickets = [ticket, ..._tickets];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ticket received — status: ${ticket.status}'
          '${ticket.priority == 'high' ? ' (marked high priority)' : ''}.',
        ),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return const Color(0xFF4CAF50);
      case 'in_progress':
        return const Color(0xFFFF9966);
      case 'high':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1C162E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Support',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Reports reach the Weekend moderations team; safety and scam '
              'reports are handled first.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF2E244A),
              initialValue: _category,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Category',
                filled: true,
                fillColor: Color(0xFF2E244A),
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                for (final (value, label) in _categories)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _category = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _subjectController,
              maxLength: 80,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Subject',
                counterStyle: TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Color(0xFF2E244A),
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _detailsController,
              maxLength: 1000,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'What happened?',
                counterStyle: TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Color(0xFF2E244A),
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _submitting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: () {
                        final subject = _subjectController.text.trim();
                        final details = _detailsController.text.trim();
                        if (subject.isEmpty || details.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Add a subject and describe what happened.'),
                            ),
                          );
                          return;
                        }
                        _submit();
                      },
                      child: const Text('Send report',
                          style: TextStyle(color: Color(0xFFFF9966))),
                    ),
            ),
            const Divider(color: Colors.white10),
            Text(
              _loadingTickets
                  ? 'Checking your previous reports…'
                  : _tickets.isEmpty
                      ? 'No support tickets yet.'
                      : 'Your tickets (${_tickets.length})',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            for (final ticket in _tickets.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  ticket.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(
                  '${ticket.category} · '
                  '${DateTime.fromMillisecondsSinceEpoch(ticket.createdAtMs).toLocal().toString().split(' ').first}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: Text(
                  ticket.status,
                  style: TextStyle(
                      color: _statusColor(ticket.status), fontSize: 12),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close',
                    style: TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
