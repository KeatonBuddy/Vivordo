import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/whoop_ble_heart_rate_service.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';
import 'package:vivordo_health/src/utils/heart_rate_zones.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/src/utils/smooth_chart_path.dart';

class HeartRateDetailScreen extends StatefulWidget {
  const HeartRateDetailScreen({super.key});

  @override
  State<HeartRateDetailScreen> createState() => _HeartRateDetailScreenState();
}

class _HeartRateDetailScreenState extends State<HeartRateDetailScreen> {
  static const red = Color(0xFFFF3B4E);
  static const purple = Color(0xFF5B42F3);
  int rangeIndex = 0;
  late final Future<QuerySnapshot<Map<String, dynamic>>> _heartDataFuture;

  @override
  void initState() {
    super.initState();
    WhoopBleHeartRateService.instance.startIfPaired();
    _heartDataFuture = _loadHeartData();
  }

  int get rangeDays => switch (rangeIndex) {
    0 => 1,
    1 => 7,
    _ => 30,
  };
  String get rangeName => switch (rangeIndex) {
    0 => 'Daily',
    1 => 'Weekly',
    _ => 'Monthly',
  };

  String keyFor(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<QuerySnapshot<Map<String, dynamic>>> _loadHeartData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to view heart-rate data.');
    // Persist any Bluetooth minute buckets collected before this screen opened
    // so the snapshot below includes the latest available graph history.
    await WhoopBleHeartRateService.instance.flush().catchError((Object _) {});
    final now = DateTime.now();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: keyFor(
            now.subtract(const Duration(days: 59)),
          ),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: keyFor(now))
        .orderBy(FieldPath.documentId)
        .get();
  }

  List<_HeartDay> allDays(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    return (snapshot?.docs ?? const []).map((doc) {
      final data = doc.data();
      final date = DateTime.parse(doc.id);
      final readings = mergedHeartRateHistory(data, fallbackDate: date)
          .map((reading) => _HeartReading(reading.bpm, reading.timestamp))
          .toList();
      final resting = ((data['resting_heart_rate'] as Map?)?['avg'] as num?)
          ?.toDouble();
      final heartHealth = data['heart_health'] as Map?;
      final heartHealthScore = (heartHealth?['avg'] as num?)?.toDouble();
      final heartHealthStatus = heartHealth?['status'] as String?;
      return _HeartDay(
        date,
        readings,
        resting,
        heartHealthScore,
        heartHealthStatus,
      );
    }).toList();
  }

  List<_HeartDay> currentDays(List<_HeartDay> all) {
    final byKey = {for (final day in all) keyFor(day.date): day};
    final today = DateUtils.dateOnly(DateTime.now());
    return List.generate(rangeDays, (index) {
      final date = today.subtract(Duration(days: rangeDays - index - 1));
      return byKey[keyFor(date)] ?? _HeartDay(date, const [], null, null, null);
    });
  }

  List<_HeartDay> previousDays(List<_HeartDay> all) {
    final end = DateUtils.dateOnly(
      DateTime.now(),
    ).subtract(Duration(days: rangeDays));
    final start = end.subtract(Duration(days: rangeDays));
    return all
        .where((day) => !day.date.isBefore(start) && day.date.isBefore(end))
        .toList();
  }

  double? average(Iterable<double> values) {
    final list = values.toList();
    return list.isEmpty ? null : list.reduce((a, b) => a + b) / list.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      appBar: AppBar(
        backgroundColor: context.vivordoColors.page,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: purple),
        ),
        title: const Text(
          'Heart Rate',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _heartDataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = allDays(snapshot.data);
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null) return const SizedBox.shrink();
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              final user = userSnapshot.data?.data();
              final hasConnectedWearable =
                  user?['whoopConnected'] == true ||
                  user?['fitbitConnected'] == true;
              return content(
                currentDays(all),
                previousDays(all),
                hasConnectedWearable: hasConnectedWearable,
              );
            },
          );
        },
      ),
    );
  }

  Widget content(
    List<_HeartDay> days,
    List<_HeartDay> previous, {
    required bool hasConnectedWearable,
  }) {
    final storedEntries = days.expand((day) => day.readings).toList();
    final storedReadings = storedEntries.map((entry) => entry.bpm).toList();
    final chartDays = days;
    final chartEntries = chartDays.expand((day) => day.readings).toList();
    final resting = days.map((day) => day.resting).whereType<double>().toList();
    final prior = previous
        .map((day) => day.resting)
        .whereType<double>()
        .toList();
    // Summary values and the graph use only the persisted screen snapshot.
    // Incoming Bluetooth packets update only the live wearable card below.
    final avg = average(storedReadings);
    final restingAvg = average(resting);
    final priorAvg = average(prior);
    final change = restingAvg == null || priorAvg == null
        ? null
        : (restingAvg - priorAvg).round();
    final low = storedReadings.isEmpty
        ? null
        : storedReadings.reduce(math.min).round();
    final high = storedReadings.isEmpty
        ? null
        : storedReadings.reduce(math.max).round();
    final dailyValues = chartDays
        .map(
          (day) =>
              average(day.readings.map((entry) => entry.bpm)) ??
              day.resting ??
              0,
        )
        .toList();
    final latestDay = days.isEmpty ? null : days.last;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'Updated ${DateFormat('h:mm a').format(DateTime.now())}',
              style: TextStyle(color: context.vivordoColors.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          rangeSelector(),
          const SizedBox(height: 18),
          if (hasConnectedWearable) ...[
            ValueListenableBuilder<WhoopBleState>(
              valueListenable: WhoopBleHeartRateService.instance.state,
              builder: (context, bleState, _) => wearableLiveCard(bleState),
            ),
            const SizedBox(height: 18),
          ],
          summary(
            avg,
            restingAvg,
            change,
            low,
            high,
            heartHealthScore: rangeIndex == 0
                ? latestDay?.heartHealthScore
                : null,
            heartHealthStatus: rangeIndex == 0
                ? latestDay?.heartHealthStatus
                : null,
          ),
          section('$rangeName trend'),
          chart(chartDays, chartEntries, dailyValues, restingAvg),
          section('Heart rate zones'),
          zones(storedReadings),
          section('Insight'),
          insight(change, restingAvg),
        ],
      ),
    );
  }

  Future<void> _pairWearable() async {
    try {
      final devices = await WhoopBleHeartRateService.instance.scanForDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No heart-rate broadcast found. Enable heart-rate sharing or broadcasting on your wearable and try again.',
            ),
          ),
        );
        return;
      }
      final selected = devices.length == 1
          ? devices.first
          : await showModalBottomSheet<WhoopBleDevice>(
              context: context,
              builder: (context) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(
                      title: Text(
                        'Choose your wearable',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('Nearby heart-rate broadcasters'),
                    ),
                    ...devices.map(
                      (device) => ListTile(
                        leading: const Icon(Icons.bluetooth_rounded),
                        title: Text(device.name),
                        subtitle: Text('Signal ${device.rssi} dBm'),
                        onTap: () => Navigator.pop(context, device),
                      ),
                    ),
                  ],
                ),
              ),
            );
      if (selected == null) return;
      await WhoopBleHeartRateService.instance.pairAndStart(selected);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _toggleWearableLive(WhoopBleState bleState) async {
    if (bleState.isConnected) {
      await WhoopBleHeartRateService.instance.stop();
    } else {
      await WhoopBleHeartRateService.instance.startIfPaired();
    }
  }

  Future<void> _forgetWearable() =>
      WhoopBleHeartRateService.instance.stop(clearPairing: true);

  Widget wearableLiveCard(WhoopBleState bleState) {
    final busy =
        bleState.status == WhoopBleStatus.scanning ||
        bleState.status == WhoopBleStatus.connecting;
    final hasReading = bleState.isConnected && bleState.bpm != null;
    final statusLabel = switch (bleState.status) {
      WhoopBleStatus.unpaired => 'NOT PAIRED',
      WhoopBleStatus.scanning => 'SCANNING',
      WhoopBleStatus.connecting => 'CONNECTING',
      WhoopBleStatus.connected when hasReading => 'LIVE',
      WhoopBleStatus.connected => 'CONNECTED',
      WhoopBleStatus.disconnected => 'PAUSED',
      WhoopBleStatus.unavailable => 'UNAVAILABLE',
      WhoopBleStatus.error => 'CONNECTION ISSUE',
    };
    final statusColor = switch (bleState.status) {
      WhoopBleStatus.connected when hasReading => red,
      WhoopBleStatus.connected => const Color(0xFF20B26B),
      WhoopBleStatus.scanning || WhoopBleStatus.connecting => purple,
      WhoopBleStatus.unpaired ||
      WhoopBleStatus.disconnected => context.vivordoColors.textSecondary,
      WhoopBleStatus.unavailable ||
      WhoopBleStatus.error => const Color(0xFFFF9F43),
    };
    final String? detailText = switch (bleState.status) {
      WhoopBleStatus.unpaired =>
        'Pair your wearable to see your heart rate here in real time.',
      WhoopBleStatus.scanning => 'Looking for nearby heart-rate broadcasts…',
      WhoopBleStatus.connecting => 'Establishing a live connection…',
      WhoopBleStatus.connected when hasReading => null,
      WhoopBleStatus.connected => 'Waiting for the first heart-rate reading…',
      WhoopBleStatus.disconnected => 'Live monitoring is currently stopped.',
      WhoopBleStatus.unavailable || WhoopBleStatus.error =>
        bleState.message ?? 'Wearable Bluetooth is unavailable.',
    };
    return card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bluetooth_rounded,
                  color: purple,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'LIVE WEARABLE HEART RATE',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasReading) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: hasReading
                ? Row(
                    key: ValueKey(bleState.bpm),
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 7),
                        child: Icon(
                          Icons.favorite_rounded,
                          color: red,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Text(
                        '${bleState.bpm}',
                        style: const TextStyle(
                          color: red,
                          fontSize: 58,
                          height: .9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 7, bottom: 5),
                        child: Text(
                          'bpm',
                          style: TextStyle(
                            color: red,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    key: ValueKey(bleState.status),
                    children: [
                      if (busy)
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      else
                        Icon(
                          Icons.monitor_heart_outlined,
                          color: statusColor,
                          size: 36,
                        ),
                      const SizedBox(width: 12),
                      Text(
                        bleState.isConnected ? '-- bpm' : 'Live heart rate',
                        style: TextStyle(
                          color: context.vivordoColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
          ),
          if (detailText != null) ...[
            const SizedBox(height: 10),
            Text(
              detailText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.vivordoColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
          if (bleState.deviceName != null) ...[
            const SizedBox(height: 5),
            Text(
              bleState.deviceName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.vivordoColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: context.vivordoColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : bleState.isPaired
                      ? () => _toggleWearableLive(bleState)
                      : _pairWearable,
                  style: FilledButton.styleFrom(
                    backgroundColor: bleState.isConnected
                        ? context.vivordoColors.cardMuted
                        : purple,
                    foregroundColor: bleState.isConnected
                        ? context.vivordoColors.textPrimary
                        : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: Icon(
                    bleState.isConnected
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    size: 19,
                  ),
                  label: Text(
                    bleState.isConnected
                        ? 'Stop live'
                        : bleState.isPaired
                        ? 'Start live'
                        : 'Pair wearable',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (bleState.isPaired) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: busy ? null : _forgetWearable,
                  child: Text(
                    'Forget',
                    style: TextStyle(
                      color: context.vivordoColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
    ),
  );

  Widget rangeSelector() {
    const labels = ['Day', 'Week', 'Month'];
    return Container(
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.vivordoColors.cardMuted,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == rangeIndex;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => rangeIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? purple : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : context.vivordoColors.textSecondary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget summary(
    double? avg,
    double? resting,
    int? change,
    int? low,
    int? high, {
    double? heartHealthScore,
    String? heartHealthStatus,
  }) {
    final avgText = avg?.round().toString() ?? '--';
    final showHeartHealth = rangeIndex == 0;
    final heartHealthText = heartHealthScore?.round().toString() ?? '--';
    final heartHealthDescription = switch (heartHealthStatus) {
      'building_baseline' => 'Building your personal baseline',
      'unavailable' => 'Not enough data to calculate',
      _ when heartHealthScore != null => 'Personalized cardiovascular score',
      _ => 'No Heart Health score available',
    };
    final heartHealthColor = heartHealthScore == null
        ? context.vivordoColors.textSecondary
        : heartHealthScore >= 75
        ? const Color(0xFF20B26B)
        : heartHealthScore >= 50
        ? const Color(0xFFFF9500)
        : red;
    return card(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!showHeartHealth) ...[
                bubble(Icons.favorite_border_rounded, red),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            showHeartHealth
                                ? 'HEART HEALTH SCORE'
                                : 'AVERAGE HEART RATE',
                            style: TextStyle(
                              color: context.vivordoColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (showHeartHealth)
                          IconButton(
                            tooltip: 'How Heart Health works',
                            onPressed: _showHeartHealthInfo,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              color: purple,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                    if (!showHeartHealth)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: avgText,
                                style: const TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const TextSpan(
                                text: ' bpm',
                                style: TextStyle(fontSize: 21),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          style: TextStyle(
                            color: context.vivordoColors.textPrimary,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    if (showHeartHealth) const SizedBox(height: 10),
                    Text(
                      showHeartHealth
                          ? heartHealthDescription
                          : resting == null
                          ? 'No resting average available'
                          : 'Resting average ${resting.round()} bpm',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    if (!showHeartHealth && change != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${change <= 0 ? '↓' : '↑'} ${change.abs()} bpm vs previous period',
                        style: TextStyle(
                          color: change <= 0 ? const Color(0xFF20B26B) : red,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showHeartHealth) ...[
                const SizedBox(width: 14),
                SizedBox(
                  width: 112,
                  height: 112,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: ((heartHealthScore ?? 0) / 100)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                          strokeWidth: 11,
                          strokeCap: StrokeCap.round,
                          color: heartHealthColor,
                          backgroundColor: context.vivordoColors.cardMuted,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.favorite_border_rounded,
                            color: red,
                            size: 23,
                          ),
                          Text(
                            heartHealthText,
                            style: const TextStyle(
                              fontSize: 29,
                              height: 1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '/100',
                            style: TextStyle(
                              color: context.vivordoColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              stat('Low', low?.toString() ?? '--'),
              divider(),
              stat('Average', avgText),
              divider(),
              stat('High', high?.toString() ?? '--'),
            ],
          ),
        ],
      ),
    );
  }

  Widget stat(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(color: context.vivordoColors.textSecondary),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: red,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget divider() =>
      Container(width: 1, height: 44, color: context.vivordoColors.border);

  Future<void> _showHeartHealthInfo() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dialogContext.vivordoColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: red.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              color: red,
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'How Heart Health works',
              style: TextStyle(
                color: dialogContext.vivordoColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(
          'Vivordo creates your Heart Health score from available signals such as resting heart rate, heart rate variability (HRV), and your heart rate during quiet periods. It compares today’s readings with your own recent baseline and combines the available signals into a score from 0 to 100.\n\nAt least seven previous days are needed to begin scoring. Higher scores mean today’s heart signals are trending favorably compared with your usual pattern. Heart Health is a wellness estimate and is not a medical diagnosis.',
          style: TextStyle(
            color: dialogContext.vivordoColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: purple,
            foregroundColor: Colors.white,
          ),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  Widget chart(
    List<_HeartDay> days,
    List<_HeartReading> entries,
    List<double> dailyValues,
    double? resting,
  ) {
    final isDay = rangeIndex == 0;
    final buckets = isDay
        ? _bucketDayReadings(entries)
        : const <_HeartBucket>[];
    final values = isDay
        ? buckets.map((bucket) => bucket.average).toList()
        : dailyValues;
    final dates = isDay
        ? buckets.map((bucket) => bucket.timestamp).toList()
        : days.map((day) => day.date).toList();
    final lows = isDay
        ? buckets.map((bucket) => bucket.low).toList()
        : const <double>[];
    final highs = isDay
        ? buckets.map((bucket) => bucket.high).toList()
        : const <double>[];
    final labels = isDay
        ? dates.map((date) => DateFormat('h:mm a').format(date)).toList()
        : days
              .map(
                (day) => rangeIndex == 2
                    ? DateFormat('M/d').format(day.date)
                    : DateFormat('E').format(day.date),
              )
              .toList();
    return card(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
      child: SizedBox(
        height: 245,
        child: _HeartChart(
          values: values,
          labels: labels,
          dates: dates,
          lows: lows,
          highs: highs,
          resting: resting,
          showTime: isDay,
        ),
      ),
    );
  }

  List<_HeartBucket> _bucketDayReadings(List<_HeartReading> entries) {
    const bucketSize = Duration(minutes: 1);
    final bucketMilliseconds = bucketSize.inMilliseconds;
    final grouped = <int, List<_HeartReading>>{};
    for (final entry in entries) {
      final bucket =
          entry.timestamp.millisecondsSinceEpoch ~/ bucketMilliseconds;
      grouped.putIfAbsent(bucket, () => []).add(entry);
    }

    final keys = grouped.keys.toList()..sort();
    return keys.map((key) {
      final readings = grouped[key]!;
      final values = readings.map((reading) => reading.bpm).toList();
      return _HeartBucket(
        average(readings.map((reading) => reading.bpm))!,
        values.reduce(math.min),
        values.reduce(math.max),
        readings.first.timestamp,
      );
    }).toList();
  }

  Widget zones(List<double> readings) {
    final counts = {for (final zone in HeartRateZone.values) zone: 0};
    for (final reading in readings) {
      final category = heartRateZoneFor(reading);
      counts[category] = counts[category]! + 1;
    }
    final total = math.max(1, readings.length);
    return card(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          for (var index = 0; index < HeartRateZone.values.length; index++) ...[
            if (index > 0)
              Divider(height: 1, color: context.vivordoColors.border),
            zone(
              HeartRateZone.values[index].label,
              HeartRateZone.values[index].rangeLabel,
              counts[HeartRateZone.values[index]]!,
              total,
            ),
          ],
        ],
      ),
    );
  }

  Widget zone(String title, String range, int count, int total) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        SizedBox(
          width: 105,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
              Text(
                range,
                style: TextStyle(color: context.vivordoColors.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: count / total,
              minHeight: 9,
              color: red.withValues(alpha: .7),
              backgroundColor: context.vivordoColors.cardMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 62,
          child: Text(
            '$count reading${count == 1 ? '' : 's'}',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget insight(int? change, double? resting) {
    final text = resting == null
        ? 'Complete a heart scan to begin building your heart rate trend.'
        : change == null
        ? 'Your resting heart rate averaged ${resting.round()} bpm.'
        : change <= 0
        ? 'Your resting heart rate improved by ${change.abs()} bpm.'
        : 'Your resting heart rate increased by $change bpm.';
    return card(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          bubble(Icons.monitor_heart_outlined, const Color(0xFF20B26B)),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget card({required Widget child, required EdgeInsets padding}) =>
      Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: context.vivordoColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.vivordoColors.border),
        ),
        child: child,
      );

  Widget bubble(IconData icon, Color color) => Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 29),
  );
}

class _HeartDay {
  const _HeartDay(
    this.date,
    this.readings,
    this.resting,
    this.heartHealthScore,
    this.heartHealthStatus,
  );
  final DateTime date;
  final List<_HeartReading> readings;
  final double? resting;
  final double? heartHealthScore;
  final String? heartHealthStatus;
}

class _HeartReading {
  const _HeartReading(this.bpm, this.timestamp);
  final double bpm;
  final DateTime timestamp;
}

class _HeartBucket {
  const _HeartBucket(this.average, this.low, this.high, this.timestamp);
  final double average;
  final double low;
  final double high;
  final DateTime timestamp;
}

class _HeartChart extends StatefulWidget {
  const _HeartChart({
    required this.values,
    required this.labels,
    required this.dates,
    required this.lows,
    required this.highs,
    required this.resting,
    required this.showTime,
  });
  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final List<double> lows;
  final List<double> highs;
  final double? resting;
  final bool showTime;

  @override
  State<_HeartChart> createState() => _HeartChartState();
}

class _HeartChartState extends State<_HeartChart> {
  int? selected;

  void select(double x, double width) {
    if (widget.values.isEmpty) return;
    final left = widget.showTime ? 8.0 : 38.0;
    final right = widget.showTime ? 40.0 : 0.0;
    var index = 0;
    if (widget.values.length > 1) {
      final chartWidth = width - left - right;
      index = (((x - left) / chartWidth) * (widget.values.length - 1))
          .round()
          .clamp(0, widget.values.length - 1);
    }
    if (selected != index) setState(() => selected = index);
  }

  @override
  void didUpdateWidget(covariant _HeartChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.values, oldWidget.values) ||
        !listEquals(widget.dates, oldWidget.dates)) {
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (event) =>
          select(event.localPosition.dx, constraints.maxWidth),
      onHorizontalDragUpdate: (event) =>
          select(event.localPosition.dx, constraints.maxWidth),
      child: CustomPaint(
        size: Size.infinite,
        painter: _HeartChartPainter(
          values: widget.values,
          labels: widget.labels,
          dates: widget.dates,
          lows: widget.lows,
          highs: widget.highs,
          resting: widget.resting,
          showTime: widget.showTime,
          selected: selected,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _HeartChartPainter extends CustomPainter {
  const _HeartChartPainter({
    required this.values,
    required this.labels,
    required this.dates,
    required this.lows,
    required this.highs,
    required this.resting,
    required this.showTime,
    required this.selected,
    required this.dark,
  });
  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final List<double> lows;
  final List<double> highs;
  final double? resting;
  final bool showTime;
  final int? selected;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final left = showTime ? 8.0 : 38.0;
    final right = showTime ? 40.0 : 0.0;
    final bottom = showTime ? 38.0 : 28.0;
    final height = size.height - bottom;
    final width = size.width - left - right;
    final rightEdge = left + width;
    var minimum = 0.0;
    var maximum = math.max(
      120.0,
      values.isEmpty ? 0.0 : values.reduce(math.max) * 1.15,
    );
    final hasRanges =
        lows.length == values.length &&
        highs.length == values.length &&
        values.isNotEmpty;
    if (showTime && values.isNotEmpty) {
      final rawMinimum = hasRanges
          ? lows.reduce(math.min)
          : values.reduce(math.min);
      final rawMaximum = hasRanges
          ? highs.reduce(math.max)
          : values.reduce(math.max);
      minimum = math.max(30.0, ((rawMinimum - 5) / 10).floor() * 10.0);
      maximum = math.min(220.0, ((rawMaximum + 5) / 10).ceil() * 10.0);
      if (maximum - minimum < 30) {
        final padding = (30 - (maximum - minimum)) / 2;
        minimum = math.max(30.0, minimum - padding);
        maximum = math.min(220.0, maximum + padding);
      }
    }
    final valueRange = math.max(1.0, maximum - minimum);
    double yFor(double value) =>
        height * (1 - ((value - minimum) / valueRange).clamp(0.0, 1.0));

    final grid = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .08)
      ..strokeWidth = 1;
    final gridDivisions = showTime ? 2 : 4;
    for (var i = 0; i <= gridDivisions; i++) {
      final y = height * i / gridDivisions;
      canvas.drawLine(Offset(left, y), Offset(rightEdge, y), grid);
      final labelValue = maximum - valueRange * i / gridDivisions;
      text(
        canvas,
        '${labelValue.round()}',
        Offset(showTime ? rightEdge + 6 : 0, math.max(0, y - 6)),
        10,
      );
    }
    if (values.isEmpty) return;

    final points = List.generate(values.length, (i) {
      final x = values.length == 1
          ? left + width / 2
          : left + width * i / (values.length - 1);
      return Offset(x, yFor(values[i]));
    });

    if (resting != null && resting! >= minimum && resting! <= maximum) {
      final y = yFor(resting!);
      canvas.drawLine(
        Offset(left, y),
        Offset(rightEdge, y),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = 1.2,
      );
    }

    if (showTime) {
      _drawDayLine(canvas, points);
    } else {
      final path = smoothChartPath(points);
      final fill = Path.from(path)
        ..lineTo(points.last.dx, height)
        ..lineTo(points.first.dx, height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, height), [
            const Color(0xFFFF3B4E).withValues(alpha: .2),
            const Color(0xFFFF3B4E).withValues(alpha: 0),
          ]),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFF3B4E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    if (showTime) {
      final tickPaint = Paint()
        ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .16)
        ..strokeWidth = 1;
      final tickCount = math.min(size.width < 330 ? 3 : 4, points.length);
      for (var i = 0; i < tickCount; i++) {
        final index = tickCount == 1
            ? 0
            : (i * (points.length - 1) / (tickCount - 1)).round();
        final tickX = points[index].dx;
        canvas.drawLine(
          Offset(tickX, height),
          Offset(tickX, height + 5),
          tickPaint,
        );
        final tickDate = dates[index];
        centerTextClamped(
          canvas,
          '${DateFormat('h:mm').format(tickDate)}\n'
          '${DateFormat('a').format(tickDate)}',
          tickX,
          height + 7,
          9,
          left,
          rightEdge,
        );
      }
    } else {
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(points[i], 5, Paint()..color = Colors.white);
        canvas.drawCircle(
          points[i],
          3.5,
          Paint()..color = const Color(0xFFFF3B4E),
        );
        if (values.length <= 10 || i % 5 == 0 || i == values.length - 1) {
          centerText(canvas, labels[i], Offset(points[i].dx, height + 7), 9);
        }
      }
    }

    final index = selected;
    if (index != null && index < points.length) {
      final point = points[index];
      canvas.drawLine(
        Offset(point.dx, 0),
        Offset(point.dx, height),
        Paint()
          ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .1)
          ..strokeWidth = 1,
      );
      if (!showTime) {
        canvas.drawCircle(
          point,
          9,
          Paint()..color = const Color(0xFFFF3B4E).withValues(alpha: .2),
        );
        canvas.drawCircle(point, 5.5, Paint()..color = Colors.white);
        canvas.drawCircle(point, 4, Paint()..color = const Color(0xFFFF3B4E));
      }
      final label = showTime
          ? '${values[index].round()} bpm\n'
                '${DateFormat('h:mm a').format(dates[index])}'
          : '${DateFormat('MMM d').format(dates[index])}\n${values[index].round()} bpm';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: dark ? Colors.white : Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final boxWidth = painter.width + 18;
      final boxHeight = painter.height + 14;
      final x = (point.dx - boxWidth / 2).clamp(left, rightEdge - boxWidth);
      final y = (point.dy - boxHeight - 12).clamp(0.0, height - boxHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, boxWidth, boxHeight),
          const Radius.circular(9),
        ),
        Paint()..color = dark ? const Color(0xFF302B48) : Colors.white,
      );
      painter.paint(canvas, Offset(x + 9, y + 7));
    }
  }

  void _drawDayLine(Canvas canvas, List<Offset> points) {
    const elevatedThreshold = 100.0;
    final normalPaint = Paint()
      ..color = const Color(0xFF69AEB2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final elevatedPaint = Paint()
      ..color = const Color(0xFFFFC43A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (points.length == 1) {
      final paint = values.first >= elevatedThreshold
          ? elevatedPaint
          : normalPaint;
      canvas.drawLine(
        Offset(points.first.dx - 4, points.first.dy),
        Offset(points.first.dx + 4, points.first.dy),
        paint,
      );
      return;
    }

    for (var i = 1; i < points.length; i++) {
      if (dates[i].difference(dates[i - 1]).abs() >
          const Duration(minutes: 30)) {
        continue;
      }

      final previousValue = values[i - 1];
      final currentValue = values[i];
      final previousElevated = previousValue >= elevatedThreshold;
      final currentElevated = currentValue >= elevatedThreshold;
      if (previousElevated == currentElevated) {
        canvas.drawLine(
          points[i - 1],
          points[i],
          currentElevated ? elevatedPaint : normalPaint,
        );
        continue;
      }

      final crossingFraction =
          (elevatedThreshold - previousValue) / (currentValue - previousValue);
      final crossing = Offset.lerp(
        points[i - 1],
        points[i],
        crossingFraction.clamp(0.0, 1.0),
      )!;
      canvas.drawLine(
        points[i - 1],
        crossing,
        previousElevated ? elevatedPaint : normalPaint,
      );
      canvas.drawLine(
        crossing,
        points[i],
        currentElevated ? elevatedPaint : normalPaint,
      );
    }
  }

  void text(Canvas canvas, String value, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: dark ? Colors.white54 : Colors.black45,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void centerText(Canvas canvas, String value, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: dark ? Colors.white54 : Colors.black45,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width / 2, offset.dy));
  }

  void centerTextClamped(
    Canvas canvas,
    String value,
    double x,
    double y,
    double size,
    double minimumX,
    double maximumX,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: dark ? Colors.white54 : Colors.black45,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final left = (x - painter.width / 2).clamp(
      minimumX,
      maximumX - painter.width,
    );
    painter.paint(canvas, Offset(left, y));
  }

  @override
  bool shouldRepaint(covariant _HeartChartPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values) ||
      !listEquals(labels, oldDelegate.labels) ||
      !listEquals(dates, oldDelegate.dates) ||
      !listEquals(lows, oldDelegate.lows) ||
      !listEquals(highs, oldDelegate.highs) ||
      selected != oldDelegate.selected ||
      resting != oldDelegate.resting ||
      showTime != oldDelegate.showTime ||
      dark != oldDelegate.dark;
}
