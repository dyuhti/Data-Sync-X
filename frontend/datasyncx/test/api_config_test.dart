import 'package:flutter_test/flutter_test.dart';

import 'package:datasyncx/config/api_config.dart';

void main() {
  test('defaults Android emulator requests to the shared backend port', () {
    expect(ApiConfig.baseUrl, 'http://10.0.2.2:5058');
  });
}
