import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimated = _result?['status'] == 'estimated';
    final source = _result?['source'];
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
                const Text('Checking published growth data…')
              else if (_failed) ...[
                const Text('Age estimate unavailable. Check your connection.'),
                TextButton(
                    onPressed: _load, child: const Text('Retry age estimate')),
              ] else ...[
                Text(estimated
                    ? 'Approximately ${_result!['min_years']}–${_result!['max_years']} years'
                    : 'Age unknown'),
                if (_result?['dbh_age_years'] != null)
                  Text('From DBH: about ${_result!['dbh_age_years']} years'),
                if (_result?['height_age_years'] != null)
                  Text(
                      'From height: about ${_result!['height_age_years']} years'),
                Text(_result?['reason']?.toString() ??
                    'No growth data available.'),
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
}

double? ageDimension(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite && number > 0 ? number : null;
}
