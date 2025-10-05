// Arquivo de constantes para centralizar configurações do app
class AppConstants {
  // Configurações de localização
  static const int defaultLocationIntervalMinutes = 2;
  static const int minLocationIntervalMinutes = 1;
  static const int maxLocationIntervalMinutes = 1440; // 24 horas
  
  // Configurações de câmera
  static const String videoAlbumName = "AMC Ganhos";
  
  // URLs
  static const String websiteUrl = 'https://amcsystem.com.br';
  static const String whatsappUrl = 'https://wa.me/5521969059726?text=<Bom dia, Solicito mais informações sobre o app.>';
  
  // Configurações de banco de dados
  static const String databaseName = 'amc_ganhos.db';
  static const int databaseVersion = 2;
  
  // Configurações de UI
  static const int splashScreenDurationSeconds = 5;
  static const double cameraPreviewHeight = 300.0;
  
  // Mensagens de erro
  static const String locationServiceDisabledMessage = 
      'Serviço de localização desativado. Ative nas configurações do dispositivo.';
  static const String locationPermissionDeniedMessage = 
      'Permissão de localização negada. É necessário para o funcionamento do diário de bordo.';
  static const String locationPermissionDeniedForeverMessage = 
      'Permissão de localização negada permanentemente. Acesse as configurações do app para habilitar.';
}
