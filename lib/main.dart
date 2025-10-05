import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart'; // Import para formatação de data/hora
// Import para localização
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart'; // Import para permissões
// Import do nosso helper
import 'logbook_history_screen.dart'; // Import da nova tela
import 'splash_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 1. Importar Riverpod
import 'settings_provider.dart'; // Importar o novo provider
import 'logbook_provider.dart'; // Importar nosso novo provider
import 'camera_provider.dart'; // Importar nosso novo provider da câmera
import 'camera_section_widget.dart'; // Importar o novo widget da câmera
import 'logbook_summary_screen.dart';
import 'database_helper.dart';

// Mantém uma referência ao container do Riverpod entre os Hot Restarts.
ProviderContainer? _container;

Future<void> main() async {
  // Garante que os bindings do Flutter sejam inicializados antes de chamar APIs de plugins.
  WidgetsFlutterBinding.ensureInitialized();

  // Solicita permissões necessárias no início
  await _requestPermissions();

  // Se um container já existe (de uma sessão anterior), descarte-o.
  // Isso garante que o CameraController antigo seja liberado.
  _container?.dispose();

  // Inicializa a câmera antes de rodar o app.
  final cameras = await availableCameras();

  // Cria um NOVO container para a sessão atual do app.
  _container = ProviderContainer(
    overrides: [availableCamerasProvider.overrideWithValue(cameras)],
  );

  runApp(
    // UncontrolledProviderScope permite que o container que criamos
    // seja usado pela árvore de widgets do Flutter.
    UncontrolledProviderScope(container: _container!, child: const MyApp()),
  );
}

/// Solicita as permissões necessárias para o funcionamento do app
Future<void> _requestPermissions() async {
  print("🔐 Solicitando permissões necessárias...");
  
  // Permissões para câmera
  final cameraStatus = await Permission.camera.request();
  print("📷 Permissão de câmera: ${cameraStatus.isGranted}");
  
  // Permissões para áudio
  final microphoneStatus = await Permission.microphone.request();
  print("🎤 Permissão de microfone: ${microphoneStatus.isGranted}");
  
  // Permissões para localização
  final locationStatus = await Permission.location.request();
  print("📍 Permissão de localização: ${locationStatus.isGranted}");
  
  // Permissões para armazenamento (vídeos) - Android 13+
  final videoStatus = await Permission.videos.request();
  print("🎥 Permissão de vídeos (Android 13+): ${videoStatus.isGranted}");
  
  // Permissões para armazenamento (geral) - Android 12 e anteriores
  final storageStatus = await Permission.storage.request();
  print("💾 Permissão de armazenamento (Android 12-): ${storageStatus.isGranted}");
  
  // Permissões para gerenciar armazenamento externo - Android 11+
  final manageStorageStatus = await Permission.manageExternalStorage.request();
  print("🗂️ Permissão de gerenciar armazenamento (Android 11+): ${manageStorageStatus.isGranted}");
  
  print("✅ Permissões solicitadas!");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AMC - Full Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      debugShowCheckedModeBanner:
          false, // Adicione esta linha para remover a faixa
      home: const SplashScreen(), // Inicia com a Splash Screen
    );
  }
}

// 3. Transformar em ConsumerWidget
class MyHomePage extends ConsumerStatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  ConsumerState<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<MyHomePage> {
  Future<void> _toggleLogbook() async {
    final notifier = ref.read(logbookProvider.notifier);

    try {
      // Lê o estado mais recente antes de tomar uma decisão
      if (ref.read(logbookProvider).isLogbookOpen) {
        await notifier.stopLogbook();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Diário de Bordo fechado e salvo!')),
          );
        }
      } else {
        await notifier.startLogbook();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Diário de Bordo aberto!')),
          );
          // Adiciona a verificação 'mounted' também para a navegação
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const LogbookHistoryScreen(),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openMap() async {
    final logbookState = ref.read(logbookProvider);
    final Uri googleMapsUrl;

    // Se um diário acabou de ser fechado, mostra a rota completa.
    if (logbookState.summary != null &&
        logbookState.initialPosition != null &&
        logbookState.lastKnownPosition != null) {
      final startLat = logbookState.initialPosition!.latitude;
      final startLong = logbookState.initialPosition!.longitude;
      final endLat = logbookState.lastKnownPosition!.latitude;
      final endLong = logbookState.lastKnownPosition!.longitude;

      googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$startLat,$startLong&destination=$endLat,$endLong',
      );
    } else if (logbookState.lastKnownPosition != null) {
      // Senão, mostra apenas o último ponto conhecido.
      final lat = logbookState.lastKnownPosition!.latitude;
      final long = logbookState.lastKnownPosition!.longitude;
      googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$long',
      );
    } else {
      return; // Não faz nada se não houver localização.
    }

    // Tenta abrir a URL
    final bool launched = await launchUrl(googleMapsUrl);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o mapa.')),
      );
    }
  }

  Future<void> _openLogbookSummary() async {
    // Busca o último diário fechado e abre a tela de resumo
    final lastClosed = await DatabaseHelper.instance.getLastClosedLog();
    if (!mounted) return;
    if (lastClosed == null || lastClosed.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum diário fechado encontrado.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogbookSummaryScreen(logbookId: lastClosed.id!),
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    // Lê o valor atual e o notifier do provider de configurações
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final newInterval = await showDialog<int>(
      context: context,
      // Usamos um StatefulBuilder para gerenciar o ciclo de vida do TextEditingController.
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // O controller é criado aqui e será descartado quando o diálogo for fechado.
          final controller = TextEditingController(
            text: '${settings.locationUpdateIntervalInMinutes}',
          );

          return AlertDialog(
            title: const Text('Configurar Intervalo'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true, // Melhora a experiência do usuário
              decoration: const InputDecoration(
                labelText: 'Minutos para salvar localização',
                suffixText: 'min',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  final value = int.tryParse(controller.text);
                  if (value != null && value > 0 && value <= 1440) {
                    Navigator.of(context).pop(value);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Digite um valor entre 1 e 1440 minutos'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );

    if (newInterval != null) {
      try {
      await settingsNotifier.updateLocationInterval(newInterval);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Intervalo salvo: $newInterval minutos.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 5. "Ouvir" as mudanças no estado do diário de bordo
    final logbookState = ref.watch(logbookProvider);
    // "Ouvir" o novo provedor do relógio
    final clock = ref.watch(clockProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon.png',
              height: 32, // Ajuste a altura conforme necessário
            ),
            const SizedBox(width: 10),
            Text(widget.title),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  _showSettingsDialog();
                  break;
                case 'about':
                  // Navega para a tela de Splash, mas agora como uma tela normal
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          const SplashScreen(showAsModal: true),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Configurações'),
                  ],
                ),
              ),
              // Nova opção de menu
              const PopupMenuItem<String>(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Sobre & Contato'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        // Adicionado para evitar overflow
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            // Container para Diário de Bordo
            Container(
              margin: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Column(
                children: [
                  const Text(
                    'Diário de Bordo',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // O clock.when reconstrói apenas o relógio, não a tela inteira.
                      clock.when(
                        data: (now) => Row(
                          children: [
                            Text(
                              'Data: ${DateFormat('dd/MM/yyyy').format(now)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        loading: () => const Text(
                          'Data: ...',
                          style: TextStyle(fontSize: 16),
                        ),
                        error: (err, stack) => const Text('Erro no relógio'),
                      ),
                      clock.when(
                        data: (now) => Text(
                          'Hora: ${DateFormat('HH:mm:ss').format(now)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        loading: () => const Text(
                          'Hora: ...',
                          style: TextStyle(fontSize: 16),
                        ),
                        error: (err, stack) => const SizedBox(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          // Botão dinâmico
                          icon: Icon(
                            logbookState.isLogbookOpen
                                ? Icons.close
                                : Icons.book,
                          ),
                          onPressed: _toggleLogbook,
                          label: Text(
                            logbookState.isLogbookOpen
                                ? 'Fechar Diário de Bordo'
                                : 'Abrir Diário de Bordo',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: logbookState.isLogbookOpen
                                ? Colors.red.shade700
                                : Colors.blue.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.history),
                          onPressed: () async {
                            // Também usamos 'await' aqui para o botão de histórico manual
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const LogbookHistoryScreen(),
                              ),
                            );
                          },
                          label: const Text('Histórico'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (logbookState.lastKnownPosition != null)
                        const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.map),
                          onPressed: _openMap,
                          label: const Text('Ver no Mapa'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!logbookState.isLogbookOpen)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.route),
                            onPressed: _openLogbookSummary,
                            label: const Text('Resumo do Diário'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  // --- Container para o Resumo ---
                  if (logbookState.summary != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 16.0),
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        logbookState.summary!,
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ),
                ],
              ),
            ),
            // Substituímos todo o bloco da câmera por nosso novo widget
            const CameraSectionWidget(),
          ],
        ),
      ),
    );
  }
}

// Novo StreamProvider que emite a hora atual a cada segundo.
final clockProvider = StreamProvider<DateTime>((ref) {
  // Retorna um Stream que emite um novo DateTime a cada segundo.
  return Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});
