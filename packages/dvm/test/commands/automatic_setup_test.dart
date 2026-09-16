import 'package:dvm/dvm.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late CommandHarness h;
  setUp(() {
    h = CommandHarness();
    h.executablePath = '/dvm/bin/dvm';
    h.fileSystem.file(h.executablePath!)
      ..createSync(recursive: true)
      ..writeAsStringSync('compiled dvm');
    h.environment['SHELL'] = '/bin/zsh';
    h.fileSystem.file('/home/dev/.zshrc')
      ..createSync(recursive: true)
      ..writeAsStringSync('# my shell settings\n');
  });

  for (final command in [
    ['install'],
    ['use'],
    ['global'],
    ['use', '--global'],
  ]) {
    for (final cached in [true, false]) {
      test('${command.join(' ')} creates missing shim (cached: $cached)',
          () async {
        if (cached) h.installVersion('3.9.0');
        expect(await h.run([...command, '3.9.0']), 0);
        expect(h.paths.dartShim.readAsStringSync(),
            '#!/bin/sh\nexec "/dvm/bin/dvm" exec dart "\$@"\n');
        expect(h.fileSystem.file('/home/dev/.zshrc').readAsStringSync(),
            '# my shell settings\n');
        expect(h.output, contains('export PATH='));
        expect(h.installer.requests.length, cached ? 0 : 1);
        h.clearOutput();
        expect(await h.run([...command, '3.9.0']), 0);
        expect(h.output, isNot(contains('Wrote /dvm/shims/dart')));
      });
    }
  }

  test('does not overwrite an existing shim', () async {
    h.paths.dartShim
      ..createSync(recursive: true)
      ..writeAsStringSync('custom shim');
    expect(await h.run(['install', '3.9.0']), 0);
    expect(h.paths.dartShim.readAsStringSync(), 'custom shim');
  });

  test('does not write shims when installation fails', () async {
    h.installer.failure = const ConfigException('download failed');
    expect(await h.run(['install', '3.9.0']), 1);
    expect(h.paths.dartShim.existsSync(), isFalse);
  });

  test('does not create a shim pointing to the Dart VM', () async {
    h.executablePath = '/sdk/bin/dart';
    expect(await h.run(['install', '3.9.0']), 0);
    expect(h.paths.dartShim.existsSync(), isFalse);
  });

  test('does not create a startup file when none exists', () async {
    h.fileSystem.file('/home/dev/.zshrc').deleteSync();
    expect(await h.run(['global', '3.9.0']), 0);
    expect(h.paths.dartShim.existsSync(), isTrue);
    expect(h.fileSystem.file('/home/dev/.zshrc').existsSync(), isFalse);
  });
}
