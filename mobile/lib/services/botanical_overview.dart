/// Returns botanical prose suitable for the scanner's Overview tab.
///
/// Provider diagnostics and technical fallback messages are deliberately
/// replaced with a neutral fallback rather than exposed as species facts.
String botanicalOverviewDescription(Object? value) {
  const fallback =
      'A detailed description of this tree species is not yet available.';

  if (value is! String) return fallback;
  final description = value.trim();
  if (description.isEmpty || description.toLowerCase() == 'null') {
    return fallback;
  }

  final normalized = description.toLowerCase();
  const technicalMarkers = [
    'plantnet',
    'gemini',
    'anthropic',
    'openai',
    'roboflow',
    'vision enrichment',
    'identified using',
    'fallback',
    'backend',
    'provider',
    'api error',
    'error:',
    'http error',
    'service unavailable',
    'temporarily unavailable',
    'request failed',
    'failed to',
    'identification failed',
    'traceback',
    'exception:',
  ];
  if (technicalMarkers.any(normalized.contains)) return fallback;

  return description;
}
