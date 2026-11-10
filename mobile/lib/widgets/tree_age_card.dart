import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart';

typedef AgeLookup = Future<Map<String, dynamic>> Function(
    String species, double? dbh, double? height, String source);

/// Display only. Never writes age, dates or predicted sizes to inventory.
class TreeAgeCard extends StatefulWidget {
  final String scientificName;
  final double? dbhCm;
  final double? heightM;
  final String dimensionsSource;
  final AgeLookup? lookup;
  const TreeAgeCard(
      {super.key,
      required this.scientificName,
      this.dbhCm,
      this.heightM,
      this.dimensionsSource = 'ai_prediction',
      this.lookup});

  @override
  State<TreeAgeCard> createState() => _TreeAgeCardState();
}

class _TreeAgeCardState extends State<TreeAgeCard> {
  Map<String, dynamic>? _result;
  bool _loading = false;
  bool _failed = false;
  String _failureMessage = 'Age estimate unavailable. Check your connection.';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TreeAgeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scientificName != widget.scientificName ||
        oldWidget.dbhCm != widget.dbhCm ||
        oldWidget.heightM != widget.heightM ||
        oldWidget.dimensionsSource != widget.dimensionsSource) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
      _result = null;
    });
    try {
      final result = await (widget.lookup ?? api.estimateTreeAge)(
          widget.scientificName,
          widget.dbhCm,
          widget.heightM,
          widget.dimensionsSource);
      if (mounted && request == _request) setState(() => _result = result);
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _failed = true;
          _failureMessage = error is DioException &&
                  (error.response?.statusCode == 402 ||
                      error.response?.statusCode == 429)
              ? 'AI age estimate limit reached. Try again later.'
              : error is DioException && error.response?.statusCode == 401
                  ? 'Sign in again to estimate age.'
                  : 'Age estimate unavailable. Check your connection.';
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimated = _result?['status'] == 'estimated';
    final source = _result?['source'];
    final aiGrowth = _result?['estimation_basis'] == 'ai_growth_guess';
    final rates = _result?['growth_rates'];
    final dbhAge = ageDimension(_result?['dbh_age_years']);
    final heightAge = ageDimension(_result?['height_age_years']);
    final primaryAge = dbhAge ?? heightAge;
    final disagrees = _result?['dimensions_disagree'] == true;
    return Card(
      key: const Key('tree-age-card'),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estimated age',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (_loading)
                const Text('Checking growth data and estimating age…')
              else if (_failed) ...[
                Text(_failureMessage),
                TextButton(
                    onPressed: _load, child: const Text('Retry age estimate')),
              ] else ...[
                Text(
                    aiGrowth
                        ? 'AI growth estimate — source unverified'
                        : source is Map
                            ? 'Published growth data'
                            : 'Growth data unavailable',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    estimated && primaryAge != null
                        ? primaryAge < 1
                            ? 'Less than 1 year (estimated)'
                            : 'About ${primaryAge.round()} ${primaryAge.round() == 1 ? 'year' : 'years'} (estimated)'
                        : estimated
                            ? 'Approximately ${_result!['min_years']}–${_result!['max_years']} years'
                            : 'Age unknown',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                if (estimated && primaryAge != null)
                  Text(dbhAge != null
                      ? 'Based on DBH and this species’ diameter growth rate. Height is a cross-check.'
                      : 'Based on height and this species’ height growth rate; no DBH age calculation is available.'),
                if (estimated && disagrees)
                  const Text(
                      'Height and DBH checks disagree. This age estimate is highly uncertain.'),
                if (dbhAge != null || heightAge != null)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Calculation details'),
                    children: [
                      if (dbhAge != null)
                        Text(
                            'From DBH: about ${_result!['dbh_age_years']} years'),
                      if (heightAge != null)
                        Text(
                            'From height: about ${_result!['height_age_years']} years'),
                    ],
                  ),
                Text(_result?['reason']?.toString() ??
                    'No growth data available.'),
                if (rates is Map) ...[
                  if (rates['dbh_cm_per_year'] is List)
                    Text(
                        'Diameter growth: ${_rate(rates['dbh_cm_per_year'])} cm/year'),
                  if (rates['height_m_per_year'] is List)
                    Text(
                        'Height growth: ${_rate(rates['height_m_per_year'])} m/year'),
                ],
                if (_result?['assumptions'] is String)
                  Text(_result!['assumptions'] as String),
                if (aiGrowth && !estimated)
                  TextButton(
                      onPressed: _load,
                      child: const Text('Retry age estimate')),
                if (source is Map) ...[
                  const SizedBox(height: 8),
                  Text('Source: ${source['citation']}'),
                  Text(source['context']?.toString() ?? ''),
                  TextButton(
                      onPressed: () async {
                        final uri =
                            Uri.tryParse(source['url']?.toString() ?? '');
                        if (uri != null && uri.scheme == 'https') {
                          await Clipboard.setData(
                              ClipboardData(text: uri.toString()));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Study link copied. Open it in your browser.')));
                          }
                        }
                      },
                      child: const Text('Copy growth study link')),
                  SelectableText(source['url']?.toString() ?? ''),
                ],
              ],
            ],
          )),
    );
  }

  String _rate(List values) {
    if (values.length != 3 || values.any((v) => v is! num)) {
      return 'Unavailable';
    }
    final low = (values.first as num).toStringAsFixed(2);
    final high = (values.last as num).toStringAsFixed(2);
    return low == high ? low : '$low–$high';
  }
}

double? ageDimension(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite && number > 0 ? number : null;
}
