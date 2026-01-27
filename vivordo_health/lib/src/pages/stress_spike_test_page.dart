import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/gemini_service.dart';

class StressSpikeTestPage extends StatefulWidget {
  const StressSpikeTestPage({super.key});

  @override
  State<StressSpikeTestPage> createState() => _StressSpikeTestPageState();
}

class _StressSpikeTestPageState extends State<StressSpikeTestPage> {
  final _contextController = TextEditingController();
  final _service = GeminiService();

  bool _loading = false;

  String? _friendlyOutput;
  String? _jsonOutput;
  String? _error;

  Future<void> _runTest() async {
    setState(() {
      _loading = true;
      _friendlyOutput = null;
      _jsonOutput = null;
      _error = null;
    });

    try {
      final sampleData = _service.getSampleData();

      final raw = await _service.analyzeStressSpikes(
        data: sampleData,
        extraUserContext: _contextController.text,
      );

      // Try to decode JSON
      final decoded = _tryDecodeJson(raw);

      if (decoded == null) {
        // If model returned non-JSON, show raw output as error-ish
        setState(() {
          _friendlyOutput = "Could not parse JSON. Model returned:\n\n$raw";
          _jsonOutput = raw;
        });
      } else {
        // Prettify JSON
        final prettyJson = const JsonEncoder.withIndent('  ').convert(decoded);

        // Generate friendly message(s)
        final friendly = _buildFriendlySpikeMessages(decoded);

        setState(() {
          _friendlyOutput = friendly.isEmpty
              ? "No spikes detected in this window."
              : friendly.join("\n\n");
          _jsonOutput = prettyJson;
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

Map<String, dynamic>? _tryDecodeJson(String text) {
  try {
    // Remove Markdown code fences if present
    var cleaned = text.trim();

    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```[a-zA-Z]*'), '')
          .replaceFirst(RegExp(r'```$'), '')
          .trim();
    }

    final obj = jsonDecode(cleaned);
    if (obj is Map<String, dynamic>) return obj;
    return null;
  } catch (e) {
    debugPrint('JSON parse error: $e');
    return null;
  }
}


List<String> _buildFriendlySpikeMessages(Map<String, dynamic> decoded) {
  final spikes = decoded["spikes"];
  if (spikes is! List) return [];

  final messages = <String>[];

  for (final spike in spikes) {
    if (spike is! Map) continue;

    final startIso = spike["start"]?.toString();
    final endIso = spike["end"]?.toString();

    final timePhrase = _formatTimeRange(startIso, endIso);

    // Extract top hypothesis (if available)
    String? hypothesisLabel;
    String? hypothesisReason;

    final hypotheses = spike["hypotheses"];
    if (hypotheses is List && hypotheses.isNotEmpty) {
      final h = hypotheses.first;
      if (h is Map) {
        hypothesisLabel = h["label"]?.toString();
        hypothesisReason = h["reason"]?.toString();
      }
    }

    // Extract nearby events (if available)
    final nearbyEvents = <String>[];
    final context = spike["context"];
    if (context is Map) {
      final events = context["nearby_events"];
      if (events is List) {
        for (final e in events) {
          if (e is Map && e["detail"] != null) {
            nearbyEvents.add(e["detail"].toString());
          }
        }
      }
    }

    // Build relational sentence
    final buffer = StringBuffer();

    if (hypothesisLabel == "exercise") {
      buffer.write(
        "You had a period of elevated stress signals around $timePhrase, "
        "which appears to be related to physical activity (exercise). "
        "Did this feel like normal exertion or something more stressful?",
      );
    } else {
      buffer.write(
        "You had a stressful period around $timePhrase",
      );

      if (hypothesisReason != null && hypothesisReason.isNotEmpty) {
        buffer.write(", which may be related to $hypothesisReason");
      } else if (nearbyEvents.isNotEmpty) {
        buffer.write(", possibly related to ${nearbyEvents.join(' or ')}");
      }

      buffer.write(". What was happening at this time?");
    }

    messages.add(buffer.toString());
  }

  return messages;
}
String _formatTimeRange(String? startIso, String? endIso) {
  try {
    if (startIso == null) return "an unknown time";

    final start = DateTime.parse(startIso).toLocal();
    final startStr = _formatTime(start);

    if (endIso == null) return startStr;

    final end = DateTime.parse(endIso).toLocal();
    final endStr = _formatTime(end);

    return "$startStr–$endStr";
  } catch (_) {
    return "an unknown time";
  }
}

String _formatTime(DateTime dt) {
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return "$hour:$minute $period";
}


  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorText = _error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stress Spike Test'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _contextController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Optional context (for better questions)',
                  hintText: 'e.g., had a quiz at 9am, drank extra coffee...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _runTest,
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Text('Run Gemini on Sample Data'),
                ),
              ),

              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText,
                  style: const TextStyle(color: Colors.red),
                ),
              ],

              const SizedBox(height: 12),

              // NEW: Friendly output panel
              Expanded(
                child: Column(
                  children: [
                    _Panel(
                      title: "Friendly Output",
                      child: SelectableText(
                        _friendlyOutput ?? "Friendly summary will appear here.",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Panel(
                      title: "JSON Output",
                      child: SelectableText(
                        _jsonOutput ?? "JSON output will appear here.",
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(child: child),
            ),
          ],
        ),
      ),
    );
  }
}
