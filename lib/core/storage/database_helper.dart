import 'dart:io';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('soseng.db');
    return _database!;
  }

  Future<Database?> _initDB(String filePath) async {
    // 크롬(웹) 환경에서는 sqflite를 사용할 수 없습니다.
    if (kIsWeb) {
      print('🌐 [소생 앱] 크롬(웹) 환경에서는 로컬 DB를 초기화할 수 없습니다.');
      return null;
    }
    
    // Windows/Linux 데스크톱 환경을 위한 FFI 초기화
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT';
    const textTypeNotNull = 'TEXT NOT NULL';
    const realType = 'REAL';

    await db.execute('''
      CREATE TABLE screenshots (
        id $idType,
        type $textTypeNotNull,
        confidence $realType,
        fields $textType,
        image_path $textType,
        status $textType DEFAULT 'DRAFT',
        created_at $textType DEFAULT CURRENT_TIMESTAMP,
        updated_at $textType DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    print('📂 [소생 앱] 로컬 DB(screenshots 테이블) 생성 완료');
  }

  // --- CRUD 메서드 ---

  // 1. Create (저장)
  Future<int> insertScreenshot(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('screenshots', row);
  }

  // 2-1. Read (타입별 조회)
  Future<List<Map<String, dynamic>>> getScreenshotsByType(String type) async {
    final db = await instance.database;
    return await db.query(
      'screenshots',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'created_at DESC',
    );
  }

  // 2-2. Read (상태별 조회)
  Future<List<Map<String, dynamic>>> getScreenshotsByStatus(String status) async {
    final db = await instance.database;
    return await db.query(
      'screenshots',
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'created_at DESC',
    );
  }

  // 3-1. Update (사용자가 텍스트 수정한 경우 fields 업데이트)
  Future<int> updateFields(int id, String fieldsJson) async {
    final db = await instance.database;
    return await db.update(
      'screenshots',
      {
        'fields': fieldsJson,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 3-2. Update (사용자가 검토 후 승인한 경우 status 업데이트)
  Future<int> updateStatus(int id, String status) async {
    final db = await instance.database;
    return await db.update(
      'screenshots',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 4. Delete (삭제)
  Future<int> deleteScreenshot(int id) async {
    final db = await instance.database;
    // 참고: 여기서 연결된 image_path 파일도 함께 삭제하는 로직을 나중에 추가할 수 있습니다.
    return await db.delete(
      'screenshots',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
