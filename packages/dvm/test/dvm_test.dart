import 'package:dvm_cli/dvm.dart';
import 'package:test/test.dart';

void main() {
  test('run returns a success exit code', () async {
    expect(await run([]), 0);
  });
}
