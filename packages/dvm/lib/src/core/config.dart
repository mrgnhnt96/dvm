import 'dart:convert';

import 'package:file/file.dart';

import 'channel.dart';
import 'exceptions.dart';
import 'paths.dart';

/// The contents of `~/.dvm/config.json`.
///
/// [channels] is not in the file's minimal example but is load-bearing: version
/// resolution must map `stable` to a concrete version without touching the
/// network, so the version a channel resolved to is recorded here at install
/// time and only ever rewritten by `dvm install` / `dvm upgrade`.
class DvmConfig {
  const DvmConfig({
    this.global,
    this.aliases = const {},
    this.channels = const {},
    Map<String, Object?> unknownKeys = const {},
  }) : _unknownKeys = unknownKeys;

  /// The default version when no `.dvmrc` applies. Null when unset.
  final String? global;

  /// User-defined names mapping to a version, a channel, or another alias.
  final Map<String, String> aliases;

  /// Channel token -> the concrete version installed for it.
  final Map<String, String> channels;

  /// Top-level keys this build does not know about, kept so that a newer dvm's
  /// settings survive being rewritten by an older one.
  final Map<String, Object?> _unknownKeys;

  static const DvmConfig empty = DvmConfig();

  /// The concrete version recorded for [channel], or null if none is installed.
  String? versionForChannel(Channel channel) => channels[channel.token];

  DvmConfig copyWith({
    String? global,
    bool clearGlobal = false,
    Map<String, String>? aliases,
    Map<String, String>? channels,
  }) {
    return DvmConfig(
      global: clearGlobal ? null : (global ?? this.global),
      aliases: aliases ?? this.aliases,
      channels: channels ?? this.channels,
      unknownKeys: _unknownKeys,
    );
  }

  Map<String, Object?> toJson() => {
        ..._unknownKeys,
        if (global != null) 'global': global,
        'aliases': aliases,
        if (channels.isNotEmpty) 'channels': channels,
      };
}

/// Reads and writes `~/.dvm/config.json`.
class ConfigStore {
  ConfigStore({required this.fileSystem, required this.paths});

  final FileSystem fileSystem;
  final DvmPaths paths;

  /// The stored config, or [DvmConfig.empty] when the file does not exist.
  ///
  /// A missing config is the normal state on a fresh machine. A *malformed*
  /// one throws — falling back to defaults there would silently ignore the
  /// global version the user believes they set.
  DvmConfig read() {
    final file = paths.configFile;
    if (!file.existsSync()) return DvmConfig.empty;

    final path = file.path;
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return DvmConfig.empty;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw ConfigException(
        '$path is not valid JSON: ${error.message}. '
        'Fix it, or delete it to start over.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw ConfigException(
        '$path must contain a JSON object like '
        '{"global": "3.9.0", "aliases": {}}, but it contains '
        '${_describeJsonType(decoded)}.',
      );
    }

    return DvmConfig(
      global: _readOptionalString(decoded, 'global', path),
      aliases: _readStringMap(decoded, 'aliases', path),
      channels: _readStringMap(decoded, 'channels', path),
      unknownKeys: {
        for (final entry in decoded.entries)
          if (!const {'global', 'aliases', 'channels'}.contains(entry.key))
            entry.key: entry.value,
      },
    );
  }

  /// Writes [config], creating `~/.dvm` if needed.
  void write(DvmConfig config) {
    final file = paths.configFile;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(config.toJson())}\n',
    );
  }

  String? _readOptionalString(
    Map<String, Object?> json,
    String key,
    String path,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw ConfigException(
        '$path: "$key" must be a string, but it is '
        '${_describeJsonType(value)}.',
      );
    }
    return value.trim().isEmpty ? null : value.trim();
  }

  Map<String, String> _readStringMap(
    Map<String, Object?> json,
    String key,
    String path,
  ) {
    final value = json[key];
    if (value == null) return const {};
    if (value is! Map<String, Object?>) {
      throw ConfigException(
        '$path: "$key" must be a JSON object mapping names to versions, but '
        'it is ${_describeJsonType(value)}.',
      );
    }
    final result = <String, String>{};
    for (final entry in value.entries) {
      final entryValue = entry.value;
      if (entryValue is! String) {
        throw ConfigException(
          '$path: "$key"."${entry.key}" must be a version string, but it is '
          '${_describeJsonType(entryValue)}.',
        );
      }
      result[entry.key] = entryValue;
    }
    return result;
  }
}

/// Reads and writes the per-project `.dvmrc`.
class DvmrcStore {
  DvmrcStore({required this.fileSystem});

  final FileSystem fileSystem;

  /// The pin recorded in [file], or null when [file] does not exist.
  ///
  /// Accepts the canonical `{"dart": "3.9.0"}` and, the way `.nvmrc` does, a
  /// bare version on one line. The returned string is the raw pin: it may be a
  /// version, an alias, or a channel, and resolving that is the resolver's job.
  String? read(File file) {
    if (!file.existsSync()) return null;
    return parse(file.readAsStringSync(), file.path);
  }

  /// Always writes the canonical JSON form, whatever was there before.
  void write(File file, String version) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{\n  "dart": "$version"\n}\n');
  }

  /// The nearest `.dvmrc` at or above [from], or null if there is none.
  ///
  /// Walks to the filesystem root. Stops when the parent stops changing, which
  /// is how both `/` and `C:\` terminate.
  File? findNearest(Directory from) {
    var directory = fileSystem.directory(
      fileSystem.path.normalize(from.absolute.path),
    );
    while (true) {
      final candidate = fileSystem.file(
        fileSystem.path.join(directory.path, DvmPaths.dvmrcFileName),
      );
      if (candidate.existsSync()) return candidate;
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  /// Parses `.dvmrc` [contents] that came from [path].
  ///
  /// Every failure names [path] and says what is wrong. A `.dvmrc` with a typo
  /// in it must never quietly behave as if it were absent — that is exactly the
  /// case where the user is running a different SDK than they think.
  String parse(String contents, String path) {
    final trimmed = contents.trim();
    if (trimmed.isEmpty) {
      throw ConfigException(
        '$path is empty. It should contain {"dart": "3.9.0"} or a bare '
        'version on one line.',
      );
    }

    // Anything that opens like JSON is judged as JSON. Otherwise a `.dvmrc`
    // with a missing brace would be read as a "version" called `{"dart":`,
    // and the user would be told their version is not installed instead of
    // that their file is broken.
    if (trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        trimmed.startsWith('"')) {
      return _parseJson(trimmed, path);
    }

    if (trimmed.contains('\n')) {
      throw ConfigException(
        '$path has more than one line but is not JSON. Use '
        '{"dart": "3.9.0"}, or put a single bare version on one line.',
      );
    }
    return _validatePin(trimmed, path);
  }

  String _parseJson(String trimmed, String path) {
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (error) {
      throw ConfigException(
        '$path is not valid JSON: ${error.message}. '
        'Expected {"dart": "3.9.0"} or a bare version on one line.',
      );
    }

    if (decoded is String) return _validatePin(decoded.trim(), path);
    if (decoded is! Map<String, Object?>) {
      throw ConfigException(
        '$path must be {"dart": "3.9.0"} or a bare version on one line, but '
        'it contains ${_describeJsonType(decoded)}.',
      );
    }

    final value = decoded['dart'];
    if (value == null) {
      throw ConfigException(
        '$path has no "dart" key. Expected {"dart": "3.9.0"}.',
      );
    }
    if (value is! String) {
      throw ConfigException(
        '$path: "dart" must be a string, but it is '
        '${_describeJsonType(value)}.',
      );
    }
    return _validatePin(value.trim(), path);
  }

  String _validatePin(String pin, String path) {
    if (pin.isEmpty) {
      throw ConfigException(
        '$path names an empty version. Expected something like '
        '{"dart": "3.9.0"}.',
      );
    }
    if (pin.contains(RegExp(r'\s'))) {
      throw ConfigException(
        '$path names "$pin", which contains whitespace. A version, alias or '
        'channel name is a single word.',
      );
    }
    return pin;
  }
}

String _describeJsonType(Object? value) => switch (value) {
      null => 'null',
      String() => 'a string',
      num() => 'a number',
      bool() => 'a boolean',
      List<Object?>() => 'a list',
      Map<Object?, Object?>() => 'an object',
      _ => 'a ${value.runtimeType}',
    };
