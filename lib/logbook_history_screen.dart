import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'database_helper.dart';

class LogbookHistoryScreen extends StatefulWidget {
  const LogbookHistoryScreen({super.key});

  @override
  State<LogbookHistoryScreen> createState() => _LogbookHistoryScreenState();
}

class _LogbookHistoryScreenState extends State<LogbookHistoryScreen> {
  // Trocamos o Future por uma lista que será atualizada
  List<LogbookEntry>? _logs;

  @override
  void initState() {
    super.initState();
    _loadLogs(); // Carrega os logs na primeira vez
  }

  Future<void> _loadLogs() async {
    final data = await DatabaseHelper.instance.getAllLogs();
    if (mounted) setState(() => _logs = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Diários'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      // Usamos um RefreshIndicator para permitir que o usuário "puxe para atualizar"
      body: RefreshIndicator(
        onRefresh: _loadLogs,
        child: _logs == null
            ? const Center(child: CircularProgressIndicator())
            : _logs!.isEmpty
            ? const Center(
                child: Text(
                  'Nenhum diário de bordo salvo.',
                  style: TextStyle(fontSize: 16),
                ),
              )
            : ListView.builder(
                // Garante que a lista possa ser rolada para ativar o RefreshIndicator
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _logs!.length,
                itemBuilder: (context, index) {
                  // Substituímos o Card por nosso novo widget
                  return LogbookCard(log: _logs![index]);
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Fecha a tela de histórico e volta para a tela principal
          Navigator.pop(context);
        },
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        child: const Icon(Icons.arrow_back),
      ),
    );
  }
}

// Novo Widget para o Card do Histórico
class LogbookCard extends StatefulWidget {
  final LogbookEntry log;

  const LogbookCard({super.key, required this.log});

  @override
  State<LogbookCard> createState() => _LogbookCardState();
}

class _LogbookCardState extends State<LogbookCard> {
  LocationPoint? _latestLocation;

  @override
  void initState() {
    super.initState();
    // Se o diário está em andamento, busca a última localização
    if (widget.log.endTime == null) {
      _fetchLatestLocation();
    }
  }

  Future<void> _fetchLatestLocation() async {
    if (widget.log.id == null) return;
    final location = await DatabaseHelper.instance.getLatestLocationPoint(
      widget.log.id!,
    );
    if (mounted) {
      setState(() {
        _latestLocation = location;
      });
    }
  }

  Future<void> _openMapForLog() async {
    final log = widget.log;
    final isOngoing = log.endTime == null;
    Uri? googleMapsUrl;

    if (isOngoing) {
      // Para diários em andamento, usa a última localização conhecida
      final location =
          _latestLocation ??
          (log.startLatitude != null
              ? LocationPoint(
                  logbookId: log.id!,
                  latitude: log.startLatitude!,
                  longitude: log.startLongitude!,
                  timestamp: log.startTime,
                )
              : null);

      if (location != null) {
        googleMapsUrl = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}',
        );
      }
    } else {
      // Para diários finalizados, mostra a rota completa
      if (log.startLatitude != null && log.endLatitude != null) {
        googleMapsUrl = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&origin=${log.startLatitude},${log.startLongitude}&destination=${log.endLatitude},${log.endLongitude}',
        );
      }
    }

    if (googleMapsUrl != null) {
      final bool launched = await launchUrl(googleMapsUrl);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o mapa.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final bool isOngoing = log.endTime == null;

    final formattedDate = DateFormat('dd/MM/yyyy').format(log.startTime);
    final startTime = DateFormat('HH:mm').format(log.startTime);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      color: isOngoing ? Colors.orange.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isOngoing
              ? Colors.orange.shade100
              : Colors.blue.shade100,
          child: Icon(
            isOngoing ? Icons.watch_later_outlined : Icons.book_online,
            color: isOngoing ? Colors.orange.shade800 : Colors.blue,
          ),
        ),
        title: Text(
          'Diário de $formattedDate',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: isOngoing
            ? _buildOngoingSubtitle(startTime)
            : _buildFinishedSubtitle(startTime),
        // Aumenta a altura do ListTile para acomodar mais informações
        isThreeLine: true,
        trailing: IconButton(
          icon: Icon(Icons.map, color: Colors.green.shade700),
          onPressed: _openMapForLog,
        ),
      ),
    );
  }

  Widget _buildFinishedSubtitle(String startTime) {
    final log = widget.log;
    final duration = log.endTime!.difference(log.startTime);
    final endTime = DateFormat('HH:mm').format(log.endTime!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Horário: $startTime - $endTime'),
        Text(
          'Duração: ${duration.inHours}h ${duration.inMinutes.remainder(60)}min',
        ),
        Text('Distância: ${(log.distanceInKm ?? 0).toStringAsFixed(2)} km'),
      ],
    );
  }

  Widget _buildOngoingSubtitle(String startTime) {
    final log = widget.log;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horário: $startTime - Em andamento...',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (log.startLatitude != null)
          Text(
            'Inicial: ${log.startLatitude!.toStringAsFixed(4)}, ${log.startLongitude!.toStringAsFixed(4)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        if (_latestLocation != null)
          Text(
            'Atual: ${_latestLocation!.latitude.toStringAsFixed(4)}, ${_latestLocation!.longitude.toStringAsFixed(4)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          )
        else
          const Text(
            'Atual: Buscando...',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
      ],
    );
  }
}
