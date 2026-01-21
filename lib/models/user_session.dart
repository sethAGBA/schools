class UserSession {
  final int? id;
  final String username;
  final String loginAt;
  final String lastSeenAt;
  final String? logoutAt;
  final String? device;
  final String? ip;

  const UserSession({
    this.id,
    required this.username,
    required this.loginAt,
    required this.lastSeenAt,
    this.logoutAt,
    this.device,
    this.ip,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'loginAt': loginAt,
      'lastSeenAt': lastSeenAt,
      'logoutAt': logoutAt,
      'device': device,
      'ip': ip,
    };
  }

  factory UserSession.fromMap(Map<String, dynamic> map) {
    return UserSession(
      id: (map['id'] as num?)?.toInt(),
      username: map['username']?.toString() ?? '',
      loginAt: map['loginAt']?.toString() ?? '',
      lastSeenAt: map['lastSeenAt']?.toString() ?? '',
      logoutAt: map['logoutAt']?.toString(),
      device: map['device']?.toString(),
      ip: map['ip']?.toString(),
    );
  }
}

