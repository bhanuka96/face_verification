// lib/src/services/storage.dart
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class FaceRecord {
  final String id;
  final String name;
  final List<double> embedding;
  final String? imagePath;

  FaceRecord(this.id, this.name, this.embedding, {this.imagePath});

  Map<String, Object?> toMap() => {'id': id, 'name': name, 'embedding': jsonEncode(embedding), 'image_path': imagePath};

  static FaceRecord fromMap(Map<String, Object?> map) => FaceRecord(
    map['id'] as String,
    map['name'] as String,
    (jsonDecode(map['embedding'] as String) as List).map((e) => (e as num).toDouble()).toList(),
    imagePath: map['image_path'] as String?,
  );
}

class FaceStore {
  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'face_verification.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
        CREATE TABLE faces (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          embedding TEXT NOT NULL,
          image_path TEXT
        )
      ''');
      },
    );
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
