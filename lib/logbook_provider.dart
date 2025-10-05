import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';
import 'settings_provider.dart'; // Importar o novo provider de configurações

// 1. Definir a classe de Estado
// Usamos uma classe imutável para representar o estado do diário.
class LogbookState {
  final bool isLogbookOpen;
  final DateTime? startTime;
  final String? summary;
  final int? currentLogbookId;
  final Position? initialPosition;
  final Position? lastKnownPosition;

  LogbookState({
    this.isLogbookOpen = false,
    this.startTime,
    this.summary,
    this.currentLogbookId,
    this.initialPosition,
    this.lastKnownPosition,
  });

  // Método para criar uma cópia do estado, alterando alguns valores.
  LogbookState copyWith({
    bool? isLogbookOpen,
    DateTime? startTime,
    String? summary,
    int? currentLogbookId,
    Position? initialPosition,
    Position? lastKnownPosition,
    bool clearSummary = false, // Flag para limpar o summary
  }) {
    return LogbookState(
      isLogbookOpen: isLogbookOpen ?? this.isLogbookOpen,
      startTime: startTime ?? this.startTime,
      summary: clearSummary ? null : summary ?? this.summary,
      currentLogbookId: currentLogbookId ?? this.currentLogbookId,
      initialPosition: initialPosition ?? this.initialPosition,
      lastKnownPosition: lastKnownPosition ?? this.lastKnownPosition,
    );
  }
}

// 2. Definir o StateNotifier
// Esta classe conterá toda a lógica que antes estava no _MyHomePageState.
class LogbookNotifier extends StateNotifier<LogbookState> {
  // Passamos o `ref` para que nosso Notifier possa ler outros providers.
  final Ref _ref;
  Timer? _locationTimer;
  Position? _lastRecordedPosition; // para cálculo incremental

  LogbookNotifier(this._ref) : super(LogbookState()) {
    // Ao ser criado, o Notifier verifica se precisa restaurar um estado anterior.
    _restoreOpenLogbookState();
  }

  /// Verifica no DB se existe um diário aberto e restaura o estado do Notifier.
  Future<void> _restoreOpenLogbookState() async {
    final openLog = await DatabaseHelper.instance.getOpenLogbook();
    if (openLog != null && openLog.id != null) {
      // Um diário aberto foi encontrado, vamos restaurar o estado.
      Position? initialPosition;
      if (openLog.startLatitude != null && openLog.startLongitude != null) {
        initialPosition = Position(
          latitude: openLog.startLatitude!,
          longitude: openLog.startLongitude!,
          timestamp: openLog.startTime,
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }

      // Atualiza o estado para refletir o diário que já estava aberto.
      state = state.copyWith(
        isLogbookOpen: true,
        startTime: openLog.startTime,
        currentLogbookId: openLog.id,
        initialPosition: initialPosition,
        lastKnownPosition:
            initialPosition, // Pode ser refinado buscando o último ponto
      );

      // Reinicia o monitoramento de localização para o diário restaurado.
      _startLocationUpdates();
    }
  }

  Future<void> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Serviço de localização desativado. Ative nas configurações do dispositivo.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permissão de localização negada. É necessário para o funcionamento do diário de bordo.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permissão de localização negada permanentemente. Acesse as configurações do app para habilitar.');
      }
    } catch (e) {
      print('Erro ao verificar permissões de localização: $e');
      rethrow;
    }
  }

  Future<void> startLogbook() async {
    await _checkLocationPermission();

    final initialPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    final initialLogEntry = LogbookEntry(
      startTime: DateTime.now(),
      startLatitude: initialPosition.latitude,
      startLongitude: initialPosition.longitude,
    );

    final logId = await DatabaseHelper.instance.createLog(initialLogEntry);

    final initialLocationPoint = LocationPoint(
      logbookId: logId,
      latitude: initialPosition.latitude,
      longitude: initialPosition.longitude,
      timestamp: initialLogEntry.startTime,
    );
    await DatabaseHelper.instance.addLocationPoint(initialLocationPoint);

    // Atualiza o estado usando o método `copyWith`
    state = state.copyWith(
      isLogbookOpen: true,
      startTime: initialLogEntry.startTime,
      currentLogbookId: logId,
      initialPosition: initialPosition,
      lastKnownPosition: initialPosition,
      clearSummary: true, // Limpa o resumo anterior
    );

    // inicializa posição passada para cálculo incremental
    _lastRecordedPosition = initialPosition;

    _startLocationUpdates();
  }

  Future<void> stopLogbook() async {
    if (state.currentLogbookId == null) return;

    final endTime = DateTime.now();
    Position? finalPosition;
    try {
      await _checkLocationPermission();
      finalPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('Não foi possível obter a localização final: $e');
    }

    // Preferir a distância acumulada no banco se disponível; senão calcular bruto
    double distanceInKm = 0;
    final current = await DatabaseHelper.instance.getLogById(state.currentLogbookId!);
    if (current?.distanceInKm != null) {
      distanceInKm = current!.distanceInKm!;
    } else {
      double distanceInMeters = 0;
      if (state.initialPosition != null && finalPosition != null) {
        distanceInMeters = Geolocator.distanceBetween(
          state.initialPosition!.latitude,
          state.initialPosition!.longitude,
          finalPosition.latitude,
          finalPosition.longitude,
        );
      }
      distanceInKm = distanceInMeters / 1000;
    }

    final finalLogEntry = LogbookEntry(
      id: state.currentLogbookId,
      startTime: state.startTime!,
      endTime: endTime,
      startLatitude: state.initialPosition?.latitude,
      startLongitude: state.initialPosition?.longitude,
      endLatitude: finalPosition?.latitude,
      endLongitude: finalPosition?.longitude,
      distanceInKm: distanceInKm,
    );
    await DatabaseHelper.instance.updateLog(finalLogEntry);

    _locationTimer?.cancel();

    // Calcula o resumo
    final duration = endTime.difference(state.startTime!);
    final summary =
        'Diário: ${DateFormat('HH:mm').format(state.startTime!)} às ${DateFormat('HH:mm').format(endTime)}. Duração: ${duration.inHours}h ${duration.inMinutes.remainder(60)}min. Distância: ${distanceInKm.toStringAsFixed(2)} km.';

    // Atualiza o estado final
    state = state.copyWith(
      isLogbookOpen: false,
      summary: summary,
      lastKnownPosition: finalPosition,
    );
  }

  void _startLocationUpdates() {
    // Lê o intervalo do nosso novo provider de configurações
    final intervalInMinutes = _ref
        .read(settingsProvider)
        .locationUpdateIntervalInMinutes;
    final interval = Duration(minutes: intervalInMinutes);
    _locationTimer = Timer.periodic(interval, (timer) async {
      if (state.currentLogbookId == null) {
        timer.cancel();
        return;
      }
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        final point = LocationPoint(
          logbookId: state.currentLogbookId!,
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: DateTime.now(),
        );
        await DatabaseHelper.instance.addLocationPoint(point);

        // Distância incremental entre o último ponto e o atual
        if (_lastRecordedPosition != null) {
          final meters = Geolocator.distanceBetween(
            _lastRecordedPosition!.latitude,
            _lastRecordedPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          final kmDelta = meters / 1000.0;
          if (kmDelta > 0) {
            await DatabaseHelper.instance.incrementDistance(state.currentLogbookId!, kmDelta);
          }
        }
        _lastRecordedPosition = position;
      } catch (e) {
        print('Erro ao obter localização periódica: $e');
      }
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }
}

// 3. Criar o Provider global
// Este é o objeto que usaremos na UI para acessar o LogbookNotifier.
final logbookProvider = StateNotifierProvider<LogbookNotifier, LogbookState>((
  ref,
) {
  return LogbookNotifier(ref);
});
