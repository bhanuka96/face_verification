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
  final DateTime createdAt;

  FaceRecord(this.id, this.imageId, this.embedding, {DateTime? createdAt}) : createdAt = createdAt ?? DateTime.now();

  Map<String, Object?> toMap() => {'id': id, 'image_id': imageId, 'embedding': jsonEncode(embedding), 'created_at': createdAt.millisecondsSinceEpoch};

  static FaceRecord fromMap(Map<String, Object?> map) => FaceRecord(
    map['id'] as String,
    map['image_id'] as String,
    (jsonDecode(map['embedding'] as String) as List).map((e) => (e as num).toDouble()).toList(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );
}

class FaceStore {
  Database? _db;

  /// Get database path without creating a FaceStore instance.
  /// This is useful for isolates where path_provider must run on main isolate.
  static Future<String> getDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'face_verification.db');
  }

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'face_verification.db');
    _db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, v) async {
        await db.execute('''
        CREATE TABLE faces (
          id TEXT NOT NULL,
          image_id TEXT NOT NULL,
          embedding TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (id, image_id)
        )
      ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          log('Migrating database from version $oldVersion to $newVersion');
          // WARNING: this will permanently delete existing faces table and its data
          await db.execute('DROP TABLE IF EXISTS faces');
          await db.execute('''
              CREATE TABLE faces (
                id TEXT NOT NULL,
                image_id TEXT NOT NULL,
                embedding TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                PRIMARY KEY (id, image_id)
              )
        ''');
          log('Dropped old faces table and created new schema (composite PK).');
        }
      },
    );
  }

  /// Get all face records for a specific user ID
  Future<List<FaceRecord>> getAllByUserId(String userId) async {
    final db = _ensureDb();
    final result = await db.query('faces', where: 'id = ?', whereArgs: [userId], orderBy: 'created_at DESC');

    return result.map(FaceRecord.fromMap).toList();
  }

  /// Get a specific face record by user ID and image ID
  Future<FaceRecord?> getByUserIdAndImageId(String userId, String imageId) async {
    final db = _ensureDb();
    final result = await db.query('faces', where: 'id = ? AND image_id = ?', whereArgs: [userId, imageId], limit: 1);

    if (result.isEmpty) {
      return null;
    }

    return FaceRecord.fromMap(result.first);
  }

  /// Legacy method for backward compatibility
  /// Returns the most recent face record for a user
  Future<FaceRecord?> getById(String id) async {
    final records = await getAllByUserId(id);
    return records.isEmpty ? null : records.first;
  }

  /// Insert or update a face record
  Future<void> upsert(FaceRecord record, {bool replace = true}) async {
    final db = _ensureDb();
    await db.insert('faces', record.toMap(), conflictAlgorithm: replace ? ConflictAlgorithm.replace : ConflictAlgorithm.abort);
  }

  /// Delete a specific face record by user ID and image ID
  Future<void> deleteByUserIdAndImageId(String userId, String imageId) async {
    final db = _ensureDb();
    await db.delete('faces', where: 'id = ? AND image_id = ?', whereArgs: [userId, imageId]);
  }

  /// Delete all face records for a user
  Future<void> deleteAllByUserId(String userId) async {
    final db = _ensureDb();
    await db.delete('faces', where: 'id = ?', whereArgs: [userId]);
  }

  /// Legacy delete method for backward compatibility
  Future<void> delete(String id) async {
    await deleteAllByUserId(id);
  }

  /// Get count of faces for a user
  Future<int> getFaceCountForUser(String userId) async {
    final db = _ensureDb();
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM faces WHERE id = ?', [userId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get all unique user IDs
  Future<List<String>> getAllUserIds() async {
    final db = _ensureDb();
    final result = await db.rawQuery('SELECT DISTINCT id FROM faces ORDER BY id');
    return result.map((row) => row['id'] as String).toList();
  }

  Future<List<FaceRecord>> listAll() async {
    final db = _ensureDb();
    final rows = await db.query('faces', orderBy: 'id, created_at DESC');
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

    // Check if database is still open (it might have been closed by an isolate)
    if (!db.isOpen) {
      throw Exception('Database connection was closed. Reinitializing...');
    }

    return db;
  }

  /// Reinitialize the database connection if it was closed
  Future<void> ensureOpen() async {
    if (_db == null || !_db!.isOpen) {
      _db = null; // Reset
      await init(); // Reinitialize
    }
  }
}
