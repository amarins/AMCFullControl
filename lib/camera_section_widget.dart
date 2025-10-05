import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'camera_provider.dart';

class CameraSectionWidget extends ConsumerWidget {
  const CameraSectionWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraProvider);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.blue.shade700,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          children: [
            // --- Controles da Câmera ---
            _buildCameraControls(context, ref, cameraState),

            // --- Visualização da Câmera ---
            if (cameraState.isPreviewVisible) _buildCameraPreview(cameraState),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraControls(
    BuildContext context,
    WidgetRef ref,
    CameraState cameraState,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Visualizar Câmera:',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            Switch(
              value: cameraState.isPreviewVisible,
              onChanged: (value) {
                ref.read(cameraProvider.notifier).togglePreview(value);
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
            Stack(
              alignment: Alignment.centerRight,
              clipBehavior: Clip
                  .none, // Permite que o ícone seja desenhado fora dos limites
              children: [
                if (cameraState.isRecording)
                  const Padding(
                    padding: EdgeInsets.only(
                      right: 50,
                    ), // Empurra o Switch para a direita, abrindo espaço
                    child: Icon(Icons.videocam, color: Colors.red, size: 28),
                  ),
                Switch(
                  value: cameraState.isRecording,
                  onChanged: (value) async {
                    // A lógica de salvar e notificar foi movida para o CameraNotifier.
                    ref.read(cameraProvider.notifier).toggleRecording(value);
                  },
                ),
              ],
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Alternar Câmera:',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            IconButton(
              icon: const Icon(Icons.switch_camera, color: Colors.white),
              onPressed: () {
                ref.read(cameraProvider.notifier).switchCamera();
              },
            ),
          ],
        ),
        // Feedback visual para vídeo salvo
        if (cameraState.lastVideoPath != null)
          Container(
            margin: const EdgeInsets.only(top: 8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vídeo salvo! Toque para abrir.',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.play_arrow, color: Colors.green.shade700),
                  onPressed: () {
                    ref.read(cameraProvider.notifier).openLastVideo();
                  },
                ),
              ],
            ),
          ),
        // Mostrar erro se houver
        if (cameraState.error != null)
          Container(
            margin: const EdgeInsets.only(top: 8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.error, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cameraState.error!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCameraPreview(CameraState cameraState) {
    return Container(
      margin: const EdgeInsets.only(top: 16.0),
      height: 300,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: cameraState.isInitialized && cameraState.controller != null
            ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cameraState.controller!.value.previewSize!.height,
                  height: cameraState.controller!.value.previewSize!.width,
                  child: CameraPreview(cameraState.controller!),
                ),
              )
            : Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        cameraState.error ?? 'Carregando câmera...',
                        style: TextStyle(
                          color: cameraState.error != null
                              ? Colors.red
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
