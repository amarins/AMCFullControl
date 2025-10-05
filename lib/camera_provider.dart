import 'package:camera/camera.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
// import 'package:gallery_saver/gallery_saver.dart';

// 1. Classe de Estado para a Câmera
class CameraState {
  final CameraController? controller;
  final bool isInitialized;
  final bool isPreviewVisible;
  final bool isRecording;
  final String? error;
  final String? lastVideoPath;

  CameraState({
    this.controller,
    this.isInitialized = false,
    this.isPreviewVisible = false,
    this.isRecording = false,
    this.error,
    this.lastVideoPath,
  });

  CameraState copyWith({
    CameraController? controller,
    bool? isInitialized,
    bool? isPreviewVisible,
    bool? isRecording,
    String? error,
    String? lastVideoPath,
    bool clearLastVideoPath = false,
    bool clearError = false,
  }) {
    return CameraState(
      controller: controller ?? this.controller,
      isInitialized: isInitialized ?? this.isInitialized,
      isPreviewVisible: isPreviewVisible ?? this.isPreviewVisible,
      isRecording: isRecording ?? this.isRecording,
      error: clearError ? null : error ?? this.error,
      lastVideoPath: clearLastVideoPath
          ? null
          : lastVideoPath ?? this.lastVideoPath,
    );
  }
}

// NOVO: Provider para a lista de câmeras disponíveis. Será sobrescrito no main.dart.
final availableCamerasProvider = Provider<List<CameraDescription>>((ref) {
  // Retorna uma lista vazia por padrão. Este valor será sobrescrito (overridden) no main.dart.
  return [];
});

// 2. StateNotifier para a Câmera
class CameraNotifier extends StateNotifier<CameraState> {
  final List<CameraDescription> _cameras;
  CameraDescription? _currentCamera;

  CameraNotifier(this._cameras) : super(CameraState()) {
    if (_cameras.isNotEmpty) {
      // Define a câmera inicial (frontal, se disponível)
      _currentCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      _initialize(_currentCamera!);
    } else {
      state = state.copyWith(error: 'Nenhuma câmera disponível.');
    }
  }

  Future<void> _initialize(CameraDescription camera) async {
    // Garante que o controller antigo seja descartado antes de criar um novo.
    await state.controller?.dispose();

    try {
      // Mostra um estado de carregamento enquanto a nova câmera inicializa
      state = state.copyWith(
        controller: null,
        isInitialized: false,
        clearError: true,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
      );

      await controller.initialize();
      // Após uma operação assíncrona, verifique se o notifier ainda está "montado".
      if (!mounted) {
        await controller.dispose();
        return;
      }

      state = state.copyWith(
        controller: controller,
        isInitialized: true,
        clearError: true,
      );
    } on CameraException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        error: 'Erro ao carregar a câmera: ${e.description}',
        isInitialized: false,
      );
    }
  }

  Future<void> switchCamera() async {
    // Não faz nada se tiver 1 ou 0 câmeras.
    if (_cameras.length < 2) return;

    // Encontra o índice da câmera atual.
    final currentIndex = _cameras.indexOf(_currentCamera!);

    // Calcula o índice da próxima câmera (dá a volta na lista).
    final nextIndex = (currentIndex + 1) % _cameras.length;
    _currentCamera = _cameras[nextIndex];

    // Inicializa a nova câmera.
    await _initialize(_currentCamera!);
  }

  void togglePreview(bool isVisible) {
    state = state.copyWith(isPreviewVisible: isVisible);
  }

  Future<void> toggleRecording(bool shouldRecord) async {
    final controller = state.controller;
    if (controller == null || !state.isInitialized) return;

    if (shouldRecord == state.isRecording) return;

    try {
      if (shouldRecord) {
        await controller.startVideoRecording();
        // Limpa o caminho do vídeo anterior ao iniciar uma nova gravação
        state = state.copyWith(isRecording: true, clearLastVideoPath: true);
      } else {
        final file = await controller.stopVideoRecording();
        String? galleryError;
        // Caminho preferido para abrir depois (ajustado se copiarmos para .mp4)
        String pathForOpening = file.path;

        // --- LÓGICA PARA SALVAR NA GALERIA com 'gal' ---
        try {
          print("Iniciando salvamento do vídeo: ${file.path}");
          
          // 1. Verificar e solicitar permissões necessárias de forma mais robusta
          final permissions = await _requestVideoPermissions();
          
          if (permissions['success'] == true) {
            // 2. Aguardar o arquivo finalizar e validar existência/tamanho
            await Future.delayed(const Duration(milliseconds: 400));
            final originalPath = file.path;
            final originalFile = File(originalPath);
            final exists = await originalFile.exists();
            final length = exists ? await originalFile.length() : 0;
            print("📄 Arquivo existe: $exists | tamanho: $length bytes | path: $originalPath");

            if (!exists || length == 0) {
              galleryError = 'Arquivo de vídeo inválido (inexistente ou vazio).';
            } else {
              // 3. Verificar se o gal está disponível
              final isGalAvailable = await _checkGalAvailability();

              Future<void> trySave(String path, {String? album}) async {
                if (album != null) {
                  print("📝 Salvando com álbum '$album'...");
                  await Gal.putVideo(path, album: album);
                } else {
                  print("📝 Salvando sem álbum...");
                  await Gal.putVideo(path);
                }
              }

              bool saved = false;
              String? lastErrorMsg;

              if (isGalAvailable) {
                // Tentativa A: com álbum
                try {
                  await trySave(originalPath, album: "AMC Ganhos");
                  saved = true;
                  print("✅ Vídeo salvo na galeria (com álbum)");
                } on GalException catch (e) {
                  lastErrorMsg = 'GAL(${e.type}) ao salvar com álbum';
                  print("❌ $lastErrorMsg");
                } catch (e) {
                  lastErrorMsg = 'Falha ao salvar com álbum: $e';
                  print("❌ $lastErrorMsg");
                }

                // Tentativa B: sem álbum
                if (!saved) {
                  try {
                    await trySave(originalPath);
                    saved = true;
                    print("✅ Vídeo salvo na galeria (sem álbum)");
                  } on GalException catch (e) {
                    lastErrorMsg = 'GAL(${e.type}) ao salvar sem álbum';
                    print("❌ $lastErrorMsg");
                  } catch (e) {
                    lastErrorMsg = 'Falha ao salvar sem álbum: $e';
                    print("❌ $lastErrorMsg");
                  }
                }

                // Tentativa C: copiar para .mp4 e tentar novamente
                if (!saved) {
                  final hasMp4 = originalPath.toLowerCase().endsWith('.mp4');
                  final mp4Path = hasMp4 ? originalPath : '${originalPath}.mp4';
                  if (!hasMp4) {
                    try {
                      print("📦 Copiando para caminho com extensão .mp4: $mp4Path");
                      await originalFile.copy(mp4Path);
                      // Se a cópia der certo, passamos a abrir este caminho
                      final mp4Exists = await File(mp4Path).exists();
                      if (mp4Exists) {
                        pathForOpening = mp4Path;
                      }
                    } catch (e) {
                      print("⚠️ Falha ao copiar para .mp4: $e");
                    }
                  } else {
                    // Já é mp4, usar como caminho preferido
                    pathForOpening = mp4Path;
                  }

                  // C1: com álbum
                  if (!saved) {
                    try {
                      await trySave(mp4Path, album: "AMC Ganhos");
                      saved = true;
                      print("✅ Vídeo salvo (mp4, com álbum)");
                    } on GalException catch (e) {
                      lastErrorMsg = 'GAL(${e.type}) ao salvar mp4 com álbum';
                      print("❌ $lastErrorMsg");
                    } catch (e) {
                      lastErrorMsg = 'Falha ao salvar mp4 com álbum: $e';
                      print("❌ $lastErrorMsg");
                    }
                  }

                  // C2: sem álbum
                  if (!saved) {
                    try {
                      await trySave(mp4Path);
                      saved = true;
                      print("✅ Vídeo salvo (mp4, sem álbum)");
                    } on GalException catch (e) {
                      lastErrorMsg = 'GAL(${e.type}) ao salvar mp4 sem álbum';
                      print("❌ $lastErrorMsg");
                    } catch (e) {
                      lastErrorMsg = 'Falha ao salvar mp4 sem álbum: $e';
                      print("❌ $lastErrorMsg");
                    }
                  }
                }

                if (!saved) {
                  if (!saved) {
                    galleryError = lastErrorMsg ?? 'Falha desconhecida ao salvar vídeo.';
                    print("⚠️ Nenhum método obteve sucesso. Ativando fallback local.");
                    await _saveVideoLocally(originalPath);
                  }
                }
              } else {
                // Fallback: salvar localmente se gal não estiver disponível
                print("⚠️ Gal não disponível, salvando localmente...");
                await _saveVideoLocally(originalPath);
                print("✅ Vídeo salvo localmente!");
              }
            }
          } else {
            print("❌ Permissões de armazenamento negadas: ${permissions['error']}");
            galleryError = permissions['error'] ?? 'Permissão negada para salvar o vídeo na galeria.';
          }
        } on GalException catch (e) {
          print("❌ GALException ao salvar vídeo: ${e.type}");
          // Tentar salvar localmente como fallback
          try {
            print("🔄 Tentando salvar localmente como fallback...");
            await _saveVideoLocally(file.path);
            print("✅ Vídeo salvo localmente como fallback!");
          } catch (fallbackError) {
            print("❌ Erro no fallback: $fallbackError");
            galleryError = 'Erro ao salvar vídeo: ${e.type}';
          }
        } catch (e) {
          print("❌ Erro geral ao salvar vídeo na galeria: $e");
          // Tentar salvar localmente como fallback
          try {
            print("🔄 Tentando salvar localmente como fallback...");
            await _saveVideoLocally(file.path);
            print("✅ Vídeo salvo localmente como fallback!");
          } catch (fallbackError) {
            print("❌ Erro no fallback: $fallbackError");
            galleryError = 'Erro ao salvar vídeo na galeria: $e';
          }
        }

        if (!mounted) {
          return; // Adicionado para segurança após operações assíncronas
        }

        // Move/copia para uma pasta estável do app para garantir acesso consistente
        String finalPath = pathForOpening;
        try {
          final Directory baseDir = Platform.isAndroid
              ? (await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory())
              : await getApplicationDocumentsDirectory();
          final Directory videosDir = Directory('${baseDir.path}/Videos');
          if (!await videosDir.exists()) {
            await videosDir.create(recursive: true);
          }
          final String fileName = finalPath.split(Platform.pathSeparator).last;
          final String targetPath = '${videosDir.path}/$fileName';
          if (finalPath != targetPath) {
            // Preferir copiar para evitar problemas de permissão
            await File(finalPath).copy(targetPath);
            finalPath = targetPath;
          }
        } catch (e) {
          print('⚠️ Falha ao mover/copiar para pasta estável: $e');
        }

        // Confirma existência; se não existir, volta ao original
        if (!await File(finalPath).exists()) {
          finalPath = file.path;
        }

        // Atualiza o estado UMA VEZ com todas as informações.
        state = state.copyWith(
          isRecording: false,
          lastVideoPath: finalPath,
          error: galleryError,
        );
      }
    } on CameraException catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: 'Erro na gravação: ${e.description}');
    }
  }

  /// Solicita permissões necessárias para salvar vídeos de forma robusta
  Future<Map<String, dynamic>> _requestVideoPermissions() async {
    try {
      // Para Android 13+ (API 33+)
      final videoPermission = await Permission.videos.request();
      print("📱 Permissão de vídeos (Android 13+): ${videoPermission.isGranted}");
      
      // Para Android 12 e anteriores
      final storagePermission = await Permission.storage.request();
      print("💾 Permissão de armazenamento (Android 12-): ${storagePermission.isGranted}");
      
      // Para Android 11+ - gerenciamento de armazenamento externo
      final manageStoragePermission = await Permission.manageExternalStorage.request();
      print("🗂️ Permissão de gerenciar armazenamento (Android 11+): ${manageStoragePermission.isGranted}");
      
      // Verifica se pelo menos uma permissão foi concedida
      final hasVideoPermission = videoPermission.isGranted;
      final hasStoragePermission = storagePermission.isGranted;
      final hasManageStoragePermission = manageStoragePermission.isGranted;
      
      if (hasVideoPermission || hasStoragePermission || hasManageStoragePermission) {
        return {'success': true};
      } else {
        String errorMessage = 'Permissões necessárias negadas:\n';
        if (!hasVideoPermission) errorMessage += '• Acesso a vídeos\n';
        if (!hasStoragePermission) errorMessage += '• Armazenamento\n';
        if (!hasManageStoragePermission) errorMessage += '• Gerenciar arquivos\n';
        errorMessage += '\nAcesse as configurações do app para habilitar as permissões.';
        
        return {'success': false, 'error': errorMessage};
      }
    } catch (e) {
      print("❌ Erro ao verificar permissões: $e");
      return {'success': false, 'error': 'Erro ao verificar permissões: $e'};
    }
  }

  /// Verifica se o pacote gal está disponível e funcionando
  Future<bool> _checkGalAvailability() async {
    try {
      // Tenta verificar se o gal está disponível fazendo uma operação simples
      await Gal.hasAccess();
      return true;
    } catch (e) {
      print("⚠️ Gal não está disponível: $e");
      return false;
    }
  }

  /// Salva o vídeo localmente como fallback
  Future<void> _saveVideoLocally(String videoPath) async {
    try {
      // Para este fallback, vamos apenas manter o arquivo no local original
      // e informar ao usuário onde ele está salvo
      print("📁 Vídeo salvo localmente em: $videoPath");
      
      // Aqui você pode implementar lógica adicional para:
      // - Copiar para uma pasta específica do app
      // - Notificar o usuário sobre a localização
      // - Adicionar ao banco de dados local
      
    } catch (e) {
      print("❌ Erro ao salvar vídeo localmente: $e");
      rethrow;
    }
  }

  /// Abre o vídeo salvo usando o player padrão do dispositivo.
  Future<void> openLastVideo() async {
    if (state.lastVideoPath == null) return;

    final filePath = state.lastVideoPath!;
    final file = File(filePath);

    // Verifica se o arquivo realmente existe antes de tentar abrir
    if (!await file.exists()) {
      if (!mounted) return;
      state = state.copyWith(
        error: 'Arquivo de vídeo não encontrado no caminho: $filePath',
      );
      return;
    }

    // Abre com o player externo usando MIME adequado
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      if (!mounted) return;
      state = state.copyWith(
        error: 'Não foi possível abrir o vídeo: ${result.message ?? 'sem app compatível'}',
      );
    }
  }

  @override
  void dispose() {
    state.controller?.dispose();
    super.dispose();
  }
}

// 3. Provider Global
final cameraProvider =
    StateNotifierProvider.autoDispose<CameraNotifier, CameraState>((ref) {
      // Lê a lista de câmeras do novo provider.
      final cameras = ref.watch(availableCamerasProvider);
      // Passa a lista para o Notifier.
      final notifier = CameraNotifier(cameras);
      ref.onDispose(() => notifier.dispose());
      return notifier;
    });
