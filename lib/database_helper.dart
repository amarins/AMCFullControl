import 'dart:convert'; // Import para JSON
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// Novo modelo para os pontos de localização individuais
class LocationPoint {
  final int? id;
  final int logbookId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  LocationPoint({
    this.id,
    required this.logbookId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'logbookId': logbookId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory LocationPoint.fromMap(Map<String, dynamic> map) {
    return LocationPoint(
      id: map['id'],
      logbookId: map['logbookId'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}

class LogbookEntry {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final double? startLatitude;
  final double? startLongitude;
  final double? endLatitude;
  final double? endLongitude;
  final double? distanceInKm;
  // O campo 'locations' foi removido, pois agora usaremos uma tabela separada.
  final List<Map<String, dynamic>>? locations; // Mantido para compatibilidade

  LogbookEntry({
    this.id,
    required this.startTime,
    this.endTime,
    this.startLatitude,
    this.startLongitude,
    this.endLatitude,
    this.endLongitude,
    this.distanceInKm,
    this.locations, // Mantido para compatibilidade
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'startLatitude': startLatitude,
      'startLongitude': startLongitude,
      'endLatitude': endLatitude,
      'endLongitude': endLongitude,
      'distanceInKm': distanceInKm,
      // O campo 'locations' não é mais salvo diretamente aqui no novo modelo,
      // mas o mantemos para evitar erros em outras partes do código que ainda o usam.
      'locations': locations != null ? jsonEncode(locations) : null,
    };
  }

  // Construtor para criar um LogbookEntry a partir de um Map (vindo do DB)
  factory LogbookEntry.fromMap(Map<String, dynamic> map) {
    return LogbookEntry(
      id: map['id'],
      startTime: DateTime.parse(map['startTime']),
      // endTime pode ser nulo se o diário ainda estiver aberto
      endTime: map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
      // Mantido para compatibilidade com dados antigos
      locations: map['locations'] != null && map['locations'] is String
          ? (jsonDecode(map['locations']) as List).cast<Map<String, dynamic>>()
          : null,
      startLatitude: map['startLatitude'],
      startLongitude: map['startLongitude'],
      endLatitude: map['endLatitude'],
      endLongitude: map['endLongitude'],
      distanceInKm: map['distanceInKm'],
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('amc_ganhos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    print('Caminho do banco de dados: $path'); // Adicione esta linha

    // A versão foi incrementada para 2 para acionar a atualização do schema
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Para novas instalações, executa a criação da v1 e depois a migração para a v2.
    // Isso garante que um banco novo já nasça na versão mais recente.
    await _createTablesV1(db);
    for (var i = 1; i < version; i++) {
      await _onUpgradeDB(db, i, i + 1);
    }
  }

  Future _createTablesV1(Database db) async {
    await db.execute('''
      CREATE TABLE logbook (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startTime TEXT NOT NULL,
        endTime TEXT,
        startLatitude REAL,
        startLongitude REAL,
        endLatitude REAL,
        endLongitude REAL,
        distanceInKm REAL,
        locations TEXT 
      )
    ''');

    // A criação da tabela location_points foi movida para o onUpgrade
  }

  // Novo método para lidar com atualizações do banco de dados
  Future _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    // Migração da versão 1 para a 2
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE location_points (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          logbookId INTEGER NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          timestamp TEXT NOT NULL,
          FOREIGN KEY (logbookId) REFERENCES logbook (id) ON DELETE CASCADE
        )
      ''');
    }
  }

  Future<int> createLog(LogbookEntry log) async {
    final db = await instance.database;

    return await db.insert('logbook', log.toMap());
  }

  // Novo método para adicionar um ponto de localização
  Future<int> addLocationPoint(LocationPoint point) async {
    final db = await instance.database;
    return await db.insert('location_points', point.toMap());
  }

  // Novo método para atualizar um log existente (para quando for fechado)
  Future<int> updateLog(LogbookEntry log) async {
    final db = await instance.database;
    return await db.update(
      'logbook',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  // Novo: atualizar distância acumulada do diário
  Future<void> incrementDistance(int logbookId, double distanceInKmDelta) async {
    final db = await instance.database;
    await db.rawUpdate(
      'UPDATE logbook SET distanceInKm = IFNULL(distanceInKm, 0) + ? WHERE id = ?',
      [distanceInKmDelta, logbookId],
    );
  }

  // Novo: buscar um diário por id
  Future<LogbookEntry?> getLogById(int id) async {
    final db = await instance.database;
    final result = await db.query('logbook', where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isNotEmpty) {
      return LogbookEntry.fromMap(result.first);
    }
    return null;
  }

  Future<List<LogbookEntry>> getAllLogs() async {
    final db = await instance.database;
    // Ordena do mais recente para o mais antigo
    final result = await db.query(
      'logbook',
      // A cláusula 'where' foi removida para buscar todos os diários,
      // incluindo os que estão em andamento (endTime IS NULL).
      orderBy: 'startTime DESC',
    );
    return result.map((json) => LogbookEntry.fromMap(json)).toList();
  }

  // Novo método para buscar o último ponto de localização de um diário
  Future<LocationPoint?> getLatestLocationPoint(int logbookId) async {
    final db = await instance.database;
    final result = await db.query(
      'location_points',
      where: 'logbookId = ?',
      whereArgs: [logbookId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return result.isNotEmpty ? LocationPoint.fromMap(result.first) : null;
  }

  // Novo: listar todos os pontos de um diário
  Future<List<LocationPoint>> getAllLocationPoints(int logbookId) async {
    final db = await instance.database;
    final result = await db.query(
      'location_points',
      where: 'logbookId = ?',
      whereArgs: [logbookId],
      orderBy: 'timestamp ASC',
    );
    return result.map((m) => LocationPoint.fromMap(m)).toList();
  }

  // Novo: pegar o último diário fechado (mais recente com endTime não nulo)
  Future<LogbookEntry?> getLastClosedLog() async {
    final db = await instance.database;
    final result = await db.query(
      'logbook',
      where: 'endTime IS NOT NULL',
      orderBy: 'endTime DESC',
      limit: 1,
    );
    if (result.isNotEmpty) return LogbookEntry.fromMap(result.first);
    return null;
  }

  // Novo método para buscar um diário que não foi fechado (endTime IS NULL)
  Future<LogbookEntry?> getOpenLogbook() async {
    final db = await instance.database;
    final result = await db.query(
      'logbook',
      where: 'endTime IS NULL',
      orderBy: 'startTime DESC', // Pega o mais recente caso haja inconsistência
      limit: 1,
    );
    if (result.isNotEmpty) {
      return LogbookEntry.fromMap(result.first);
    }
    return null;
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
