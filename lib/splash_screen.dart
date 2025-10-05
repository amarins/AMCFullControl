import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart'; // Importa a tela principal
import 'constants.dart';

class SplashScreen extends StatefulWidget {
  // Novo parâmetro para controlar o comportamento da tela
  final bool showAsModal;

  const SplashScreen({super.key, this.showAsModal = false});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Define um timer para navegar para a tela principal após alguns segundos
    // Apenas se a tela NÃO for exibida como modal (ou seja, na abertura do app)
    if (!widget.showAsModal) {
      Timer(const Duration(seconds: AppConstants.splashScreenDurationSeconds), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => MyHomePage(title: 'AMC - Full Control'),
            ),
          );
        }
      });
    }
  }

  // Função auxiliar para abrir URLs
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Opcional: Mostrar um aviso se não conseguir abrir o link
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o link: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Adiciona uma AppBar com botão de voltar se for exibida como modal
      appBar: widget.showAsModal
          ? AppBar(
              title: const Text('Sobre & Contato'),
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              elevation: 0,
            )
          : null,
      body: Container(
        // Um gradiente de fundo para um visual mais moderno
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade800, Colors.blue.shade400],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Spacer(flex: 2),
              // 1. Ícone do App
              Image.asset('assets/icon.png', height: 120),
              const SizedBox(height: 24),
              // 2. Nome do App
              const Text(
                'AMC - Full Control',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              // 3. Descrição
              const Text(
                'Sua solução completa para controle e monitoramento.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const Spacer(flex: 3),
              // 4. Links
              TextButton.icon(
                icon: const Icon(Icons.public, color: Colors.white),
                label: const Text(
                  'Visite nosso site',
                  style: TextStyle(color: Colors.white),
                ),
                onPressed: () => _launchUrl(AppConstants.websiteUrl),
              ),
              TextButton.icon(
                icon: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                ),
                label: const Text(
                  'Contato via WhatsApp',
                  style: TextStyle(color: Colors.white),
                ),
                // Use o formato de link do WhatsApp com o código do país + DDD + número
                onPressed: () => _launchUrl(AppConstants.whatsappUrl),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
