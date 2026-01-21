import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:school_manager/models/category.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/student_document.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/evaluation_template.dart';
import 'package:school_manager/models/payment_adjustment.dart';
import 'package:school_manager/models/payment_attachment.dart';
import 'package:school_manager/models/payment_schedule_rule.dart';
import 'package:school_manager/models/supplier.dart';
import 'package:school_manager/models/expense_attachment.dart';
import 'package:school_manager/models/finance_budget.dart';
import 'package:school_manager/models/permission_group.dart';
import 'package:school_manager/models/user_session.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/models/expense.dart';
import 'package:school_manager/models/inventory_item.dart';
import 'package:school_manager/models/signature.dart';
import 'package:school_manager/models/library_book.dart';
import 'package:school_manager/models/library_loan.dart';
import 'package:school_manager/models/teacher_assignment.dart';
// Removed UI and prefs from data layer
// NOUVELLE MÉTHODE: import 'package:path_provider/path_provider.dart';
// ANCIENNE MÉTHODE: utilise getDatabasesPath() de sqflite (pas besoin d'import supplémentaire)

/// Service de gestion de la base de données
///
/// ============================================================================
/// DOCUMENTATION: DEUX MÉTHODES D'INITIALISATION
/// ============================================================================
///
/// Ce service supporte deux méthodes d'initialisation de la base de données :
///
/// 1. ANCIENNE MÉTHODE (ACTUELLEMENT ACTIVE)
///    - Utilise `getDatabasesPath()` de sqflite
///    - Chemin standard de sqflite pour chaque plateforme
///    - Plus simple, pas de dépendance supplémentaire
///    - Initialisation lazy au premier accès via `database` getter
///    - Pas de méthode `init()` publique
///
/// 2. NOUVELLE MÉTHODE (ACTUELLEMENT COMMENTÉE)
///    - Utilise `getApplicationDocumentsDirectory()` de path_provider
///    - Chemin dans le répertoire Documents de l'application
///    - Support pour base en mémoire (`useInMemory = true`)
///    - Support pour chemin personnalisé via `init(dbPath: "...")`
///    - Méthode `init()` publique pour configuration avancée
///
/// POUR BASCULER ENTRE LES DEUX MÉTHODES :
///
/// Pour utiliser l'ANCIENNE MÉTHODE (actuelle) :
///   - Décommentez la section "ANCIENNE MÉTHODE" dans _initDatabase()
///   - Commentez la section "NOUVELLE MÉTHODE"
///   - Commentez les variables _dbPathOverride et _useInMemory
///   - Commentez la méthode init()
///   - Commentez l'import path_provider
///
/// Pour utiliser la NOUVELLE MÉTHODE :
///   - Décommentez la section "NOUVELLE MÉTHODE" dans _initDatabase()
///   - Commentez la section "ANCIENNE MÉTHODE"
///   - Décommentez les variables _dbPathOverride et _useInMemory
///   - Décommentez la méthode init()
///   - Décommentez l'import path_provider
///
/// ============================================================================

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static final ValueNotifier<int> teacherAssignmentsVersion =
      ValueNotifier<int>(0);

  static Database? _database;
  static Future<Database>? _openingDatabase;

  // ============================================================================
  // NOUVELLE MÉTHODE - Variables pour configuration avancée (COMMENTÉES)
  // ============================================================================
  // String? _dbPathOverride;
  // bool _useInMemory = false;
  // ============================================================================

  static void _bumpTeacherAssignmentsVersion() {
    teacherAssignmentsVersion.value = teacherAssignmentsVersion.value + 1;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_openingDatabase != null) {
      return await _openingDatabase!;
    }
    _openingDatabase = _initDatabase();
    _database = await _openingDatabase!;
    _openingDatabase = null;
    return _database!;
  }

  // ============================================================================
  // NOUVELLE MÉTHODE - Méthode init() publique (COMMENTÉE)
  // ============================================================================
  // Permet de configurer le chemin de la base ou d'utiliser une base en mémoire
  // Exemple d'utilisation:
  //   await DatabaseService().init(dbPath: '/custom/path/db.db');
  //   await DatabaseService().init(useInMemory: true);
  // ============================================================================
  // Future<void> init({String? dbPath, bool useInMemory = false}) async {
  //   _dbPathOverride = dbPath;
  //   _useInMemory = useInMemory;
  //   if (_database != null || _openingDatabase != null) {
  //     return;
  //   }
  //   await database;
  // }
  // ============================================================================

  Future<void> _migrateStaffTable(Database db) async {
    // Vérifier si les nouvelles colonnes existent déjà
    final columns = await db.rawQuery("PRAGMA table_info(staff)");
    final columnNames = columns.map((col) => col['name'] as String).toList();

    // Liste des nouvelles colonnes à ajouter
    final newColumns = [
      'first_name TEXT',
      'last_name TEXT',
      'gender TEXT',
      'birth_date TEXT',
      'birth_place TEXT',
      'nationality TEXT',
      'address TEXT',
      'photo TEXT',
      'matricule TEXT',
      'id_number TEXT',
      'social_security TEXT',
      'marital_status TEXT',
      'number_of_children INTEGER',
      'region TEXT',
      'levels TEXT',
      'highest_degree TEXT',
      'specialty TEXT',
      'experience_years INTEGER',
      'previous_institution TEXT',
      'contract_type TEXT',
      'base_salary REAL',
      'weekly_hours INTEGER',
      'supervisor TEXT',
      'retirement_date TEXT',
      'documents TEXT',
    ];

    // Ajouter les colonnes manquantes
    for (final columnDef in newColumns) {
      final columnName = columnDef.split(' ')[0];
      if (!columnNames.contains(columnName)) {
        try {
          await db.execute('ALTER TABLE staff ADD COLUMN $columnDef');
          print('Added column: $columnName');
        } catch (e) {
          print('Error adding column $columnName: $e');
        }
      }
    }
  }

  Future<Database> _initDatabase() async {
    // ============================================================================
    // ANCIENNE MÉTHODE (ACTIVE) - Utilise getDatabasesPath() de sqflite
    // ============================================================================
    String path = join(await getDatabasesPath(), 'ecole_manager.db');
    // ============================================================================

    // ============================================================================
    // NOUVELLE MÉTHODE (COMMENTÉE) - Utilise getApplicationDocumentsDirectory()
    // ============================================================================
    // String path;
    // if (_useInMemory) {
    //   path = ':memory:';
    // } else if (_dbPathOverride != null) {
    //   path = _dbPathOverride!;
    // } else {
    //   final documents = await getApplicationDocumentsDirectory();
    //   path = join(documents.path, 'ecole_manager.db');
    // }
    // ============================================================================

    debugPrint('[DatabaseService] Ouverture de la base à : $path');
    final db = await openDatabase(
      path,
      version: 12, // v12: student new columns (placeOfBirth)
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // Some platforms (macOS/iOS) may report a benign error here; ignore if unsupported
        try {
          final res = await db.rawQuery('PRAGMA journal_mode = WAL');
          debugPrint('[DatabaseService] journal_mode set: $res');
        } catch (e) {
          debugPrint(
            '[DatabaseService] WAL not supported, continuing. Reason: $e',
          );
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE classes(
            name TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            titulaire TEXT,
            fraisEcole REAL,
            fraisCotisationParallele REAL,
            level TEXT,
            -- Seuils de passage personnalisés par classe
            seuilFelicitations REAL DEFAULT 16.0,
            seuilEncouragements REAL DEFAULT 14.0,
            seuilAdmission REAL DEFAULT 12.0,
            seuilAvertissement REAL DEFAULT 10.0,
            seuilConditions REAL DEFAULT 8.0,
            seuilRedoublement REAL DEFAULT 8.0,
            PRIMARY KEY (name, academicYear)
          )
        ''');
        await db.execute('''
          CREATE TABLE students(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            dateOfBirth TEXT NOT NULL,
            placeOfBirth TEXT,
            address TEXT NOT NULL,
            gender TEXT NOT NULL,
            contactNumber TEXT NOT NULL,
            email TEXT NOT NULL,
            emergencyContact TEXT NOT NULL,
            guardianName TEXT NOT NULL,
            guardianContact TEXT NOT NULL,
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            enrollmentDate TEXT NOT NULL, -- New field
            medicalInfo TEXT,
            photoPath TEXT,
            FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
          )
        ''');
        await db.execute('''
          CREATE TABLE payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            studentId TEXT NOT NULL,
            className TEXT NOT NULL,
            classAcademicYear TEXT NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            comment TEXT,
            isCancelled INTEGER DEFAULT 0,
            cancelledAt TEXT,
            cancelReason TEXT,
            cancelBy TEXT,
            recordedBy TEXT,
            FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY (className, classAcademicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
          )
        ''');
        await db.execute('''
          CREATE TABLE staff(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            role TEXT NOT NULL,
            department TEXT NOT NULL,
            phone TEXT NOT NULL,
            email TEXT NOT NULL,
            qualifications TEXT,
            courses TEXT,
            classes TEXT,
            status TEXT NOT NULL,
            hireDate TEXT NOT NULL,
            typeRole TEXT NOT NULL,

            -- Nouveaux champs
            first_name TEXT,
            last_name TEXT,
            gender TEXT,
            birth_date TEXT,
            birth_place TEXT,
            nationality TEXT,
            address TEXT,
            photo TEXT,
            matricule TEXT,
            id_number TEXT,
            social_security TEXT,
            marital_status TEXT,
            number_of_children INTEGER,
            region TEXT,
            levels TEXT,
            highest_degree TEXT,
            specialty TEXT,
            experience_years INTEGER,
            previous_institution TEXT,
            contract_type TEXT,
            base_salary REAL,
            weekly_hours INTEGER,
            supervisor TEXT,
            retirement_date TEXT,
            documents TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE categories(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            color TEXT NOT NULL,
            order_index INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE courses(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            categoryId TEXT,
            FOREIGN KEY (categoryId) REFERENCES categories(id) ON UPDATE CASCADE ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE grades(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            studentId TEXT NOT NULL,
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            subject TEXT NOT NULL,
            term TEXT NOT NULL,
            value REAL NOT NULL,
            label TEXT,
            maxValue REAL DEFAULT 20,
            coefficient REAL DEFAULT 1,
            type TEXT DEFAULT 'Devoir',
            subjectId TEXT,
            FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS grades_archive(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            studentId TEXT NOT NULL,
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            subject TEXT NOT NULL,
            term TEXT NOT NULL,
            value REAL NOT NULL,
            label TEXT,
            maxValue REAL DEFAULT 20,
            coefficient REAL DEFAULT 1,
            type TEXT DEFAULT 'Devoir',
            subjectId TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE subject_appreciation(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            studentId TEXT NOT NULL,
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            subject TEXT NOT NULL,
            term TEXT NOT NULL,
            professeur TEXT,
            appreciation TEXT,
            moyenne_classe TEXT,
            coefficient REAL,
            FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
          )
        ''');
        await db.execute('''
          CREATE TABLE class_courses(
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            courseId TEXT NOT NULL,
            coefficient REAL,
            weeklyHours REAL,
            PRIMARY KEY (className, academicYear, courseId),
            FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY (courseId) REFERENCES courses(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE teacher_assignments(
            id TEXT PRIMARY KEY,
            teacherId TEXT NOT NULL,
            courseId TEXT NOT NULL,
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            weeklyHours REAL,
            FOREIGN KEY (teacherId) REFERENCES staff(id) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY (courseId) REFERENCES courses(id) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL,
            category TEXT,
            supplier TEXT,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            className TEXT,
            academicYear TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS inventory_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            name TEXT NOT NULL,
            quantity INTEGER NOT NULL DEFAULT 0,
            location TEXT,
            itemCondition TEXT,
            value REAL,
            supplier TEXT,
            purchaseDate TEXT,
            className TEXT,
            academicYear TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS report_cards(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            studentId TEXT NOT NULL,
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            term TEXT NOT NULL,
            appreciation_generale TEXT,
            decision TEXT,
            fait_a TEXT,
            le_date TEXT,
            moyenne_generale REAL,
            rang INTEGER,
            nb_eleves INTEGER,
            mention TEXT,
            moyennes_par_periode TEXT, -- JSON encodé
            all_terms TEXT, -- JSON encodé
            moyenne_generale_classe REAL,
            moyenne_la_plus_forte REAL,
            moyenne_la_plus_faible REAL,
            moyenne_annuelle REAL,
            sanctions TEXT,
            FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS subject_appreciation_archive(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            report_card_id INTEGER NOT NULL,
            subject TEXT NOT NULL,
            professeur TEXT,
            appreciation TEXT,
            moyenne_classe TEXT,
            coefficient REAL,
            academicYear TEXT NOT NULL,
            FOREIGN KEY (report_card_id) REFERENCES report_cards_archive(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS report_cards_archive(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            studentId TEXT NOT NULL,
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            term TEXT NOT NULL,
            appreciation_generale TEXT,
            decision TEXT,
            fait_a TEXT,
            le_date TEXT,
            moyenne_generale REAL,
            rang INTEGER,
            exaequo INTEGER DEFAULT 0,
            nb_eleves INTEGER,
            mention TEXT,
            moyennes_par_periode TEXT, -- JSON encodé
            all_terms TEXT, -- JSON encodé
            moyenne_generale_classe REAL,
            moyenne_la_plus_forte REAL,
            moyenne_la_plus_faible REAL,
            moyenne_annuelle REAL,
            sanctions TEXT,
            FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
            FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS users(
            username TEXT PRIMARY KEY,
            displayName TEXT,
            role TEXT,
            passwordHash TEXT NOT NULL,
            salt TEXT NOT NULL,
            isTwoFactorEnabled INTEGER DEFAULT 0,
            totpSecret TEXT,
            isActive INTEGER DEFAULT 1,
            createdAt TEXT,
            lastLoginAt TEXT,
            permissions TEXT,
            staffId TEXT,
            FOREIGN KEY (staffId) REFERENCES staff(id) ON UPDATE CASCADE ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS school_info(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT NOT NULL,
            bp TEXT,
            telephone TEXT,
            email TEXT,
            website TEXT,
            logoPath TEXT,
            director TEXT,
            directorPrimary TEXT,
            directorCollege TEXT,
            directorLycee TEXT,
            directorUniversity TEXT,
            civilityPrimary TEXT,
            civilityCollege TEXT,
            civilityLycee TEXT,
            civilityUniversity TEXT,
            motto TEXT,
            republic TEXT,
            ministry TEXT,
            republicMotto TEXT,
            educationDirection TEXT,
            inspection TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS timetable_entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subject TEXT NOT NULL,
            teacher TEXT NOT NULL,
            className TEXT NOT NULL,
            academicYear TEXT NOT NULL,
            dayOfWeek TEXT NOT NULL,
            startTime TEXT NOT NULL,
            endTime TEXT NOT NULL,
            room TEXT,
            FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS import_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            filename TEXT,
            user TEXT,
            mode TEXT, -- partial or all_or_nothing
            className TEXT,
            academicYear TEXT,
            term TEXT,
            total INTEGER,
            success INTEGER,
            errors INTEGER,
            warnings INTEGER,
            details TEXT -- JSON array of row results
          )
        ''');
        // Indexes to speed up lookups
        await _ensureIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Centralize all schema adjustments in one place
        await _runPostOpenMigrations(db);
      },
    );
    await _runPostOpenMigrations(db);
    return db;
  }

  Future<void> _ensureIndexes(Database db) async {
    // Students
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_students_class ON students(className)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_students_class_year ON students(className, academicYear)',
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_students_enrollment ON students(enrollmentDate)",
    );
    // Payments
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_student_date ON payments(studentId, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_class ON payments(className)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_class_year ON payments(className, classAcademicYear)',
    );
    // Grades
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grades_lookup ON grades(studentId, className, academicYear, term)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grades_subject ON grades(subject, subjectId)',
    );
    // Report cards
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_report_cards_lookup ON report_cards(studentId, className, academicYear, term)',
    );
    // Subject appreciation
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_subject_app_lookup ON subject_appreciation(studentId, className, academicYear, term)',
    );
    // Timetable
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tt_class_day_time ON timetable_entries(className, dayOfWeek, startTime)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tt_class_year_day_time ON timetable_entries(className, academicYear, dayOfWeek, startTime)',
    );
    // Users
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_users_active ON users(isActive)',
    );
  }

  Future<void> _runPostOpenMigrations(Database db) async {
    debugPrint('[DatabaseService][MIGRATION] Starting post-open migrations...');
    // Idempotent, safe to run on every open
    await _migrateClassesCompositeKey(db);
    await _ensureClassRelatedColumns(db);
    await _ensureIndexes(db);
    await _migrateGradesSubjectId(db);
    await _migrateReportCardsExtraFields(db);
    await _migrateStudentsEnrollmentDate(db);
    await _ensureUsersPermissionsColumn(db);
    await _ensureUsersSecurityColumns(db);
    await _ensureUsersStaffIdColumn(db);
    await _ensureStudentAcademicYearColumn(db);
    await _ensureImportLogsTable(db);
    await _ensureStudentStatusColumn(db);
    await _migrateForeignKeysWithCascade(db);
    await _dropClassesBackup(db);
    await _migrateStaffTable(db);
    await _ensureStudentMatriculeColumn(db);
    await _ensureStudentNameColumns(db);
    await _ensureStudentPlaceOfBirthColumn(db);
    await _ensureStudentDocumentsColumn(db);
    await _ensureStudentSoftDeleteColumns(db);
    await _ensureSchoolInfoColumns(db);
    await _ensureArchiveExtraColumns(db);
    await _migrateSignaturesTable(db);
    await _ensureSubjectAppreciationCoeffColumns(db);
    await _ensureClassCoursesCoeffColumn(db);
    await _ensureClassCoursesWeeklyHoursColumn(db);
    await _ensureTeacherAssignmentsTable(db);
    await _ensureTeacherUnavailabilityTable(db);
    await _ensureInventoryTable(db);
    await _ensureExpensesTable(db);
    await _ensureSuppliersTable(db);
    await _ensureExpenseAttachmentsTable(db);
    await _ensureFinanceBudgetsTable(db);
    await _ensurePaymentCancelReason(db);
    await _ensureAuditTable(db);
    await _ensureExpensesTable(db);
    await _ensureSignaturesTable(db);
    await _ensureLibraryTables(db);
    await _ensureDisciplineTables(db);
    await _ensureStaffAbsencesTable(db);
    await _ensurePaymentReceiptCountersTable(db);
    await _ensurePaymentAdjustmentsTable(db);
    await _ensurePaymentAttachmentsTable(db);
    await _ensurePaymentScheduleRulesTable(db);
    await _ensureGradesPeriodWorkflowTable(db);
    await _ensureEvaluationTemplatesTable(db);
    await _ensurePermissionGroupsTable(db);
    await _ensureUserSessionsTable(db);
    debugPrint(
      '[DatabaseService][MIGRATION] All post-open migrations completed',
    );
  }

  Future<void> _ensureUsersSecurityColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(users)');
    final hasFailed = cols.any((c) => c['name'] == 'failedLoginCount');
    if (!hasFailed) {
      try {
        await db.execute(
          'ALTER TABLE users ADD COLUMN failedLoginCount INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
    final hasLockedUntil = cols.any((c) => c['name'] == 'lockedUntil');
    if (!hasLockedUntil) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN lockedUntil TEXT');
      } catch (_) {}
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_users_lockedUntil ON users(lockedUntil)',
    );
  }

  Future<void> _ensureUsersStaffIdColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(users)');
    final has = cols.any((c) => c['name'] == 'staffId');
    if (!has) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN staffId TEXT');
      } catch (_) {}
    }
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_users_staffId ON users(staffId)',
      );
    } catch (_) {}
    // SQLite unique indexes allow multiple NULL values, which is what we want.
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_staffId_unique ON users(staffId)',
      );
    } catch (_) {}
  }

  Future<void> _ensurePermissionGroupsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS permission_groups(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        permissionsJson TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        updatedBy TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_permission_groups_name ON permission_groups(name)',
    );
  }

  Future<void> _ensureUserSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        loginAt TEXT NOT NULL,
        lastSeenAt TEXT NOT NULL,
        logoutAt TEXT,
        device TEXT,
        ip TEXT,
        FOREIGN KEY (username) REFERENCES users(username) ON UPDATE CASCADE ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_sessions_username ON user_sessions(username)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_sessions_lastSeen ON user_sessions(lastSeenAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_sessions_logout ON user_sessions(logoutAt)',
    );
  }

  Future<void> _ensurePaymentReceiptCountersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_receipt_counters(
        academicYear TEXT PRIMARY KEY,
        seq INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _ensurePaymentAdjustmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_adjustments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId TEXT NOT NULL,
        className TEXT NOT NULL,
        classAcademicYear TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        reason TEXT,
        createdAt TEXT NOT NULL,
        createdBy TEXT,
        isCancelled INTEGER NOT NULL DEFAULT 0,
        cancelledAt TEXT,
        cancelReason TEXT,
        cancelBy TEXT,
        FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (className, classAcademicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_adj_student_year ON payment_adjustments(studentId, classAcademicYear)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_adj_class_year ON payment_adjustments(className, classAcademicYear)',
    );
  }

  Future<void> _ensurePaymentAttachmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_attachments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        paymentId INTEGER NOT NULL,
        studentId TEXT NOT NULL,
        classAcademicYear TEXT NOT NULL,
        fileName TEXT NOT NULL,
        filePath TEXT NOT NULL,
        sizeBytes INTEGER,
        createdAt TEXT NOT NULL,
        createdBy TEXT,
        FOREIGN KEY (paymentId) REFERENCES payments(id) ON UPDATE CASCADE ON DELETE CASCADE,
        FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_attach_payment ON payment_attachments(paymentId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_attach_student_year ON payment_attachments(studentId, classAcademicYear)',
    );
  }

  Future<void> _ensurePaymentScheduleRulesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_schedule_rules(
        classAcademicYear TEXT NOT NULL,
        className TEXT,
        scheduleJson TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        updatedBy TEXT,
        PRIMARY KEY (classAcademicYear, className)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_schedule_year ON payment_schedule_rules(classAcademicYear)',
    );
  }

  Future<void> _ensureEvaluationTemplatesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS evaluation_templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        className TEXT NOT NULL,
        academicYear TEXT NOT NULL,
        subjectId TEXT NOT NULL,
        subject TEXT NOT NULL,
        type TEXT NOT NULL,
        label TEXT NOT NULL,
        maxValue REAL NOT NULL DEFAULT 20,
        coefficient REAL NOT NULL DEFAULT 1,
        orderIndex INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_eval_tpl_lookup ON evaluation_templates(className, academicYear, subjectId, type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_eval_tpl_order ON evaluation_templates(className, academicYear, subjectId, type, orderIndex)',
    );
  }

  Future<void> _ensureGradesPeriodWorkflowTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS grades_period_workflow(
        className TEXT NOT NULL,
        academicYear TEXT NOT NULL,
        term TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Brouillon',
        locked INTEGER NOT NULL DEFAULT 0,
        updatedAt TEXT NOT NULL,
        updatedBy TEXT,
        PRIMARY KEY (className, academicYear, term),
        FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grades_workflow_lookup ON grades_period_workflow(className, academicYear, term)',
    );
  }

  Future<void> _ensureStaffAbsencesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_absences(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staffId TEXT NOT NULL,
        type TEXT NOT NULL,
        startDate TEXT NOT NULL,
        endDate TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Prévu',
        reason TEXT,
        recordedBy TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (staffId) REFERENCES staff(id) ON UPDATE CASCADE ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_staff_absences_staff ON staff_absences(staffId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_staff_absences_dates ON staff_absences(startDate, endDate)',
    );
  }

  Future<void> _ensureDisciplineTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId TEXT NOT NULL,
        academicYear TEXT NOT NULL,
        className TEXT NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        minutes INTEGER NOT NULL DEFAULT 0,
        justified INTEGER NOT NULL DEFAULT 0,
        reason TEXT,
        recordedBy TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sanction_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId TEXT NOT NULL,
        academicYear TEXT NOT NULL,
        className TEXT NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        description TEXT NOT NULL,
        recordedBy TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attendance_year_class_date ON attendance_events(academicYear, className, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attendance_student_date ON attendance_events(studentId, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attendance_type ON attendance_events(type)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sanctions_year_class_date ON sanction_events(academicYear, className, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sanctions_student_date ON sanction_events(studentId, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sanctions_type ON sanction_events(type)',
    );
  }

  Future<void> _ensureLibraryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_books(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        coverImagePath TEXT,
        isbn TEXT,
        category TEXT,
        publishedYear INTEGER,
        totalCopies INTEGER NOT NULL DEFAULT 1,
        availableCopies INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    try {
      final cols = await db.rawQuery("PRAGMA table_info(library_books)");
      final names = cols.map((c) => c['name'] as String).toSet();
      if (!names.contains('coverImagePath')) {
        await db.execute(
          'ALTER TABLE library_books ADD COLUMN coverImagePath TEXT',
        );
      }
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batchId TEXT,
        bookId TEXT NOT NULL,
        studentId TEXT NOT NULL,
        loanDate TEXT NOT NULL,
        dueDate TEXT NOT NULL,
        returnDate TEXT,
        status TEXT NOT NULL DEFAULT 'borrowed',
        recordedBy TEXT,
        FOREIGN KEY (bookId) REFERENCES library_books(id) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_loan_batches(
        id TEXT PRIMARY KEY,
        studentId TEXT NOT NULL,
        loanDate TEXT NOT NULL,
        dueDate TEXT NOT NULL,
        recordedBy TEXT,
        FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    try {
      final cols = await db.rawQuery("PRAGMA table_info(library_loans)");
      final names = cols.map((c) => c['name'] as String).toSet();
      if (!names.contains('batchId')) {
        await db.execute('ALTER TABLE library_loans ADD COLUMN batchId TEXT');
      }
    } catch (_) {}
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_books_title ON library_books(title)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_books_author ON library_books(author)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_loans_book_status ON library_loans(bookId, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_loans_student_status ON library_loans(studentId, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_loans_due ON library_loans(dueDate)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_loans_batch ON library_loans(batchId)',
    );
  }

  Future<List<LibraryBook>> getLibraryBooks({String? query}) async {
    final db = await database;
    final q = (query ?? '').trim();
    if (q.isEmpty) {
      final rows = await db.query(
        'library_books',
        orderBy: 'title COLLATE NOCASE ASC',
      );
      return rows.map(LibraryBook.fromMap).toList();
    }
    final like = '%$q%';
    final rows = await db.query(
      'library_books',
      where:
          'title LIKE ? OR author LIKE ? OR (isbn IS NOT NULL AND isbn LIKE ?)',
      whereArgs: [like, like, like],
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return rows.map(LibraryBook.fromMap).toList();
  }

  Future<void> upsertLibraryBook(LibraryBook book) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final normalized = book.copyWith(
      createdAt: book.createdAt.trim().isEmpty ? now : book.createdAt,
      updatedAt: now,
      totalCopies: book.totalCopies < 0 ? 0 : book.totalCopies,
      availableCopies: book.availableCopies < 0 ? 0 : book.availableCopies,
    );
    await db.transaction((txn) async {
      final existing = await txn.query(
        'library_books',
        columns: const ['id', 'totalCopies', 'availableCopies', 'createdAt'],
        where: 'id = ?',
        whereArgs: [normalized.id],
        limit: 1,
      );

      final borrowedActive =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              "SELECT COUNT(*) FROM library_loans WHERE bookId = ? AND status = 'borrowed'",
              [normalized.id],
            ),
          ) ??
          0;

      final total = normalized.totalCopies;
      if (total < borrowedActive) {
        throw Exception(
          'Impossible de réduire les exemplaires à $total: $borrowedActive emprunt(s) actif(s).',
        );
      }
      final maxAvailable = total - borrowedActive;
      final available = normalized.availableCopies > maxAvailable
          ? maxAvailable
          : normalized.availableCopies;

      if (existing.isEmpty) {
        await txn.insert(
          'library_books',
          normalized.copyWith(availableCopies: available).toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        return;
      }

      final existingCreatedAt = (existing.first['createdAt'] as String?) ?? now;
      await txn.update(
        'library_books',
        normalized
            .copyWith(createdAt: existingCreatedAt, availableCopies: available)
            .toMap(),
        where: 'id = ?',
        whereArgs: [normalized.id],
      );
    });
    try {
      await logAudit(
        category: 'library',
        action: 'upsert_book',
        details:
            'id=${normalized.id} title=${normalized.title} total=${normalized.totalCopies}',
      );
    } catch (_) {}
  }

  Future<void> deleteLibraryBook(String bookId) async {
    final db = await database;
    final active =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM library_loans WHERE bookId = ? AND status = 'borrowed'",
            [bookId],
          ),
        ) ??
        0;
    if (active > 0) {
      throw Exception(
        'Impossible de supprimer ce livre: des emprunts sont encore actifs.',
      );
    }
    await db.delete('library_books', where: 'id = ?', whereArgs: [bookId]);
    try {
      await logAudit(
        category: 'library',
        action: 'delete_book',
        details: 'id=$bookId',
      );
    } catch (_) {}
  }

  Future<void> borrowLibraryBook({
    required String bookId,
    required String studentId,
    required DateTime dueDate,
    String? recordedBy,
  }) async {
    await createLibraryLoanBatch(
      studentId: studentId,
      bookIds: [bookId],
      dueDate: dueDate,
      recordedBy: recordedBy,
    );
    try {
      await logAudit(
        category: 'library',
        action: 'borrow',
        details:
            'book=$bookId student=$studentId due=${dueDate.toIso8601String()}',
      );
    } catch (_) {}
  }

  Future<String> createLibraryLoanBatch({
    required String studentId,
    required List<String> bookIds,
    required DateTime dueDate,
    String? recordedBy,
  }) async {
    final db = await database;
    final ids = bookIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) throw Exception('Aucun livre sélectionné.');
    final unique = ids.toSet().toList();
    final now = DateTime.now().toIso8601String();
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();

    await db.transaction((txn) async {
      // Ensure student exists
      final studentRows = await txn.query(
        'students',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [studentId],
        limit: 1,
      );
      if (studentRows.isEmpty) throw Exception('Élève introuvable.');

      // Check availability for each book
      for (final bookId in unique) {
        final bookRows = await txn.query(
          'library_books',
          where: 'id = ?',
          whereArgs: [bookId],
          limit: 1,
        );
        if (bookRows.isEmpty) {
          throw Exception('Livre introuvable: $bookId');
        }
        final book = LibraryBook.fromMap(bookRows.first);
        if (book.availableCopies <= 0) {
          throw Exception('Aucun exemplaire disponible: ${book.title}');
        }
      }

      await txn.insert('library_loan_batches', {
        'id': batchId,
        'studentId': studentId,
        'loanDate': now,
        'dueDate': dueDate.toIso8601String(),
        'recordedBy': recordedBy,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      for (final bookId in unique) {
        final bookRows = await txn.query(
          'library_books',
          where: 'id = ?',
          whereArgs: [bookId],
          limit: 1,
        );
        final book = LibraryBook.fromMap(bookRows.first);
        await txn.update(
          'library_books',
          {
            'availableCopies': book.availableCopies - 1,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [bookId],
        );
        await txn.insert('library_loans', {
          'batchId': batchId,
          'bookId': bookId,
          'studentId': studentId,
          'loanDate': now,
          'dueDate': dueDate.toIso8601String(),
          'returnDate': null,
          'status': 'borrowed',
          'recordedBy': recordedBy,
        });
      }
    });

    try {
      await logAudit(
        category: 'library',
        action: 'borrow_batch',
        details:
            'batch=$batchId student=$studentId count=${unique.length} due=${dueDate.toIso8601String()}',
      );
    } catch (_) {}
    return batchId;
  }

  Future<String> ensureLibraryLoanBatchForLoan({required int loanId}) async {
    final db = await database;
    var created = false;
    final ensured = await db.transaction((txn) async {
      final rows = await txn.query(
        'library_loans',
        where: 'id = ?',
        whereArgs: [loanId],
        limit: 1,
      );
      if (rows.isEmpty) throw Exception('Emprunt introuvable.');
      final loan = LibraryLoan.fromMap(rows.first);
      final existing = (loan.batchId ?? '').trim();
      if (existing.isNotEmpty) return existing;

      final candidate = 'loan_$loanId';
      var batchId = candidate;
      final batchRow = {
        'id': batchId,
        'studentId': loan.studentId,
        'loanDate': loan.loanDate,
        'dueDate': loan.dueDate,
        'recordedBy': loan.recordedBy,
      };
      try {
        await txn.insert(
          'library_loan_batches',
          batchRow,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } catch (_) {
        batchId = '${candidate}_${DateTime.now().millisecondsSinceEpoch}';
        await txn.insert('library_loan_batches', {
          ...batchRow,
          'id': batchId,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      await txn.update(
        'library_loans',
        {'batchId': batchId},
        where: 'id = ?',
        whereArgs: [loanId],
      );
      created = true;
      return batchId;
    });

    if (created) {
      try {
        await logAudit(
          category: 'library',
          action: 'link_batch',
          details: 'loan=$loanId batch=$ensured',
        );
      } catch (_) {}
    }
    return ensured;
  }

  Future<Map<String, dynamic>?> getLibraryLoanBatchDetails(
    String batchId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        b.id as batchId,
        b.loanDate,
        b.dueDate,
        b.recordedBy,
        s.id as studentId,
        COALESCE(s.name, (s.firstName || ' ' || s.lastName)) as studentName,
        s.className as studentClassName,
        s.academicYear as studentAcademicYear
      FROM library_loan_batches b
      INNER JOIN students s ON s.id = b.studentId
      WHERE b.id = ?
      LIMIT 1
    ''',
      [batchId],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> getLibraryLoanBatchItems(
    String batchId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        l.id as loanId,
        l.bookId,
        l.studentId,
        l.loanDate,
        l.dueDate,
        l.status,
        b.title as bookTitle,
        b.author as bookAuthor,
        b.isbn as bookIsbn
      FROM library_loans l
      INNER JOIN library_books b ON b.id = l.bookId
      WHERE l.batchId = ?
      ORDER BY b.title COLLATE NOCASE ASC
    ''',
      [batchId],
    );
  }

  Future<void> returnLibraryLoan({required int loanId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final loanRows = await txn.query(
        'library_loans',
        where: 'id = ?',
        whereArgs: [loanId],
        limit: 1,
      );
      if (loanRows.isEmpty) throw Exception('Emprunt introuvable.');
      final loan = LibraryLoan.fromMap(loanRows.first);
      if (loan.status != 'borrowed') return;

      await txn.update(
        'library_loans',
        {'status': 'returned', 'returnDate': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [loanId],
      );

      final bookRows = await txn.query(
        'library_books',
        where: 'id = ?',
        whereArgs: [loan.bookId],
        limit: 1,
      );
      if (bookRows.isEmpty) return;
      final book = LibraryBook.fromMap(bookRows.first);
      final nextAvailable = (book.availableCopies + 1) > book.totalCopies
          ? book.totalCopies
          : (book.availableCopies + 1);
      await txn.update(
        'library_books',
        {
          'availableCopies': nextAvailable,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [loan.bookId],
      );
    });
    try {
      await logAudit(
        category: 'library',
        action: 'return',
        details: 'loan=$loanId',
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getLibraryLoansView({
    bool onlyActive = true,
  }) async {
    final db = await database;
    final where = onlyActive ? "WHERE l.status = 'borrowed'" : '';
    final rows = await db.rawQuery('''
      SELECT
        l.id as loanId,
        l.batchId,
        l.status,
        l.loanDate,
        l.dueDate,
        l.returnDate,
        l.recordedBy,
        b.id as bookId,
        b.title as bookTitle,
        b.author as bookAuthor,
        s.id as studentId,
        COALESCE(s.name, (s.firstName || ' ' || s.lastName)) as studentName,
        s.className as studentClassName,
        s.academicYear as studentAcademicYear
      FROM library_loans l
      INNER JOIN library_books b ON b.id = l.bookId
      INNER JOIN students s ON s.id = l.studentId
      $where
      ORDER BY l.dueDate ASC
    ''');
    return rows;
  }

  Future<List<LibraryBook>> getLibraryBooksByLastUpdate() async {
    final db = await database;
    final rows = await db.query('library_books', orderBy: 'updatedAt DESC');
    return rows.map(LibraryBook.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getAttendanceEvents({
    required String academicYear,
    String? className,
    String? studentId,
    String? type,
  }) async {
    final db = await database;
    final parts = <String>['e.academicYear = ?'];
    final args = <Object?>[academicYear];
    if ((className ?? '').trim().isNotEmpty) {
      parts.add('e.className = ?');
      args.add(className!.trim());
    }
    if ((studentId ?? '').trim().isNotEmpty) {
      parts.add('e.studentId = ?');
      args.add(studentId!.trim());
    }
    if ((type ?? '').trim().isNotEmpty) {
      parts.add('e.type = ?');
      args.add(type!.trim());
    }
    final where = parts.join(' AND ');
    return db.rawQuery('''
      SELECT
        e.*,
        COALESCE(s.name, (s.firstName || ' ' || s.lastName)) as studentName
      FROM attendance_events e
      INNER JOIN students s ON s.id = e.studentId
      WHERE $where
      ORDER BY e.date DESC, e.id DESC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getAttendanceTotals({
    required String academicYear,
    String? className,
    String? studentId,
  }) async {
    final db = await database;
    final parts = <String>['e.academicYear = ?'];
    final args = <Object?>[academicYear];
    if ((className ?? '').trim().isNotEmpty) {
      parts.add('e.className = ?');
      args.add(className!.trim());
    }
    if ((studentId ?? '').trim().isNotEmpty) {
      parts.add('e.studentId = ?');
      args.add(studentId!.trim());
    }
    final where = parts.join(' AND ');
    return db.rawQuery('''
      SELECT
        e.studentId,
        e.className,
        COALESCE(s.name, (s.firstName || ' ' || s.lastName)) as studentName,
        SUM(CASE WHEN e.type = 'absence' THEN e.minutes ELSE 0 END) as absenceMinutes,
        SUM(CASE WHEN e.type = 'retard' THEN e.minutes ELSE 0 END) as retardMinutes,
        SUM(CASE WHEN e.type = 'absence' THEN 1 ELSE 0 END) as absenceCount,
        SUM(CASE WHEN e.type = 'retard' THEN 1 ELSE 0 END) as retardCount,
        SUM(CASE WHEN e.type = 'absence' AND e.justified = 1 THEN e.minutes ELSE 0 END) as absenceJustifiedMinutes,
        SUM(CASE WHEN e.type = 'absence' AND e.justified = 0 THEN e.minutes ELSE 0 END) as absenceUnjustifiedMinutes,
        SUM(CASE WHEN e.type = 'retard' AND e.justified = 1 THEN e.minutes ELSE 0 END) as retardJustifiedMinutes,
        SUM(CASE WHEN e.type = 'retard' AND e.justified = 0 THEN e.minutes ELSE 0 END) as retardUnjustifiedMinutes
      FROM attendance_events e
      INNER JOIN students s ON s.id = e.studentId
      WHERE $where
      GROUP BY e.studentId, e.className
      ORDER BY studentName COLLATE NOCASE ASC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getSanctionEvents({
    required String academicYear,
    String? className,
    String? studentId,
    String? type,
  }) async {
    final db = await database;
    final parts = <String>['e.academicYear = ?'];
    final args = <Object?>[academicYear];
    if ((className ?? '').trim().isNotEmpty) {
      parts.add('e.className = ?');
      args.add(className!.trim());
    }
    if ((studentId ?? '').trim().isNotEmpty) {
      parts.add('e.studentId = ?');
      args.add(studentId!.trim());
    }
    if ((type ?? '').trim().isNotEmpty) {
      parts.add('e.type = ?');
      args.add(type!.trim());
    }
    final where = parts.join(' AND ');
    return db.rawQuery('''
      SELECT
        e.*,
        COALESCE(s.name, (s.firstName || ' ' || s.lastName)) as studentName
      FROM sanction_events e
      INNER JOIN students s ON s.id = e.studentId
      WHERE $where
      ORDER BY e.date DESC, e.id DESC
    ''', args);
  }

  Future<int> insertAttendanceEvent({
    required String studentId,
    required String academicYear,
    required String className,
    required DateTime date,
    required String type,
    required int minutes,
    required bool justified,
    String? reason,
    String? recordedBy,
  }) async {
    final db = await database;
    await _ensureStudentExists(db, studentId);
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('attendance_events', {
      'studentId': studentId,
      'academicYear': academicYear,
      'className': className,
      'date': date.toIso8601String(),
      'type': type,
      'minutes': minutes < 0 ? 0 : minutes,
      'justified': justified ? 1 : 0,
      'reason': (reason ?? '').trim(),
      'recordedBy': recordedBy,
      'createdAt': now,
      'updatedAt': now,
    });
    try {
      await logAudit(
        category: 'discipline',
        action: 'add_attendance',
        details:
            'id=$id student=$studentId type=$type date=${date.toIso8601String()}',
      );
    } catch (_) {}
    return id;
  }

  Future<void> updateAttendanceEvent({
    required int id,
    required DateTime date,
    required String type,
    required int minutes,
    required bool justified,
    String? reason,
    String? recordedBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'attendance_events',
      {
        'date': date.toIso8601String(),
        'type': type,
        'minutes': minutes < 0 ? 0 : minutes,
        'justified': justified ? 1 : 0,
        'reason': (reason ?? '').trim(),
        'recordedBy': recordedBy,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await logAudit(
        category: 'discipline',
        action: 'update_attendance',
        details: 'id=$id type=$type date=${date.toIso8601String()}',
      );
    } catch (_) {}
  }

  Future<int> insertSanctionEvent({
    required String studentId,
    required String academicYear,
    required String className,
    required DateTime date,
    required String type,
    required String description,
    String? recordedBy,
  }) async {
    final db = await database;
    await _ensureStudentExists(db, studentId);
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('sanction_events', {
      'studentId': studentId,
      'academicYear': academicYear,
      'className': className,
      'date': date.toIso8601String(),
      'type': type,
      'description': description,
      'recordedBy': recordedBy,
      'createdAt': now,
      'updatedAt': now,
    });
    try {
      await logAudit(
        category: 'discipline',
        action: 'add_sanction',
        details:
            'id=$id student=$studentId type=$type date=${date.toIso8601String()}',
      );
    } catch (_) {}
    return id;
  }

  Future<void> updateSanctionEvent({
    required int id,
    required DateTime date,
    required String type,
    required String description,
    String? recordedBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sanction_events',
      {
        'date': date.toIso8601String(),
        'type': type,
        'description': description,
        'recordedBy': recordedBy,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await logAudit(
        category: 'discipline',
        action: 'update_sanction',
        details: 'id=$id type=$type date=${date.toIso8601String()}',
      );
    } catch (_) {}
  }

  Future<void> deleteAttendanceEvent({required int id}) async {
    final db = await database;
    await db.delete('attendance_events', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'discipline',
        action: 'delete_attendance',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<void> deleteSanctionEvent({required int id}) async {
    final db = await database;
    await db.delete('sanction_events', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'discipline',
        action: 'delete_sanction',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<void> _ensureAuditTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        username TEXT,
        category TEXT NOT NULL,
        action TEXT NOT NULL,
        details TEXT,
        success INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_logs(timestamp)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_cat ON audit_logs(category)',
    );
  }

  Future<void> _ensureSignaturesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS signatures(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        imagePath TEXT,
        description TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        associatedClass TEXT,
        associatedRole TEXT,
        staffId TEXT,
        isDefault INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signatures_type ON signatures(type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signatures_active ON signatures(isActive)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signatures_class ON signatures(associatedClass)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signatures_role ON signatures(associatedRole)',
    );
  }

  Future<void> _migrateSignaturesTable(Database db) async {
    // Vérifier si les nouvelles colonnes existent déjà
    final columns = await db.rawQuery("PRAGMA table_info(signatures)");
    final columnNames = columns.map((col) => col['name'] as String).toList();

    // Liste des nouvelles colonnes à ajouter
    final newColumns = [
      'associatedClass TEXT',
      'associatedRole TEXT',
      'staffId TEXT',
      'isDefault INTEGER NOT NULL DEFAULT 0',
    ];

    for (final column in newColumns) {
      final columnName = column.split(' ')[0];
      if (!columnNames.contains(columnName)) {
        try {
          await db.execute('ALTER TABLE signatures ADD COLUMN $column');
        } catch (e) {
          // Ignorer les erreurs si la colonne existe déjà
        }
      }
    }

    // Créer les nouveaux index
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_signatures_class ON signatures(associatedClass)',
      );
    } catch (e) {
      // Ignorer les erreurs si l'index existe déjà
    }

    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_signatures_role ON signatures(associatedRole)',
      );
    } catch (e) {
      // Ignorer les erreurs si l'index existe déjà
    }
  }

  Future<void> logAudit({
    required String category,
    required String action,
    String? details,
    String? username,
    bool success = true,
  }) async {
    final db = await database;
    // Récupérer le nom d'utilisateur courant si non fourni
    String? effectiveUser = username;
    if (effectiveUser == null || effectiveUser.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(
          const Duration(seconds: 1),
        );
        effectiveUser = prefs.getString('current_username');
      } catch (_) {}
    }
    await db.insert('audit_logs', {
      'timestamp': DateTime.now().toIso8601String(),
      'username': effectiveUser,
      'category': category,
      'action': action,
      'details': details,
      'success': success ? 1 : 0,
    });
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({
    String? category,
    String? username,
    int limit = 500,
  }) async {
    final db = await database;
    String where = '';
    final args = <Object?>[];
    if (category != null && category.isNotEmpty) {
      where += (where.isEmpty ? '' : ' AND ') + 'category = ?';
      args.add(category);
    }
    if (username != null && username.isNotEmpty) {
      where += (where.isEmpty ? '' : ' AND ') + 'username = ?';
      args.add(username);
    }
    return await db.query(
      'audit_logs',
      where: where.isEmpty ? null : where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  /// Purge les anciens journaux d'audit de plus de [days] jours.
  Future<int> deleteOldAuditLogs(int days) async {
    final db = await database;
    final limitDate = DateTime.now().subtract(Duration(days: days));
    final limitStr = limitDate.toIso8601String();
    return await db.delete(
      'audit_logs',
      where: 'timestamp < ?',
      whereArgs: [limitStr],
    );
  }

  Future<List<Map<String, dynamic>>> getAuditLogsForStudent({
    required String studentId,
    int limit = 300,
  }) async {
    final db = await database;
    final id = studentId.trim();
    if (id.isEmpty) return const [];
    // Heuristic: many actions log details like "student=<id>" or "id=<id>".
    final likeAny = '%$id%';
    return db.query(
      'audit_logs',
      where:
          "(details LIKE ? OR details LIKE ? OR details LIKE ? OR details LIKE ?)",
      whereArgs: ['%student=$id%', '%studentId=$id%', '%id=$id%', likeAny],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getAuditLogsForStaff({
    required String staffId,
    int limit = 300,
  }) async {
    final db = await database;
    final id = staffId.trim();
    if (id.isEmpty) return const [];
    final likeAny = '%$id%';
    return db.query(
      'audit_logs',
      where: "(details LIKE ? OR details LIKE ? OR details LIKE ?)",
      whereArgs: ['%staff=$id%', '%staffId=$id%', likeAny],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<void> _ensurePaymentCancelReason(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(payments)');
    final has = cols.any((c) => c['name'] == 'cancelReason');
    if (!has) {
      try {
        await db.execute('ALTER TABLE payments ADD COLUMN cancelReason TEXT');
        debugPrint('[DatabaseService][MIGRATION] Added payments.cancelReason');
      } catch (e) {
        debugPrint('[DatabaseService][MIGRATION][ERROR] cancelReason: $e');
      }
    }
    final hasBy = cols.any((c) => c['name'] == 'cancelBy');
    if (!hasBy) {
      try {
        await db.execute('ALTER TABLE payments ADD COLUMN cancelBy TEXT');
        debugPrint('[DatabaseService][MIGRATION] Added payments.cancelBy');
      } catch (e) {
        debugPrint('[DatabaseService][MIGRATION][ERROR] cancelBy: $e');
      }
    }
    final hasRecordedBy = cols.any((c) => c['name'] == 'recordedBy');
    if (!hasRecordedBy) {
      try {
        await db.execute('ALTER TABLE payments ADD COLUMN recordedBy TEXT');
        debugPrint('[DatabaseService][MIGRATION] Added payments.recordedBy');
      } catch (e) {
        debugPrint('[DatabaseService][MIGRATION][ERROR] recordedBy: $e');
      }
    }
  }

  Future<void> _ensureInventoryTable(Database db) async {
    // Create table if missing
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        minQuantity INTEGER,
        location TEXT,
        itemCondition TEXT,
        value REAL,
        supplier TEXT,
        purchaseDate TEXT,
        notes TEXT,
        className TEXT,
        academicYear TEXT NOT NULL
      )
    ''');
    final cols = await db.rawQuery('PRAGMA table_info(inventory_items)');
    final hasMin = cols.any((c) => c['name'] == 'minQuantity');
    if (!hasMin) {
      await db.execute(
        'ALTER TABLE inventory_items ADD COLUMN minQuantity INTEGER',
      );
    }
    final hasNotes = cols.any((c) => c['name'] == 'notes');
    if (!hasNotes) {
      await db.execute('ALTER TABLE inventory_items ADD COLUMN notes TEXT');
    }
    // Indexes
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inv_year_class ON inventory_items(academicYear, className)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inv_category ON inventory_items(category)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inv_condition ON inventory_items(itemCondition)',
    );
  }

  Future<void> _ensureTeacherUnavailabilityTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teacher_unavailability(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        teacher TEXT NOT NULL,
        academicYear TEXT NOT NULL,
        dayOfWeek TEXT NOT NULL,
        startTime TEXT NOT NULL,
        UNIQUE(teacher, academicYear, dayOfWeek, startTime)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_unavail_teacher_year ON teacher_unavailability(teacher, academicYear)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_unavail_day_time ON teacher_unavailability(dayOfWeek, startTime)',
    );
  }

  Future<void> _ensureExpensesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        category TEXT,
        supplierId INTEGER,
        supplier TEXT,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        className TEXT,
        academicYear TEXT NOT NULL
      )
    ''');
    // Add missing columns if needed
    final cols = await db.rawQuery('PRAGMA table_info(expenses)');
    bool hasSupplier = cols.any((c) => c['name'] == 'supplier');
    if (!hasSupplier) {
      await db.execute('ALTER TABLE expenses ADD COLUMN supplier TEXT');
    }
    final hasSupplierId = cols.any((c) => c['name'] == 'supplierId');
    if (!hasSupplierId) {
      await db.execute('ALTER TABLE expenses ADD COLUMN supplierId INTEGER');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exp_year_class ON expenses(academicYear, className)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exp_date ON expenses(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exp_category ON expenses(category)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exp_supplierId ON expenses(supplierId)',
    );
  }

  Future<void> _ensureSuppliersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(name)',
    );
  }

  Future<void> _ensureExpenseAttachmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_attachments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expenseId INTEGER NOT NULL,
        academicYear TEXT NOT NULL,
        fileName TEXT NOT NULL,
        filePath TEXT NOT NULL,
        sizeBytes INTEGER,
        createdAt TEXT NOT NULL,
        createdBy TEXT,
        FOREIGN KEY (expenseId) REFERENCES expenses(id) ON UPDATE CASCADE ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exp_attach_expense ON expense_attachments(expenseId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exp_attach_year ON expense_attachments(academicYear)',
    );
  }

  Future<void> _ensureFinanceBudgetsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS finance_budgets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        academicYear TEXT NOT NULL,
        category TEXT NOT NULL,
        className TEXT,
        plannedAmount REAL NOT NULL,
        updatedAt TEXT NOT NULL,
        updatedBy TEXT,
        UNIQUE(academicYear, category, className)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_budget_year ON finance_budgets(academicYear)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_budget_category ON finance_budgets(category)',
    );
  }

  Future<void> _ensureSubjectAppreciationCoeffColumns(Database db) async {
    Future<void> addCoeff(String table) async {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      final has = cols.any((c) => c['name'] == 'coefficient');
      if (!has) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN coefficient REAL');
          debugPrint(
            '[DatabaseService][MIGRATION] Added coefficient column to $table',
          );
        } catch (e) {
          debugPrint(
            '[DatabaseService][MIGRATION][ERROR] Failed to add coefficient to $table: $e',
          );
        }
      }
    }

    await addCoeff('subject_appreciation');
    await addCoeff('subject_appreciation_archive');
  }

  Future<void> _ensureClassCoursesCoeffColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(class_courses)');
    final has = cols.any((c) => c['name'] == 'coefficient');
    if (!has) {
      try {
        await db.execute(
          'ALTER TABLE class_courses ADD COLUMN coefficient REAL',
        );
        debugPrint(
          '[DatabaseService][MIGRATION] Added coefficient column to class_courses',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add coefficient to class_courses: $e',
        );
      }
    }
  }

  Future<void> _ensureClassCoursesWeeklyHoursColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(class_courses)');
    final has = cols.any((c) => c['name'] == 'weeklyHours');
    if (!has) {
      try {
        await db.execute(
          'ALTER TABLE class_courses ADD COLUMN weeklyHours REAL',
        );
        debugPrint(
          '[DatabaseService][MIGRATION] Added weeklyHours column to class_courses',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add weeklyHours to class_courses: $e',
        );
      }
    }
  }

  Future<void> _ensureTeacherAssignmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teacher_assignments(
        id TEXT PRIMARY KEY,
        teacherId TEXT NOT NULL,
        courseId TEXT NOT NULL,
        className TEXT NOT NULL,
        academicYear TEXT NOT NULL,
        weeklyHours REAL,
        FOREIGN KEY (teacherId) REFERENCES staff(id) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (courseId) REFERENCES courses(id) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_teacher_assignments_unique ON teacher_assignments(teacherId, courseId, className, academicYear)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_teacher_assignments_class_year ON teacher_assignments(className, academicYear)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_teacher_assignments_teacher ON teacher_assignments(teacherId)',
    );
  }

  Future<Map<String, double>> getClassSubjectCoefficients(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    final res = await db.rawQuery(
      '''
      SELECT c.name as subject, cc.coefficient as coeff
      FROM class_courses cc
      JOIN courses c ON c.id = cc.courseId
      WHERE cc.className = ? AND cc.academicYear = ?
    ''',
      [className, academicYear],
    );
    final map = <String, double>{};
    for (final row in res) {
      final subject = row['subject'] as String?;
      final num? coeff = row['coeff'] as num?;
      if (subject != null && coeff != null) map[subject] = coeff.toDouble();
    }
    return map;
  }

  Future<Map<String, double>> getClassCourseCoefficientsById(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    final res = await db.rawQuery(
      '''
      SELECT cc.courseId as courseId, cc.coefficient as coeff
      FROM class_courses cc
      WHERE cc.className = ? AND cc.academicYear = ?
    ''',
      [className, academicYear],
    );
    final map = <String, double>{};
    for (final row in res) {
      final courseId = row['courseId'] as String?;
      final num? coeff = row['coeff'] as num?;
      if (courseId != null && coeff != null) map[courseId] = coeff.toDouble();
    }
    return map;
  }

  Future<void> updateClassCourseCoefficient({
    required String className,
    required String academicYear,
    required String courseId,
    required double coefficient,
  }) async {
    final db = await database;
    await db.update(
      'class_courses',
      {'coefficient': coefficient},
      where: 'className = ? AND academicYear = ? AND courseId = ?',
      whereArgs: [className, academicYear, courseId],
    );
  }

  Future<void> upsertClassCourseSettings({
    required String className,
    required String academicYear,
    required String courseId,
    double? coefficient,
    double? weeklyHours,
  }) async {
    await addCourseToClass(className, academicYear, courseId);
    final db = await database;
    final values = <String, Object?>{};
    if (coefficient != null) values['coefficient'] = coefficient;
    if (weeklyHours != null) values['weeklyHours'] = weeklyHours;
    if (values.isEmpty) return;
    await db.update(
      'class_courses',
      values,
      where: 'className = ? AND academicYear = ? AND courseId = ?',
      whereArgs: [className, academicYear, courseId],
    );
  }

  Future<List<Map<String, dynamic>>> getClassCourseSettings({
    required String className,
    required String academicYear,
  }) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT c.*,
             cc.coefficient AS coefficient,
             cc.weeklyHours AS weeklyHours
      FROM class_courses cc
      JOIN courses c ON c.id = cc.courseId
      WHERE cc.className = ? AND cc.academicYear = ?
      ORDER BY c.name COLLATE NOCASE
      ''',
      [className, academicYear],
    );
  }

  Future<void> _ensureStudentMatriculeColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(students)');
    final hasMatricule = cols.any((c) => c['name'] == 'matricule');
    if (!hasMatricule) {
      try {
        await db.execute("ALTER TABLE students ADD COLUMN matricule TEXT");
        debugPrint(
          '[DatabaseService][MIGRATION] Added matricule column to students',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add matricule column: $e',
        );
      }
    }
  }

  Future<void> _ensureStudentNameColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(students)');
    final hasFirstName = cols.any((c) => c['name'] == 'firstName');
    final hasLastName = cols.any((c) => c['name'] == 'lastName');

    if (!hasFirstName) {
      try {
        await db.execute("ALTER TABLE students ADD COLUMN firstName TEXT");
        debugPrint(
          '[DatabaseService][MIGRATION] Added firstName column to students',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add firstName column: $e',
        );
      }
    }

    if (!hasLastName) {
      try {
        await db.execute("ALTER TABLE students ADD COLUMN lastName TEXT");
        debugPrint(
          '[DatabaseService][MIGRATION] Added lastName column to students',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add lastName column: $e',
        );
      }
    }
  }

  Future<void> _ensureStudentPlaceOfBirthColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(students)');
    final hasPlaceOfBirth = cols.any((c) => c['name'] == 'placeOfBirth');
    if (!hasPlaceOfBirth) {
      try {
        await db.execute("ALTER TABLE students ADD COLUMN placeOfBirth TEXT");
        debugPrint(
          '[DatabaseService][MIGRATION] Added placeOfBirth column to students',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add placeOfBirth column: $e',
        );
      }
    }
  }

  Future<void> _ensureStudentDocumentsColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(students)');
    final hasDocuments = cols.any((c) => c['name'] == 'documents');
    if (!hasDocuments) {
      try {
        await db.execute('ALTER TABLE students ADD COLUMN documents TEXT');
        debugPrint(
          '[DatabaseService][MIGRATION] Added documents column to students',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add documents column: $e',
        );
      }
    }
  }

  Future<void> _ensureStudentSoftDeleteColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(students)');
    final hasIsDeleted = cols.any((c) => c['name'] == 'isDeleted');
    final hasDeletedAt = cols.any((c) => c['name'] == 'deletedAt');
    if (!hasIsDeleted) {
      try {
        await db.execute(
          'ALTER TABLE students ADD COLUMN isDeleted INTEGER DEFAULT 0',
        );
        await db.execute(
          'UPDATE students SET isDeleted = 0 WHERE isDeleted IS NULL',
        );
        debugPrint(
          '[DatabaseService][MIGRATION] Added isDeleted column to students',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add isDeleted column: $e',
        );
      }
    }
    if (!hasDeletedAt) {
      try {
        await db.execute('ALTER TABLE students ADD COLUMN deletedAt TEXT');
        debugPrint(
          '[DatabaseService][MIGRATION] Added deletedAt column to students',
        );
      } catch (e) {
        debugPrint(
          '[DatabaseService][MIGRATION][ERROR] Failed to add deletedAt column: $e',
        );
      }
    }
  }

  Future<void> _ensureSchoolInfoColumns(Database db) async {
    debugPrint(
      '[DatabaseService][MIGRATION] Starting school_info columns migration...',
    );
    // Ensure table exists; create with final schema if missing
    final exists = await _tableExists(db, 'school_info');
    if (!exists) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS school_info(
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          address TEXT NOT NULL,
          bp TEXT,
          telephone TEXT,
          email TEXT,
          website TEXT,
          logoPath TEXT,
          director TEXT,
          directorPrimary TEXT,
          directorCollege TEXT,
          directorLycee TEXT,
          directorUniversity TEXT,
          civilityPrimary TEXT,
          civilityCollege TEXT,
          civilityLycee TEXT,
          civilityUniversity TEXT,
          motto TEXT,
          ministry TEXT,
          republicMotto TEXT,
          educationDirection TEXT,
          inspection TEXT
        )
      ''');
      debugPrint(
        '[DatabaseService][MIGRATION] Created school_info table with latest schema',
      );
      return; // Fresh table already has all columns
    }

    final cols = await db.rawQuery('PRAGMA table_info(school_info)');
    final columnNames = cols.map((c) => c['name'] as String).toList();
    debugPrint(
      '[DatabaseService][MIGRATION] Current school_info columns: $columnNames',
    );

    final newColumns = [
      'bp TEXT',
      'republic TEXT',
      'ministry TEXT',
      'republicMotto TEXT',
      'educationDirection TEXT',
      'inspection TEXT',
      'paymentsAdminRole TEXT',
      'flagPath TEXT',
      'directorPrimary TEXT',
      'directorCollege TEXT',
      'directorLycee TEXT',
      'directorUniversity TEXT',
      'civilityPrimary TEXT',
      'civilityCollege TEXT',
      'civilityLycee TEXT',
      'civilityUniversity TEXT',
    ];

    for (final columnDef in newColumns) {
      final columnName = columnDef.split(' ')[0];
      if (!columnNames.contains(columnName)) {
        try {
          await db.execute('ALTER TABLE school_info ADD COLUMN $columnDef');
          debugPrint(
            '[DatabaseService][MIGRATION] Successfully added column: $columnName to school_info',
          );
        } catch (e) {
          debugPrint(
            '[DatabaseService][MIGRATION][ERROR] Failed to add column $columnName: $e',
          );
        }
      } else {
        debugPrint(
          '[DatabaseService][MIGRATION] Column $columnName already exists in school_info',
        );
      }
    }
    debugPrint(
      '[DatabaseService][MIGRATION] school_info columns migration completed',
    );
  }

  Future<bool> _tableExists(Database db, String table) async {
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name = ?",
      [table],
    );
    return res.isNotEmpty;
  }

  Future<void> _migrateClassesCompositeKey(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(classes)');
    final pkCount = cols.where((c) => (c['pk'] as int? ?? 0) > 0).length;
    if (pkCount > 1) {
      // Already using composite key
      return;
    }

    debugPrint(
      '[DatabaseService][MIGRATION] Upgrading classes table to composite primary key (name, academicYear)',
    );
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      if (await _tableExists(db, 'classes_backup')) {
        await db.execute('DROP TABLE classes_backup');
      }
      await db.execute('ALTER TABLE classes RENAME TO classes_backup');
      await db.execute('''
        CREATE TABLE classes(
          name TEXT NOT NULL,
          academicYear TEXT NOT NULL,
          titulaire TEXT,
          fraisEcole REAL,
          fraisCotisationParallele REAL,
          level TEXT,
          -- Seuils de passage personnalisés par classe
          seuilFelicitations REAL DEFAULT 16.0,
          seuilEncouragements REAL DEFAULT 14.0,
          seuilAdmission REAL DEFAULT 12.0,
          seuilAvertissement REAL DEFAULT 10.0,
          seuilConditions REAL DEFAULT 8.0,
          seuilRedoublement REAL DEFAULT 8.0,
          PRIMARY KEY (name, academicYear)
        )
      ''');
      await db.execute('''
        INSERT INTO classes (name, academicYear, titulaire, fraisEcole, fraisCotisationParallele, level, seuilFelicitations, seuilEncouragements, seuilAdmission, seuilAvertissement, seuilConditions, seuilRedoublement)
        SELECT name, academicYear, titulaire, fraisEcole, fraisCotisationParallele, '' AS level, 16.0, 14.0, 12.0, 10.0, 8.0, 8.0 FROM classes_backup
      ''');
    } catch (e) {
      debugPrint(
        '[DatabaseService][MIGRATION][ERROR] Failed to rebuild classes table: $e',
      );
      rethrow;
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<void> _dropClassesBackup(Database db) async {
    if (!await _tableExists(db, 'classes_backup')) {
      return;
    }
    // If we reach here, dependent tables may still reference classes_backup.
    // Leave the backup table in place for manual inspection instead of dropping it automatically.
    debugPrint(
      '[DatabaseService][MIGRATION] classes_backup detected; keeping backup table for further cleanup.',
    );
  }

  Future<void> _ensureClassRelatedColumns(Database db) async {
    Future<void> addColumnIfMissing(
      String table,
      String column,
      String type,
    ) async {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      final exists = cols.any((c) => c['name'] == column);
      if (!exists) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      }
    }

    // Créer la table categories si elle n'existe pas
    final categoriesTableExists = await db.rawQuery(
      'SELECT name FROM sqlite_master WHERE type="table" AND name="categories"',
    );
    if (categoriesTableExists.isEmpty) {
      await db.execute('''
        CREATE TABLE categories(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          color TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }

    // Ajouter la colonne categoryId à la table courses si elle n'existe pas
    await addColumnIfMissing('courses', 'categoryId', 'TEXT');

    await addColumnIfMissing('payments', 'classAcademicYear', 'TEXT');
    await addColumnIfMissing('payments', 'receiptNo', 'TEXT');
    await addColumnIfMissing('class_courses', 'academicYear', 'TEXT');
    await addColumnIfMissing('timetable_entries', 'academicYear', 'TEXT');

    // Ajouter les colonnes de seuils de passage à la table classes
    await addColumnIfMissing(
      'classes',
      'seuilFelicitations',
      'REAL DEFAULT 16.0',
    );
    await addColumnIfMissing(
      'classes',
      'seuilEncouragements',
      'REAL DEFAULT 14.0',
    );
    await addColumnIfMissing('classes', 'seuilAdmission', 'REAL DEFAULT 12.0');
    await addColumnIfMissing(
      'classes',
      'seuilAvertissement',
      'REAL DEFAULT 10.0',
    );
    await addColumnIfMissing('classes', 'seuilConditions', 'REAL DEFAULT 8.0');
    await addColumnIfMissing(
      'classes',
      'seuilRedoublement',
      'REAL DEFAULT 8.0',
    );
    await addColumnIfMissing('classes', 'level', 'TEXT');

    // Populate newly added columns when possible
    await db.execute('''
      UPDATE payments
      SET classAcademicYear = (
        SELECT c.academicYear FROM classes c WHERE c.name = payments.className
      )
      WHERE (classAcademicYear IS NULL OR classAcademicYear = '') AND className IS NOT NULL
    ''');

    await db.execute('''
      UPDATE payments
      SET classAcademicYear = (
        SELECT s.academicYear FROM students s WHERE s.id = payments.studentId
      )
      WHERE (classAcademicYear IS NULL OR classAcademicYear = '') AND studentId IN (SELECT id FROM students)
    ''');

    await db.execute('''
      DELETE FROM payments
      WHERE classAcademicYear IS NULL OR TRIM(classAcademicYear) = ''
    ''');

    await db.execute('''
      UPDATE class_courses
      SET academicYear = (
        SELECT c.academicYear FROM classes c WHERE c.name = class_courses.className
      )
      WHERE (academicYear IS NULL OR academicYear = '') AND className IS NOT NULL
    ''');

    await db.execute('''
      DELETE FROM class_courses
      WHERE academicYear IS NULL OR TRIM(academicYear) = ''
    ''');

    await db.execute('''
      UPDATE timetable_entries
      SET academicYear = (
        SELECT c.academicYear FROM classes c WHERE c.name = timetable_entries.className
      )
      WHERE (academicYear IS NULL OR academicYear = '') AND className IS NOT NULL
    ''');

    await db.execute('''
      DELETE FROM timetable_entries
      WHERE academicYear IS NULL OR TRIM(academicYear) = ''
    ''');

    // Initialiser les valeurs par défaut des seuils pour les classes existantes
    await db.execute('''
      UPDATE classes 
      SET seuilFelicitations = 16.0, 
          seuilEncouragements = 14.0, 
          seuilAdmission = 12.0, 
          seuilAvertissement = 10.0, 
          seuilConditions = 8.0, 
          seuilRedoublement = 8.0
      WHERE seuilFelicitations IS NULL
    ''');
  }

  Future<void> _ensureStudentStatusColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(students)');
    final hasStatus = cols.any((c) => c['name'] == 'status');
    if (!hasStatus) {
      await db.execute(
        "ALTER TABLE students ADD COLUMN status TEXT DEFAULT 'Nouveau'",
      );
      await db.execute(
        "UPDATE students SET status = 'Nouveau' WHERE status IS NULL OR status = ''",
      );
    }
  }

  Future<void> _ensureClassExists(
    DatabaseExecutor exec,
    String className, {
    String? academicYear,
  }) async {
    List<Map<String, Object?>> rows;
    if (academicYear != null) {
      rows = await exec.query(
        'classes',
        where: 'name = ? AND academicYear = ?',
        whereArgs: [className, academicYear],
      );
    } else {
      rows = await exec.query(
        'classes',
        where: 'name = ?',
        whereArgs: [className],
      );
    }
    if (rows.isEmpty) {
      throw Exception(
        academicYear == null
            ? 'Classe introuvable: "$className"'
            : 'Classe introuvable: "$className" ($academicYear)',
      );
    }
  }

  Future<void> _ensureStudentExists(
    DatabaseExecutor exec,
    String studentId,
  ) async {
    final rows = await exec.query(
      'students',
      where: 'id = ?',
      whereArgs: [studentId],
    );
    if (rows.isEmpty) {
      throw Exception('Élève introuvable: "$studentId"');
    }
  }

  Future<void> _ensureCourseExists(
    DatabaseExecutor exec,
    String courseId,
  ) async {
    final rows = await exec.query(
      'courses',
      where: 'id = ?',
      whereArgs: [courseId],
    );
    if (rows.isEmpty) {
      throw Exception('Matière introuvable: "$courseId"');
    }
  }

  Future<void> _migrateForeignKeysWithCascade(Database db) async {
    // Add ON UPDATE CASCADE / ON DELETE RESTRICT where appropriate by rebuilding child tables
    Future<bool> hasFk(
      Database db,
      String table,
      Map<String, String> exp,
    ) async {
      final fks = await db.rawQuery('PRAGMA foreign_key_list($table)');
      return fks.any(
        (row) =>
            (row['table']?.toString() == exp['table']) &&
            (row['from']?.toString() == exp['from']) &&
            (row['to']?.toString() == exp['to']) &&
            ((row['on_update']?.toString().toUpperCase() ?? '') ==
                (exp['on_update'] ?? '').toUpperCase()) &&
            ((row['on_delete']?.toString().toUpperCase() ?? '') ==
                (exp['on_delete'] ?? '').toUpperCase()),
      );
    }

    Future<void> recreateIfNeeded({
      required String table,
      required List<Map<String, String>> expectedFks,
      required String createSql,
      required List<String> columns,
    }) async {
      bool ok = true;
      for (final exp in expectedFks) {
        if (!await hasFk(db, table, exp)) {
          ok = false;
          break;
        }
      }
      if (ok) return;
      // Basic orphan check: skip migration if orphans exist to avoid failure
      for (final exp in expectedFks) {
        final from = exp['from'];
        final parent = exp['table'];
        final to = exp['to'];
        if (from == null || parent == null || to == null) continue;
        final count =
            Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM $table t LEFT JOIN $parent p ON t.$from = p.$to WHERE t.$from IS NOT NULL AND p.$to IS NULL',
              ),
            ) ??
            0;
        if (count > 0) {
          debugPrint(
            '[DatabaseService][FK MIGRATION] Skip $table: found $count orphan rows for FK $from -> $parent($to).',
          );
          return;
        }
      }
      // Temporarily disable FK enforcement to allow parent table rebuild
      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await db.transaction((txn) async {
          await txn.execute(createSql.replaceAll(table, '${table}_new'));
          final oldColsInfo = await txn.rawQuery('PRAGMA table_info($table)');
          final newColsInfo = await txn.rawQuery(
            'PRAGMA table_info(${table}_new)',
          );
          final oldCols = oldColsInfo.map((c) => c['name'] as String).toSet();
          final newCols = newColsInfo.map((c) => c['name'] as String).toSet();
          final common = columns.where(
            (c) => oldCols.contains(c) && newCols.contains(c),
          );
          final cols = common.join(', ');
          if (cols.isNotEmpty) {
            await txn.execute(
              'INSERT INTO ${table}_new ($cols) SELECT $cols FROM $table',
            );
          }
          await txn.execute('DROP TABLE $table');
          await txn.execute('ALTER TABLE ${table}_new RENAME TO $table');
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
        try {
          final issues = await db.rawQuery('PRAGMA foreign_key_check');
          if (issues.isNotEmpty) {
            debugPrint(
              '[DatabaseService][FK MIGRATION] foreign_key_check reported ${issues.length} issues after rebuilding $table',
            );
          }
        } catch (_) {}
      }
    }

    // students -> classes(name, academicYear)
    await recreateIfNeeded(
      table: 'students',
      expectedFks: [
        {
          'table': 'classes',
          'from': 'className',
          'to': 'name',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'academicYear',
          'to': 'academicYear',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
      ],
      createSql: '''
        CREATE TABLE students(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          dateOfBirth TEXT NOT NULL,
          address TEXT NOT NULL,
          gender TEXT NOT NULL,
          contactNumber TEXT NOT NULL,
          email TEXT NOT NULL,
          emergencyContact TEXT NOT NULL,
          guardianName TEXT NOT NULL,
          guardianContact TEXT NOT NULL,
          className TEXT NOT NULL,
          academicYear TEXT NOT NULL,
          enrollmentDate TEXT,
          medicalInfo TEXT,
          photoPath TEXT,
          FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
        )
      ''',
      columns: [
        'id',
        'name',
        'dateOfBirth',
        'address',
        'gender',
        'contactNumber',
        'email',
        'emergencyContact',
        'guardianName',
        'guardianContact',
        'className',
        'academicYear',
        'enrollmentDate',
        'medicalInfo',
        'photoPath',
      ],
    );

    // payments -> students(id), classes(name, academicYear)
    await recreateIfNeeded(
      table: 'payments',
      expectedFks: [
        {
          'table': 'students',
          'from': 'studentId',
          'to': 'id',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'className',
          'to': 'name',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'classAcademicYear',
          'to': 'academicYear',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
      ],
      createSql: '''
        CREATE TABLE payments(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId TEXT NOT NULL,
          className TEXT NOT NULL,
          classAcademicYear TEXT NOT NULL,
          amount REAL NOT NULL,
          date TEXT NOT NULL,
          comment TEXT,
          isCancelled INTEGER DEFAULT 0,
          cancelledAt TEXT,
          FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
          FOREIGN KEY (className, classAcademicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
        )
      ''',
      columns: [
        'id',
        'studentId',
        'className',
        'classAcademicYear',
        'amount',
        'date',
        'comment',
        'isCancelled',
        'cancelledAt',
      ],
    );

    // users -> staff(id) (optional link)
    await recreateIfNeeded(
      table: 'users',
      expectedFks: [
        {
          'table': 'staff',
          'from': 'staffId',
          'to': 'id',
          'on_update': 'CASCADE',
          'on_delete': 'SET NULL',
        },
      ],
      createSql: '''
        CREATE TABLE users(
          username TEXT PRIMARY KEY,
          displayName TEXT,
          role TEXT,
          passwordHash TEXT NOT NULL,
          salt TEXT NOT NULL,
          isTwoFactorEnabled INTEGER DEFAULT 0,
          totpSecret TEXT,
          isActive INTEGER DEFAULT 1,
          createdAt TEXT,
          lastLoginAt TEXT,
          permissions TEXT,
          staffId TEXT,
          failedLoginCount INTEGER NOT NULL DEFAULT 0,
          lockedUntil TEXT,
          FOREIGN KEY (staffId) REFERENCES staff(id) ON UPDATE CASCADE ON DELETE SET NULL
        )
      ''',
      columns: [
        'username',
        'displayName',
        'role',
        'passwordHash',
        'salt',
        'isTwoFactorEnabled',
        'totpSecret',
        'isActive',
        'createdAt',
        'lastLoginAt',
        'permissions',
        'staffId',
        'failedLoginCount',
        'lockedUntil',
      ],
    );

    // grades -> students(id), classes(name, academicYear)
    await recreateIfNeeded(
      table: 'grades',
      expectedFks: [
        {
          'table': 'students',
          'from': 'studentId',
          'to': 'id',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'className',
          'to': 'name',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'academicYear',
          'to': 'academicYear',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
      ],
      createSql: '''
        CREATE TABLE grades(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId TEXT NOT NULL,
          className TEXT NOT NULL,
          academicYear TEXT NOT NULL,
          subject TEXT NOT NULL,
          term TEXT NOT NULL,
          value REAL NOT NULL,
          label TEXT,
          maxValue REAL DEFAULT 20,
          coefficient REAL DEFAULT 1,
          type TEXT DEFAULT 'Devoir',
          subjectId TEXT,
          FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
          FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
        )
      ''',
      columns: [
        'id',
        'studentId',
        'className',
        'academicYear',
        'subject',
        'term',
        'value',
        'label',
        'maxValue',
        'coefficient',
        'type',
        'subjectId',
      ],
    );

    // class_courses -> classes(name, academicYear), courses(id)
    await recreateIfNeeded(
      table: 'class_courses',
      expectedFks: [
        {
          'table': 'classes',
          'from': 'className',
          'to': 'name',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'academicYear',
          'to': 'academicYear',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'courses',
          'from': 'courseId',
          'to': 'id',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
      ],
      createSql: '''
        CREATE TABLE class_courses(
          className TEXT NOT NULL,
          academicYear TEXT NOT NULL,
          courseId TEXT NOT NULL,
          coefficient REAL,
          weeklyHours REAL,
          PRIMARY KEY (className, academicYear, courseId),
          FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT,
          FOREIGN KEY (courseId) REFERENCES courses(id) ON UPDATE CASCADE ON DELETE RESTRICT
        )
      ''',
      columns: ['className', 'academicYear', 'courseId'],
    );

    // timetable_entries -> classes(name, academicYear)
    await recreateIfNeeded(
      table: 'timetable_entries',
      expectedFks: [
        {
          'table': 'classes',
          'from': 'className',
          'to': 'name',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'academicYear',
          'to': 'academicYear',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
      ],
      createSql: '''
        CREATE TABLE timetable_entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          subject TEXT NOT NULL,
          teacher TEXT NOT NULL,
          className TEXT NOT NULL,
          academicYear TEXT NOT NULL,
          dayOfWeek TEXT NOT NULL,
          startTime TEXT NOT NULL,
          endTime TEXT NOT NULL,
          room TEXT,
          FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
        )
      ''',
      columns: [
        'id',
        'subject',
        'teacher',
        'className',
        'academicYear',
        'dayOfWeek',
        'startTime',
        'endTime',
        'room',
      ],
    );

    // report_cards -> students(id), classes(name, academicYear)
    await recreateIfNeeded(
      table: 'report_cards',
      expectedFks: [
        {
          'table': 'students',
          'from': 'studentId',
          'to': 'id',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'className',
          'to': 'name',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'academicYear',
          'to': 'academicYear',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
      ],
      createSql: '''
        CREATE TABLE report_cards(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId TEXT NOT NULL,
          className TEXT NOT NULL,
          academicYear TEXT NOT NULL,
          term TEXT NOT NULL,
          appreciation_generale TEXT,
          decision TEXT,
          fait_a TEXT,
          le_date TEXT,
          moyenne_generale REAL,
          rang INTEGER,
          nb_eleves INTEGER,
          mention TEXT,
          moyennes_par_periode TEXT,
          all_terms TEXT,
          moyenne_generale_classe REAL,
          moyenne_la_plus_forte REAL,
          moyenne_la_plus_faible REAL,
          moyenne_annuelle REAL,
          sanctions TEXT,
          recommandations TEXT,
          forces TEXT,
          points_a_developper TEXT,
          attendance_justifiee INTEGER,
          attendance_injustifiee INTEGER,
          retards INTEGER,
          presence_percent REAL,
          conduite TEXT,
          FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
          FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
        )
      ''',
      columns: [
        'id',
        'studentId',
        'className',
        'academicYear',
        'term',
        'appreciation_generale',
        'decision',
        'fait_a',
        'le_date',
        'moyenne_generale',
        'rang',
        'nb_eleves',
        'mention',
        'moyennes_par_periode',
        'all_terms',
        'moyenne_generale_classe',
        'moyenne_la_plus_forte',
        'moyenne_la_plus_faible',
        'moyenne_annuelle',
        'sanctions',
        'recommandations',
        'forces',
        'points_a_developper',
        'attendance_justifiee',
        'attendance_injustifiee',
        'retards',
        'presence_percent',
        'conduite',
      ],
    );

    // subject_appreciation -> students(id), classes(name, academicYear)
    await recreateIfNeeded(
      table: 'subject_appreciation',
      expectedFks: [
        {
          'table': 'students',
          'from': 'studentId',
          'to': 'id',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'className',
          'to': 'name',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'academicYear',
          'to': 'academicYear',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
      ],
      createSql: '''
        CREATE TABLE subject_appreciation(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId TEXT NOT NULL,
          className TEXT NOT NULL,
          academicYear TEXT NOT NULL,
          subject TEXT NOT NULL,
          term TEXT NOT NULL,
          professeur TEXT,
          appreciation TEXT,
          moyenne_classe TEXT,
          FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
          FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
        )
      ''',
      columns: [
        'id',
        'studentId',
        'className',
        'academicYear',
        'subject',
        'term',
        'professeur',
        'appreciation',
        'moyenne_classe',
      ],
    );

    // report_cards_archive -> students(id), classes(name, academicYear); subject_appreciation_archive unchanged
    await recreateIfNeeded(
      table: 'report_cards_archive',
      expectedFks: [
        {
          'table': 'students',
          'from': 'studentId',
          'to': 'id',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'className',
          'to': 'name',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
        {
          'table': 'classes',
          'from': 'academicYear',
          'to': 'academicYear',
          'on_update': 'CASCADE',
          'on_delete': 'RESTRICT',
        },
      ],
      createSql: '''
        CREATE TABLE report_cards_archive(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          studentId TEXT NOT NULL,
          className TEXT NOT NULL,
          academicYear TEXT NOT NULL,
          term TEXT NOT NULL,
          appreciation_generale TEXT,
          decision TEXT,
          fait_a TEXT,
          le_date TEXT,
          moyenne_generale REAL,
          rang INTEGER,
          exaequo INTEGER DEFAULT 0,
          nb_eleves INTEGER,
          mention TEXT,
          moyennes_par_periode TEXT, -- JSON encodé
          all_terms TEXT, -- JSON encodé
          moyenne_generale_classe REAL,
          moyenne_la_plus_forte REAL,
          moyenne_la_plus_faible REAL,
          moyenne_annuelle REAL,
          sanctions TEXT,
          FOREIGN KEY (studentId) REFERENCES students(id) ON UPDATE CASCADE ON DELETE RESTRICT,
          FOREIGN KEY (className, academicYear) REFERENCES classes(name, academicYear) ON UPDATE CASCADE ON DELETE RESTRICT
        )
      ''',
      columns: [
        'id',
        'studentId',
        'className',
        'academicYear',
        'term',
        'appreciation_generale',
        'decision',
        'fait_a',
        'le_date',
        'moyenne_generale',
        'rang',
        'exaequo',
        'nb_eleves',
        'mention',
        'moyennes_par_periode',
        'all_terms',
        'moyenne_generale_classe',
        'moyenne_la_plus_forte',
        'moyenne_la_plus_faible',
        'moyenne_annuelle',
        'sanctions',
        'recommandations',
        'forces',
        'points_a_developper',
        'attendance_justifiee',
        'attendance_injustifiee',
        'retards',
        'presence_percent',
        'conduite',
      ],
    );
    await recreateIfNeeded(
      table: 'subject_appreciation_archive',
      expectedFks: [
        {
          'table': 'report_cards_archive',
          'from': 'report_card_id',
          'to': 'id',
          'on_update': 'CASCADE',
          'on_delete': 'CASCADE',
        },
      ],
      createSql: '''
        CREATE TABLE subject_appreciation_archive(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          report_card_id INTEGER NOT NULL,
          subject TEXT NOT NULL,
          professeur TEXT,
          appreciation TEXT,
          moyenne_classe TEXT,
          academicYear TEXT NOT NULL,
          FOREIGN KEY (report_card_id) REFERENCES report_cards_archive(id) ON UPDATE CASCADE ON DELETE CASCADE
        )
      ''',
      columns: [
        'id',
        'report_card_id',
        'subject',
        'professeur',
        'appreciation',
        'moyenne_classe',
        'academicYear',
      ],
    );
  }

  Future<void> _ensureUsersPermissionsColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(users)');
    final hasPermissions = cols.any((c) => c['name'] == 'permissions');
    if (!hasPermissions) {
      await db.execute('ALTER TABLE users ADD COLUMN permissions TEXT');
    }
  }

  Future<void> _ensureArchiveExtraColumns(Database db) async {
    Future<void> add(String col, String type) async {
      final cols = await db.rawQuery('PRAGMA table_info(report_cards_archive)');
      final exists = cols.any((c) => c['name'] == col);
      if (!exists) {
        await db.execute(
          'ALTER TABLE report_cards_archive ADD COLUMN $col $type',
        );
      }
    }

    // Snapshot d'infos école & élève utiles
    await add('school_ministry', 'TEXT');
    await add('school_republic', 'TEXT');
    await add('school_republic_motto', 'TEXT');
    await add('school_education_direction', 'TEXT');
    await add('school_inspection', 'TEXT');
    await add('student_dob', 'TEXT');
    await add('student_status', 'TEXT');
    await add('student_photo_path', 'TEXT');
  }

  Future<void> _ensureStudentAcademicYearColumn(Database db) async {
    final studentCols = await db.rawQuery('PRAGMA table_info(students)');
    final hasStudentAcademicYear = studentCols.any(
      (c) => c['name'] == 'academicYear',
    );
    if (!hasStudentAcademicYear) {
      await db.execute('ALTER TABLE students ADD COLUMN academicYear TEXT');
      await db.execute('''
        UPDATE students
        SET academicYear = (
          SELECT c.academicYear FROM classes c WHERE c.name = students.className
        )
        WHERE academicYear IS NULL OR academicYear = ''
      ''');
      await db.execute(
        "UPDATE students SET academicYear = strftime('%Y', date('now')) || '-' || (cast(strftime('%Y', date('now')) as integer) + 1) WHERE academicYear IS NULL OR academicYear = ''",
      );
    }
  }

  Future<void> _ensureImportLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        filename TEXT,
        user TEXT,
        mode TEXT,
        className TEXT,
        academicYear TEXT,
        term TEXT,
        total INTEGER,
        success INTEGER,
        errors INTEGER,
        warnings INTEGER,
        details TEXT
      )
    ''');
  }

  Future<void> _migrateReportCardsExtraFields(Database db) async {
    // Helper to add column if missing
    Future<void> addColumnIfMissing(
      String table,
      String column,
      String type,
    ) async {
      final cols = await db.rawQuery("PRAGMA table_info($table)");
      final has = cols.any((c) => c['name'] == column);
      if (!has) {
        await db.execute(
          'ALTER TABLE ' + table + ' ADD COLUMN ' + column + ' ' + type,
        );
      }
    }

    // report_cards
    await addColumnIfMissing('report_cards', 'recommandations', 'TEXT');
    await addColumnIfMissing('report_cards', 'forces', 'TEXT');
    await addColumnIfMissing('report_cards', 'points_a_developper', 'TEXT');
    await addColumnIfMissing('report_cards', 'attendance_justifiee', 'INTEGER');
    await addColumnIfMissing(
      'report_cards',
      'attendance_injustifiee',
      'INTEGER',
    );
    await addColumnIfMissing('report_cards', 'retards', 'INTEGER');
    await addColumnIfMissing('report_cards', 'presence_percent', 'REAL');
    await addColumnIfMissing('report_cards', 'conduite', 'TEXT');
    // report_cards_archive
    await addColumnIfMissing('report_cards_archive', 'recommandations', 'TEXT');
    await addColumnIfMissing('report_cards_archive', 'forces', 'TEXT');
    await addColumnIfMissing(
      'report_cards_archive',
      'points_a_developper',
      'TEXT',
    );
    await addColumnIfMissing(
      'report_cards_archive',
      'attendance_justifiee',
      'INTEGER',
    );
    await addColumnIfMissing(
      'report_cards_archive',
      'attendance_injustifiee',
      'INTEGER',
    );
    await addColumnIfMissing('report_cards_archive', 'retards', 'INTEGER');
    await addColumnIfMissing(
      'report_cards_archive',
      'presence_percent',
      'REAL',
    );
    await addColumnIfMissing('report_cards_archive', 'conduite', 'TEXT');
    await addColumnIfMissing('report_cards_archive', 'exaequo', 'INTEGER');
  }

  Future<void> _migrateStudentsEnrollmentDate(Database db) async {
    final columns = await db.rawQuery("PRAGMA table_info(students)");
    final hasEnrollmentDate = columns.any(
      (col) => col['name'] == 'enrollmentDate',
    );
    if (!hasEnrollmentDate) {
      await db.execute(
        "ALTER TABLE students ADD COLUMN enrollmentDate TEXT DEFAULT ''",
      );
      // Optionally, populate with a default value like current date or dateOfBirth if appropriate
      await db.execute(
        "UPDATE students SET enrollmentDate = dateOfBirth WHERE enrollmentDate = ''",
      );
    }
  }

  Future<void> _migrateGradesSubjectId(Database db) async {
    await db.transaction((txn) async {
      final columns = await txn.rawQuery("PRAGMA table_info(grades)");
      final hasSubjectId = columns.any((col) => col['name'] == 'subjectId');
      if (!hasSubjectId) {
        await txn.execute("ALTER TABLE grades ADD COLUMN subjectId TEXT");
      }
      final grades = await txn.query('grades');
      for (final grade in grades) {
        final currentSubjectId = grade['subjectId'];
        if (currentSubjectId == null ||
            (currentSubjectId is String && currentSubjectId.isEmpty)) {
          final subjectName = grade['subject'] as String?;
          if (subjectName != null && subjectName.isNotEmpty) {
            final course = await txn.query(
              'courses',
              where: 'name = ?',
              whereArgs: [subjectName],
            );
            if (course.isNotEmpty) {
              final courseId = course.first['id'] as String;
              await txn.update(
                'grades',
                {'subjectId': courseId},
                where: 'id = ?',
                whereArgs: [grade['id']],
              );
            }
          }
        }
      }
    });
  }

  // Class operations
  Future<void> insertClass(Class cls) async {
    final db = await database;
    final data = cls.toMap();
    debugPrint('[DatabaseService] insertClass -> data=$data');
    try {
      // Always insert a new class; do not update existing by name to avoid accidental overwrites
      await db.insert(
        'classes',
        data,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      debugPrint(
        '[DatabaseService] insertClass <- inserted name=${cls.name} year=${cls.academicYear}',
      );
    } catch (e) {
      debugPrint('[DatabaseService][ERROR] insertClass failed: $e');
      rethrow;
    }
    try {
      await logAudit(
        category: 'class',
        action: 'insert_class',
        details: 'name=${cls.name} year=${cls.academicYear}',
      );
    } catch (_) {}
  }

  Future<List<Class>> getClasses() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('classes');
    return List.generate(maps.length, (i) => Class.fromMap(maps[i]));
  }

  Future<List<Class>> getClassesByYear(String academicYear) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'classes',
      where: 'academicYear = ?',
      whereArgs: [academicYear],
    );
    return List.generate(maps.length, (i) => Class.fromMap(maps[i]));
  }

  Future<Class?> getClassByName(String name, {String? academicYear}) async {
    final db = await database;
    String where = 'name = ?';
    final whereArgs = <Object?>[name];
    if (academicYear != null) {
      where += ' AND academicYear = ?';
      whereArgs.add(academicYear);
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'classes',
      where: where,
      whereArgs: whereArgs,
    );
    if (maps.isNotEmpty) {
      return Class.fromMap(maps.first);
    }
    return null;
  }

  /// Récupère les seuils de passage d'une classe spécifique
  Future<Map<String, double>> getClassPassingThresholds(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    final result = await db.query(
      'classes',
      columns: [
        'seuilFelicitations',
        'seuilEncouragements',
        'seuilAdmission',
        'seuilAvertissement',
        'seuilConditions',
        'seuilRedoublement',
      ],
      where: 'name = ? AND academicYear = ?',
      whereArgs: [className, academicYear],
    );

    if (result.isEmpty) {
      // Retourner les seuils par défaut si la classe n'existe pas
      return {
        'felicitations': 16.0,
        'encouragements': 14.0,
        'admission': 12.0,
        'avertissement': 10.0,
        'conditions': 8.0,
        'redoublement': 8.0,
      };
    }

    final row = result.first;
    return {
      'felicitations': (row['seuilFelicitations'] as num).toDouble(),
      'encouragements': (row['seuilEncouragements'] as num).toDouble(),
      'admission': (row['seuilAdmission'] as num).toDouble(),
      'avertissement': (row['seuilAvertissement'] as num).toDouble(),
      'conditions': (row['seuilConditions'] as num).toDouble(),
      'redoublement': (row['seuilRedoublement'] as num).toDouble(),
    };
  }

  Future<void> updateClass(
    String oldName,
    String oldAcademicYear,
    Class updatedClass,
  ) async {
    final db = await database;
    debugPrint(
      '[DatabaseService] updateClass -> old=($oldName, $oldAcademicYear) newData=${updatedClass.toMap()}',
    );
    await db.transaction((txn) async {
      await _ensureClassExists(txn, oldName, academicYear: oldAcademicYear);
      await txn.update(
        'classes',
        updatedClass.toMap(),
        where: 'name = ? AND academicYear = ?',
        whereArgs: [oldName, oldAcademicYear],
      );
      if (oldName != updatedClass.name) {
        final newName = updatedClass.name;
        // ON UPDATE CASCADE will propagate to child tables automatically.
        // Update staff assignments
        final staffList = await txn.query('staff');
        for (final staff in staffList) {
          final classesStr = staff['classes'] as String?;
          if (classesStr != null && classesStr.isNotEmpty) {
            final classes = classesStr.split(',');
            final updatedClasses = classes
                .map((c) => c == oldName ? newName : c)
                .toList();
            await txn.update(
              'staff',
              {'classes': updatedClasses.join(',')},
              where: 'id = ?',
              whereArgs: [staff['id']],
            );
          }
        }
        debugPrint(
          '[DatabaseService] updateClass <- cascaded to children and staff updated',
        );
      }
    });
    try {
      await logAudit(
        category: 'class',
        action: 'update_class',
        details: 'old=$oldName new=${updatedClass.name} year=$oldAcademicYear',
      );
    } catch (_) {}
  }

  // Diagnostics: count orphan rows for known foreign key relations
  Future<Map<String, int>> diagnoseForeignKeyOrphans() async {
    final db = await database;
    final checks = <Map<String, String>>[
      {
        'label': 'students.(className, academicYear) -> classes',
        'sql': '''
          SELECT COUNT(*)
          FROM students s
          LEFT JOIN classes c ON s.className = c.name AND s.academicYear = c.academicYear
          WHERE c.name IS NULL
        ''',
      },
      {
        'label': 'payments.studentId -> students',
        'sql': '''
          SELECT COUNT(*)
          FROM payments p
          LEFT JOIN students s ON p.studentId = s.id
          WHERE s.id IS NULL
        ''',
      },
      {
        'label': 'payments.(className, classAcademicYear) -> classes',
        'sql': '''
          SELECT COUNT(*)
          FROM payments p
          LEFT JOIN classes c ON p.className = c.name AND p.classAcademicYear = c.academicYear
          WHERE c.name IS NULL
        ''',
      },
      {
        'label': 'grades.studentId -> students',
        'sql': '''
          SELECT COUNT(*)
          FROM grades g
          LEFT JOIN students s ON g.studentId = s.id
          WHERE s.id IS NULL
        ''',
      },
      {
        'label': 'grades.(className, academicYear) -> classes',
        'sql': '''
          SELECT COUNT(*)
          FROM grades g
          LEFT JOIN classes c ON g.className = c.name AND g.academicYear = c.academicYear
          WHERE c.name IS NULL
        ''',
      },
      {
        'label': 'class_courses.(className, academicYear) -> classes',
        'sql': '''
          SELECT COUNT(*)
          FROM class_courses cc
          LEFT JOIN classes c ON cc.className = c.name AND cc.academicYear = c.academicYear
          WHERE c.name IS NULL
        ''',
      },
      {
        'label': 'class_courses.courseId -> courses',
        'sql': '''
          SELECT COUNT(*)
          FROM class_courses cc
          LEFT JOIN courses c ON cc.courseId = c.id
          WHERE c.id IS NULL
        ''',
      },
      {
        'label': 'timetable_entries.(className, academicYear) -> classes',
        'sql': '''
          SELECT COUNT(*)
          FROM timetable_entries t
          LEFT JOIN classes c ON t.className = c.name AND t.academicYear = c.academicYear
          WHERE c.name IS NULL
        ''',
      },
      {
        'label': 'report_cards.studentId -> students',
        'sql': '''
          SELECT COUNT(*)
          FROM report_cards r
          LEFT JOIN students s ON r.studentId = s.id
          WHERE s.id IS NULL
        ''',
      },
      {
        'label': 'report_cards.(className, academicYear) -> classes',
        'sql': '''
          SELECT COUNT(*)
          FROM report_cards r
          LEFT JOIN classes c ON r.className = c.name AND r.academicYear = c.academicYear
          WHERE c.name IS NULL
        ''',
      },
      {
        'label': 'report_cards_archive.studentId -> students',
        'sql': '''
          SELECT COUNT(*)
          FROM report_cards_archive r
          LEFT JOIN students s ON r.studentId = s.id
          WHERE s.id IS NULL
        ''',
      },
      {
        'label': 'report_cards_archive.(className, academicYear) -> classes',
        'sql': '''
          SELECT COUNT(*)
          FROM report_cards_archive r
          LEFT JOIN classes c ON r.className = c.name AND r.academicYear = c.academicYear
          WHERE c.name IS NULL
        ''',
      },
      {
        'label': 'subject_appreciation.studentId -> students',
        'sql': '''
          SELECT COUNT(*)
          FROM subject_appreciation sa
          LEFT JOIN students s ON sa.studentId = s.id
          WHERE s.id IS NULL
        ''',
      },
      {
        'label': 'subject_appreciation.(className, academicYear) -> classes',
        'sql': '''
          SELECT COUNT(*)
          FROM subject_appreciation sa
          LEFT JOIN classes c ON sa.className = c.name AND sa.academicYear = c.academicYear
          WHERE c.name IS NULL
        ''',
      },
      {
        'label':
            'subject_appreciation_archive.report_card_id -> report_cards_archive',
        'sql': '''
          SELECT COUNT(*)
          FROM subject_appreciation_archive saa
          LEFT JOIN report_cards_archive rca ON saa.report_card_id = rca.id
          WHERE rca.id IS NULL
        ''',
      },
    ];

    final results = <String, int>{};
    for (final check in checks) {
      final label = check['label']!;
      final sql = check['sql']!;
      try {
        final count = Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;
        results[label] = count;
      } catch (_) {
        results[label] = -1;
      }
    }
    return results;
  }

  /// Cleanup orphan rows created by prior inconsistent states.
  /// If [dryRun] is true, no deletion occurs; returns the counts that would be deleted.
  /// If [dryRun] is false, performs deletions and returns the counts actually removed.
  Future<Map<String, int>> cleanOrphans({bool dryRun = true}) async {
    final db = await database;
    final result = <String, int>{};
    await db.transaction((txn) async {
      Future<int> count(String sql) async =>
          Sqflite.firstIntValue(await txn.rawQuery(sql)) ?? 0;
      Future<int> runDelete(
        String table,
        String where,
        List<Object?> args,
      ) async {
        if (dryRun) {
          final c = await count('SELECT COUNT(*) FROM $table WHERE $where');
          result['$table'] = (result['$table'] ?? 0) + c;
          return c;
        } else {
          final c = await txn.delete(table, where: where, whereArgs: args);
          result['$table'] = (result['$table'] ?? 0) + c;
          return c;
        }
      }

      // timetable_entries: orphan class reference
      await runDelete(
        'timetable_entries',
        'NOT EXISTS (SELECT 1 FROM classes c WHERE c.name = timetable_entries.className AND c.academicYear = timetable_entries.academicYear)',
        const [],
      );

      // class_courses: orphan class or course
      await runDelete(
        'class_courses',
        'NOT EXISTS (SELECT 1 FROM classes c WHERE c.name = class_courses.className AND c.academicYear = class_courses.academicYear) OR courseId NOT IN (SELECT id FROM courses)',
        const [],
      );

      // payments: orphan student or class
      await runDelete(
        'payments',
        'studentId NOT IN (SELECT id FROM students) OR NOT EXISTS (SELECT 1 FROM classes c WHERE c.name = payments.className AND c.academicYear = payments.classAcademicYear)',
        const [],
      );

      // grades: orphan student or class
      await runDelete(
        'grades',
        'studentId NOT IN (SELECT id FROM students) OR NOT EXISTS (SELECT 1 FROM classes c WHERE c.name = grades.className AND c.academicYear = grades.academicYear)',
        const [],
      );

      // subject_appreciation: orphan student or class
      await runDelete(
        'subject_appreciation',
        'studentId NOT IN (SELECT id FROM students) OR NOT EXISTS (SELECT 1 FROM classes c WHERE c.name = subject_appreciation.className AND c.academicYear = subject_appreciation.academicYear)',
        const [],
      );

      // report_cards: orphan student or class
      await runDelete(
        'report_cards',
        'studentId NOT IN (SELECT id FROM students) OR NOT EXISTS (SELECT 1 FROM classes c WHERE c.name = report_cards.className AND c.academicYear = report_cards.academicYear)',
        const [],
      );

      // report_cards_archive: orphan student or class (keep archives coherent)
      await runDelete(
        'report_cards_archive',
        'studentId NOT IN (SELECT id FROM students) OR NOT EXISTS (SELECT 1 FROM classes c WHERE c.name = report_cards_archive.className AND c.academicYear = report_cards_archive.academicYear)',
        const [],
      );

      // subject_appreciation_archive: orphan report_card_id
      await runDelete(
        'subject_appreciation_archive',
        'report_card_id NOT IN (SELECT id FROM report_cards_archive)',
        const [],
      );
    });
    return result;
  }

  /// Reassign orphan child rows that point to a missing class name to a valid class.
  /// Affects timetable_entries, payments, grades, subject_appreciation, report_cards, report_cards_archive, class_courses.
  Future<Map<String, int>> reassignOrphanClassReferences({
    required String missingClassName,
    required String missingAcademicYear,
    required String newClassName,
    required String newAcademicYear,
  }) async {
    final db = await database;
    final res = <String, int>{};
    await db.transaction((txn) async {
      // Ensure target class exists
      await _ensureClassExists(
        txn,
        newClassName,
        academicYear: newAcademicYear,
      );
      // Quick check: confirm missingClassName is not present in classes
      final exists = await txn.query(
        'classes',
        where: 'name = ? AND academicYear = ?',
        whereArgs: [missingClassName, missingAcademicYear],
      );
      if (exists.isNotEmpty) {
        return; // nothing to reassign; source exists
      }
      Future<void> upd(
        String table,
        Map<String, Object?> values,
        String whereClause,
        List<Object?> whereArgs,
      ) async {
        final c = await txn.update(
          table,
          values,
          where: whereClause,
          whereArgs: whereArgs,
        );
        res[table] = c;
      }

      await upd(
        'timetable_entries',
        {'className': newClassName, 'academicYear': newAcademicYear},
        'className = ? AND academicYear = ?',
        [missingClassName, missingAcademicYear],
      );
      await upd(
        'payments',
        {'className': newClassName, 'classAcademicYear': newAcademicYear},
        'className = ? AND classAcademicYear = ?',
        [missingClassName, missingAcademicYear],
      );
      await upd(
        'grades',
        {'className': newClassName, 'academicYear': newAcademicYear},
        'className = ? AND academicYear = ?',
        [missingClassName, missingAcademicYear],
      );
      await upd(
        'subject_appreciation',
        {'className': newClassName, 'academicYear': newAcademicYear},
        'className = ? AND academicYear = ?',
        [missingClassName, missingAcademicYear],
      );
      await upd(
        'report_cards',
        {'className': newClassName, 'academicYear': newAcademicYear},
        'className = ? AND academicYear = ?',
        [missingClassName, missingAcademicYear],
      );
      await upd(
        'report_cards_archive',
        {'className': newClassName, 'academicYear': newAcademicYear},
        'className = ? AND academicYear = ?',
        [missingClassName, missingAcademicYear],
      );
      await upd(
        'class_courses',
        {'className': newClassName, 'academicYear': newAcademicYear},
        'className = ? AND academicYear = ?',
        [missingClassName, missingAcademicYear],
      );
    });
    return res;
  }

  // Student operations
  Future<void> insertStudent(Student student) async {
    final db = await database;
    await db.insert(
      'students',
      student.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'student',
        action: 'insert_student',
        details:
            'id=${student.id} name=${student.name} class=${student.className}',
      );
    } catch (_) {}
  }

  Future<List<Student>> getStudents({
    String? className,
    String? academicYear,
    bool includeDeleted = false,
    bool onlyDeleted = false,
  }) async {
    final db = await database;
    String? where;
    List<Object?>? whereArgs;
    final parts = <String>[];
    final args = <Object?>[];
    if (className != null && className.isNotEmpty) {
      parts.add('className = ?');
      args.add(className);
    }
    if (academicYear != null && academicYear.isNotEmpty) {
      parts.add('academicYear = ?');
      args.add(academicYear);
    }
    if (onlyDeleted) {
      parts.add('isDeleted = 1');
    } else if (!includeDeleted) {
      // Exclude soft-deleted students by default
      parts.add('(isDeleted IS NULL OR isDeleted = 0)');
    }
    if (parts.isNotEmpty) {
      where = parts.join(' AND ');
      whereArgs = args;
    }
    debugPrint(
      '[DatabaseService] getStudents(className=$className, academicYear=$academicYear)',
    );
    final List<Map<String, dynamic>> maps = await db.query(
      'students',
      where: where,
      whereArgs: whereArgs,
    );
    return List.generate(maps.length, (i) => Student.fromMap(maps[i]));
  }

  // Returns students for a class where the class' academicYear matches, ensuring consistency with classes table
  Future<List<Student>> getStudentsByClassAndClassYear(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT s.*
      FROM students s
      INNER JOIN classes c ON c.name = s.className
      WHERE s.className = ? AND c.academicYear = ? AND s.academicYear = ? AND (s.isDeleted IS NULL OR s.isDeleted = 0)
    ''',
      [className, academicYear, academicYear],
    );
    return rows.map((m) => Student.fromMap(m)).toList();
  }

  Future<List<Map<String, dynamic>>> getAttendanceEventsForStudent(
    String studentId, {
    int limit = 200,
  }) async {
    final db = await database;
    try {
      return await db.query(
        'attendance_events',
        where: 'studentId = ?',
        whereArgs: [studentId],
        orderBy: 'date DESC',
        limit: limit,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> getSanctionEventsForStudent(
    String studentId, {
    int limit = 200,
  }) async {
    final db = await database;
    try {
      return await db.query(
        'sanction_events',
        where: 'studentId = ?',
        whereArgs: [studentId],
        orderBy: 'date DESC',
        limit: limit,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> updateStudent(String oldId, Student updatedStudent) async {
    final db = await database;
    await db.update(
      'students',
      updatedStudent.toMap(),
      where: 'id = ?',
      whereArgs: [oldId],
    );
    try {
      await logAudit(
        category: 'student',
        action: 'update_student',
        details: 'id=$oldId -> ${updatedStudent.id}',
      );
    } catch (_) {}
  }

  Future<void> updateStudentDocuments({
    required String studentId,
    required List<StudentDocument> documents,
    String? updatedBy,
  }) async {
    final db = await database;
    await db.update(
      'students',
      {'documents': StudentDocument.encodeList(documents)},
      where: 'id = ?',
      whereArgs: [studentId],
    );
    try {
      await logAudit(
        category: 'student',
        action: 'update_student_documents',
        details:
            'id=$studentId count=${documents.length} by=${updatedBy ?? ''}',
      );
    } catch (_) {}
  }

  Future<void> deleteStudent(String id) async {
    final db = await database;
    await db.delete('students', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'student',
        action: 'delete_student',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<void> softDeleteStudents({
    required List<String> studentIds,
    String? deletedBy,
  }) async {
    if (studentIds.isEmpty) return;
    debugPrint(
      '[DatabaseService] softDeleteStudents(count=${studentIds.length}, deletedBy=${deletedBy ?? ''})',
    );
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(studentIds.length, '?').join(',');
    await db.update(
      'students',
      {'isDeleted': 1, 'deletedAt': now},
      where: 'id IN ($placeholders)',
      whereArgs: studentIds,
    );
    try {
      await logAudit(
        category: 'student',
        action: 'soft_delete_student',
        details:
            'count=${studentIds.length} by=${deletedBy ?? ''} ids=${studentIds.take(10).join(',')}',
      );
    } catch (_) {}
  }

  Future<void> restoreStudents({
    required List<String> studentIds,
    String? restoredBy,
  }) async {
    if (studentIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(studentIds.length, '?').join(',');
    await db.update(
      'students',
      {'isDeleted': 0, 'deletedAt': null},
      where: 'id IN ($placeholders)',
      whereArgs: studentIds,
    );
    try {
      await logAudit(
        category: 'student',
        action: 'restore_student',
        details:
            'count=${studentIds.length} by=${restoredBy ?? ''} ids=${studentIds.take(10).join(',')}',
      );
    } catch (_) {}
  }

  Future<void> updateStudentsClassAndYear({
    required List<String> studentIds,
    required String className,
    required String academicYear,
    String? updatedBy,
  }) async {
    if (studentIds.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await _ensureClassExists(txn, className, academicYear: academicYear);
      final placeholders = List.filled(studentIds.length, '?').join(',');
      await txn.update(
        'students',
        {'className': className, 'academicYear': academicYear},
        where: 'id IN ($placeholders)',
        whereArgs: studentIds,
      );
    });
    try {
      await logAudit(
        category: 'student',
        action: 'bulk_update_class',
        details:
            'count=${studentIds.length} to=$className($academicYear) by=${updatedBy ?? ''}',
      );
    } catch (_) {}
  }

  /// Delete a student and all dependent data (payments, grades, appreciations, report cards, archives).
  Future<void> deleteStudentDeep(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      debugPrint('[DatabaseService] deleteStudentDeep: start id=$id');

      // Defensive cleanup: delete from *any* table that has a FK to students(id).
      // This protects against older DB schemas that may have additional FK tables.
      try {
        final tables = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );
        final tableNames = tables
            .map((r) => r['name'])
            .whereType<String>()
            .where(
              (t) =>
                  t != 'students' &&
                  t != 'sqlite_sequence' &&
                  RegExp(r'^[A-Za-z0-9_]+$').hasMatch(t),
            )
            .toList();

        for (final table in tableNames) {
          final fks = await txn.rawQuery('PRAGMA foreign_key_list($table)');
          for (final fk in fks) {
            final refTable = fk['table']?.toString();
            final fromColumn = fk['from']?.toString();
            final toColumn = fk['to']?.toString();
            if (refTable != 'students') continue;
            if (toColumn != 'id') continue;
            if (fromColumn == null ||
                fromColumn.isEmpty ||
                !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(fromColumn)) {
              continue;
            }
            try {
              await txn.delete(
                table,
                where: '$fromColumn = ?',
                whereArgs: [id],
              );
            } catch (_) {}
          }
        }
      } catch (_) {}

      // Discipline tables (FK RESTRICT -> must delete first)
      try {
        await txn.delete(
          'attendance_events',
          where: 'studentId = ?',
          whereArgs: [id],
        );
      } catch (_) {}
      try {
        await txn.delete(
          'sanction_events',
          where: 'studentId = ?',
          whereArgs: [id],
        );
      } catch (_) {}

      // Library tables (FK RESTRICT -> must delete first)
      try {
        await txn.delete(
          'library_loans',
          where: 'studentId = ?',
          whereArgs: [id],
        );
      } catch (_) {}
      try {
        await txn.delete(
          'library_loan_batches',
          where: 'studentId = ?',
          whereArgs: [id],
        );
      } catch (_) {}

      // Current year data
      await txn.delete(
        'subject_appreciation',
        where: 'studentId = ?',
        whereArgs: [id],
      );
      await txn.delete('report_cards', where: 'studentId = ?', whereArgs: [id]);
      await txn.delete('grades', where: 'studentId = ?', whereArgs: [id]);
      await txn.delete('payments', where: 'studentId = ?', whereArgs: [id]);
      // Archives
      // subject_appreciation_archive will be deleted automatically by FK CASCADE when report_cards_archive rows are deleted
      await txn.delete(
        'report_cards_archive',
        where: 'studentId = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'grades_archive',
        where: 'studentId = ?',
        whereArgs: [id],
      );
      // Finally the student
      await txn.delete('students', where: 'id = ?', whereArgs: [id]);
    });
    try {
      await logAudit(
        category: 'student',
        action: 'delete_student_deep',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  // Aggregate data for charts and table
  Future<Map<String, int>> getClassDistribution() async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT className, academicYear, COUNT(*) as count
      FROM students
      WHERE (isDeleted IS NULL OR isDeleted = 0)
      GROUP BY className, academicYear
    ''');
    return {
      for (var item in result)
        '${item['className']} (${item['academicYear']})': item['count'],
    };
  }

  Future<Map<String, int>> getGenderDistribution(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT gender, COUNT(*) as count
      FROM students
      WHERE className = ? AND academicYear = ? AND (isDeleted IS NULL OR isDeleted = 0)
      GROUP BY gender
    ''',
      [className, academicYear],
    );
    return {for (var item in result) item['gender']: item['count']};
  }

  Future<Map<String, int>> getAcademicYearDistribution() async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT academicYear, COUNT(*) as count
      FROM students
      WHERE (isDeleted IS NULL OR isDeleted = 0)
      GROUP BY academicYear
    ''');
    return {for (var item in result) item['academicYear']: item['count']};
  }

  Future<void> insertPayment(Payment payment) async {
    final db = await database;
    String? usedReceiptNo;
    await db.transaction((txn) async {
      await _ensureStudentExists(txn, payment.studentId);
      await _ensureClassExists(
        txn,
        payment.className,
        academicYear: payment.classAcademicYear,
      );
      String? receiptNo = (payment.receiptNo ?? '').trim();
      if (receiptNo.isEmpty) {
        receiptNo = await _nextPaymentReceiptNo(
          txn,
          academicYear: payment.classAcademicYear,
        );
      }
      usedReceiptNo = receiptNo;
      final map = payment.toMap()..['receiptNo'] = receiptNo;
      await txn.insert(
        'payments',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    try {
      await logAudit(
        category: 'payment',
        action: 'insert_payment',
        details:
            'student=${payment.studentId} class=${payment.className} amount=${payment.amount} receipt=${usedReceiptNo ?? ''}',
      );
    } catch (_) {}
  }

  Future<String> _nextPaymentReceiptNo(
    Transaction txn, {
    required String academicYear,
  }) async {
    final year = academicYear.trim();
    if (year.isEmpty) {
      return 'PAY-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch}';
    }
    final rows = await txn.query(
      'payment_receipt_counters',
      columns: ['seq'],
      where: 'academicYear = ?',
      whereArgs: [year],
      limit: 1,
    );
    int next = 1;
    if (rows.isEmpty) {
      await txn.insert('payment_receipt_counters', {
        'academicYear': year,
        'seq': next,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      final current = (rows.first['seq'] as int?) ?? 0;
      next = current + 1;
      await txn.update(
        'payment_receipt_counters',
        {'seq': next},
        where: 'academicYear = ?',
        whereArgs: [year],
      );
    }
    final padded = next.toString().padLeft(5, '0');
    return 'PAY-$year-$padded';
  }

  Future<void> cancelPayment(int id) async {
    final db = await database;
    await db.update(
      'payments',
      {'isCancelled': 1, 'cancelledAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await logAudit(
        category: 'payment',
        action: 'cancel_payment',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<void> cancelPaymentWithReason(
    int id,
    String reason, {
    String? by,
  }) async {
    final db = await database;
    await db.update(
      'payments',
      {
        'isCancelled': 1,
        'cancelledAt': DateTime.now().toIso8601String(),
        'cancelReason': reason,
        if (by != null) 'cancelBy': by,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await logAudit(
        category: 'payment',
        action: 'cancel_payment_reason',
        details: 'id=$id reason=$reason by=${by ?? ''}',
      );
    } catch (_) {}
  }

  Future<List<Payment>> getPaymentsForStudent(String studentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'studentId = ? AND (isCancelled IS NULL OR isCancelled = 0)',
      whereArgs: [studentId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => Payment.fromMap(maps[i]));
  }

  Future<double> getTotalPaidForStudent(String studentId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM payments WHERE studentId = ? AND (isCancelled IS NULL OR isCancelled = 0)',
      [studentId],
    );
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }

  Future<void> deletePayment(int id) async {
    final db = await database;
    await db.delete('payments', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'payment',
        action: 'delete_payment',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<List<Payment>> getAllPayments() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'isCancelled IS NULL OR isCancelled = 0',
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => Payment.fromMap(maps[i]));
  }

  Future<List<Payment>> getCancelledPaymentsForYear(String academicYear) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: '(isCancelled = 1) AND classAcademicYear = ?',
      whereArgs: [academicYear],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => Payment.fromMap(maps[i]));
  }

  Future<Student?> getStudentById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'students',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Student.fromMap(maps.first);
    }
    return null;
  }

  Future<int> insertPaymentAdjustment(PaymentAdjustment adjustment) async {
    final db = await database;
    final id = await db.transaction((txn) async {
      await _ensureStudentExists(txn, adjustment.studentId);
      await _ensureClassExists(
        txn,
        adjustment.className,
        academicYear: adjustment.classAcademicYear,
      );
      return txn.insert(
        'payment_adjustments',
        adjustment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    try {
      await logAudit(
        category: 'payment',
        action: 'insert_payment_adjustment',
        details:
            'student=${adjustment.studentId} class=${adjustment.className} year=${adjustment.classAcademicYear} type=${adjustment.type} amount=${adjustment.amount}',
      );
    } catch (_) {}
    return id;
  }

  Future<int> insertPaymentAttachment(PaymentAttachment attachment) async {
    final db = await database;
    final id = await db.insert(
      'payment_attachments',
      attachment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'payment',
        action: 'insert_payment_attachment',
        details:
            'paymentId=${attachment.paymentId} student=${attachment.studentId} file=${attachment.fileName}',
      );
    } catch (_) {}
    return id;
  }

  Future<List<PaymentAttachment>> getPaymentAttachmentsForPayment({
    required int paymentId,
  }) async {
    final db = await database;
    final maps = await db.query(
      'payment_attachments',
      where: 'paymentId = ?',
      whereArgs: [paymentId],
      orderBy: 'createdAt DESC',
    );
    return maps.map(PaymentAttachment.fromMap).toList();
  }

  Future<void> deletePaymentAttachment({required int id}) async {
    final db = await database;
    await db.delete('payment_attachments', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'payment',
        action: 'delete_payment_attachment',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<void> setPaymentScheduleRule({
    required String classAcademicYear,
    String? className,
    required String scheduleJson,
    String? updatedBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('payment_schedule_rules', {
      'classAcademicYear': classAcademicYear,
      'className': className,
      'scheduleJson': scheduleJson,
      'updatedAt': now,
      'updatedBy': updatedBy,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      await logAudit(
        category: 'payment',
        action: 'set_payment_schedule_rule',
        details:
            'year=$classAcademicYear class=${className ?? ''} updatedBy=${updatedBy ?? ''}',
      );
    } catch (_) {}
  }

  Future<PaymentScheduleRule?> getPaymentScheduleRule({
    required String classAcademicYear,
    String? className,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps;
    if (className == null) {
      maps = await db.query(
        'payment_schedule_rules',
        where: 'classAcademicYear = ? AND className IS NULL',
        whereArgs: [classAcademicYear],
        limit: 1,
      );
    } else {
      maps = await db.query(
        'payment_schedule_rules',
        where: 'classAcademicYear = ? AND className = ?',
        whereArgs: [classAcademicYear, className],
        limit: 1,
      );
    }
    if (maps.isEmpty) return null;
    return PaymentScheduleRule.fromMap(maps.first);
  }

  Future<PaymentScheduleRule?> getEffectivePaymentScheduleRule({
    required String classAcademicYear,
    required String className,
  }) async {
    final specific = await getPaymentScheduleRule(
      classAcademicYear: classAcademicYear,
      className: className,
    );
    if (specific != null) return specific;
    return getPaymentScheduleRule(
      classAcademicYear: classAcademicYear,
      className: null,
    );
  }

  Future<void> cancelPaymentAdjustmentWithReason(
    int id,
    String reason, {
    String? by,
  }) async {
    final db = await database;
    await db.update(
      'payment_adjustments',
      {
        'isCancelled': 1,
        'cancelledAt': DateTime.now().toIso8601String(),
        'cancelReason': reason,
        if (by != null) 'cancelBy': by,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await logAudit(
        category: 'payment',
        action: 'cancel_payment_adjustment',
        details: 'id=$id reason=$reason by=${by ?? ''}',
      );
    } catch (_) {}
  }

  Future<List<PaymentAdjustment>> getPaymentAdjustmentsForYear(
    String academicYear,
  ) async {
    final db = await database;
    final maps = await db.query(
      'payment_adjustments',
      where:
          'classAcademicYear = ? AND (isCancelled IS NULL OR isCancelled = 0)',
      whereArgs: [academicYear],
      orderBy: 'createdAt DESC',
    );
    return maps.map(PaymentAdjustment.fromMap).toList();
  }

  Future<List<PaymentAdjustment>> getPaymentAdjustmentsForStudent({
    required String studentId,
    required String academicYear,
  }) async {
    final db = await database;
    final maps = await db.query(
      'payment_adjustments',
      where:
          'studentId = ? AND classAcademicYear = ? AND (isCancelled IS NULL OR isCancelled = 0)',
      whereArgs: [studentId, academicYear],
      orderBy: 'createdAt DESC',
    );
    return maps.map(PaymentAdjustment.fromMap).toList();
  }

  // Staff operations
  Future<void> insertStaff(Staff staff) async {
    final db = await database;
    await db.insert(
      'staff',
      staff.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'staff',
        action: 'insert_staff',
        details: 'id=${staff.id} name=${staff.name}',
      );
    } catch (_) {}
  }

  // Inventory operations
  Future<int> insertInventoryItem(InventoryItem item) async {
    final db = await database;
    final id = await db.insert(
      'inventory_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'inventory',
        action: 'insert_item',
        details: 'id=$id name=${item.name} qty=${item.quantity}',
      );
    } catch (_) {}
    return id;
  }

  // Expenses operations
  Future<int> insertExpense(Expense e) async {
    final db = await database;
    final id = await db.insert(
      'expenses',
      e.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'expense',
        action: 'insert_expense',
        details: 'id=$id label=${e.label} amount=${e.amount}',
      );
    } catch (_) {}
    return id;
  }

  Future<void> updateExpense(Expense e) async {
    if (e.id == null) return;
    final db = await database;
    await db.update('expenses', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    try {
      await logAudit(
        category: 'expense',
        action: 'update_expense',
        details: 'id=${e.id} label=${e.label} amount=${e.amount}',
      );
    } catch (_) {}
  }

  Future<void> deleteExpense(int id) async {
    final db = await database;
    // Ensure attachments are removed even if foreign keys are disabled.
    await db.delete(
      'expense_attachments',
      where: 'expenseId = ?',
      whereArgs: [id],
    );
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'expense',
        action: 'delete_expense',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<int> insertExpenseAttachment(ExpenseAttachment attachment) async {
    final db = await database;
    final id = await db.insert(
      'expense_attachments',
      attachment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'expense',
        action: 'insert_expense_attachment',
        details:
            'expenseId=${attachment.expenseId} file=${attachment.fileName}',
      );
    } catch (_) {}
    return id;
  }

  Future<List<ExpenseAttachment>> getExpenseAttachmentsForExpense({
    required int expenseId,
  }) async {
    final db = await database;
    final maps = await db.query(
      'expense_attachments',
      where: 'expenseId = ?',
      whereArgs: [expenseId],
      orderBy: 'createdAt DESC',
    );
    return maps.map(ExpenseAttachment.fromMap).toList();
  }

  Future<void> deleteExpenseAttachment({required int id}) async {
    final db = await database;
    await db.delete('expense_attachments', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'expense',
        action: 'delete_expense_attachment',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<List<Supplier>> getSuppliers() async {
    final db = await database;
    final maps = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    return maps.map(Supplier.fromMap).toList();
  }

  Future<int> insertOrGetSupplierIdByName({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    final db = await database;
    final clean = name.trim();
    if (clean.isEmpty) return 0;
    final existing = await db.query(
      'suppliers',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return (existing.first['id'] as num?)?.toInt() ?? 0;
    }
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('suppliers', {
      'name': clean,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'createdAt': now,
      'updatedAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != 0) {
      try {
        await logAudit(
          category: 'expense',
          action: 'insert_supplier',
          details: 'id=$id name=$clean',
        );
      } catch (_) {}
      return id;
    }
    final after = await db.query(
      'suppliers',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (after.isEmpty) return 0;
    return (after.first['id'] as num?)?.toInt() ?? 0;
  }

  Future<int> setFinanceBudget({
    required String academicYear,
    required String category,
    String? className,
    required double plannedAmount,
    String? updatedBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('finance_budgets', {
      'academicYear': academicYear,
      'category': category,
      'className': className,
      'plannedAmount': plannedAmount,
      'updatedAt': now,
      'updatedBy': updatedBy,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      await logAudit(
        category: 'expense',
        action: 'set_finance_budget',
        details:
            'id=$id year=$academicYear category=$category class=${className ?? ''} amount=$plannedAmount by=${updatedBy ?? ''}',
      );
    } catch (_) {}
    return id;
  }

  Future<List<FinanceBudget>> getFinanceBudgets({
    required String academicYear,
    String? className,
  }) async {
    final db = await database;
    final where = <String>['academicYear = ?'];
    final args = <Object?>[academicYear];
    if (className == null) {
      where.add('className IS NULL');
    } else if (className.trim().isNotEmpty) {
      where.add('className = ?');
      args.add(className.trim());
    }
    final maps = await db.query(
      'finance_budgets',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'category COLLATE NOCASE',
    );
    return maps.map(FinanceBudget.fromMap).toList();
  }

  Future<List<Expense>> getExpenses({
    String? className,
    String? academicYear,
    String? category,
    String? supplier,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (academicYear != null && academicYear.isNotEmpty) {
      where.add('academicYear = ?');
      args.add(academicYear);
    }
    if (className != null && className.isNotEmpty) {
      where.add('className = ?');
      args.add(className);
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    if (supplier != null && supplier.isNotEmpty) {
      where.add('supplier = ?');
      args.add(supplier);
    }
    final rows = await db.query(
      'expenses',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'date DESC',
    );
    return rows.map((m) => Expense.fromMap(m)).toList();
  }

  Future<double> getTotalExpenses({
    String? className,
    String? academicYear,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (academicYear != null && academicYear.isNotEmpty) {
      where.add('academicYear = ?');
      args.add(academicYear);
    }
    if (className != null && className.isNotEmpty) {
      where.add('className = ?');
      args.add(className);
    }
    final res = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses' +
          (where.isEmpty ? '' : ' WHERE ' + where.join(' AND ')),
      args,
    );
    final total = res.isNotEmpty && res.first['total'] != null
        ? (res.first['total'] as num).toDouble()
        : 0.0;
    return total;
  }

  Future<void> updateInventoryItem(InventoryItem item) async {
    if (item.id == null) return;
    final db = await database;
    await db.update(
      'inventory_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
    try {
      await logAudit(
        category: 'inventory',
        action: 'update_item',
        details: 'id=${item.id} name=${item.name} qty=${item.quantity}',
      );
    } catch (_) {}
  }

  Future<void> deleteInventoryItem(int id) async {
    final db = await database;
    await db.delete('inventory_items', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'inventory',
        action: 'delete_item',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<List<InventoryItem>> getInventoryItems({
    String? className,
    String? academicYear,
  }) async {
    final db = await database;
    String? where;
    List<Object?>? whereArgs;
    final parts = <String>[];
    final args = <Object?>[];
    if (className != null && className.isNotEmpty) {
      parts.add('className = ?');
      args.add(className);
    }
    if (academicYear != null && academicYear.isNotEmpty) {
      parts.add('academicYear = ?');
      args.add(academicYear);
    }
    if (parts.isNotEmpty) {
      where = parts.join(' AND ');
      whereArgs = args;
    }
    final rows = await db.query(
      'inventory_items',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'category ASC, name ASC',
    );
    return rows.map((m) => InventoryItem.fromMap(m)).toList();
  }

  Future<List<Staff>> getStaff() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('staff');
    return List.generate(maps.length, (i) => Staff.fromMap(maps[i]));
  }

  Future<void> updateStaff(String id, Staff updatedStaff) async {
    final db = await database;
    await db.update(
      'staff',
      updatedStaff.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await logAudit(
        category: 'staff',
        action: 'update_staff',
        details: 'id=$id name=${updatedStaff.name}',
      );
    } catch (_) {}
  }

  Future<List<TeacherAssignment>> getTeacherAssignmentsForTeacher(
    String teacherId, {
    String? academicYear,
  }) async {
    final db = await database;
    final whereParts = <String>['teacherId = ?'];
    final args = <Object?>[teacherId];
    if (academicYear != null && academicYear.isNotEmpty) {
      whereParts.add('academicYear = ?');
      args.add(academicYear);
    }
    final maps = await db.query(
      'teacher_assignments',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'className ASC',
    );
    return maps.map(TeacherAssignment.fromMap).toList();
  }

  Future<List<TeacherAssignment>> getTeacherAssignmentsForClass(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    final maps = await db.query(
      'teacher_assignments',
      where: 'className = ? AND academicYear = ?',
      whereArgs: [className, academicYear],
      orderBy: 'courseId ASC',
    );
    return maps.map(TeacherAssignment.fromMap).toList();
  }

  Future<void> replaceTeacherAssignmentsForTeacherYear({
    required String teacherId,
    required String academicYear,
    required List<TeacherAssignment> assignments,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'teacher_assignments',
        where: 'teacherId = ? AND academicYear = ?',
        whereArgs: [teacherId, academicYear],
      );
      for (final assignment in assignments) {
        await txn.insert(
          'teacher_assignments',
          assignment.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _bumpTeacherAssignmentsVersion();
  }

  Future<void> replaceTeacherAssignmentsForClassYear({
    required String className,
    required String academicYear,
    required List<TeacherAssignment> assignments,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'teacher_assignments',
        where: 'className = ? AND academicYear = ?',
        whereArgs: [className, academicYear],
      );
      for (final assignment in assignments) {
        await txn.insert(
          'teacher_assignments',
          assignment.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _bumpTeacherAssignmentsVersion();
  }

  Future<Map<String, String>> getTeacherNameByCourseForClass({
    required String className,
    required String academicYear,
  }) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT ta.courseId, s.name AS teacherName
      FROM teacher_assignments ta
      JOIN staff s ON s.id = ta.teacherId
      WHERE ta.className = ? AND ta.academicYear = ?
    ''',
      [className, academicYear],
    );
    final map = <String, String>{};
    for (final row in rows) {
      final courseId = row['courseId'] as String?;
      final teacherName = row['teacherName'] as String?;
      if (courseId != null && teacherName != null) {
        map[courseId] = teacherName;
      }
    }
    return map;
  }

  Future<void> updateTeacherWeeklyHours(String id, int? weeklyHours) async {
    final db = await database;
    await db.update(
      'staff',
      {'weekly_hours': weeklyHours},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteStaff(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'teacher_assignments',
        where: 'teacherId = ?',
        whereArgs: [id],
      );
      await txn.delete('staff', where: 'id = ?', whereArgs: [id]);
    });
    try {
      await logAudit(
        category: 'staff',
        action: 'delete_staff',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<void> updateStaffDocuments({
    required String staffId,
    required List<String> documents,
    String? updatedBy,
  }) async {
    final db = await database;
    await db.update(
      'staff',
      {'documents': documents.join(',')},
      where: 'id = ?',
      whereArgs: [staffId],
    );
    try {
      await logAudit(
        category: 'staff',
        action: 'update_staff_documents',
        details: 'id=$staffId count=${documents.length} by=${updatedBy ?? ''}',
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getStaffAbsences({
    required String staffId,
    int limit = 500,
  }) async {
    final db = await database;
    return db.query(
      'staff_absences',
      where: 'staffId = ?',
      whereArgs: [staffId],
      orderBy: 'startDate DESC',
      limit: limit,
    );
  }

  Future<int> insertStaffAbsence({
    required String staffId,
    required String type,
    required String startDate,
    required String endDate,
    String status = 'Prévu',
    String? reason,
    String? recordedBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('staff_absences', {
      'staffId': staffId,
      'type': type,
      'startDate': startDate,
      'endDate': endDate,
      'status': status,
      'reason': reason,
      'recordedBy': recordedBy,
      'createdAt': now,
      'updatedAt': now,
    });
    try {
      await logAudit(
        category: 'staff',
        action: 'add_staff_absence',
        details: 'id=$id staffId=$staffId type=$type $startDate->$endDate',
      );
    } catch (_) {}
    return id;
  }

  Future<void> updateStaffAbsence({
    required int id,
    required String staffId,
    required String type,
    required String startDate,
    required String endDate,
    required String status,
    String? reason,
    String? recordedBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'staff_absences',
      {
        'type': type,
        'startDate': startDate,
        'endDate': endDate,
        'status': status,
        'reason': reason,
        'recordedBy': recordedBy,
        'updatedAt': now,
      },
      where: 'id = ? AND staffId = ?',
      whereArgs: [id, staffId],
    );
    try {
      await logAudit(
        category: 'staff',
        action: 'update_staff_absence',
        details: 'id=$id staffId=$staffId type=$type $startDate->$endDate',
      );
    } catch (_) {}
  }

  Future<void> deleteStaffAbsence({
    required int id,
    required String staffId,
  }) async {
    final db = await database;
    await db.delete(
      'staff_absences',
      where: 'id = ? AND staffId = ?',
      whereArgs: [id, staffId],
    );
    try {
      await logAudit(
        category: 'staff',
        action: 'delete_staff_absence',
        details: 'id=$id staffId=$staffId',
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getGradesPeriodWorkflow({
    required String className,
    required String academicYear,
    required String term,
  }) async {
    final db = await database;
    final rows = await db.query(
      'grades_period_workflow',
      where: 'className = ? AND academicYear = ? AND term = ?',
      whereArgs: [className, academicYear, term],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> setGradesPeriodWorkflow({
    required String className,
    required String academicYear,
    required String term,
    required String status,
    required bool locked,
    String? updatedBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('grades_period_workflow', {
      'className': className,
      'academicYear': academicYear,
      'term': term,
      'status': status,
      'locked': locked ? 1 : 0,
      'updatedAt': now,
      'updatedBy': updatedBy,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      await logAudit(
        category: 'grade',
        action: 'set_period_workflow',
        details:
            'class=$className year=$academicYear term=$term status=$status locked=${locked ? 1 : 0} by=${updatedBy ?? ''}',
      );
    } catch (_) {}
  }

  // Category operations
  Future<void> insertCategory(Category category) async {
    final db = await database;
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'subjects',
        action: 'insert_category',
        details: 'id=${category.id} name=${category.name}',
      );
    } catch (_) {}
  }

  Future<List<Category>> getCategories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      orderBy: 'order_index ASC, name ASC',
    );
    return List.generate(maps.length, (i) => Category.fromMap(maps[i]));
  }

  Future<void> updateCategory(String id, Category updatedCategory) async {
    final db = await database;
    await db.update(
      'categories',
      updatedCategory.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await logAudit(
        category: 'subjects',
        action: 'update_category',
        details: 'id=$id name=${updatedCategory.name}',
      );
    } catch (_) {}
  }

  Future<void> deleteCategory(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      // Mettre à jour les cours pour retirer la référence à cette catégorie
      await txn.update(
        'courses',
        {'categoryId': null},
        where: 'categoryId = ?',
        whereArgs: [id],
      );
      // Supprimer la catégorie
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
    try {
      await logAudit(
        category: 'subjects',
        action: 'delete_category',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<void> initializeDefaultCategories() async {
    final db = await database;
    final existingCategories = await db.query('categories');

    if (existingCategories.isEmpty) {
      final defaultCategories = [
        {
          'id': 'scientific',
          'name': 'Scientifiques',
          'description': 'Matières scientifiques et techniques',
          'color': '#3B82F6',
          'order_index': 1,
        },
        {
          'id': 'literary',
          'name': 'Littéraires',
          'description': 'Matières littéraires et linguistiques',
          'color': '#10B981',
          'order_index': 2,
        },
        {
          'id': 'optional',
          'name': 'Facultatives',
          'description': 'Matières optionnelles et activités',
          'color': '#F59E0B',
          'order_index': 3,
        },
        {
          'id': 'general',
          'name': 'Générales',
          'description': 'Matières générales et transversales',
          'color': '#8B5CF6',
          'order_index': 4,
        },
      ];

      for (final category in defaultCategories) {
        await db.insert(
          'categories',
          category,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  // Course operations
  Future<void> insertCourse(Course course) async {
    final db = await database;
    await db.insert(
      'courses',
      course.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'subjects',
        action: 'insert_course',
        details: 'id=${course.id} name=${course.name}',
      );
    } catch (_) {}
  }

  Future<List<Course>> getCourses() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('courses');
    return List.generate(maps.length, (i) => Course.fromMap(maps[i]));
  }

  Future<void> updateCourse(String id, Course updatedCourse) async {
    final db = await database;
    await db.update(
      'courses',
      updatedCourse.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await logAudit(
        category: 'subjects',
        action: 'update_course',
        details: 'id=$id name=${updatedCourse.name}',
      );
    } catch (_) {}
  }

  Future<void> deleteCourse(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      // Remove bindings first to satisfy FK RESTRICT
      await txn.delete('class_courses', where: 'courseId = ?', whereArgs: [id]);
      await txn.delete(
        'teacher_assignments',
        where: 'courseId = ?',
        whereArgs: [id],
      );
      await txn.delete('courses', where: 'id = ?', whereArgs: [id]);
    });
    try {
      await logAudit(
        category: 'subjects',
        action: 'delete_course',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // --- Class deletion helpers ---
  Future<Map<String, int>> getClassDependenciesCounts(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    final Map<String, int> counts = {};
    Future<int> cnt(
      String table, {
      String classColumn = 'className',
      String? yearColumn = 'academicYear',
    }) async {
      String where = '$classColumn = ?';
      final args = <Object?>[className];
      if (yearColumn != null) {
        where += ' AND $yearColumn = ?';
        args.add(academicYear);
      }
      final res = await db.rawQuery(
        'SELECT COUNT(*) as c FROM $table WHERE $where',
        args,
      );
      return (res.first['c'] as int?) ?? (res.first['c'] as num?)?.toInt() ?? 0;
    }

    counts['students'] = await cnt('students');
    counts['payments'] = await cnt(
      'payments',
      classColumn: 'className',
      yearColumn: 'classAcademicYear',
    );
    counts['grades'] = await cnt('grades');
    counts['report_cards'] = await cnt('report_cards');
    counts['subject_appreciation'] = await cnt('subject_appreciation');
    counts['timetable_entries'] = await cnt('timetable_entries');
    counts['class_courses'] = await cnt('class_courses');
    counts['teacher_assignments'] = await cnt('teacher_assignments');
    counts['report_cards_archive'] = await cnt('report_cards_archive');
    counts['grades_archive'] = await cnt('grades_archive');
    return counts;
  }

  Future<void> deleteClassByName(String className, String academicYear) async {
    final db = await database;
    // Check dependencies to avoid FK RESTRICT errors and offer clear message
    final counts = await getClassDependenciesCounts(className, academicYear);
    final hasDeps = counts.values.any((v) => v > 0);
    if (hasDeps) {
      throw Exception(
        'Impossible de supprimer la classe. Supprimez d\'abord les éléments liés (élèves, notes, paiements, etc.).',
      );
    }
    await db.delete(
      'classes',
      where: 'name = ? AND academicYear = ?',
      whereArgs: [className, academicYear],
    );
    try {
      await logAudit(
        category: 'class',
        action: 'delete_class',
        details: 'name=$className year=$academicYear',
      );
    } catch (_) {}
  }

  // Import logs operations
  Future<void> insertImportLog({
    required String filename,
    String? user,
    required String mode,
    required String className,
    required String academicYear,
    required String term,
    required int total,
    required int success,
    required int errors,
    required int warnings,
    required String detailsJson,
  }) async {
    final db = await database;
    await db.insert('import_logs', {
      'timestamp': DateTime.now().toIso8601String(),
      'filename': filename,
      'user': user,
      'mode': mode,
      'className': className,
      'academicYear': academicYear,
      'term': term,
      'total': total,
      'success': success,
      'errors': errors,
      'warnings': warnings,
      'details': detailsJson,
    });
  }

  // Met à jour le nom d'une classe dans tous les membres du personnel
  Future<void> updateClassNameInStaff(String oldName, String newName) async {
    final db = await database;
    final List<Map<String, dynamic>> staffList = await db.query('staff');
    for (final staff in staffList) {
      final classesStr = staff['classes'] as String?;
      if (classesStr != null && classesStr.isNotEmpty) {
        final classes = classesStr.split(',');
        final updatedClasses = classes
            .map((c) => c == oldName ? newName : c)
            .toList();
        await db.update(
          'staff',
          {'classes': updatedClasses.join(',')},
          where: 'id = ?',
          whereArgs: [staff['id']],
        );
      }
    }
  }

  // Grade operations
  Future<void> insertGrade(Grade grade) async {
    final db = await database;
    await db.transaction((txn) async {
      await _ensureStudentExists(txn, grade.studentId);
      await _ensureClassExists(
        txn,
        grade.className,
        academicYear: grade.academicYear,
      );
      await txn.insert(
        'grades',
        grade.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    try {
      await logAudit(
        category: 'grade',
        action: 'insert_grade',
        details:
            'student=${grade.studentId} subject=${grade.subject} term=${grade.term}',
      );
    } catch (_) {}
  }

  Future<void> updateGrade(Grade grade) async {
    final db = await database;
    // Récupérer l'ancienne valeur pour journaliser avant/après
    double? oldValue;
    try {
      final prev = await db.query(
        'grades',
        where: 'id = ?',
        whereArgs: [grade.id],
        limit: 1,
      );
      if (prev.isNotEmpty) {
        final v = prev.first['value'];
        if (v is int) oldValue = v.toDouble();
        if (v is double) oldValue = v;
      }
    } catch (_) {}
    await db.transaction((txn) async {
      await _ensureStudentExists(txn, grade.studentId);
      await _ensureClassExists(
        txn,
        grade.className,
        academicYear: grade.academicYear,
      );
      await txn.update(
        'grades',
        grade.toMap(),
        where: 'id = ?',
        whereArgs: [grade.id],
      );
    });
    try {
      final before = oldValue?.toStringAsFixed(2) ?? '';
      final after = grade.value.toStringAsFixed(2);
      await logAudit(
        category: 'grade',
        action: 'update_grade',
        details:
            'id=${grade.id} subject=${grade.subject} term=${grade.term} value_old=$before value_new=$after',
      );
    } catch (_) {}
  }

  Future<void> deleteGrade(int id) async {
    final db = await database;
    await db.delete('grades', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'grade',
        action: 'delete_grade',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  // Modèles d'évaluations (Devoir/Composition, barème, coefficient)
  Future<List<EvaluationTemplate>> getEvaluationTemplates({
    required String className,
    required String academicYear,
    String? subjectId,
  }) async {
    final db = await database;
    final whereParts = <String>['className = ?', 'academicYear = ?'];
    final args = <Object?>[className, academicYear];
    if (subjectId != null && subjectId.trim().isNotEmpty) {
      whereParts.add('subjectId = ?');
      args.add(subjectId.trim());
    }
    final rows = await db.query(
      'evaluation_templates',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'type COLLATE NOCASE ASC, orderIndex ASC, id ASC',
    );
    return rows.map(EvaluationTemplate.fromMap).toList();
  }

  Future<int> upsertEvaluationTemplate(EvaluationTemplate template) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await _ensureClassExists(
      db,
      template.className,
      academicYear: template.academicYear,
    );
    if (template.id == null) {
      return await db.insert('evaluation_templates', {
        ...template.toMap()..remove('id'),
        'createdAt': now,
        'updatedAt': now,
      });
    }
    await db.update(
      'evaluation_templates',
      {...template.toMap()..remove('id'), 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [template.id],
    );
    return template.id!;
  }

  Future<void> deleteEvaluationTemplate(int id) async {
    final db = await database;
    await db.delete('evaluation_templates', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> ensureDefaultEvaluationTemplates({
    required String className,
    required String academicYear,
    required Course subject,
  }) async {
    final existing = await getEvaluationTemplates(
      className: className,
      academicYear: academicYear,
      subjectId: subject.id,
    );
    if (existing.isNotEmpty) return;

    double defaultCoeff = 1.0;
    try {
      final subjectCoeffs = await getClassSubjectCoefficients(
        className,
        academicYear,
      );
      final v = subjectCoeffs[subject.name];
      if (v != null && v > 0) defaultCoeff = v;
    } catch (_) {}
    await upsertEvaluationTemplate(
      EvaluationTemplate(
        className: className,
        academicYear: academicYear,
        subjectId: subject.id,
        subject: subject.name,
        type: 'Devoir',
        label: 'Devoir 1',
        maxValue: 20,
        coefficient: defaultCoeff,
        orderIndex: 1,
      ),
    );
    await upsertEvaluationTemplate(
      EvaluationTemplate(
        className: className,
        academicYear: academicYear,
        subjectId: subject.id,
        subject: subject.name,
        type: 'Composition',
        label: 'Composition 1',
        maxValue: 20,
        coefficient: defaultCoeff,
        orderIndex: 1,
      ),
    );
  }

  Future<List<Grade>> getGradesForSelection({
    required String className,
    required String academicYear,
    required String subject,
    required String term,
  }) async {
    final db = await database;
    // On cherche d'abord par subjectId si possible
    final course = await db.query(
      'courses',
      where: 'name = ?',
      whereArgs: [subject],
    );
    String? subjectId = course.isNotEmpty ? course.first['id'] as String : null;
    final List<Map<String, dynamic>> maps = await db.query(
      'grades',
      where: subjectId != null
          ? 'className = ? AND academicYear = ? AND (subject = ? OR subjectId = ?) AND term = ?'
          : 'className = ? AND academicYear = ? AND subject = ? AND term = ?',
      whereArgs: subjectId != null
          ? [className, academicYear, subject, subjectId, term]
          : [className, academicYear, subject, term],
    );
    return List.generate(maps.length, (i) => Grade.fromMap(maps[i]));
  }

  Future<Grade?> getGradeForStudent({
    required String studentId,
    required String className,
    required String academicYear,
    required String subject,
    required String term,
  }) async {
    final db = await database;
    final course = await db.query(
      'courses',
      where: 'name = ?',
      whereArgs: [subject],
    );
    String? subjectId = course.isNotEmpty ? course.first['id'] as String : null;
    final List<Map<String, dynamic>> maps = await db.query(
      'grades',
      where: subjectId != null
          ? 'studentId = ? AND className = ? AND academicYear = ? AND (subject = ? OR subjectId = ?) AND term = ?'
          : 'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
      whereArgs: subjectId != null
          ? [studentId, className, academicYear, subject, subjectId, term]
          : [studentId, className, academicYear, subject, term],
    );
    if (maps.isNotEmpty) {
      return Grade.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Grade>> getAllGradesForPeriod({
    required String className,
    required String academicYear,
    required String term,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'grades',
      where: 'className = ? AND academicYear = ? AND term = ?',
      whereArgs: [className, academicYear, term],
    );
    return List.generate(maps.length, (i) => Grade.fromMap(maps[i]));
  }

  // Appreciation/professeur par matière
  Future<void> insertOrUpdateSubjectAppreciation({
    required String studentId,
    required String className,
    required String academicYear,
    required String subject,
    required String term,
    String? professeur,
    String? appreciation,
    String? moyenneClasse,
    double? coefficient,
  }) async {
    final db = await database;
    await _ensureStudentExists(db, studentId);
    await _ensureClassExists(db, className, academicYear: academicYear);
    final existing = await db.query(
      'subject_appreciation',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, subject, term],
    );
    final data = {
      'studentId': studentId,
      'className': className,
      'academicYear': academicYear,
      'subject': subject,
      'term': term,
      'professeur': professeur,
      'appreciation': appreciation,
      'moyenne_classe': moyenneClasse,
      'coefficient': coefficient,
    };
    if (existing.isEmpty) {
      await db.insert('subject_appreciation', data);
    } else {
      await db.update(
        'subject_appreciation',
        data,
        where:
            'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
        whereArgs: [studentId, className, academicYear, subject, term],
      );
    }
    try {
      await logAudit(
        category: 'grade',
        action: 'upsert_subject_app',
        details: 'student=$studentId subject=$subject term=$term',
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getSubjectAppreciations({
    required String studentId,
    required String className,
    required String academicYear,
    required String term,
  }) async {
    final db = await database;
    return await db.query(
      'subject_appreciation',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, term],
    );
  }

  Future<List<Map<String, dynamic>>> getSubjectAppreciationsArchiveByKeys({
    required String studentId,
    required String className,
    required String academicYear,
    required String term,
  }) async {
    final db = await database;
    final rc = await db.query(
      'report_cards_archive',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, term],
      limit: 1,
    );
    if (rc.isEmpty) return [];
    final id = rc.first['id'] as int;
    return await db.query(
      'subject_appreciation_archive',
      where: 'report_card_id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getSubjectAppreciation({
    required String studentId,
    required String className,
    required String academicYear,
    required String subject,
    required String term,
  }) async {
    final db = await database;
    final res = await db.query(
      'subject_appreciation',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, subject, term],
    );
    if (res.isNotEmpty) return res.first;
    return null;
  }

  // Association Classe <-> Matière
  Future<void> addCourseToClass(
    String className,
    String academicYear,
    String courseId,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await _ensureClassExists(txn, className, academicYear: academicYear);
      await _ensureCourseExists(txn, courseId);
      await txn.insert('class_courses', {
        'className': className,
        'academicYear': academicYear,
        'courseId': courseId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    try {
      await logAudit(
        category: 'class_course',
        action: 'add_course_to_class',
        details: 'class=$className year=$academicYear course=$courseId',
      );
    } catch (_) {}
  }

  Future<void> removeCourseFromClass(
    String className,
    String academicYear,
    String courseId,
  ) async {
    final db = await database;
    await db.delete(
      'class_courses',
      where: 'className = ? AND academicYear = ? AND courseId = ?',
      whereArgs: [className, academicYear, courseId],
    );
  }

  Future<List<Course>> getCoursesForClass(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT c.* FROM courses c
      INNER JOIN class_courses cc ON cc.courseId = c.id
      WHERE cc.className = ? AND cc.academicYear = ?
    ''',
      [className, academicYear],
    );
    return List.generate(maps.length, (i) => Course.fromMap(maps[i]));
  }

  Future<List<Map<String, String>>> getClassesForCourse(String courseId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'class_courses',
      columns: ['className', 'academicYear'],
      where: 'courseId = ?',
      whereArgs: [courseId],
    );
    return maps
        .map(
          (m) => {
            'className': m['className'] as String,
            'academicYear': m['academicYear'] as String,
          },
        )
        .toList();
  }

  Future<void> archiveGradesForYear(String year) async {
    final db = await database;
    // Copier toutes les notes de l'année dans grades_archive
    await db.execute(
      '''
      INSERT INTO grades_archive (studentId, className, academicYear, subject, term, value, label, maxValue, coefficient, type, subjectId)
      SELECT studentId, className, academicYear, subject, term, value, label, maxValue, coefficient, type, subjectId
      FROM grades WHERE academicYear = ?
    ''',
      [year],
    );
  }

  Future<List<Grade>> getArchivedGrades({
    required String academicYear,
    String? className,
    String? studentId,
  }) async {
    final db = await database;
    String where = 'academicYear = ?';
    List<dynamic> whereArgs = [academicYear];
    if (className != null && className.isNotEmpty) {
      where += ' AND className = ?';
      whereArgs.add(className);
    }
    if (studentId != null && studentId != 'all' && studentId.isNotEmpty) {
      where += ' AND studentId = ?';
      whereArgs.add(studentId);
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'grades_archive',
      where: where,
      whereArgs: whereArgs,
    );
    return List.generate(maps.length, (i) => Grade.fromMap(maps[i]));
  }

  /// Archive tous les bulletins d'une année académique (notes, appréciations, synthèse)
  Future<void> archiveReportCardsForYear(String academicYear) async {
    final db = await database;
    await db.transaction((txn) async {
      // Supprimer les anciennes archives pour cette année
      await txn.delete(
        'subject_appreciation_archive',
        where:
            'report_card_id IN (SELECT id FROM report_cards_archive WHERE academicYear = ?)',
        whereArgs: [academicYear],
      );
      await txn.delete(
        'report_cards_archive',
        where: 'academicYear = ?',
        whereArgs: [academicYear],
      );
      await txn.delete(
        'grades_archive',
        where: 'academicYear = ?',
        whereArgs: [academicYear],
      );
      // Archiver toutes les notes de l'année dans grades_archive
      // Utiliser la transaction pour les inserts massifs
      final gradesToArchive = await txn.query(
        'grades',
        where: 'academicYear = ?',
        whereArgs: [academicYear],
      );
      for (final g in gradesToArchive) {
        final gradeCopy = Map<String, Object?>.from(g);
        gradeCopy.remove('id');
        await txn.insert('grades_archive', gradeCopy);
      }
      // Récupérer tous les élèves de l'année
      final classes = await txn.query(
        'classes',
        where: 'academicYear = ?',
        whereArgs: [academicYear],
      );
      for (final classRow in classes) {
        final className = classRow['name'] as String;
        // Ne considérer que les élèves de la classe pour l'année académique cible
        final students = await txn.query(
          'students',
          where: 'className = ? AND academicYear = ?',
          whereArgs: [className, academicYear],
        );
        for (final student in students) {
          final studentId = student['id'] as String;
          // On récupère tous les termes utilisés pour cette classe/année
          final grades = await txn.query(
            'grades',
            where: 'studentId = ? AND className = ? AND academicYear = ?',
            whereArgs: [studentId, className, academicYear],
          );
          final terms = grades.map((g) => g['term'] as String).toSet();
          for (final term in terms) {
            // Récupérer toutes les notes de ce bulletin
            final gradesForTerm = grades
                .where((g) => g['term'] == term)
                .toList();
            if (gradesForTerm.isEmpty) continue;
            // Récupérer toutes les appréciations par matière
            final subjectAppreciations = await txn.query(
              'subject_appreciation',
              where:
                  'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
              whereArgs: [studentId, className, academicYear, term],
            );
            // Récupérer la synthèse du bulletin (report_cards)
            final reportCard = await txn.query(
              'report_cards',
              where:
                  'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
              whereArgs: [studentId, className, academicYear, term],
            );
            Map<String, dynamic> synthese;
            if (reportCard.isNotEmpty) {
              synthese = reportCard.first;
            } else {
              // Calculer la synthèse automatiquement si elle n'existe pas
              // Moyenne générale pondérée par coefficients de matières définis au niveau de la classe
              final wRows = await txn.rawQuery(
                'SELECT c.name AS subject, cc.coefficient AS coeff FROM class_courses cc JOIN courses c ON c.id = cc.courseId WHERE cc.className = ? AND cc.academicYear = ?',
                [className, academicYear],
              );
              final Map<String, double> subjectWeights = {
                for (final r in wRows)
                  if (r['subject'] != null && r['coeff'] != null)
                    (r['subject'] as String): (r['coeff'] as num).toDouble(),
              };
              double sumPoints = 0.0;
              double sumWeights = 0.0;
              final Map<String, List<Map<String, dynamic>>> bySubject = {};
              for (final g in gradesForTerm) {
                final subj = (g['subject'] as String?) ?? '';
                bySubject.putIfAbsent(subj, () => []).add(g);
              }
              bySubject.forEach((subj, list) {
                double n = 0.0;
                double c = 0.0;
                for (final g in list) {
                  final value = g['value'] is int
                      ? (g['value'] as int).toDouble()
                      : (g['value'] as num? ?? 0.0);
                  final maxValue = g['maxValue'] is int
                      ? (g['maxValue'] as int).toDouble()
                      : (g['maxValue'] as num? ?? 20.0);
                  final coeff = g['coefficient'] is int
                      ? (g['coefficient'] as int).toDouble()
                      : (g['coefficient'] as num? ?? 1.0);
                  if (maxValue > 0 && coeff > 0) {
                    n += ((value / maxValue) * 20) * coeff;
                    c += coeff;
                  }
                }
                final double moyMatiere = c > 0 ? (n / c) : 0.0;
                final double w =
                    subjectWeights[subj] ?? c; // fallback si non défini
                if (w > 0) {
                  sumPoints += moyMatiere * w;
                  sumWeights += w;
                }
              });
              final moyenneGenerale = sumWeights > 0
                  ? (sumPoints / sumWeights)
                  : 0.0;
              // Calcul du rang (effectif limité à l'année académique concernée)
              final classStudentIds = (await txn.query(
                'students',
                where: 'className = ? AND academicYear = ?',
                whereArgs: [className, academicYear],
              )).map((s) => s['id'] as String).toList();
              final List<double> allMoyennes = [];
              for (final sid in classStudentIds) {
                final sg = await txn.query(
                  'grades',
                  where:
                      'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
                  whereArgs: [sid, className, academicYear, term],
                );
                // Moyenne pondérée par matière
                final Map<String, List<Map<String, dynamic>>> bySub = {};
                for (final g in sg) {
                  final subj = (g['subject'] as String?) ?? '';
                  bySub.putIfAbsent(subj, () => []).add(g);
                }
                double pts = 0.0;
                double wsum = 0.0;
                bySub.forEach((subj, list) {
                  double n = 0.0;
                  double c = 0.0;
                  for (final g in list) {
                    final value = g['value'] is int
                        ? (g['value'] as int).toDouble()
                        : (g['value'] as num? ?? 0.0);
                    final maxValue = g['maxValue'] is int
                        ? (g['maxValue'] as int).toDouble()
                        : (g['maxValue'] as num? ?? 20.0);
                    final coeff = g['coefficient'] is int
                        ? (g['coefficient'] as int).toDouble()
                        : (g['coefficient'] as num? ?? 1.0);
                    if (maxValue > 0 && coeff > 0) {
                      n += ((value / maxValue) * 20) * coeff;
                      c += coeff;
                    }
                  }
                  final double moyM = c > 0 ? (n / c) : 0.0;
                  final double w = subjectWeights[subj] ?? c;
                  if (w > 0) {
                    pts += moyM * w;
                    wsum += w;
                  }
                });
                allMoyennes.add(wsum > 0 ? (pts / wsum) : 0.0);
              }
              allMoyennes.sort((a, b) => b.compareTo(a));
              final rang =
                  allMoyennes.indexWhere(
                    (m) => (m - moyenneGenerale).abs() < 0.001,
                  ) +
                  1;
              final nbEleves = classStudentIds.length;

              final double? moyenneGeneraleDeLaClasse = allMoyennes.isNotEmpty
                  ? allMoyennes.reduce((a, b) => a + b) / allMoyennes.length
                  : null;
              final double? moyenneLaPlusForte = allMoyennes.isNotEmpty
                  ? allMoyennes.reduce((a, b) => a > b ? a : b)
                  : null;
              final double? moyenneLaPlusFaible = allMoyennes.isNotEmpty
                  ? allMoyennes.reduce((a, b) => a < b ? a : b)
                  : null;

              // Calcul de la moyenne annuelle (pondérée par matière)
              double? moyenneAnnuelle;
              final allGradesForYear =
                  (await txn.query(
                        'grades',
                        where:
                            'studentId = ? AND className = ? AND academicYear = ?',
                        whereArgs: [studentId, className, academicYear],
                      ))
                      .where(
                        (g) =>
                            (g['type'] == 'Devoir' ||
                                g['type'] == 'Composition') &&
                            g['value'] != null,
                      )
                      .toList();

              if (allGradesForYear.isNotEmpty) {
                final Map<String, List<Map<String, dynamic>>> bySubYear = {};
                for (final g in allGradesForYear) {
                  final subj = (g['subject'] as String?) ?? '';
                  bySubYear.putIfAbsent(subj, () => []).add(g);
                }
                double pts = 0.0;
                double wsum = 0.0;
                bySubYear.forEach((subj, list) {
                  double n = 0.0;
                  double c = 0.0;
                  for (final g in list) {
                    final value = g['value'] is int
                        ? (g['value'] as int).toDouble()
                        : (g['value'] as num? ?? 0.0);
                    final maxValue = g['maxValue'] is int
                        ? (g['maxValue'] as int).toDouble()
                        : (g['maxValue'] as num? ?? 20.0);
                    final coeff = g['coefficient'] is int
                        ? (g['coefficient'] as int).toDouble()
                        : (g['coefficient'] as num? ?? 1.0);
                    if (maxValue > 0 && coeff > 0) {
                      n += ((value / maxValue) * 20) * coeff;
                      c += coeff;
                    }
                  }
                  final double moyM = c > 0 ? (n / c) : 0.0;
                  final double w = subjectWeights[subj] ?? c;
                  if (w > 0) {
                    pts += moyM * w;
                    wsum += w;
                  }
                });
                moyenneAnnuelle = wsum > 0 ? (pts / wsum) : null;
              }

              // Déterminer le mode (Trimestre / Semestre) et calculer les moyennes par période
              final allTermsForStudent = (await txn.query(
                'grades',
                where: 'studentId = ? AND className = ? AND academicYear = ?',
                whereArgs: [studentId, className, academicYear],
              )).map((g) => g['term'] as String).toSet();
              List<String> orderedTerms;
              if (allTermsForStudent.any(
                (t) => t.toLowerCase().contains('semestre'),
              )) {
                orderedTerms = ['Semestre 1', 'Semestre 2'];
              } else {
                orderedTerms = ['Trimestre 1', 'Trimestre 2', 'Trimestre 3'];
              }
              // Restreindre aux termes effectivement utilisés
              orderedTerms = orderedTerms
                  .where((t) => allTermsForStudent.contains(t))
                  .toList();
              final List<double?> moyennesParPeriode = [];
              for (final t in orderedTerms) {
                final termGrades = await txn.query(
                  'grades',
                  where:
                      'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
                  whereArgs: [studentId, className, academicYear, t],
                );
                double sNotes = 0.0;
                double sCoeffs = 0.0;
                for (final g in termGrades) {
                  final value = g['value'] is int
                      ? (g['value'] as int).toDouble()
                      : (g['value'] as num? ?? 0.0);
                  final maxValue = g['maxValue'] is int
                      ? (g['maxValue'] as int).toDouble()
                      : (g['maxValue'] as num? ?? 20.0);
                  final coeff = g['coefficient'] is int
                      ? (g['coefficient'] as int).toDouble()
                      : (g['coefficient'] as num? ?? 1.0);
                  if (maxValue > 0 && coeff > 0) {
                    sNotes += ((value / maxValue) * 20) * coeff;
                    sCoeffs += coeff;
                  }
                }
                moyennesParPeriode.add(sCoeffs > 0 ? sNotes / sCoeffs : null);
              }

              // Mention
              String mention;
              if (moyenneGenerale >= 19) {
                mention = 'EXCELLENT';
              } else if (moyenneGenerale >= 16) {
                mention = 'TRÈS BIEN';
              } else if (moyenneGenerale >= 14) {
                mention = 'BIEN';
              } else if (moyenneGenerale >= 12) {
                mention = 'ASSEZ BIEN';
              } else if (moyenneGenerale >= 10) {
                mention = 'PASSABLE';
              } else {
                mention = 'INSUFFISANT';
              }
              synthese = {
                'studentId': studentId,
                'className': className,
                'academicYear': academicYear,
                'term': term,
                'appreciation_generale': '',
                'decision': '',
                'fait_a': '',
                'le_date': '',
                'moyenne_generale': moyenneGenerale,
                'rang': rang,
                'nb_eleves': nbEleves,
                'mention': mention,
                'moyennes_par_periode': moyennesParPeriode.toString(),
                'all_terms': orderedTerms.toString(),
                'moyenne_generale_classe': moyenneGeneraleDeLaClasse,
                'moyenne_la_plus_forte': moyenneLaPlusForte,
                'moyenne_la_plus_faible': moyenneLaPlusFaible,
                'moyenne_annuelle': moyenneAnnuelle,
                'sanctions': '',
                'recommandations': '',
                'forces': '',
                'points_a_developper': '',
                'attendance_justifiee': 0,
                'attendance_injustifiee': 0,
                'retards': 0,
                'presence_percent': 0.0,
                'conduite': '',
              };
              await txn.insert('report_cards', synthese);
            }
            // Déterminer ex æquo (moyennes pondérées par coeff. matières)
            bool isExAequo = false;
            try {
              final classStudentIds = (await txn.query(
                'students',
                where: 'className = ? AND academicYear = ?',
                whereArgs: [className, academicYear],
              )).map((s) => s['id'] as String).toList();
              final wRows = await txn.rawQuery(
                'SELECT c.name AS subject, cc.coefficient AS coeff FROM class_courses cc JOIN courses c ON c.id = cc.courseId WHERE cc.className = ? AND cc.academicYear = ?',
                [className, academicYear],
              );
              final Map<String, double> subjectWeights = {
                for (final r in wRows)
                  if (r['subject'] != null && r['coeff'] != null)
                    (r['subject'] as String): (r['coeff'] as num).toDouble(),
              };
              final List<double> allMoyennes = [];
              for (final sid in classStudentIds) {
                final sg = await txn.query(
                  'grades',
                  where:
                      'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
                  whereArgs: [sid, className, academicYear, term],
                );
                final Map<String, List<Map<String, Object?>>> bySub = {};
                for (final g in sg) {
                  final subj = (g['subject'] as String?) ?? '';
                  bySub.putIfAbsent(subj, () => []).add(g);
                }
                double pts = 0.0;
                double wsum = 0.0;
                bySub.forEach((subj, list) {
                  double n = 0.0;
                  double c = 0.0;
                  for (final g in list) {
                    final value = g['value'] is int
                        ? (g['value'] as int).toDouble()
                        : (g['value'] as num? ?? 0.0);
                    final maxValue = g['maxValue'] is int
                        ? (g['maxValue'] as int).toDouble()
                        : (g['maxValue'] as num? ?? 20.0);
                    final coeff = g['coefficient'] is int
                        ? (g['coefficient'] as int).toDouble()
                        : (g['coefficient'] as num? ?? 1.0);
                    if (maxValue > 0 && coeff > 0) {
                      n += ((value / maxValue) * 20) * coeff;
                      c += coeff;
                    }
                  }
                  final double moyM = c > 0 ? (n / c) : 0.0;
                  final double w = subjectWeights[subj] ?? c;
                  if (w > 0) {
                    pts += moyM * w;
                    wsum += w;
                  }
                });
                allMoyennes.add(wsum > 0 ? (pts / wsum) : 0.0);
              }
              final double myAvg =
                  (synthese['moyenne_generale'] as num?)?.toDouble() ?? 0.0;
              const double eps = 0.001;
              isExAequo =
                  allMoyennes.where((m) => (m - myAvg).abs() < eps).length > 1;
            } catch (_) {}

            // Snapshots extras
            final sRow = await txn.query(
              'students',
              where: 'id = ?',
              whereArgs: [studentId],
            );
            final st = sRow.isNotEmpty ? sRow.first : <String, Object?>{};
            final siRow = await txn.query(
              'school_info',
              orderBy: 'id DESC',
              limit: 1,
            );
            final si = siRow.isNotEmpty ? siRow.first : <String, Object?>{};

            final reportCardId = await txn.insert('report_cards_archive', {
              'studentId': studentId,
              'className': className,
              'academicYear': academicYear,
              'term': term,
              'appreciation_generale': synthese['appreciation_generale'] ?? '',
              'decision': synthese['decision'] ?? '',
              'recommandations': synthese['recommandations'] ?? '',
              'forces': synthese['forces'] ?? '',
              'points_a_developper': synthese['points_a_developper'] ?? '',
              'fait_a': synthese['fait_a'] ?? '',
              'le_date': synthese['le_date'] ?? '',
              'moyenne_generale': synthese['moyenne_generale'] ?? 0.0,
              'rang': synthese['rang'] ?? 0,
              'exaequo': isExAequo ? 1 : 0,
              'nb_eleves': synthese['nb_eleves'] ?? students.length,
              'mention': synthese['mention'] ?? '',
              'moyennes_par_periode': synthese['moyennes_par_periode'] ?? '[]',
              'all_terms': synthese['all_terms'] ?? '[]',
              'moyenne_generale_classe':
                  synthese['moyenne_generale_classe'] ?? 0.0,
              'moyenne_la_plus_forte': synthese['moyenne_la_plus_forte'] ?? 0.0,
              'moyenne_la_plus_faible':
                  synthese['moyenne_la_plus_faible'] ?? 0.0,
              'moyenne_annuelle': synthese['moyenne_annuelle'] ?? 0.0,
              'sanctions': synthese['sanctions'] ?? '',
              'attendance_justifiee': synthese['attendance_justifiee'] ?? 0,
              'attendance_injustifiee': synthese['attendance_injustifiee'] ?? 0,
              'retards': synthese['retards'] ?? 0,
              'presence_percent': synthese['presence_percent'] ?? 0.0,
              'conduite': synthese['conduite'] ?? '',
              'school_ministry': si['ministry'] ?? '',
              'school_republic': si['republic'] ?? '',
              'school_republic_motto': si['republicMotto'] ?? '',
              'school_education_direction': si['educationDirection'] ?? '',
              'school_inspection': si['inspection'] ?? '',
              'student_dob': st['dateOfBirth'] ?? '',
              'student_status': st['status'] ?? '',
              'student_photo_path': st['photoPath'] ?? '',
            });
            // Archiver les appréciations par matière
            for (final app in subjectAppreciations) {
              await txn.insert('subject_appreciation_archive', {
                'report_card_id': reportCardId,
                'subject': app['subject'],
                'professeur': app['professeur'],
                'appreciation': app['appreciation'],
                'moyenne_classe': app['moyenne_classe'],
                'coefficient': app['coefficient'],
                'academicYear': academicYear,
              });
            }
          }
        }
      }
    });
  }

  Future<void> archiveSingleReportCard({
    required String studentId,
    required String className,
    required String academicYear,
    required String term,
    required List<Grade> grades,
    required Map<String, String> professeurs,
    required Map<String, String> appreciations,
    required Map<String, String> moyennesClasse,
    required Map<String, dynamic> synthese,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Supprimer l'ancienne archive pour ce bulletin spécifique
      final existingArchives = await txn.query(
        'report_cards_archive',
        where:
            'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
        whereArgs: [studentId, className, academicYear, term],
      );

      for (final archive in existingArchives) {
        final reportCardId = archive['id'];
        await txn.delete(
          'subject_appreciation_archive',
          where: 'report_card_id = ?',
          whereArgs: [reportCardId],
        );
      }
      await txn.delete(
        'report_cards_archive',
        where:
            'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
        whereArgs: [studentId, className, academicYear, term],
      );

      // 2. Archiver les notes (sans l'ID pour éviter collisions)
      for (final grade in grades) {
        final map = Map<String, Object?>.from(grade.toMap());
        map.remove('id');
        await txn.insert(
          'grades_archive',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 3. Archiver la synthèse du bulletin + snapshot infos école & élève
      // Charger snapshot élève
      final studentRow = await txn.query(
        'students',
        where: 'id = ?',
        whereArgs: [studentId],
      );
      final stud = studentRow.isNotEmpty
          ? studentRow.first
          : <String, Object?>{};
      // Charger infos école
      final schoolInfoRow = await txn.query(
        'school_info',
        orderBy: 'id DESC',
        limit: 1,
      );
      final sch = schoolInfoRow.isNotEmpty
          ? schoolInfoRow.first
          : <String, Object?>{};

      // Calcul ex æquo basé sur les moyennes pondérées (coeff. matières) de la classe pour cette période
      bool isExAequo = false;
      try {
        final classStudentIds = (await txn.query(
          'students',
          where: 'className = ? AND academicYear = ?',
          whereArgs: [className, academicYear],
        )).map((s) => s['id'] as String).toList();
        // Récupérer les coefficients de matières
        final wRows = await txn.rawQuery(
          'SELECT c.name AS subject, cc.coefficient AS coeff FROM class_courses cc JOIN courses c ON c.id = cc.courseId WHERE cc.className = ? AND cc.academicYear = ?',
          [className, academicYear],
        );
        final Map<String, double> subjectWeights = {
          for (final r in wRows)
            if (r['subject'] != null && r['coeff'] != null)
              (r['subject'] as String): (r['coeff'] as num).toDouble(),
        };
        final List<double> allMoyennes = [];
        for (final sid in classStudentIds) {
          final sg = await txn.query(
            'grades',
            where:
                'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
            whereArgs: [sid, className, academicYear, term],
          );
          final Map<String, List<Map<String, Object?>>> bySub = {};
          for (final g in sg) {
            final subj = (g['subject'] as String?) ?? '';
            bySub.putIfAbsent(subj, () => []).add(g);
          }
          double pts = 0.0;
          double wsum = 0.0;
          bySub.forEach((subj, list) {
            double n = 0.0;
            double c = 0.0;
            for (final g in list) {
              final value = g['value'] is int
                  ? (g['value'] as int).toDouble()
                  : (g['value'] as num? ?? 0.0);
              final maxValue = g['maxValue'] is int
                  ? (g['maxValue'] as int).toDouble()
                  : (g['maxValue'] as num? ?? 20.0);
              final coeff = g['coefficient'] is int
                  ? (g['coefficient'] as int).toDouble()
                  : (g['coefficient'] as num? ?? 1.0);
              if (maxValue > 0 && coeff > 0) {
                n += ((value / maxValue) * 20) * coeff;
                c += coeff;
              }
            }
            final double moyM = c > 0 ? (n / c) : 0.0;
            final double w = subjectWeights[subj] ?? c;
            if (w > 0) {
              pts += moyM * w;
              wsum += w;
            }
          });
          allMoyennes.add(wsum > 0 ? (pts / wsum) : 0.0);
        }
        final double myAvg =
            (synthese['moyenne_generale'] as num?)?.toDouble() ?? 0.0;
        const double eps = 0.001;
        isExAequo =
            allMoyennes.where((m) => (m - myAvg).abs() < eps).length > 1;
      } catch (_) {}

      final reportCardId = await txn.insert('report_cards_archive', {
        'studentId': studentId,
        'className': className,
        'academicYear': academicYear,
        'term': term,
        'appreciation_generale': synthese['appreciation_generale'] ?? '',
        'decision': synthese['decision'] ?? '',
        'recommandations': synthese['recommandations'] ?? '',
        'forces': synthese['forces'] ?? '',
        'points_a_developper': synthese['points_a_developper'] ?? '',
        'fait_a': synthese['fait_a'] ?? '',
        'le_date': synthese['le_date'] ?? '',
        'moyenne_generale': synthese['moyenne_generale'] ?? 0.0,
        'rang': synthese['rang'] ?? 0,
        'exaequo': isExAequo ? 1 : 0,
        'nb_eleves': synthese['nb_eleves'] ?? 0,
        'mention': synthese['mention'] ?? '',
        'moyennes_par_periode': synthese['moyennes_par_periode'] ?? '[]',
        'all_terms': synthese['all_terms'] ?? '[]',
        'moyenne_generale_classe': synthese['moyenne_generale_classe'] ?? 0.0,
        'moyenne_la_plus_forte': synthese['moyenne_la_plus_forte'] ?? 0.0,
        'moyenne_la_plus_faible': synthese['moyenne_la_plus_faible'] ?? 0.0,
        'moyenne_annuelle': synthese['moyenne_annuelle'] ?? 0.0,
        'sanctions': synthese['sanctions'] ?? '',
        'attendance_justifiee': synthese['attendance_justifiee'] ?? 0,
        'attendance_injustifiee': synthese['attendance_injustifiee'] ?? 0,
        'retards': synthese['retards'] ?? 0,
        'presence_percent': synthese['presence_percent'] ?? 0.0,
        'conduite': synthese['conduite'] ?? '',
        // Snapshots supplémentaires
        'school_ministry': sch['ministry'] ?? '',
        'school_republic': sch['republic'] ?? '',
        'school_republic_motto': sch['republicMotto'] ?? '',
        'school_education_direction': sch['educationDirection'] ?? '',
        'school_inspection': sch['inspection'] ?? '',
        'student_dob': stud['dateOfBirth'] ?? '',
        'student_status': stud['status'] ?? '',
        'student_photo_path': stud['photoPath'] ?? '',
      });

      // 4. Archiver les appréciations par matière
      for (final subject in appreciations.keys) {
        await txn.insert('subject_appreciation_archive', {
          'report_card_id': reportCardId,
          'subject': subject,
          'professeur': professeurs[subject] ?? '-',
          'appreciation': appreciations[subject] ?? '-',
          'moyenne_classe': moyennesClasse[subject] ?? '-',
          'coefficient':
              synthese['coefficients'] != null &&
                  (synthese['coefficients'] as Map<String, dynamic>)
                      .containsKey(subject)
              ? (synthese['coefficients'] as Map<String, dynamic>)[subject]
              : null,
          'academicYear': academicYear,
        });
      }
    });
    // Journaliser l'archivage du bulletin
    try {
      await logAudit(
        category: 'report_card',
        action: 'archive_report_card',
        details:
            'student=$studentId class=$className year=$academicYear term=$term',
      );
    } catch (_) {}
  }

  /// Récupère les bulletins archivés pour une classe et une année, groupés par élève
  Future<List<Map<String, dynamic>>> getArchivedReportCardsByClassAndYear({
    required String academicYear,
    required String className,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'report_cards_archive',
      where: 'academicYear = ? AND className = ?',
      whereArgs: [academicYear, className],
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> getAllArchivedReportCards() async {
    final db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'report_cards_archive',
    );
    return rows;
  }

  // ===================== Users (Authentication) =====================
  Future<void> upsertUser(Map<String, dynamic> userData) async {
    final db = await database;
    final String username = (userData['username'] ?? '').toString();
    bool existed = false;
    try {
      final existing = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [username],
        limit: 1,
      );
      existed = existing.isNotEmpty;
    } catch (_) {}
    await db.insert(
      'users',
      userData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'user',
        action: existed ? 'update_user' : 'create_user',
        details: 'username=$username role=${userData['role'] ?? ''}',
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getUserRowByUsername(String username) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> getAllUserRows() async {
    final db = await database;
    return await db.query('users', orderBy: 'username ASC');
  }

  Future<SchoolInfo?> getSchoolInfo() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'school_info',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return SchoolInfo.fromMap(maps.first);
    }
    return null;
  }

  Future<void> insertSchoolInfo(SchoolInfo schoolInfo) async {
    final db = await database;
    // Ensure migration ran (idempotent) so legacy DBs get new columns
    await _ensureSchoolInfoColumns(db);

    // Filter payload to existing columns to avoid "no such column" on legacy DBs
    try {
      final cols = await db.rawQuery('PRAGMA table_info(school_info)');
      final allowed = cols.map((c) => c['name'] as String).toSet();
      final filtered = Map<String, dynamic>.fromEntries(
        schoolInfo.toMap().entries.where((e) => allowed.contains(e.key)),
      );
      await db.insert(
        'school_info',
        filtered,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // As a last resort, try inserting full map (should not happen once migrations apply)
      await db.insert(
        'school_info',
        schoolInfo.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // TimetableEntry operations
  Future<void> insertTimetableEntry(TimetableEntry entry) async {
    final db = await database;
    await db.transaction((txn) async {
      await _ensureClassExists(
        txn,
        entry.className,
        academicYear: entry.academicYear,
      );
      await txn.insert(
        'timetable_entries',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<TimetableEntry>> getTimetableEntries({
    String? className,
    String? academicYear,
    String? teacherName,
  }) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (className != null && className.isNotEmpty) {
      whereClause += 'className = ?';
      whereArgs.add(className);
    }
    if (academicYear != null && academicYear.isNotEmpty) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'academicYear = ?';
      whereArgs.add(academicYear);
    }
    if (teacherName != null && teacherName.isNotEmpty) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'teacher = ?';
      whereArgs.add(teacherName);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'timetable_entries',
      where: whereClause.isNotEmpty ? whereClause : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'dayOfWeek, startTime', // Order by day and time
    );
    return List.generate(maps.length, (i) => TimetableEntry.fromMap(maps[i]));
  }

  Future<void> updateTimetableEntry(TimetableEntry entry) async {
    final db = await database;
    await db.transaction((txn) async {
      await _ensureClassExists(
        txn,
        entry.className,
        academicYear: entry.academicYear,
      );
      await txn.update(
        'timetable_entries',
        entry.toMap(),
        where: 'id = ?',
        whereArgs: [entry.id],
      );
    });
  }

  Future<void> deleteTimetableEntry(int id) async {
    final db = await database;
    await db.delete('timetable_entries', where: 'id = ?', whereArgs: [id]);
  }

  // Delete all timetable entries for a given class and academic year
  Future<void> deleteTimetableForClass(
    String className,
    String academicYear,
  ) async {
    final db = await database;
    await db.delete(
      'timetable_entries',
      where: 'className = ? AND academicYear = ?',
      whereArgs: [className, academicYear],
    );
  }

  // Delete all timetable entries for a given teacher (optionally for a given academic year)
  Future<void> deleteTimetableForTeacher(
    String teacherName, {
    String? academicYear,
  }) async {
    final db = await database;
    if (academicYear == null || academicYear.isEmpty) {
      await db.delete(
        'timetable_entries',
        where: 'teacher = ?',
        whereArgs: [teacherName],
      );
    } else {
      await db.delete(
        'timetable_entries',
        where: 'teacher = ? AND academicYear = ?',
        whereArgs: [teacherName, academicYear],
      );
    }
  }

  // Clear all timetable entries (restore to blank)
  Future<void> clearAllTimetableEntries() async {
    final db = await database;
    await db.delete('timetable_entries');
  }

  Future<List<Map<String, String>>> getTeacherUnavailability(
    String teacherName,
    String academicYear,
  ) async {
    final db = await database;
    final rows = await db.query(
      'teacher_unavailability',
      where: 'teacher = ? AND academicYear = ?',
      whereArgs: [teacherName, academicYear],
    );
    return rows
        .map(
          (r) => {
            'dayOfWeek': (r['dayOfWeek'] ?? '').toString(),
            'startTime': (r['startTime'] ?? '').toString(),
          },
        )
        .toList();
  }

  Future<void> saveTeacherUnavailability({
    required String teacherName,
    required String academicYear,
    required List<Map<String, String>> slots,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'teacher_unavailability',
        where: 'teacher = ? AND academicYear = ?',
        whereArgs: [teacherName, academicYear],
      );
      for (final s in slots) {
        await txn.insert('teacher_unavailability', {
          'teacher': teacherName,
          'academicYear': academicYear,
          'dayOfWeek': s['dayOfWeek'] ?? '',
          'startTime': s['startTime'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> deleteUserByUsername(String username) async {
    final db = await database;
    await db.delete('users', where: 'username = ?', whereArgs: [username]);
    try {
      await logAudit(
        category: 'user',
        action: 'delete_user',
        details: 'username=$username',
      );
    } catch (_) {}
  }

  Future<void> updateUserLastLoginAt(String username) async {
    final db = await database;
    await db.update(
      'users',
      {'lastLoginAt': DateTime.now().toIso8601String()},
      where: 'username = ?',
      whereArgs: [username],
    );
  }

  /// Récupère la synthèse du bulletin pour un élève/classe/année/période
  Future<Map<String, dynamic>?> getReportCard({
    required String studentId,
    required String className,
    required String academicYear,
    required String term,
  }) async {
    final db = await database;
    debugPrint(
      '[DatabaseService] getReportCard(studentId=$studentId, class=$className, year=$academicYear, term=$term)',
    );
    final res = await db.query(
      'report_cards',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, term],
    );
    if (res.isEmpty) {
      debugPrint('[DatabaseService] getReportCard <- not found');
      return null;
    }
    debugPrint('[DatabaseService] getReportCard <- found');
    return res.first;
  }

  /// Récupère la synthèse archivée du bulletin pour un élève/classe/année/période
  Future<Map<String, dynamic>?> getReportCardArchive({
    required String studentId,
    required String className,
    required String academicYear,
    required String term,
  }) async {
    final db = await database;
    final res = await db.query(
      'report_cards_archive',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, term],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return res.first;
  }

  /// Récupère un bulletin "prioritaire" pour un élève/classe/année (fin d'année en priorité),
  /// pour réutiliser la décision/moyenne annuelle lors de la réinscription.
  Future<Map<String, dynamic>?> getPreferredReportCardForStudent({
    required String studentId,
    required String className,
    required String academicYear,
  }) async {
    final db = await database;
    const terms = <String>[
      'Trimestre 3',
      'Semestre 2',
      'Trimestre 2',
      'Semestre 1',
      'Trimestre 1',
    ];
    final placeholders = List.filled(terms.length, '?').join(',');
    final res = await db.rawQuery(
      '''
      SELECT *
      FROM report_cards
      WHERE studentId = ? AND className = ? AND academicYear = ? AND term IN ($placeholders)
      ORDER BY CASE term
        WHEN 'Trimestre 3' THEN 1
        WHEN 'Semestre 2' THEN 2
        WHEN 'Trimestre 2' THEN 3
        WHEN 'Semestre 1' THEN 4
        WHEN 'Trimestre 1' THEN 5
        ELSE 999
      END
      LIMIT 1
    ''',
      [studentId, className, academicYear, ...terms],
    );
    if (res.isEmpty) return null;
    return res.first;
  }

  Future<int> countReportCardsForClassYear({
    required String className,
    required String academicYear,
  }) async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM report_cards WHERE className = ? AND academicYear = ?',
      [className, academicYear],
    );
    final row = res.isNotEmpty ? res.first : const <String, Object?>{};
    return (row['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<int> countReportCardsForAcademicYear(String academicYear) async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM report_cards WHERE academicYear = ?',
      [academicYear],
    );
    final row = res.isNotEmpty ? res.first : const <String, Object?>{};
    return (row['cnt'] as num?)?.toInt() ?? 0;
  }

  /// Insère ou met à jour un bulletin complet (infos synthèse)
  Future<void> insertOrUpdateReportCard({
    required String studentId,
    required String className,
    required String academicYear,
    required String term,
    String? appreciationGenerale,
    String? decision,
    String? faitA,
    String? leDate,
    double? moyenneGenerale,
    int? rang,
    int? nbEleves,
    String? mention,
    String? moyennesParPeriode,
    String? allTerms,
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    double? moyenneAnnuelle,
    String? sanctions,
    String? recommandations,
    String? forces,
    String? pointsADevelopper,
    int? attendanceJustifiee,
    int? attendanceInjustifiee,
    int? retards,
    double? presencePercent,
    String? conduite,
  }) async {
    final db = await database;
    debugPrint(
      '[DatabaseService] insertOrUpdateReportCard -> student=$studentId class=$className year=$academicYear term=$term',
    );
    await _ensureStudentExists(db, studentId);
    await _ensureClassExists(db, className);
    final existing = await db.query(
      'report_cards',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, term],
    );
    final data = {
      'studentId': studentId,
      'className': className,
      'academicYear': academicYear,
      'term': term,
      'appreciation_generale': appreciationGenerale,
      'decision': decision,
      'fait_a': faitA,
      'le_date': leDate,
      'moyenne_generale': moyenneGenerale,
      'rang': rang,
      'nb_eleves': nbEleves,
      'mention': mention,
      'moyennes_par_periode': moyennesParPeriode,
      'all_terms': allTerms,
      'moyenne_generale_classe': moyenneGeneraleDeLaClasse,
      'moyenne_la_plus_forte': moyenneLaPlusForte,
      'moyenne_la_plus_faible': moyenneLaPlusFaible,
      'moyenne_annuelle': moyenneAnnuelle,
      'sanctions': sanctions,
      'recommandations': recommandations,
      'forces': forces,
      'points_a_developper': pointsADevelopper,
      'attendance_justifiee': attendanceJustifiee,
      'attendance_injustifiee': attendanceInjustifiee,
      'retards': retards,
      'presence_percent': presencePercent,
      'conduite': conduite,
    };
    if (existing.isEmpty) {
      await db.insert('report_cards', data);
      debugPrint('[DatabaseService] insertOrUpdateReportCard <- inserted');
    } else {
      await db.update(
        'report_cards',
        data,
        where:
            'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
        whereArgs: [studentId, className, academicYear, term],
      );
      debugPrint('[DatabaseService] insertOrUpdateReportCard <- updated');
    }
  }

  Future<List<Payment>> getRecentPayments(int limit) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      orderBy: 'date DESC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => Payment.fromMap(maps[i]));
  }

  Future<List<Payment>> getRecentCancelledPayments(int limit) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'isCancelled = 1 AND cancelledAt IS NOT NULL',
      orderBy: 'cancelledAt DESC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => Payment.fromMap(maps[i]));
  }

  Future<List<Staff>> getRecentStaff(int limit) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'staff',
      orderBy: 'hireDate DESC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => Staff.fromMap(maps[i]));
  }

  Future<List<Student>> getRecentStudents(int limit) async {
    final db = await database;
    // Assuming students are ordered by their ID or a creation timestamp if available
    // For now, we'll just order by ID as there's no explicit creation date.
    final List<Map<String, dynamic>> maps = await db.query(
      'students',
      orderBy: 'enrollmentDate DESC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => Student.fromMap(maps[i]));
  }

  // For the chart, we need to get monthly enrollment data.
  // This requires a 'createdAt' or 'enrollmentDate' column in the students table.
  // For now, we'll return dummy data or an empty list.
  Future<List<Map<String, dynamic>>> getMonthlyEnrollmentData() async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT strftime('%Y-%m', datetime(enrollmentDate)) as month, COUNT(*) as count
      FROM students
      WHERE enrollmentDate IS NOT NULL AND TRIM(enrollmentDate) <> ''
      GROUP BY month
      HAVING month IS NOT NULL
      ORDER BY month
    ''');
    return result;
  }

  Future<List<Map<String, dynamic>>> getArchivedReportCardsForStudent(
    String studentId,
  ) async {
    final db = await database;
    return await db.query(
      'report_cards_archive',
      where: 'studentId = ?',
      whereArgs: [studentId],
      orderBy: 'academicYear DESC, term DESC',
    );
  }

  // Signature and Cachet operations
  Future<void> insertSignature(Signature signature) async {
    final db = await database;
    await db.insert('signatures', signature.toMap());
  }

  Future<List<Signature>> getAllSignatures() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'signatures',
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => Signature.fromMap(maps[i]));
  }

  Future<List<Signature>> getSignaturesByType(String type) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'signatures',
      where: 'type = ? AND isActive = 1',
      whereArgs: [type],
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => Signature.fromMap(maps[i]));
  }

  Future<Signature?> getSignatureById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'signatures',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Signature.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateSignature(Signature signature) async {
    final db = await database;
    await db.update(
      'signatures',
      signature.toMap(),
      where: 'id = ?',
      whereArgs: [signature.id],
    );
  }

  Future<void> deleteSignature(String id) async {
    final db = await database;
    await db.delete('signatures', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleSignatureStatus(String id, bool isActive) async {
    final db = await database;
    await db.update(
      'signatures',
      {
        'isActive': isActive ? 1 : 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Users: active/deactivate + lockout
  Future<void> setUserActive({
    required String username,
    required bool isActive,
    String? by,
  }) async {
    final db = await database;
    await db.update(
      'users',
      {'isActive': isActive ? 1 : 0},
      where: 'username = ?',
      whereArgs: [username],
    );
    try {
      await logAudit(
        category: 'user',
        action: isActive ? 'activate_user' : 'deactivate_user',
        details: 'username=$username by=${by ?? ''}',
      );
    } catch (_) {}
  }

  Future<void> unlockUser({required String username, String? by}) async {
    final db = await database;
    await db.update(
      'users',
      {'failedLoginCount': 0, 'lockedUntil': null},
      where: 'username = ?',
      whereArgs: [username],
    );
    try {
      await logAudit(
        category: 'user',
        action: 'unlock_user',
        details: 'username=$username by=${by ?? ''}',
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getUserSecurityState(String username) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['failedLoginCount', 'lockedUntil', 'isActive', 'role'],
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> recordFailedLoginAttempt({
    required String username,
    required int lockAfter,
    required Duration lockDuration,
  }) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['failedLoginCount'],
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    final current = (rows.isNotEmpty ? rows.first['failedLoginCount'] : 0);
    final int next = (current is num ? current.toInt() : 0) + 1;

    String? lockedUntil;
    int storedCount = next;
    if (next >= lockAfter) {
      lockedUntil = DateTime.now().add(lockDuration).toIso8601String();
      storedCount = 0;
    }

    await db.update(
      'users',
      {'failedLoginCount': storedCount, 'lockedUntil': lockedUntil},
      where: 'username = ?',
      whereArgs: [username],
    );
    try {
      await logAudit(
        category: 'auth',
        action: lockedUntil == null ? 'login_failed' : 'login_locked',
        details:
            'username=$username failed=$next lockedUntil=${lockedUntil ?? ''}',
        username: username,
        success: false,
      );
    } catch (_) {}
    return next;
  }

  Future<void> resetFailedLoginAttempts(String username) async {
    final db = await database;
    await db.update(
      'users',
      {'failedLoginCount': 0, 'lockedUntil': null},
      where: 'username = ?',
      whereArgs: [username],
    );
  }

  // Permission groups
  Future<List<PermissionGroup>> getPermissionGroups() async {
    final db = await database;
    final maps = await db.query(
      'permission_groups',
      orderBy: 'name COLLATE NOCASE',
    );
    return maps.map(PermissionGroup.fromMap).toList();
  }

  Future<int> upsertPermissionGroup({
    int? id,
    required String name,
    required String permissionsJson,
    String? updatedBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final map = <String, dynamic>{
      if (id != null) 'id': id,
      'name': name,
      'permissionsJson': permissionsJson,
      'createdAt': now,
      'updatedAt': now,
      'updatedBy': updatedBy,
    };
    final insertedId = await db.insert(
      'permission_groups',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await logAudit(
        category: 'user',
        action: 'upsert_permission_group',
        details: 'id=${id ?? insertedId} name=$name by=${updatedBy ?? ''}',
      );
    } catch (_) {}
    return insertedId;
  }

  Future<void> deletePermissionGroup(int id) async {
    final db = await database;
    await db.delete('permission_groups', where: 'id = ?', whereArgs: [id]);
    try {
      await logAudit(
        category: 'user',
        action: 'delete_permission_group',
        details: 'id=$id',
      );
    } catch (_) {}
  }

  // --- Statistics Aggregations ---

  Future<Map<String, dynamic>> getGlobalAcademicStats(
    String academicYear,
  ) async {
    final db = await database;

    // Répartition des moyennes
    final distribution = {
      '<10': 0,
      '10-12': 0,
      '12-14': 0,
      '14-16': 0,
      '>16': 0,
    };

    final reports = await db.query(
      'report_cards',
      where: 'academicYear = ?',
      whereArgs: [academicYear],
    );

    double totalMoyenne = 0;
    int count = 0;
    final Map<String, List<double>> classMoyennes = {};

    for (final r in reports) {
      final moy = r['moyenneGenerale'] as double? ?? 0.0;
      final className = r['className'] as String? ?? 'Inconnue';

      if (moy > 0) {
        totalMoyenne += moy;
        count++;

        classMoyennes.putIfAbsent(className, () => []).add(moy);

        if (moy < 10)
          distribution['<10'] = (distribution['<10'] ?? 0) + 1;
        else if (moy < 12)
          distribution['10-12'] = (distribution['10-12'] ?? 0) + 1;
        else if (moy < 14)
          distribution['12-14'] = (distribution['12-14'] ?? 0) + 1;
        else if (moy < 16)
          distribution['14-16'] = (distribution['14-16'] ?? 0) + 1;
        else
          distribution['>16'] = (distribution['>16'] ?? 0) + 1;
      }
    }

    final classAvgs = <String, double>{};
    classMoyennes.forEach((key, value) {
      final sum = value.reduce((a, b) => a + b);
      classAvgs[key] = sum / value.length;
    });

    return {
      'globalAverage': count > 0 ? totalMoyenne / count : 0.0,
      'distribution': distribution,
      'classAverages': classAvgs,
    };
  }

  Future<Map<String, dynamic>> getDisciplineStats(String academicYear) async {
    final db = await database;

    final absencesByMonth = await db.rawQuery(
      '''
      SELECT strftime('%m', date) as month, COUNT(*) as count 
      FROM attendance_events 
      WHERE academicYear = ? AND type != 'Retard'
      GROUP BY month
    ''',
      [academicYear],
    );

    final sanctionsByClass = await db.rawQuery(
      '''
      SELECT className, COUNT(*) as count 
      FROM sanction_events 
      WHERE academicYear = ?
      GROUP BY className
    ''',
      [academicYear],
    );

    final topAbsentRows = await db.rawQuery(
      '''
      SELECT s.id, s.firstName, s.lastName, s.className, COUNT(*) as count
      FROM attendance_events ae
      JOIN students s ON ae.studentId = s.id
      WHERE ae.academicYear = ? AND ae.type = 'absence'
      GROUP BY s.id
      ORDER BY count DESC
      LIMIT 10
    ''',
      [academicYear],
    );

    return {
      'absencesByMonth': <String, dynamic>{
        for (var e in absencesByMonth)
          (e['month'] ?? '').toString(): e['count'],
      },
      'sanctionsByClass': <String, dynamic>{
        for (var e in sanctionsByClass)
          (e['className'] ?? '').toString(): e['count'],
      },
      'topAbsentStudents': topAbsentRows
          .map(
            (row) => {
              'id': row['id'],
              'name': '${row['lastName']} ${row['firstName']}'.trim(),
              'className': row['className'],
              'count': row['count'],
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> getDemographicStats(String academicYear) async {
    final db = await database;

    final genderStats = await db.rawQuery(
      '''
      SELECT gender, COUNT(*) as count 
      FROM students 
      WHERE academicYear = ? 
      GROUP BY gender
    ''',
      [academicYear],
    );

    final students = await db.query(
      'students',
      columns: ['dateOfBirth'],
      where: 'academicYear = ?',
      whereArgs: [academicYear],
    );

    final ageDistribution = <String, int>{
      '<10': 0,
      '10-14': 0,
      '15-18': 0,
      '>18': 0,
    };

    final now = DateTime.now();
    for (final s in students) {
      final bdStr = s['dateOfBirth'] as String?;
      if (bdStr != null) {
        final bd = DateTime.tryParse(bdStr);
        if (bd != null) {
          final age = now.year - bd.year;
          if (age < 10)
            ageDistribution['<10'] = (ageDistribution['<10'] ?? 0) + 1;
          else if (age <= 14)
            ageDistribution['10-14'] = (ageDistribution['10-14'] ?? 0) + 1;
          else if (age <= 18)
            ageDistribution['15-18'] = (ageDistribution['15-18'] ?? 0) + 1;
          else
            ageDistribution['>18'] = (ageDistribution['>18'] ?? 0) + 1;
        }
      }
    }

    final statusStats = await db.rawQuery(
      '''
      SELECT status, COUNT(*) as count 
      FROM students 
      WHERE academicYear = ? 
      GROUP BY status
    ''',
      [academicYear],
    );

    return {
      'gender': <String, dynamic>{
        for (var e in genderStats) (e['gender'] ?? '').toString(): e['count'],
      },
      'status': <String, dynamic>{
        for (var e in statusStats)
          (e['status'] ?? 'Nouveau').toString(): e['count'],
      },
      'age': ageDistribution,
    };
  }

  Future<Map<String, dynamic>> getFinanceStats(String academicYear) async {
    final db = await database;

    // 1. Revenus mensuels (Payments)
    // On groupe par mois sur la date
    final incomeByMonthRows = await db.rawQuery(
      '''
      SELECT strftime('%m', date) as month, SUM(amount) as total
      FROM payments
      WHERE classAcademicYear = ? AND isCancelled = 0
      GROUP BY month
      ''',
      [academicYear],
    );

    // 2. Dépenses mensuelles (Expenses)
    final expenseByMonthRows = await db.rawQuery(
      '''
      SELECT strftime('%m', date) as month, SUM(amount) as total
      FROM expenses
      WHERE academicYear = ?
      GROUP BY month
      ''',
      [academicYear],
    );

    // 3. Dépenses par catégorie
    final expenseByCategoryRows = await db.rawQuery(
      '''
      SELECT category, SUM(amount) as total
      FROM expenses
      WHERE academicYear = ?
      GROUP BY category
      ''',
      [academicYear],
    );

    // 4. Totaux globaux
    final totalIncomeRow = await db.rawQuery(
      'SELECT SUM(amount) as total FROM payments WHERE classAcademicYear = ? AND isCancelled = 0',
      [academicYear],
    );
    final totalExpenseRow = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses WHERE academicYear = ?',
      [academicYear],
    );

    final totalIncome =
        (totalIncomeRow.first['total'] as num?)?.toDouble() ?? 0.0;
    final totalExpense =
        (totalExpenseRow.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'incomeByMonth': <String, dynamic>{
        for (var e in incomeByMonthRows)
          (e['month'] ?? '').toString(): e['total'],
      },
      'expenseByMonth': <String, dynamic>{
        for (var e in expenseByMonthRows)
          (e['month'] ?? '').toString(): e['total'],
      },
      'expenseByCategory': <String, dynamic>{
        for (var e in expenseByCategoryRows)
          (e['category'] ?? 'Autre').toString(): e['total'],
      },
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'balance': totalIncome - totalExpense,
    };
  }

  Future<Map<String, dynamic>> getAdvancedAcademicStats(
    String academicYear, {
    String? className,
    String? term,
    int limit = 5,
  }) async {
    final db = await database;

    // 1. Build Query with Filters
    final parts = <String>['g.academicYear = ?'];
    final args = <Object>[academicYear];

    if ((className ?? '').trim().isNotEmpty) {
      parts.add('s.className = ?');
      args.add(className!.trim());
    }

    if ((term ?? '').trim().isNotEmpty) {
      parts.add('g.term = ?');
      args.add(term!.trim());
    }

    final whereClause = parts.join(' AND ');

    // 2. Fetch live grades with gender and status
    final gradesRows = await db.rawQuery('''
      SELECT g.value, g.maxValue, g.coefficient, g.subject, g.subjectId, 
             s.id as studentId, s.firstName, s.lastName, s.className, s.gender, s.status
      FROM grades g
      JOIN students s ON g.studentId = s.id
      WHERE $whereClause
    ''', args);

    if (gradesRows.isEmpty) {
      return {
        'globalSuccessRate': 0.0,
        'globalFailureRate': 0.0,
        'topStudents': [],
        'bottomStudents': [],
        'subjectStats': [],
        'genderStats': {},
        'statusStats': {},
      };
    }

    // 3. Compute averages per student
    final studentAverages = <String, Map<String, dynamic>>{};
    // Map<StudentId, {totalPoints, totalCoeff, studentInfo}>

    for (final row in gradesRows) {
      final sId = row['studentId'] as String;
      final val = (row['value'] as num).toDouble();
      final max = (row['maxValue'] as num).toDouble();
      final coeff = (row['coefficient'] as num).toDouble();

      if (max <= 0 || coeff <= 0) continue;

      // Normalize to 20
      final normalizedVal = (val / max) * 20;

      studentAverages.putIfAbsent(
        sId,
        () => {
          'totalPoints': 0.0,
          'totalCoeff': 0.0,
          'firstName': row['firstName'],
          'lastName': row['lastName'],
          'className': row['className'],

          'gender': row['gender'],
          'status': row['status'] ?? 'Nouveau',
        },
      );

      studentAverages[sId]!['totalPoints'] += normalizedVal * coeff;
      studentAverages[sId]!['totalCoeff'] += coeff;
    }

    final studentsList = studentAverages.entries.map((e) {
      final data = e.value;
      final totalPts = data['totalPoints'] as double;
      final totalCoeff = data['totalCoeff'] as double;
      final avg = totalCoeff > 0 ? totalPts / totalCoeff : 0.0;
      return {
        'id': e.key,
        'name': '${data['lastName']} ${data['firstName']}'.trim(),
        'className': data['className'],
        'gender': data['gender'],
        'status': data['status'],
        'average': avg,
      };
    }).toList();

    // 4. Success / Failure Counts
    int totalSuccess = 0;
    int totalFailure = 0;

    // Breakdown maps
    final genderBreakdown = <String, Map<String, int>>{};
    final statusBreakdown = <String, Map<String, int>>{};
    final classBreakdown = <String, Map<String, int>>{};

    // Intersectional tracking: { "key": { success, failure, total, class, gender, status } }
    final intersectional = <String, Map<String, dynamic>>{};

    for (final s in studentsList) {
      final avg = s['average'] as double;
      final success = avg >= 10;
      final gender = (s['gender'] as String? ?? 'M').toUpperCase();
      final status = (s['status'] as String? ?? 'Nouveau');
      final className = (s['className'] as String? ?? 'Inconnue');

      if (success)
        totalSuccess++;
      else
        totalFailure++;

      // Gender tracking
      genderBreakdown.putIfAbsent(
        gender,
        () => {'success': 0, 'failure': 0, 'total': 0},
      );
      genderBreakdown[gender]!['total'] =
          genderBreakdown[gender]!['total']! + 1;
      if (success) {
        genderBreakdown[gender]!['success'] =
            genderBreakdown[gender]!['success']! + 1;
      } else {
        genderBreakdown[gender]!['failure'] =
            genderBreakdown[gender]!['failure']! + 1;
      }

      // Status tracking
      statusBreakdown.putIfAbsent(
        status,
        () => {'success': 0, 'failure': 0, 'total': 0},
      );
      statusBreakdown[status]!['total'] =
          statusBreakdown[status]!['total']! + 1;
      if (success) {
        statusBreakdown[status]!['success'] =
            statusBreakdown[status]!['success']! + 1;
      } else {
        statusBreakdown[status]!['failure'] =
            statusBreakdown[status]!['failure']! + 1;
      }

      // Class tracking
      classBreakdown.putIfAbsent(
        className,
        () => {'success': 0, 'failure': 0, 'total': 0},
      );
      classBreakdown[className]!['total'] =
          classBreakdown[className]!['total']! + 1;
      if (success) {
        classBreakdown[className]!['success'] =
            classBreakdown[className]!['success']! + 1;
      } else {
        classBreakdown[className]!['failure'] =
            classBreakdown[className]!['failure']! + 1;
      }

      // Intersectional tracking: combine class, status, gender
      final comboKey = '${className}_${status}_${gender}';
      intersectional.putIfAbsent(
        comboKey,
        () => {
          'class': className,
          'status': status,
          'gender': gender,
          'success': 0,
          'failure': 0,
          'total': 0,
        },
      );
      intersectional[comboKey]!['total'] =
          intersectional[comboKey]!['total'] + 1;
      if (success) {
        intersectional[comboKey]!['success'] =
            intersectional[comboKey]!['success'] + 1;
      } else {
        intersectional[comboKey]!['failure'] =
            intersectional[comboKey]!['failure'] + 1;
      }
    }

    final globalSuccessRate = studentsList.isNotEmpty
        ? (totalSuccess / studentsList.length) * 100
        : 0.0;
    final globalFailureRate = studentsList.isNotEmpty
        ? (totalFailure / studentsList.length) * 100
        : 0.0;

    // 5. Top & Bottom Students
    studentsList.sort(
      (a, b) => (b['average'] as double).compareTo(a['average'] as double),
    );
    final topStudents = studentsList.take(limit).toList();
    final bottomStudents = studentsList.reversed.take(limit).toList();

    // 6. Subject Performance
    final subjectSums = <String, Map<String, double>>{};
    // Map<SubjectName, {sumAvg, count}>

    for (final row in gradesRows) {
      final subject = (row['subject'] as String?) ?? 'Inconnu';
      final val = (row['value'] as num).toDouble();
      final max = (row['maxValue'] as num).toDouble();

      if (max <= 0) continue;
      final normalizedVal = (val / max) * 20;

      subjectSums.putIfAbsent(subject, () => {'total': 0.0, 'count': 0.0});
      subjectSums[subject]!['total'] =
          (subjectSums[subject]!['total']!) + normalizedVal;
      subjectSums[subject]!['count'] = (subjectSums[subject]!['count']!) + 1;
    }

    final subjectStats = subjectSums.entries.map((e) {
      final total = e.value['total']!;
      final count = e.value['count']!;
      return {
        'subject': e.key,
        'average': count > 0 ? total / count : 0.0,
        'count': count.toInt(),
      };
    }).toList();

    // Sort subjects by difficulty (lowest average first)
    subjectStats.sort(
      (a, b) => (a['average'] as double).compareTo(b['average'] as double),
    );

    // 7. Compute Progression
    double? previousGlobalAverage;
    if ((term ?? '').isNotEmpty) {
      String? prevTerm;
      if (term == 'Trimestre 2')
        prevTerm = 'Trimestre 1';
      else if (term == 'Trimestre 3')
        prevTerm = 'Trimestre 2';
      else if (term == 'Semestre 2')
        prevTerm = 'Semestre 1';

      if (prevTerm != null) {
        final prevStats = await getAdvancedAcademicStats(
          academicYear,
          className: className,
          term: prevTerm,
          limit: limit,
        );
        previousGlobalAverage = prevStats['globalAverage'] as double?;
      }
    }

    return {
      'globalSuccessRate': globalSuccessRate,
      'globalFailureRate': globalFailureRate,
      'globalAverage': studentsList.isNotEmpty
          ? studentsList
                    .map((s) => s['average'] as double)
                    .reduce((a, b) => a + b) /
                studentsList.length
          : 0.0,
      'previousGlobalAverage': previousGlobalAverage,
      'topStudents': topStudents,
      'bottomStudents': bottomStudents,
      'subjectStats': subjectStats,
      'genderStats': genderBreakdown,
      'statusStats': statusBreakdown,
      'classStats': classBreakdown,
      'intersectionalStats': intersectional.values.toList(),
      'totalStudents': studentsList.length,
      'totalSuccess': totalSuccess,
      'totalFailure': totalFailure,
    };
  }

  // User activity logs
  Future<List<Map<String, dynamic>>> getAuditLogsForUser({
    required String username,
    int limit = 300,
  }) async {
    final db = await database;
    final u = username.trim();
    if (u.isEmpty) return const [];
    return db.query(
      'audit_logs',
      where: 'username = ?',
      whereArgs: [u],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  // Sessions
  Future<int> startUserSession({
    required String username,
    String? device,
    String? ip,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('user_sessions', {
      'username': username,
      'loginAt': now,
      'lastSeenAt': now,
      'logoutAt': null,
      'device': device,
      'ip': ip,
    });
    try {
      await logAudit(
        category: 'auth',
        action: 'session_start',
        details: 'sessionId=$id',
        username: username,
      );
    } catch (_) {}
    return id;
  }

  Future<void> touchUserSession(int sessionId) async {
    final db = await database;
    await db.update(
      'user_sessions',
      {'lastSeenAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> endUserSession(int sessionId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'user_sessions',
      {'logoutAt': now, 'lastSeenAt': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<UserSession>> getUserSessions({
    String? username,
    int limit = 200,
    bool onlyActive = false,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (username != null && username.trim().isNotEmpty) {
      where.add('username = ?');
      args.add(username.trim());
    }
    if (onlyActive) {
      where.add('logoutAt IS NULL');
    }
    final maps = await db.query(
      'user_sessions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'loginAt DESC',
      limit: limit,
    );
    return maps.map(UserSession.fromMap).toList();
  }
}
