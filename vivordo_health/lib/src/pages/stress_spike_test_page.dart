import 'dart:async';
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

  // Timer/stopwatch for visible LLM execution time
  Stopwatch? _stopwatch;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  String? _friendlyOutput;
  String? _jsonOutput;
  String? _error;

  // ---- History ----
  final List<_RunRecord> _history = [];
  static const int _maxHistory = 10;

  // ---- Timer helpers ----
  void _startTimer() {
    _stopwatch = Stopwatch()..start();
    _elapsed = Duration.zero;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = _stopwatch?.elapsed ?? Duration.zero;
      });
    });
  }

  void _stopTimer() {
    _stopwatch?.stop();
    _timer?.cancel();
    _timer = null;

    if (!mounted) return;
    setState(() {
      _elapsed = _stopwatch?.elapsed ?? _elapsed;
    });
  }

  String _formatDuration(Duration d) {
    final seconds = (d.inMilliseconds / 1000.0).toStringAsFixed(2);
    return "$seconds s";
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final min = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return "$y-$m-$d  $hour12:$min $ampm";
  }

  // ---- Main action ----
  Future<void> _runTest() async {
    final startedAt = DateTime.now();
    int? spikeCount;
    bool success = false;
    String? historyError;

    setState(() {
      _loading = true;
      _friendlyOutput = null;
      _jsonOutput = null;
      _error = null;
    });

    _startTimer();

    try {
      final sampleData = _service.getSampleData();

      final raw = await _service
          .analyzeStressSpikes(
            data: sampleData,
            extraUserContext: _contextController.text,
          )
          .timeout(const Duration(seconds: 30));
      final raw = await _service
          .analyzeStressSpikes(
            data: sampleData,
            extraUserContext: _contextController.text,
          )
          .timeout(const Duration(seconds: 30));

      final decoded = _tryDecodeJson(raw);

      if (decoded == null) {
        historyError = "Could not parse JSON (possibly code-fenced or malformed).";
        setState(() {
          _friendlyOutput = "Could not parse JSON. Model returned:\n\n$raw";
          _jsonOutput = raw;
        });
      } else {
        final prettyJson = const JsonEncoder.withIndent('  ').convert(decoded);
        final friendly = _buildFriendlySpikeMessages(decoded);

        // spikeCount for history
        final spikes = decoded["spikes"];
        if (spikes is List) spikeCount = spikes.length;

        success = true;

        setState(() {
          _friendlyOutput = friendly.isEmpty
              ? "No spikes detected in this window."
              : friendly.join("\n\n");
          _jsonOutput = prettyJson;
        });
      }
    } on TimeoutException {
      historyError = "Request timed out after 30 seconds.";
      setState(() {
        _error = "Request timed out after 30 seconds.";
      });
    } catch (e) {
      historyError = e.toString();
      historyError = e.toString();
      setState(() => _error = e.toString());
    } finally {
      _stopTimer();
      final duration = _elapsed;

      // push history record
      _addHistory(
        _RunRecord(
          startedAt: startedAt,
          duration: duration,
          spikeCount: spikeCount,
          success: success,
          error: historyError,
          contextSnippet: _contextController.text.trim().isEmpty
              ? null
              : _contextController.text.trim(),
        ),
      );

      if (mounted) setState(() => _loading = false);
    }
  }

  void _addHistory(_RunRecord record) {
    if (!mounted) return;
    setState(() {
      _history.insert(0, record);
      if (_history.length > _maxHistory) {
        _history.removeRange(_maxHistory, _history.length);
      }
    });
  }

  void _clearHistory() {
    setState(() {
      _history.clear();
    });
  }

  // ---- JSON parsing helpers ----
  Map<String, dynamic>? _tryDecodeJson(String text) {
    try {
      var cleaned = text.trim();

      // Strip markdown code fences if present: ```json ... ```
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceFirst(RegExp(r'^```[a-zA-Z]*'), '')
            .replaceFirst(RegExp(r'```$'), '')
            .trim();
      }
      // Strip markdown code fences if present: ```json ... ```
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
      final obj = jsonDecode(cleaned);
      if (obj is Map<String, dynamic>) return obj;
      return null;
    } catch (e) {
      debugPrint('JSON parse error: $e');
      return null;
    }
  }

  // ---- Friendly output generation ----
  List<String> _buildFriendlySpikeMessages(Map<String, dynamic> decoded) {
    final spikes = decoded["spikes"];
    if (spikes is! List) return [];
  // ---- Friendly output generation ----
  List<String> _buildFriendlySpikeMessages(Map<String, dynamic> decoded) {
    final spikes = decoded["spikes"];
    if (spikes is! List) return [];

    final messages = <String>[];
    final messages = <String>[];

    for (final spike in spikes) {
      if (spike is! Map) continue;
    for (final spike in spikes) {
      if (spike is! Map) continue;

      final startIso = spike["start"]?.toString();
      final endIso = spike["end"]?.toString();
      final timePhrase = _formatTimeRange(startIso, endIso);
      final startIso = spike["start"]?.toString();
      final endIso = spike["end"]?.toString();
      final timePhrase = _formatTimeRange(startIso, endIso);

      // Top hypothesis
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
      // Top hypothesis
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

      // Nearby events (fallback)
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
      // Nearby events (fallback)
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

      final buffer = StringBuffer();
      final buffer = StringBuffer();

      if (hypothesisLabel == "exercise") {
        buffer.write(
          "You had a peak in your stress-related signals around $timePhrase, "
          "which looks most consistent with exercise (elevated heart rate and activity). "
          "Did this feel like normal exertion, or did something stressful happen too?",
        );
      } else {
        buffer.write("You had a stressful period with peak signals around $timePhrase");
      if (hypothesisLabel == "exercise") {
        buffer.write(
          "You had a peak in your stress-related signals around $timePhrase, "
          "which looks most consistent with exercise (elevated heart rate and activity). "
          "Did this feel like normal exertion, or did something stressful happen too?",
        );
      } else {
        buffer.write("You had a stressful period with peak signals around $timePhrase");

        if (hypothesisReason != null && hypothesisReason.isNotEmpty) {
          buffer.write(", which may be related to $hypothesisReason");
        } else if (nearbyEvents.isNotEmpty) {
          buffer.write(", possibly related to ${nearbyEvents.join(' or ')}");
        }
        if (hypothesisReason != null && hypothesisReason.isNotEmpty) {
          buffer.write(", which may be related to $hypothesisReason");
        } else if (nearbyEvents.isNotEmpty) {
          buffer.write(", possibly related to ${nearbyEvents.join(' or ')}");
        }

        buffer.write(". What was happening then?");
      }
        buffer.write(". What was happening then?");
      }

      messages.add(buffer.toString());
    }
      messages.add(buffer.toString());
    }

    return messages;
  }

  String _formatTimeRange(String? startIso, String? endIso) {
    try {
      if (startIso == null) return "an unknown time";
    return messages;
  }

  String _formatTimeRange(String? startIso, String? endIso) {
    try {
      if (startIso == null) return "an unknown time";

      final start = DateTime.parse(startIso).toLocal();
      final startStr = _formatTime(start);
      final start = DateTime.parse(startIso).toLocal();
      final startStr = _formatTime(start);

      if (endIso == null) return startStr;
      if (endIso == null) return startStr;

      final end = DateTime.parse(endIso).toLocal();
      final endStr = _formatTime(end);
      final end = DateTime.parse(endIso).toLocal();
      final endStr = _formatTime(end);

      return "$startStr–$endStr";
    } catch (_) {
      return "an unknown time";
    }
  }
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
  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return "$hour:$minute $period";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch?.stop();
    _contextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stress Spike Test'),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Test"),
              Tab(text: "History"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTestTab(context),
            _buildHistoryTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTestTab(BuildContext context) {
    final errorText = _error;

    return SafeArea(
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

            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _loading ? "LLM Execution Time: " : "Last LLM Time: ",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _formatDuration(_elapsed),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: _loading ? Colors.deepPurple : Colors.black87,
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(width: 10),
                  const Text(
                    "(running...)",
                    style: TextStyle(color: Colors.deepPurple),
                  ),
                ],
              ],
            ),
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

            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _loading ? "LLM Execution Time: " : "Last LLM Time: ",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _formatDuration(_elapsed),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: _loading ? Colors.deepPurple : Colors.black87,
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(width: 10),
                  const Text(
                    "(running...)",
                    style: TextStyle(color: Colors.deepPurple),
                  ),
                ],
              ],
            ),

            if (errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                errorText,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            if (errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                errorText,
                style: const TextStyle(color: Colors.red),
              ),
            ],

            const SizedBox(height: 12),
            const SizedBox(height: 12),

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
    );
  }

  Widget _buildHistoryTab(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Recent Runs (latest first)",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                TextButton(
                  onPressed: _history.isEmpty ? null : _clearHistory,
                  child: const Text("Clear"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _history.isEmpty
                  ? const Center(
                      child: Text(
                        "No history yet.\nRun the test to see entries here.",
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final r = _history[index];

                        final statusText = r.success ? "Success" : "Failed";
                        final statusColor =
                            r.success ? Colors.green : Colors.red;

                        final spikesText = r.spikeCount == null
                            ? "Spikes: —"
                            : "Spikes: ${r.spikeCount}";

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatDateTime(r.startedAt),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                          color: statusColor.withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    "Time: ${_formatDuration(r.duration)}",
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Text(spikesText),
                                ],
                              ),
                              if (r.contextSnippet != null &&
                                  r.contextSnippet!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  "Context: ${r.contextSnippet}",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                              if (!r.success && r.error != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  "Error: ${r.error}",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
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

class _RunRecord {
  _RunRecord({
    required this.startedAt,
    required this.duration,
    required this.success,
    this.spikeCount,
    this.error,
    this.contextSnippet,
  });

  final DateTime startedAt;
  final Duration duration;
  final bool success;
  final int? spikeCount;
  final String? error;
  final String? contextSnippet;
}
