// lib/src/services/storage.dart
import 'dart:convert';
import 'dart:developer';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class FaceRecord {
  final String id;
  final String imageId;
  final List<double> embedding;

  FaceRecord(this.id, this.imageId, this.embedding);

  Map<String, Object?> toMap() => {'id': id, 'image_id': imageId, 'embedding': jsonEncode(embedding)};

  static FaceRecord fromMap(Map<String, Object?> map) =>
      FaceRecord(map['id'] as String, map['image_id'] as String, (jsonDecode(map['embedding'] as String) as List).map((e) => (e as num).toDouble()).toList());
}

class FaceStore {
  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'face_verification.db');
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''
        CREATE TABLE faces (
          id TEXT PRIMARY KEY,
          image_id TEXT NOT NULL,
          embedding TEXT NOT NULL
        )
      ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          log('Migrating database from version $oldVersion to $newVersion');
          // Drop the old table
          await db.execute('DROP TABLE IF EXISTS faces');
          
          // Create new table with new schema
          await db.execute('''
            CREATE TABLE faces (
              id TEXT PRIMARY KEY,
              image_id TEXT NOT NULL,
              embedding TEXT NOT NULL
            )
          ''');
          
          log('Database recreated successfully');
        }
      },
    );
  }

  /// Get a face record by ID
  Future<FaceRecord?> getById(String id) async {
    final db = _ensureDb();
    final result = await db.query('faces', where: 'id = ?', whereArgs: [id], limit: 1);

    if (result.isEmpty) {
      return null;
    }

    return FaceRecord.fromMap(result.first);
  }

  Future<void> upsert(FaceRecord record) async {
    final db = _ensureDb();
    await db.insert('faces', record.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = _ensureDb();
    await db.delete('faces', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<FaceRecord>> listAll() async {
    final db = _ensureDb();
    final rows = await db.query('faces');
    return rows.map(FaceRecord.fromMap).toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Database _ensureDb() {
    final db = _db;
    if (db == null) {
      throw Exception('Database not initialized. Call init() first.');
    }
    return db;
  }
}
