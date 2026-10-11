import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// Inbox for the admin and the helpdesk (incharge).
///
///  * Complaints      - addressed to the admin (admin inbox) or to the incharge
///                      (helpdesk inbox). Reply and set a status; the student
///                      sees it live. Complaints addressed to Faculty are kept
///                      and shown to nobody until the faculty dashboard exists.
///  * Ride requests   - a student asking to ride another route for a day.
///                      Approve or reject. Approved ones show to that driver.
///  * Absences        - students who will not board (read only).
///  * Driver issues   - admin only. Reply and resolve; the driver sees it.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late final TabController _tabs =
      TabController(length: widget.isAdmin ? 4 : 3, vsync: this);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _complaints = [];
  List<Map<String, dynamic>> _rides = [];
  List<Map<String, dynamic>> _absences = [];
  List<Map<String, dynamic>> _issues = [];
  String _filter = 'active'; // active | resolved | all
  RealtimeChannel? _channel;

  static const _categories = <String, String>{
    'driver_behavior': 'Driver Behavior',
    'delay': 'Bus Delay',
    'cleanliness': 'Cleanliness',
    'safety': 'Safety',
    'route_issue': 'Route Issue',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
  }

  @override
  void dispose() {
    if (_channel != null) _sb.removeChannel(_channel!);
    _tabs.dispose();
    super.dispose();
  }

  void _listen() {
    var ch = _sb.channel('inbox_${widget.isAdmin ? 'admin' : 'helpdesk'}');
    for (final table in [
      'complaints',
      'one_day_requests',
      'attendance_notifications',
      if (widget.isAdmin) 'driver_issues',
    ]) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _load(silent: true),
      );
    }
    _channel = ch.subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final c = await _sb.rpc('inbox_complaints');
      final r = await _sb.rpc('inbox_ride_requests');
      final a = await _sb.rpc('inbox_absences');
      var i = <dynamic>[];
      if (widget.isAdmin) i = await _sb.rpc('inbox_driver_issues') as List;

      if (!mounted) return;
      setState(() {
        _complaints = List<Map<String, dynamic>>.from(c as List);
        _rides = List<Map<String, dynamic>>.from(r as List);
        _absences = List<Map<String, dynamic>>.from(a as List);
        _issues = List<Map<String, dynamic>>.from(i);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) return; // a quiet refresh never replaces the screen with an error
      setState(() {
        _error = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Ym.red : Ym.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _err(Object e) => e is PostgrestException ? e.message : e.toString();

  // ───────────────────────── reply sheet ─────────────────────────

  Future<void> _reply({
    required String title,
    required String subtitle,
    required String detail,
    required String status,
    required String? response,
    required List<(String, String)> statuses,
    required Future<void> Function(String status, String reply) onSave,
  }) async {
    final text = TextEditingController(text: response ?? '');
    var chosen = status;
    var saving = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4.5,
                    decoration: BoxDecoration(
                        color: Ym.line, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(title, style: Ym.h(19)),
                const SizedBox(height: 3),
                Text(subtitle, style: Ym.t(12.5, color: Ym.grey)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Ym.creamTop,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(detail, style: Ym.t(13.5)),
                ),
                const SizedBox(height: 16),
                Text('Status', style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in statuses)
                      ChoiceChip(
                        label: Text(s.$2),
                        selected: chosen == s.$1,
                        selectedColor: Ym.amber.withOpacity(0.3),
                        onSelected: (_) => setSheet(() => chosen = s.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: text,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Your reply (the sender will see it)',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: const Color(0xFFF8F9FB),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: Ym.t(12.5, color: Ym.red)),
                  ),
                const SizedBox(height: 14),
                YmButton(
                  label: 'Save and notify',
                  icon: Icons.send_rounded,
                  loading: saving,
                  onPressed: () async {
                    setSheet(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await onSave(chosen, text.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setSheet(() {
                        error = _err(e);
                        saving = false;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    text.dispose();
  }

  Future<void> _openComplaint(Map<String, dynamic> c) async {
    await _reply(
      title: _categories[c['category']] ?? 'Complaint',
      subtitle:
          '${c['from_parent'] == true ? 'Parent of ' : ''}${c['student_name'] ?? 'A student'}'
          '${c['from_parent'] == true && (c['parent_name'] ?? '').toString().isNotEmpty ? '  (${c['parent_name']})' : ''}'
          '${c['route_name'] != null ? '  •  ${c['route_name']}' : ''}'
          '${c['bus_number'] != null ? '  •  ${c['bus_number']}' : ''}',
      detail: c['description']?.toString() ?? '',
      status: c['status']?.toString() ?? 'open',
      response: c['response']?.toString(),
      statuses: const [
        ('open', 'Open'),
        ('in_progress', 'In progress'),
        ('resolved', 'Resolved'),
      ],
      onSave: (status, reply) async {
        await _sb.rpc('respond_complaint', params: {
          'p_id': c['id'],
          'p_status': status,
          'p_response': reply,
        });
        _snack('Saved. The student has been told.');
        await _load(silent: true);
      },
    );
  }

  Future<void> _openIssue(Map<String, dynamic> i) async {
    await _reply(
      title: 'Driver issue: ${i['type'] ?? 'issue'}',
      subtitle:
          'Driver ${i['driver_name'] ?? '-'}${i['bus_number'] != null ? '  •  Bus ${i['bus_number']}' : ''}',
      detail: i['description']?.toString() ?? '',
      status: i['status']?.toString() ?? 'open',
      response: i['response']?.toString(),
      statuses: const [('open', 'Open'), ('resolved', 'Resolved')],
      onSave: (status, reply) async {
        await _sb.rpc('respond_driver_issue', params: {
          'p_id': i['id'],
          'p_status': status,
          'p_response': reply,
        });
        _snack('Saved. The driver has been told.');
        await _load(silent: true);
      },
    );
  }

  Future<void> _answerRide(Map<String, dynamic> r, bool approve) async {
    try {
      await _sb.rpc('respond_ride_request',
          params: {'p_id': r['id'], 'p_approve': approve});
      _snack(approve ? 'Approved. The driver and student were told.' : 'Declined.');
      await _load(silent: true);
    } catch (e) {
      _snack(_err(e), error: true);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  bool _matches(String status) {
    if (_filter == 'all') return true;
    if (_filter == 'resolved') return status == 'resolved';
    return status != 'resolved';
  }

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: widget.isAdmin ? 'Inbox' : 'Help Desk Inbox',
      subtitle: 'Complaints, requests and reports',
      child: _loading
          ? const YmSkeletonList(count: 4, height: 110)
          : _error != null
              ? YmEmpty(
                  icon: Icons.error_outline_rounded,
                  color: Ym.red,
                  title: 'Could not load the inbox',
                  subtitle: _error,
                  action: YmButton(
                      label: 'Try again',
                      expanded: false,
                      icon: Icons.refresh_rounded,
                      onPressed: _load),
                )
              : Column(
                  children: [
                    TabBar(
                      controller: _tabs,
                      labelColor: Ym.navy,
                      unselectedLabelColor: Ym.grey,
                      indicatorColor: Ym.amberDark,
                      isScrollable: true,
                      labelStyle: Ym.t(13, w: FontWeight.w800),
                      tabs: [
                        Tab(text: 'Complaints (${_complaints.where((c) => c['status'] != 'resolved').length})'),
                        Tab(text: 'Ride requests (${_rides.where((r) => r['status'] == 'pending').length})'),
                        Tab(text: 'Absences (${_absences.length})'),
                        if (widget.isAdmin)
                          Tab(text: 'Driver issues (${_issues.where((i) => i['status'] != 'resolved').length})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _complaintsTab(),
                          _ridesTab(),
                          _absencesTab(),
                          if (widget.isAdmin) _issuesTab(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _filterRow() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(
          children: [
            for (final f in const [
              ('active', 'Active'),
              ('resolved', 'Resolved'),
              ('all', 'All'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.$2),
                  selected: _filter == f.$1,
                  selectedColor: Ym.amber.withOpacity(0.3),
                  onSelected: (_) => setState(() => _filter = f.$1),
                ),
              ),
          ],
        ),
      );

  Widget _list(List<Widget> items, String empty) => RefreshIndicator(
        color: Ym.amber,
        onRefresh: () => _load(silent: true),
        child: items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  YmEmpty(
                      icon: Icons.inbox_rounded,
                      title: empty,
                      subtitle: 'New items appear here by themselves.'),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                children: items,
              ),
      );

  (String, Color) _statusChip(String s) => switch (s) {
        'resolved' => ('Resolved', Ym.green),
        'in_progress' => ('In progress', Ym.amberDark),
        'approved' => ('Approved', Ym.green),
        'rejected' => ('Declined', Ym.grey),
        'pending' => ('Pending', Ym.amberDark),
        _ => ('Open', Ym.red),
      };

  Widget _complaintsTab() {
    final items = _complaints
        .where((c) => _matches(c['status']?.toString() ?? 'open'))
        .toList();
    return Column(
      children: [
        _filterRow(),
        Expanded(
          child: _list([
            for (var i = 0; i < items.length; i++)
              YmFadeSlide(index: i, child: _complaintCard(items[i])),
          ], 'No complaints here'),
        ),
      ],
    );
  }

  Widget _complaintCard(Map<String, dynamic> c) {
    final (label, color) = _statusChip(c['status']?.toString() ?? 'open');
    final at = parseUtc(c['created_at']);
    final replied = (c['response'] ?? '').toString().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        onTap: () => _openComplaint(c),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      c['from_parent'] == true
                          ? 'Parent of ${c['student_name'] ?? 'a student'}'
                          : (c['student_name']?.toString() ?? 'A student'),
                      style: Ym.h(15)),
                ),
                YmChip(label, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                YmChip(_categories[c['category']] ?? 'Other', color: Ym.blue),
                if (c['from_parent'] == true)
                  const YmChip('Parent',
                      color: Ym.green, icon: Icons.family_restroom_rounded),
                if (c['route_name'] != null)
                  YmChip(c['route_name'].toString(), color: Ym.purple),
              ],
            ),
            const SizedBox(height: 8),
            Text(c['description']?.toString() ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Ym.t(13, color: Ym.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                if (at != null)
                  Text('${fmtDate(at)}  •  ${fmtClock(at)}',
                      style: Ym.t(11, color: Ym.grey)),
                const Spacer(),
                if (replied)
                  Row(
                    children: [
                      const Icon(Icons.reply_rounded, size: 14, color: Ym.green),
                      const SizedBox(width: 4),
                      Text('Replied',
                          style: Ym.t(11.5, color: Ym.green, w: FontWeight.w700)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ridesTab() {
    return _list([
      for (var i = 0; i < _rides.length; i++)
        YmFadeSlide(index: i, child: _rideCard(_rides[i])),
    ], 'No ride requests');
  }

  Widget _rideCard(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? 'pending';
    final (label, color) = _statusChip(status);
    final date = DateTime.tryParse('${r['ride_date']}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r['student_name']?.toString() ?? 'A student',
                      style: Ym.h(15)),
                ),
                YmChip(label, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Wants to ride ${r['route_name'] ?? 'a route'}'
              '${date != null ? ' on ${fmtDate(date)}' : ''}',
              style: Ym.t(13, color: Ym.grey),
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: YmButton(
                      label: 'Approve',
                      icon: Icons.check_rounded,
                      color: Ym.green,
                      onPressed: () => _answerRide(r, true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: YmButton(
                      label: 'Decline',
                      outline: true,
                      onPressed: () => _answerRide(r, false),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _absencesTab() {
    return _list([
      for (var i = 0; i < _absences.length; i++)
        YmFadeSlide(
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: YmCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const YmIconBadge(
                      icon: Icons.event_busy_rounded, color: Ym.purple, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_absences[i]['student_name']?.toString() ?? '',
                            style: Ym.h(14.5)),
                        Text(
                          [
                            if (DateTime.tryParse('${_absences[i]['absent_date']}') != null)
                              fmtDate(DateTime.parse('${_absences[i]['absent_date']}')),
                            if (_absences[i]['route_name'] != null)
                              _absences[i]['route_name'].toString(),
                          ].join('  •  '),
                          style: Ym.t(12, color: Ym.grey),
                        ),
                        if ((_absences[i]['reason'] ?? '').toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(_absences[i]['reason'].toString(),
                                style: Ym.t(12.5)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ], 'No upcoming absences');
  }

  Widget _issuesTab() {
    final items = _issues
        .where((i) => _matches(i['status']?.toString() ?? 'open'))
        .toList();
    return Column(
      children: [
        _filterRow(),
        Expanded(
          child: _list([
            for (var i = 0; i < items.length; i++)
              YmFadeSlide(index: i, child: _issueCard(items[i])),
          ], 'No driver issues'),
        ),
      ],
    );
  }

  Widget _issueCard(Map<String, dynamic> i) {
    final (label, color) = _statusChip(i['status']?.toString() ?? 'open');
    final at = parseUtc(i['created_at']);
    final type = i['type']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        onTap: () => _openIssue(i),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '${type == null || type.isEmpty ? 'Issue' : type[0].toUpperCase() + type.substring(1)}'
                      ' • ${i['driver_name'] ?? ''}',
                      style: Ym.h(15)),
                ),
                YmChip(label, color: color),
              ],
            ),
            if (i['bus_number'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Bus ${i['bus_number']}', style: Ym.t(12, color: Ym.grey)),
              ),
            const SizedBox(height: 8),
            Text(i['description']?.toString() ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Ym.t(13, color: Ym.grey)),
            if (at != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${fmtDate(at)}  •  ${fmtClock(at)}',
                    style: Ym.t(11, color: Ym.grey)),
              ),
          ],
        ),
      ),
    );
  }
}