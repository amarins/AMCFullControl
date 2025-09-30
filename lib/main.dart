import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AMC Controle de Ganhos',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(title: 'AMC Controle de Ganhos'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isPreviewVisible = true; // Novo estado para controlar a visualização

  @override
  void initState() {
    super.initState();
    _initializeCamera(); // Corrigido para chamar a função que existe
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        // Procura pela câmera frontal, se não encontrar, usa a primeira disponível.
        final frontCamera = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );

        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.high,
          enableAudio: true,
        );
        await _cameraController!.initialize();
      }
    } on CameraException catch (e) {
      print('Erro ao inicializar a câmera: ${e.code}\n${e.description}');
      // Opcional: Mostrar um SnackBar ou diálogo para o usuário
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar a câmera: ${e.description}'),
          ),
        );
      }
    } finally {
      if (mounted)
        setState(() {}); // Atualiza a UI para mostrar a câmera ou o erro
    }
  }

  Future<void> _toggleRecording(bool value) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      print('Erro: Câmera não inicializada.');
      return;
    }

    // Garante que o estado do switch e da gravação estejam sincronizados
    if (value != controller.value.isRecordingVideo) {
      try {
        if (value) {
          // Iniciar gravação
          await controller.startVideoRecording();
          if (mounted) setState(() {}); // Atualiza a UI para mostrar o ícone
        } else {
          // Parar gravação
          final XFile videoFile = await controller.stopVideoRecording();
          if (mounted) setState(() {}); // Atualiza a UI para esconder o ícone
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Vídeo salvo em: ${videoFile.path}')),
            );
          }
        }
      } on CameraException catch (e) {
        print('Erro ao controlar a gravação: ${e.code}\n${e.description}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro na gravação: ${e.description}')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose(); // Libera o controller da câmera
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child:
                    _cameraController != null &&
                        _cameraController!.value.isInitialized
                    ? _isPreviewVisible
                          ? ClipRect(
                              child: Transform.scale(
                                scale:
                                    1 /
                                    (_cameraController!.value.aspectRatio *
                                        MediaQuery.of(
                                          context,
                                        ).size.aspectRatio),
                                alignment: Alignment.topCenter,
                                child: CameraPreview(_cameraController!),
                              ),
                            )
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: Text(
                                  'Visualização desligada',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Carregando câmera...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          SafeArea(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                // Usamos uma coluna para empilhar os controles
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Visualizar Câmera:',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      Switch(
                        value: _isPreviewVisible,
                        onChanged: (value) {
                          setState(() {
                            _isPreviewVisible = value;
                          });
                        },
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Gravar Vídeo:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20.0,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          Switch(
                            value:
                                _cameraController?.value.isRecordingVideo ??
                                false,
                            onChanged: _toggleRecording,
                          ),
                          if (_cameraController?.value.isRecordingVideo ??
                              false)
                            const Icon(
                              Icons.videocam,
                              color: Colors.red,
                              size: 28,
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
