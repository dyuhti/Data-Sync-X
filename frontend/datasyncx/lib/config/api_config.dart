class ApiConfig {
  const ApiConfig._();

  // Use 10.0.2.2 when running the Android emulator against a host Flask server.
  static const String baseUrl = String.fromEnvironment(
    'DATASYNC_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );
}
