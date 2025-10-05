import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. Classe de Estado para as Configurações
class AppSettings {
  final int locationUpdateIntervalInMinutes;

  AppSettings({this.locationUpdateIntervalInMinutes = 2}); // Valor padrão agora é 2 min

  AppSettings copyWith({int? locationUpdateIntervalInMinutes}) {
    return AppSettings(
      locationUpdateIntervalInMinutes:
          locationUpdateIntervalInMinutes ??
          this.locationUpdateIntervalInMinutes,
    );
  }
}

// 2. StateNotifier para as Configurações
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('locationInterval') ?? 2;
    state = state.copyWith(locationUpdateIntervalInMinutes: interval);
  }

  Future<void> updateLocationInterval(int newInterval) async {
    // Validação mais robusta do intervalo
    if (newInterval <= 0 || newInterval > 1440) {
      throw Exception('Intervalo deve estar entre 1 e 1440 minutos (24 horas)');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('locationInterval', newInterval);
      state = state.copyWith(locationUpdateIntervalInMinutes: newInterval);
    } catch (e) {
      print('Erro ao salvar configurações: $e');
      throw Exception('Erro ao salvar configurações. Tente novamente.');
    }
  }
}

// 3. Provider Global para as Configurações
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier();
});
