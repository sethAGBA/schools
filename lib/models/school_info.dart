import 'dart:io';
import 'package:school_manager/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SchoolInfo {
  final String name;
  final String address;
  final String? bp;
  final String director;
  final String? logoPath;
  final String? flagPath; // Photo/drapeau du pays
  final String? telephone;
  final String? email;
  final String? website;
  final String? motto;
  final String? republic; // e.g., "République du Sénégal"
  final String? ministry;
  final String? republicMotto;
  final String? educationDirection;
  final String? inspection;
  final String? paymentsAdminRole; // 'directeur' ou 'proviseur' (pour reçus)
  final String? directorPrimary;
  final String? directorCollege;
  final String? directorLycee;
  final String? directorUniversity;
  final String? civilityPrimary;
  final String? civilityCollege;
  final String? civilityLycee;
  final String? civilityUniversity;

  SchoolInfo({
    required this.name,
    required this.address,
    this.bp,
    required this.director,
    this.logoPath,
    this.flagPath,
    this.telephone,
    this.email,
    this.website,
    this.motto,
    this.republic,
    this.ministry,
    this.republicMotto,
    this.educationDirection,
    this.inspection,
    this.paymentsAdminRole,
    this.directorPrimary,
    this.directorCollege,
    this.directorLycee,
    this.directorUniversity,
    this.civilityPrimary,
    this.civilityCollege,
    this.civilityLycee,
    this.civilityUniversity,
  });

  factory SchoolInfo.fromMap(Map<String, dynamic> map) {
    return SchoolInfo(
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      bp: map['bp'],
      director: map['director'] ?? '',
      logoPath: map['logoPath'],
      flagPath: map['flagPath'],
      telephone: map['telephone'],
      email: map['email'],
      website: map['website'],
      motto: map['motto'],
      republic: map['republic'],
      ministry: map['ministry'],
      republicMotto: map['republicMotto'],
      educationDirection: map['educationDirection'],
      inspection: map['inspection'],
      paymentsAdminRole: map['paymentsAdminRole'],
      directorPrimary: map['directorPrimary'],
      directorCollege: map['directorCollege'],
      directorLycee: map['directorLycee'],
      directorUniversity: map['directorUniversity'],
      civilityPrimary: map['civilityPrimary'],
      civilityCollege: map['civilityCollege'],
      civilityLycee: map['civilityLycee'],
      civilityUniversity: map['civilityUniversity'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'bp': bp,
      'director': director,
      'logoPath': logoPath,
      'flagPath': flagPath,
      'telephone': telephone,
      'email': email,
      'website': website,
      'motto': motto,
      'republic': republic,
      'ministry': ministry,
      'republicMotto': republicMotto,
      'educationDirection': educationDirection,
      'inspection': inspection,
      'paymentsAdminRole': paymentsAdminRole,
      'directorPrimary': directorPrimary,
      'directorCollege': directorCollege,
      'directorLycee': directorLycee,
      'directorUniversity': directorUniversity,
      'civilityPrimary': civilityPrimary,
      'civilityCollege': civilityCollege,
      'civilityLycee': civilityLycee,
      'civilityUniversity': civilityUniversity,
    };
  }
}

Future<SchoolInfo> loadSchoolInfo() async {
  final dbService = DatabaseService();
  SchoolInfo? schoolInfo = await dbService.getSchoolInfo();

  if (schoolInfo == null) {
    // If no info in DB, try to load from SharedPreferences (legacy) and save to DB
    final prefs = await SharedPreferences.getInstance();
    schoolInfo = SchoolInfo(
      name: prefs.getString('school_name') ?? '',
      address: prefs.getString('school_address') ?? '',
      bp: prefs.getString('school_bp'),
      director: prefs.getString('school_director') ?? '',
      directorPrimary: prefs.getString('school_director_primary'),
      directorCollege: prefs.getString('school_director_college'),
      directorLycee: prefs.getString('school_director_lycee'),
      directorUniversity: prefs.getString('school_director_university'),
      civilityPrimary: prefs.getString('school_civility_primary'),
      civilityCollege: prefs.getString('school_civility_college'),
      civilityLycee: prefs.getString('school_civility_lycee'),
      civilityUniversity: prefs.getString('school_civility_university'),
      logoPath: prefs.getString('school_logo'),
      flagPath: prefs.getString('school_flag'),
      telephone: prefs.getString('school_phone'),
      email: prefs.getString('school_email'),
      website: prefs.getString('school_website'),
      motto: prefs.getString('school_motto'),
      republic: prefs.getString('school_republic'),
      ministry: prefs.getString('school_ministry'),
      republicMotto: prefs.getString('school_republic_motto'),
      educationDirection: prefs.getString('school_education_direction'),
      inspection: prefs.getString('school_inspection'),
    );
    // Save to DB for future use
    await dbService.insertSchoolInfo(schoolInfo);
  } else {
    // DB has a row: if logoPath is missing or file doesn't exist, try to recover from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final prefLogo = prefs.getString('school_logo');
    final dbLogo = schoolInfo.logoPath;
    final dbLogoMissing =
        dbLogo == null || dbLogo.trim().isEmpty || !File(dbLogo).existsSync();
    final prefLogoAvailable = prefLogo != null && prefLogo.trim().isNotEmpty;

    if (dbLogoMissing && prefLogoAvailable) {
      final merged = SchoolInfo(
        name: schoolInfo.name,
        address: schoolInfo.address,
        bp: schoolInfo.bp,
        director: schoolInfo.director,
        directorPrimary: schoolInfo.directorPrimary,
        directorCollege: schoolInfo.directorCollege,
        directorLycee: schoolInfo.directorLycee,
        directorUniversity: schoolInfo.directorUniversity,
        civilityPrimary: schoolInfo.civilityPrimary,
        civilityCollege: schoolInfo.civilityCollege,
        civilityLycee: schoolInfo.civilityLycee,
        civilityUniversity: schoolInfo.civilityUniversity,
        logoPath: prefLogo,
        flagPath: schoolInfo.flagPath,
        telephone: schoolInfo.telephone,
        email: schoolInfo.email,
        website: schoolInfo.website,
        motto: schoolInfo.motto,
        republic: schoolInfo.republic,
        ministry: schoolInfo.ministry,
        republicMotto: schoolInfo.republicMotto,
        educationDirection: schoolInfo.educationDirection,
        inspection: schoolInfo.inspection,
      );
      await dbService.insertSchoolInfo(merged);
      schoolInfo = merged;
    }
  }
  print('SchoolInfo loaded: $schoolInfo');
  return schoolInfo;
}
