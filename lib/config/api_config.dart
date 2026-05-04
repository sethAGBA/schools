class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000',
  );

  static const String defaultTenantId = String.fromEnvironment(
    'TENANT_ID',
    defaultValue: 'demo-school',
  );
}
