import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/ym_ui.dart';

/// Monthly report for the admin.
///
/// For the chosen month, for every route: how many trips ran, on how many days
/// the bus was in service, how long a trip took, and how many issues, breakdowns,
/// SOS alerts, absences and complaints there were. All of it comes from the app's
/// own records (`admin_month_report`), nothing needs the GPS hardware.
/// The report can be downloaded as a PDF.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _sb = Supabase.instance.client;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _institution = '';
  Map<String, dynamic>? _r;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  String get _monthLabel => '${_months[_month.month - 1]} ${_month.year}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in.');
      final inst = await _sb
          .from('institutions')
          .select('name')
          .eq('admin_id', uid)
          .maybeSingle();

      final first =
          '${_month.year}-${_month.month.toString().padLeft(2, '0')}-01';
      final res = await _sb.rpc('admin_month_report', params: {
        'p_month': first,
        'p_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      });

      if (!mounted) return;
      setState(() {
        _institution = (inst?['name'] ?? '').toString();
        _r = Map<String, dynamic>.from(res as Map);
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

  void _shiftMonth(int by) {
    setState(() => _month = DateTime(_month.year, _month.month + by));
    _load();
  }

  List<Map<String, dynamic>> get _routes => [
        for (final x in (_r?['routes'] as List? ?? []))
          Map<String, dynamic>.from(x as Map),
      ];

  Map<String, dynamic> get _totals =>
      Map<String, dynamic>.from((_r?['totals'] as Map?) ?? {});

  // ───────────────────────── text + PDF ─────────────────────────

  String _summaryText() {
    final t = _totals;
    final days = _n(_r?['days_in_month']);
    final b = StringBuffer()
      ..writeln('Monthly transport report - $_monthLabel')
      ..writeln(_institution)
      ..writeln()
      ..writeln('Trips: ${_n(t['completed'])} completed of ${_n(t['trips'])}')
      ..writeln('Days in service: ${_n(t['service_days'])} of $days')
      ..writeln('Issues reported: ${_n(t['issues'])} (breakdowns: ${_n(t['breakdowns'])})')
      ..writeln('SOS alerts: ${_n(t['sos'])}')
      ..writeln('Student absences: ${_n(t['absences'])}')
      ..writeln('Complaints: ${_n(t['complaints'])}')
      ..writeln();
    for (final r in _routes) {
      b.writeln('${r['route_name']} (Bus ${r['bus_number'] ?? '-'}): '
          '${_n(r['trips'])} trips, ${_n(r['days_run'])} of $days days, '
          '${_n(r['issues'])} issues, ${_n(r['sos'])} SOS, '
          '${_n(r['absences'])} absences, ${_n(r['complaints'])} complaints');
    }
    return b.toString();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _summaryText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Report summary copied'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<Uint8List> _buildPdf() async {
    const navy = PdfColor.fromInt(0xFF0F1B4D);
    const amber = PdfColor.fromInt(0xFFFFC21E);
    const cream = PdfColor.fromInt(0xFFFFF8EC);
    const grey = PdfColor.fromInt(0xFF6B7390);
    final t = _totals;
    final days = _n(_r?['days_in_month']);

    pw.Widget cell(String text, {bool head = false, pw.TextAlign align = pw.TextAlign.center}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: pw.Text(text,
              textAlign: align,
              style: pw.TextStyle(
                  fontSize: head ? 8.5 : 9,
                  fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: head ? PdfColors.white : navy)),
        );

    pw.Widget stat(String label, String value) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: cream,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: amber, width: 1),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold, color: navy)),
                pw.SizedBox(height: 2),
                pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: grey)),
              ],
            ),
          ),
        );

    final doc = pw.Document(title: 'Monthly transport report', author: 'Yatra Mitra');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: const pw.BoxDecoration(
              color: navy,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('MONTHLY TRANSPORT REPORT',
                        style: pw.TextStyle(
                            fontSize: 16,
                            color: amber,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.5)),
                    pw.SizedBox(height: 3),
                    pw.Text(_institution,
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
                  ],
                ),
                pw.Text(_monthLabel,
                    style: pw.TextStyle(
                        fontSize: 15,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              stat('Trips completed', '${_n(t['completed'])} / ${_n(t['trips'])}'),
              stat('Days in service', '${_n(t['service_days'])} of $days'),
              stat('Issues reported', '${_n(t['issues'])}'),
              stat('Breakdowns', '${_n(t['breakdowns'])}'),
              stat('SOS alerts', '${_n(t['sos'])}'),
              stat('Absences', '${_n(t['absences'])}'),
              stat('Complaints', '${_n(t['complaints'])}'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('Route by route',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: navy)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E0D6), width: 0.6),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.2),
              1: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: navy),
                children: [
                  cell('Route', head: true, align: pw.TextAlign.left),
                  cell('Bus', head: true),
                  cell('Students', head: true),
                  cell('Trips', head: true),
                  cell('Days run', head: true),
                  cell('Avg trip (min)', head: true),
                  cell('Issues', head: true),
                  cell('Breakdowns', head: true),
                  cell('SOS', head: true),
                  cell('Absences', head: true),
                  cell('Complaints', head: true),
                ],
              ),
              for (final r in _routes)
                pw.TableRow(
                  children: [
                    cell('${r['route_name'] ?? ''}', align: pw.TextAlign.left),
                    cell('${r['bus_number'] ?? '-'}'),
                    cell('${_n(r['students'])}'),
                    cell('${_n(r['completed'])} / ${_n(r['trips'])}'),
                    cell('${_n(r['days_run'])} / $days'),
                    cell(r['avg_minutes'] == null ? '-' : '${_n(r['avg_minutes'])}'),
                    cell('${_n(r['issues'])}'),
                    cell('${_n(r['breakdowns'])}'),
                    cell('${_n(r['sos'])}'),
                    cell('${_n(r['absences'])}'),
                    cell('${_n(r['complaints'])}'),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
              'Trips are shown as completed / started. Days run are the days the bus '
              'made at least one trip. Generated from the Yatra Mitra records.',
              style: const pw.TextStyle(fontSize: 8, color: grey)),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> _downloadPdf() async {
    if (_r == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'transport-report-${_month.year}-${_month.month.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not make the report: $e'),
          backgroundColor: Ym.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Monthly Report',
      subtitle: 'Trips, days run and issues per route',
      child: Column(
        children: [
          _monthBar(),
          Expanded(
            child: _loading
                ? const YmSkeletonList(count: 4, height: 110)
                : _error != null
                    ? YmEmpty(
                        icon: Icons.error_outline_rounded,
                        color: Ym.red,
                        title: 'Could not load the report',
                        subtitle: _error,
                        action: YmButton(
                            label: 'Try again',
                            expanded: false,
                            icon: Icons.refresh_rounded,
                            onPressed: _load),
                      )
                    : RefreshIndicator(
                        color: Ym.amber,
                        onRefresh: _load,
                        child: _body(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _monthBar() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: Ym.shadow(Ym.navy, 0.06),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: Ym.navy),
                onPressed: () => _shiftMonth(-1),
              ),
              Expanded(
                child: Text(_monthLabel,
                    textAlign: TextAlign.center, style: Ym.h(17)),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right_rounded,
                    color: _isCurrentMonth ? Ym.line : Ym.navy),
                onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
              ),
            ],
          ),
        ),
      );

  Widget _body() {
    final t = _totals;
    final days = _n(_r?['days_in_month']);
    final routes = _routes;
    final daily = [
      for (final x in (_r?['daily'] as List? ?? [])) Map<String, dynamic>.from(x as Map),
    ];
    final types = [
      for (final x in (_r?['issue_types'] as List? ?? [])) Map<String, dynamic>.from(x as Map),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
      children: [
        YmFadeSlide(
          index: 0,
          child: Row(
            children: [
              _stat('${_n(t['completed'])}/${_n(t['trips'])}', 'Trips done',
                  Icons.route_rounded, Ym.blue),
              const SizedBox(width: 10),
              _stat('${_n(t['service_days'])}/$days', 'Days in service',
                  Icons.calendar_month_rounded, Ym.green),
              const SizedBox(width: 10),
              _stat('${_n(t['issues'])}', 'Issues',
                  Icons.warning_amber_rounded, Ym.amberDark),
            ],
          ),
        ),
        const SizedBox(height: 10),
        YmFadeSlide(
          index: 1,
          child: Row(
            children: [
              _stat('${_n(t['sos'])}', 'SOS alerts', Icons.warning_rounded, Ym.red),
              const SizedBox(width: 10),
              _stat('${_n(t['absences'])}', 'Absences',
                  Icons.event_busy_rounded, Ym.purple),
              const SizedBox(width: 10),
              _stat('${_n(t['complaints'])}', 'Complaints',
                  Icons.mail_outline_rounded, const Color(0xFF0EA5E9)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        YmFadeSlide(index: 2, child: _dailyCard(daily)),
        const SizedBox(height: 16),
        YmFadeSlide(index: 3, child: _daysCard(routes, days)),
        const SizedBox(height: 16),
        YmFadeSlide(index: 4, child: _issuesCard(types)),
        const SizedBox(height: 24),
        const YmSectionTitle('Route by route'),
        if (routes.isEmpty)
          YmCard(
              child: Text('No routes yet.', style: Ym.t(13.5, color: Ym.grey)))
        else
          for (var i = 0; i < routes.length; i++)
            YmFadeSlide(
                index: i > 6 ? 6 : i, child: _routeCard(routes[i], days)),
        const SizedBox(height: 10),
        YmButton(
          label: 'Download report (PDF)',
          icon: Icons.download_rounded,
          loading: _busy,
          onPressed: _downloadPdf,
        ),
        const SizedBox(height: 10),
        YmButton(
          label: 'Copy summary',
          icon: Icons.copy_rounded,
          outline: true,
          onPressed: _copy,
        ),
      ],
    );
  }

  Widget _stat(String value, String label, IconData icon, Color color) => Expanded(
        child: YmCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          radius: 20,
          child: Column(
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(height: 6),
              Text(value, style: Ym.h(19)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Ym.t(10.5, color: Ym.grey)),
            ],
          ),
        ),
      );

  // trips per day, as bars
  Widget _dailyCard(List<Map<String, dynamic>> daily) {
    final maxTrips = daily.fold<int>(0, (m, d) => _n(d['trips']) > m ? _n(d['trips']) : m);
    return YmCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmIconBadge(icon: Icons.bar_chart_rounded, size: 40),
              const SizedBox(width: 10),
              Expanded(child: Text('Trips per day', style: Ym.h(15))),
              if (maxTrips > 0)
                YmChip('Most: $maxTrips in a day', color: Ym.amberDark),
            ],
          ),
          const SizedBox(height: 14),
          if (maxTrips == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('No trips this month.',
                      style: Ym.t(13, color: Ym.grey))),
            )
          else
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in daily)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: _n(d['trips']) == 0
                                  ? 3
                                  : 8 + 84.0 * _n(d['trips']) / maxTrips,
                              decoration: BoxDecoration(
                                gradient: _n(d['trips']) == 0
                                    ? null
                                    : const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Ym.amber, Ym.amberDark],
                                      ),
                                color: _n(d['trips']) == 0 ? Ym.line : null,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              height: 12,
                              child: (_n(d['day']) == 1 || _n(d['day']) % 5 == 0)
                                  ? FittedBox(
                                      child: Text('${_n(d['day'])}',
                                          style: Ym.t(9, color: Ym.grey)))
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // days in service per route, as bars
  Widget _daysCard(List<Map<String, dynamic>> routes, int days) {
    return YmCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmIconBadge(
                  icon: Icons.calendar_month_rounded, color: Ym.green, size: 40),
              const SizedBox(width: 10),
              Expanded(child: Text('Days in service', style: Ym.h(15))),
              YmChip('of $days days', color: Ym.grey),
            ],
          ),
          const SizedBox(height: 14),
          if (routes.isEmpty)
            Text('No routes yet.', style: Ym.t(13, color: Ym.grey))
          else
            for (final r in routes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${r['route_name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ym.t(12.5, w: FontWeight.w700)),
                        ),
                        Text('${_n(r['days_run'])} days',
                            style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        children: [
                          Container(height: 10, color: Ym.line),
                          FractionallySizedBox(
                            widthFactor: days == 0
                                ? 0
                                : (_n(r['days_run']) / days).clamp(0.0, 1.0),
                            child: Container(
                              height: 10,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                    colors: [Ym.green, Color(0xFF34D399)]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // issues by type
  Widget _issuesCard(List<Map<String, dynamic>> types) {
    final total = types.fold<int>(0, (a, x) => a + _n(x['count']));
    Color colorOf(String t) => switch (t) {
          'breakdown' => Ym.red,
          'accident' => Ym.red,
          'delay' => Ym.amberDark,
          _ => Ym.purple,
        };
    return YmCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmIconBadge(
                  icon: Icons.warning_amber_rounded, color: Ym.red, size: 40),
              const SizedBox(width: 10),
              Expanded(child: Text('Issues reported by drivers', style: Ym.h(15))),
              YmChip('$total', color: total == 0 ? Ym.green : Ym.red),
            ],
          ),
          const SizedBox(height: 14),
          if (types.isEmpty)
            Text('No issues were reported this month.',
                style: Ym.t(13, color: Ym.green, w: FontWeight.w600))
          else
            for (final x in types)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              '${x['type']}'.isEmpty
                                  ? 'Other'
                                  : '${x['type']}'[0].toUpperCase() +
                                      '${x['type']}'.substring(1),
                              style: Ym.t(12.5, w: FontWeight.w700)),
                        ),
                        Text('${_n(x['count'])}',
                            style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        children: [
                          Container(height: 10, color: Ym.line),
                          FractionallySizedBox(
                            widthFactor:
                                total == 0 ? 0 : (_n(x['count']) / total).clamp(0.0, 1.0),
                            child: Container(
                                height: 10, color: colorOf('${x['type']}')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _metric(String value, String label, {Color? color}) => Expanded(
        child: Column(
          children: [
            Text(value, style: Ym.h(17, color: color ?? Ym.navy)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: Ym.t(10.5, color: Ym.grey)),
          ],
        ),
      );

  Widget _routeCard(Map<String, dynamic> r, int days) {
    final issues = _n(r['issues']);
    final run = _n(r['days_run']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const YmIconBadge(icon: Icons.directions_bus_rounded, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['route_name'] ?? ''}', style: Ym.h(15.5)),
                      const SizedBox(height: 2),
                      Text(
                        run == 0
                            ? 'No trips this month'
                            : 'Ran $run of $days days, ${_n(r['trips'])} trips',
                        style: Ym.t(12, color: Ym.grey),
                      ),
                    ],
                  ),
                ),
                if (r['bus_number'] != null)
                  YmChip('${r['bus_number']}',
                      color: Ym.navy, icon: Icons.directions_bus_rounded),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _metric('${_n(r['completed'])}/${_n(r['trips'])}', 'Trips done'),
                _metric('$run', 'Days run'),
                _metric(r['avg_minutes'] == null ? '-' : '${_n(r['avg_minutes'])}',
                    'Avg trip (min)'),
                _metric('${_n(r['students'])}', 'Students'),
              ],
            ),
            const Divider(height: 24, color: Ym.line),
            Row(
              children: [
                _metric('$issues', 'Issues',
                    color: issues > 0 ? Ym.amberDark : Ym.navy),
                _metric('${_n(r['breakdowns'])}', 'Breakdowns',
                    color: _n(r['breakdowns']) > 0 ? Ym.red : Ym.navy),
                _metric('${_n(r['sos'])}', 'SOS',
                    color: _n(r['sos']) > 0 ? Ym.red : Ym.navy),
                _metric('${_n(r['absences'])}', 'Absences'),
                _metric('${_n(r['complaints'])}', 'Complaints'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}