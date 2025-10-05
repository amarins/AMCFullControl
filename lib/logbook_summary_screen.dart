import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';

class LogbookSummaryScreen extends StatefulWidget {
  final int logbookId;
  const LogbookSummaryScreen({super.key, required this.logbookId});

  @override
  State<LogbookSummaryScreen> createState() => _LogbookSummaryScreenState();
}

class _LogbookSummaryScreenState extends State<LogbookSummaryScreen> {
  LogbookEntry? _log;
  List<LocationPoint>? _points;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await DatabaseHelper.instance.getLogById(widget.logbookId);
    final pts = await DatabaseHelper.instance.getAllLocationPoints(widget.logbookId);
    if (mounted) {
      setState(() {
        _log = log;
        _points = pts;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = _log;
    final points = _points;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumo do Diário'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: (log == null || points == null)
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Início: ${DateFormat('dd/MM/yyyy HH:mm').format(log.startTime)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (log.endTime != null)
                        Text('Fim: ${DateFormat('dd/MM/yyyy HH:mm').format(log.endTime!)}'),
                      const SizedBox(height: 6),
                      Text('Distância: ${(log.distanceInKm ?? 0).toStringAsFixed(2)} km'),
                      if (log.startLatitude != null)
                        Text('Inicial: ${log.startLatitude!.toStringAsFixed(5)}, ${log.startLongitude!.toStringAsFixed(5)}'),
                      if (log.endLatitude != null)
                        Text('Final: ${log.endLatitude!.toStringAsFixed(5)}, ${log.endLongitude!.toStringAsFixed(5)}'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('Pontos registrados', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: points.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = points[index];
                      return ListTile(
                        title: Text('${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'),
                        subtitle: Text(DateFormat('dd/MM/yyyy HH:mm:ss').format(p.timestamp)),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}


