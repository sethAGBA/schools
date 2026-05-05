import 'dart:convert';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/services/api/api_client.dart';
import 'package:flutter/foundation.dart';

class RemoteStaffService {
  RemoteStaffService._();
  static final RemoteStaffService instance = RemoteStaffService._();

  Future<List<Staff>> fetchStaff({String? role, String? department}) async {
    try {
      final queryParams = <String, String>{};
      if (role != null) queryParams['role'] = role;
      if (department != null) queryParams['department'] = department;
      
      final uri = Uri.parse('/api/staff').replace(queryParameters: queryParams);
      final response = await ApiClient.instance.get(uri.toString());

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => _mapBackendToStaff(json)).toList();
      } else {
        throw Exception('Erreur lors de la récupération du personnel: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('RemoteStaffService.fetchStaff error: $e');
      rethrow;
    }
  }

  Future<bool> bulkUpsert(List<Staff> staffList) async {
    try {
      final response = await ApiClient.instance.post(
        '/api/staff/bulk',
        body: {
          'staff': staffList.map((s) => _mapStaffToBackend(s)).toList(),
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('RemoteStaffService.bulkUpsert error: $e');
      return false;
    }
  }

  Future<bool> deleteStaff(String id) async {
    try {
      final response = await ApiClient.instance.delete('/api/staff/$id');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint('RemoteStaffService.deleteStaff error: $e');
      return false;
    }
  }

  Staff _mapBackendToStaff(Map<String, dynamic> json) {
    return Staff(
      id: json['id'],
      name: json['name'] ?? '',
      role: json['role'] ?? '',
      department: json['department'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      qualifications: json['qualifications'] ?? '',
      courses: (json['courses'] as String?)?.split(',').where((e) => e.isNotEmpty).toList() ?? [],
      classes: (json['classes'] as String?)?.split(',').where((e) => e.isNotEmpty).toList() ?? [],
      status: json['status'] ?? 'Actif',
      hireDate: json['hireDate'] != null ? DateTime.parse(json['hireDate']) : DateTime.now(),
      typeRole: json['typeRole'] ?? 'Administration',
      firstName: json['firstName'],
      lastName: json['lastName'],
      gender: json['gender'],
      birthDate: json['birthDate'] != null ? DateTime.parse(json['birthDate']) : null,
      birthPlace: json['birthPlace'],
      nationality: json['nationality'],
      address: json['address'],
      photoPath: json['photoPath'],
      matricule: json['matricule'],
      idNumber: json['idNumber'],
      socialSecurityNumber: json['socialSecurityNumber'],
      maritalStatus: json['maritalStatus'],
      numberOfChildren: json['numberOfChildren'],
      region: json['region'],
      levels: (json['levels'] as String?)?.split(',').where((e) => e.isNotEmpty).toList() ?? [],
      highestDegree: json['highestDegree'],
      specialty: json['specialty'],
      experienceYears: json['experienceYears'],
      previousInstitution: json['previousInstitution'],
      contractType: json['contractType'],
      baseSalary: json['baseSalary']?.toDouble(),
      weeklyHours: json['weeklyHours'],
      supervisor: json['supervisor'],
      retirementDate: json['retirementDate'] != null ? DateTime.parse(json['retirementDate']) : null,
      documents: (json['documents'] as String?)?.split(',').where((e) => e.isNotEmpty).toList() ?? [],
    );
  }

  Map<String, dynamic> _mapStaffToBackend(Staff s) {
    return {
      'id': s.id,
      'name': s.name,
      'role': s.role,
      'department': s.department,
      'phone': s.phone,
      'email': s.email,
      'qualifications': s.qualifications,
      'courses': s.courses.join(','),
      'classes': s.classes.join(','),
      'status': s.status,
      'hireDate': s.hireDate.toIso8601String(),
      'typeRole': s.typeRole,
      'firstName': s.firstName,
      'lastName': s.lastName,
      'gender': s.gender,
      'birthDate': s.birthDate?.toIso8601String(),
      'birthPlace': s.birthPlace,
      'nationality': s.nationality,
      'address': s.address,
      'photoPath': s.photoPath,
      'matricule': s.matricule,
      'idNumber': s.idNumber,
      'socialSecurityNumber': s.socialSecurityNumber,
      'maritalStatus': s.maritalStatus,
      'numberOfChildren': s.numberOfChildren,
      'region': s.region,
      'levels': s.levels?.join(','),
      'highestDegree': s.highestDegree,
      'specialty': s.specialty,
      'experienceYears': s.experienceYears,
      'previousInstitution': s.previousInstitution,
      'contractType': s.contractType,
      'baseSalary': s.baseSalary,
      'weeklyHours': s.weeklyHours,
      'supervisor': s.supervisor,
      'retirementDate': s.retirementDate?.toIso8601String(),
      'documents': s.documents?.join(','),
    };
  }
}
