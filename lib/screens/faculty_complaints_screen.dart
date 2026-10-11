import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

const _categories = <String, (String, IconData)>{
  'driver_behavior': ('Driver behaviour', Icons.person_pin_rounded),
  'delay': ('Bus delay', Icons.schedule_rounded),
  'cleanliness': ('Cleanliness', Icons.cleaning_services_rounded),
  'safety': ('Safety', Icons.shield_rounded),
  'route_issue': ('Route or stop', Icons.alt_route_rounded),
  'other': ('Other', Icons.more_horiz_rounded),
};

/// Complaints for the faculty member to look at.
///   * sent to "Faculty": every faculty member of that route sees it; any can reply
///   * sent to "In-charge": only the in-charge of the route sees it, follows it up
///     and resolves it
/// The student (or parent) sees the status and the reply, and gets an alert.
class FacultyComplaintsScreen extends StatefulWidget {
  const FacultyComplaintsScreen({super.key, required this.isIncharge});

  final bool isIncharge;

  @override
  State<FacultyComplaintsScreen> createState() => _FacultyComplaintsScreenState();
}

class _FacultyComplaintsScreenState extends State<FacultyComplaintsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  bool _showDone = false;
  RealtimeChannel? _chan;

  @override
  void initState() {
    super.initState();
    _load();
    final uid = _sb.auth.currentUser?.id;
    if (uid != null) {
      // a new complaint arrives as an alert: refresh the list
      _chan = _sb
          .channel('faculty_complaints_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq, column: 'recipient_id', value: uid),
            callback: (_) {
              if (mounted) _load(silent: true);
            },
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _chan?.unsubscribe();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _sb.rpc('faculty_inbox_complaints') as List;
      if (!mounted) return;
      setState(() {
        _items = [for (final r in rows) Map<String, dynamic>.from(r as Map)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  ({String label, Color color}) _status(String s) {
    switch (s) {
      case 'resolved':
        return (label: 'Resolved', color: Ym.green);
      case 'in_progress':
        return (label: 'Looking into it', color: Ym.blue);
      default:
        return (label: 'Open', color: Ym.amberDark);
    }
  }

  Future<void> _open(Map<String, dynamic> c) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReplySheet(item: c),
    );
    if (changed == true) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final open = _items.where((c) => c['status'] != 'resolved').toList();
    final done = _items.where((c) => c['status'] == 'resolved').toList();
    final list = _showDone ? done : open;

    return YmPage(
      title: 'Complaints',
      subtitle: widget.isIncharge
          ? 'For faculty and for you as in-charge'
          : 'Sent to faculty on your route',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                _tab('Open (${open.length})', !_showDone, () => setState(() => _showDone = false)),
                const SizedBox(width: 8),
                _tab('Resolved (${done.length})', _showDone, () => setState(() => _showDone = true)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 4, height: 110),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load complaints',
                        subtitle: _error,
                        action: YmButton(
                            label: 'Try again',
                            icon: Icons.refresh_rounded,
                            expanded: false,
                            onPressed: _load),
                      )
                    : RefreshIndicator(
                        color: Ym.amber,
                        onRefresh: _load,
                        child: list.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 50),
                                  YmEmpty(
                                    icon: _showDone
                                        ? Icons.history_rounded
                                        : Icons.sentiment_satisfied_rounded,
                                    color: _showDone ? Ym.grey : Ym.green,
                                    title: _showDone ? 'Nothing resolved yet' : 'No open complaints',
                                    subtitle: _showDone
                                        ? 'Complaints you resolve are listed here.'
                                        : 'Complaints from students of your route appear here.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                                itemCount: list.length,
                                itemBuilder: (_, i) => YmFadeSlide(
                                  index: i > 6 ? 6 : i,
                                  child: _tile(list[i]),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String text, bool on, VoidCallback onTap) => YmPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: on ? const LinearGradient(colors: [Ym.amber, Ym.amberDark]) : null,
            color: on ? null : Colors.white,
            boxShadow: Ym.shadow(Ym.navy, 0.06),
          ),
          child: Text(text,
              style: Ym.t(12.5, color: on ? Ym.navy : Ym.grey, w: FontWeight.w800)),
        ),
      );

  Widget _tile(Map<String, dynamic> c) {
    final cat = _categories[c['category']?.toString()] ?? ('Other', Icons.more_horiz_rounded);
    final st = _status((c['status'] ?? 'open').toString());
    final at = parseUtc(c['created_at']);
    final onlyMe = c['send_to'] == 'incharge';
    final who = c['from_parent'] == true
        ? 'Parent of ${c['student_name'] ?? 'a student'}'
        : (c['student_name'] ?? 'A student').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        onTap: () => _open(c),
        padding: const EdgeInsets.all(16),
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                YmIconBadge(icon: cat.$2, color: st.color, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(who, style: Ym.h(14.5)),
                      Text(
                          [
                            cat.$1,
                            if ((c['route_name'] ?? '').toString().isNotEmpty)
                              c['route_name'].toString(),
                          ].join('  •  '),
                          style: Ym.t(11.5, color: Ym.grey)),
                    ],
                  ),
                ),
                YmChip(st.label, color: st.color),
              ],
            ),
            const SizedBox(height: 10),
            Text((c['description'] ?? '').toString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Ym.t(13, color: const Color(0xFF374151)).copyWith(height: 1.45)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (onlyMe)
                const YmChip('Only the in-charge sees this',
                    color: Ym.purple, icon: Icons.lock_outline_rounded),
              if (at != null)
                YmChip('${fmtDate(at)}  ${fmtClock(at)}',
                    color: Ym.grey, icon: Icons.schedule_rounded),
            ]),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── reply sheet ─────────────────────────

class _ReplySheet extends StatefulWidget {
  const _ReplySheet({required this.item});

  final Map<String, dynamic> item;

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _sb = Supabase.instance.client;
  late final TextEditingController _reply =
      TextEditingController(text: (widget.item['response'] ?? '').toString());
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get c => widget.item;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _save(String status) async {
    if (status == 'resolved' && _reply.text.trim().isEmpty) {
      setState(() => _error = 'Please write a short reply before resolving, so the student knows what was done.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _sb.rpc('respond_complaint_faculty', params: {
        'p_id': c['id'],
        'p_status': status,
        'p_response': _reply.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is PostgrestException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _categories[c['category']?.toString()] ?? ('Other', Icons.more_horiz_rounded);
    final at = parseUtc(c['created_at']);
    final resolved = c['status'] == 'resolved';
    final who = c['from_parent'] == true
        ? 'Parent of ${c['student_name'] ?? 'a student'}'
        : (c['student_name'] ?? 'A student').toString();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  decoration:
                      BoxDecoration(color: Ym.line, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                YmIconBadge(icon: cat.$2, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(who, style: Ym.h(17)),
                      Text(cat.$1, style: Ym.t(12.5, color: Ym.grey)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Text((c['description'] ?? '').toString(),
                  style: Ym.t(14, color: const Color(0xFF374151)).copyWith(height: 1.5)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if ((c['route_name'] ?? '').toString().isNotEmpty)
                  YmChip(c['route_name'].toString(), color: Ym.navy, icon: Icons.alt_route_rounded),
                if ((c['bus_number'] ?? '').toString().isNotEmpty)
                  YmChip(c['bus_number'].toString(), color: Ym.navy, icon: Icons.directions_bus_rounded),
                if (at != null)
                  YmChip('${fmtDate(at)}  ${fmtClock(at)}', color: Ym.grey, icon: Icons.schedule_rounded),
              ]),
              const SizedBox(height: 16),
              Text('Your reply',
                  style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _reply,
                maxLines: 4,
                maxLength: 400,
                style: Ym.t(14),
                decoration: InputDecoration(
                  hintText: 'What will be done, or what was done',
                  hintStyle: Ym.t(13, color: Ym.grey),
                  filled: true,
                  fillColor: Ym.creamTop,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: Ym.t(12.5, color: Ym.red)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: YmButton(
                      label: 'Looking into it',
                      outline: true,
                      onPressed: _busy ? null : () => _save('in_progress'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: YmButton(
                      label: resolved ? 'Update' : 'Resolve',
                      icon: Icons.check_rounded,
                      loading: _busy,
                      onPressed: () => _save('resolved'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}