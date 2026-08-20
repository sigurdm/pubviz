import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart' as parse;
import 'package:pubviz/src/colors.dart';
import 'package:pubviz/src/converters.dart';
import 'package:pubviz/src/dependency.dart';
import 'package:pubviz/src/options.dart';
import 'package:pubviz/src/root_builder.dart';
import 'package:pubviz/src/service.dart';
import 'package:pubviz/src/viz_package.dart';
import 'package:pubviz/src/viz_root.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('colors', () {
    test('isOutdatedColor', () {
      expect(isOutdatedColor(null), isFalse);
      expect(isOutdatedColor('pink'), isTrue);
      expect(isOutdatedColor('red'), isTrue);
      expect(isOutdatedColor('BLUE'), isFalse);
    });
  });

  group('converters', () {
    test('FalseNullConverter', () {
      const converter = FalseNullConverter();
      expect(converter.fromJson(null), isFalse);
      expect(converter.fromJson(true), isTrue);
      expect(converter.fromJson(false), isFalse);
      expect(converter.toJson(true), isTrue);
      expect(converter.toJson(false), isNull);
    });

    test('VersionConverter', () {
      const converter = VersionConverter();
      expect(converter.fromJson(null), isNull);
      expect(converter.fromJson('1.0.0'), Version(1, 0, 0));
      expect(converter.toJson(Version(1, 0, 0)), '1.0.0');
      expect(converter.toJson(null), isNull);
    });

    test('VersionConstraintConverter', () {
      const converter = VersionConstraintConverter();
      expect(converter.fromJson('^1.0.0'), VersionConstraint.parse('^1.0.0'));
      expect(converter.fromJson('bad'), VersionConstraint.empty);
      expect(converter.toJson(VersionConstraint.parse('^1.0.0')), '^1.0.0');
    });
  });

  group('Dependency', () {
    test('equality and hashCode', () {
      final d1 = Dependency('a', VersionConstraint.any, false);
      final d2 = Dependency('a', VersionConstraint.parse('^1.0.0'), true);
      final d3 = Dependency('b', VersionConstraint.any, false);

      expect(d1, d2);
      expect(d1.hashCode, d2.hashCode);
      expect(d1, isNot(d3));
    });

    test('compareTo', () {
      final da1 = Dependency('a', VersionConstraint.any, false);
      final da2 = Dependency('a', VersionConstraint.any, true);
      final db1 = Dependency('b', VersionConstraint.any, false);

      expect(da1.compareTo(db1), isNegative);
      expect(db1.compareTo(da1), isPositive);
      expect(da1.compareTo(da2), isNegative);
      expect(da2.compareTo(da1), isPositive);
      expect(da1.compareTo(da1), 0);
    });

    test('toString', () {
      expect(
        Dependency('a', VersionConstraint.parse('^1.0.0'), false).toString(),
        'a ^1.0.0',
      );
      expect(
        Dependency('a', VersionConstraint.parse('^1.0.0'), true).toString(),
        'a(dev) ^1.0.0',
      );
    });

    test('json', () {
      final dep = Dependency('a', VersionConstraint.parse('^1.0.0'), true);
      final json = dep.toJson();
      expect(json['name'], 'a');
      expect(json['versionConstraint'], '^1.0.0');
      expect(json['isDevDependency'], true);

      final dep2 = Dependency.fromJson(json);
      expect(dep2.name, dep.name);
      expect(dep2.versionConstraint, dep.versionConstraint);
      expect(dep2.isDevDependency, dep.isDevDependency);
    });
  });

  group('VizPackage', () {
    test('equality and hashCode', () {
      final p1 = VizPackage('a', Version(1, 0, 0), {}, null);
      final p2 = VizPackage('a', Version(1, 0, 0), {}, null);
      final p3 = VizPackage('b', Version(1, 0, 0), {}, null);

      expect(p1, p2);
      expect(p1.hashCode, p2.hashCode);
      expect(p1, isNot(p3));
    });

    test('compareTo', () {
      final p1 = VizPackage('a', Version(1, 0, 0), {}, null);
      final p2 = VizPackage('b', Version(1, 0, 0), {}, null);

      expect(p1.compareTo(p2), isNegative);
      expect(p2.compareTo(p1), isPositive);
    });

    test('toString', () {
      expect(
        VizPackage('a', Version(1, 0, 0), {}, null).toString(),
        'a @ 1.0.0',
      );
    });

    test('json', () {
      final pkg = VizPackage(
        'a',
        Version(1, 0, 0),
        {Dependency('b', VersionConstraint.any, false)},
        Version(1, 1, 0),
        isPrimary: true,
      );
      final json = pkg.toJson();
      expect(json['name'], 'a');
      expect(json['version'], '1.0.0');
      expect(json['latestVersion'], '1.1.0');
      expect(json['isPrimary'], true);

      // Manually handle the fact that explicitToJson is false
      final fullJson = jsonDecode(jsonEncode(pkg)) as Map<String, dynamic>;
      final pkg2 = VizPackage.fromJson(fullJson);
      expect(pkg2.name, pkg.name);
      expect(pkg2.version, pkg.version);
      expect(pkg2.latestVersion, pkg.latestVersion);
      expect(pkg2.isPrimary, pkg.isPrimary);

      expect(pkg2.dependencies, hasLength(1));
      final dep = pkg2.dependencies.first;
      expect(dep.name, 'b');
      expect(dep.versionConstraint, VersionConstraint.any);
      expect(dep.isDevDependency, isFalse);
    });
  });

  group('VizRoot', () {
    test('json', () {
      final root = VizRoot('a', {
        'a': VizPackage('a', Version(1, 0, 0), {}, null),
      });
      final json = root.toJson();
      expect(json['rootPackageName'], 'a');

      final fullJson = jsonDecode(jsonEncode(root)) as Map<String, dynamic>;
      final root2 = VizRoot.fromJson(fullJson);
      expect(root2.rootPackageName, root.rootPackageName);
      expect(root2.packages.keys, contains('a'));
    });

    test('filter workspace with excludeDev', () {
      final root = VizRoot.assemble('a', {
        'a': VizPackage('a', Version(1, 0, 0), {
          Dependency('b', VersionConstraint.any, false),
          Dependency('c', VersionConstraint.any, true),
        }, null),
        'b': VizPackage('b', Version(1, 0, 0), {
          Dependency('a', VersionConstraint.any, false),
        }, null),
        'c': VizPackage('c', Version(1, 0, 0), {
          Dependency('a', VersionConstraint.any, false),
        }, null),
      });

      final filtered = root.filter(onlyWorkspace: true, excludeDev: true);
      expect(filtered.packages.keys, contains('a'));
      expect(filtered.packages.keys, contains('b'));
      expect(filtered.packages.keys, isNot(contains('c')));
    });

    test('Dependency.getDependencies', () {
      final pubspec = parse.Pubspec.parse('''
name: foo
dependencies:
  bar: ^1.0.0
  baz:
    path: ../baz
dev_dependencies:
  qux: '>=1.0.0 <2.0.0'
''');
      final deps = Dependency.getDependencies(pubspec);
      expect(
        deps.map((d) => d.name).toList(),
        containsAll(['bar', 'baz', 'qux']),
      );

      final bar = deps.firstWhere((d) => d.name == 'bar');
      expect(bar.versionConstraint.toString(), '^1.0.0');
      expect(bar.isDevDependency, isFalse);

      final baz = deps.firstWhere((d) => d.name == 'baz');
      // PathDependency.toString() is "path: ../baz", which is not a valid version constraint.
      expect(baz.versionConstraint, VersionConstraint.empty);
      expect(baz.isDevDependency, isFalse);

      final qux = deps.firstWhere((d) => d.name == 'qux');
      expect(qux.isDevDependency, isTrue);
    });
  });

  group('options', () {
    test('parser getter', () {
      expect(parser, isNotNull);
    });
  });

  group('Service', () {
    test('vizRoot orElse throw StateError', () async {
      await d.dir('simple_pkg', [
        d.file('pubspec.yaml', 'name: a\n'),
        d.dir('.dart_tool', [
          d.file('package_graph.json', '''
{
  "roots": ["a"],
  "packages": [
    {
      "name": "a",
      "version": "1.0.0",
      "dependencies": ["b"]
    },
    {
      "name": "b",
      "version": "1.0.0",
      "dependencies": ["c"]
    }
  ]
}
'''),
          d.file('package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    {"name": "a", "rootUri": "../", "packageUri": "lib/"},
    {"name": "b", "rootUri": "file:///fake/b", "packageUri": "lib/"}
  ]
}
'''),
        ]),
      ]).create();

      final service = _SimpleMockService(d.path('simple_pkg'));
      // 'c' is a dependency of 'b', but 'c' is not in package_graph.json
      expect(
        service.vizRoot(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Could not find an entry for `c`'),
          ),
        ),
      );
    });

    test('vizRoot workspace with outdated', testOn: 'vm', () async {
      await d.dir('fake_pkg', [
        d.file('pubspec.yaml', 'name: a\n'),
        d.dir('member', [d.file('pubspec.yaml', 'name: member\n')]),
        d.dir('.dart_tool', [
          d.file('package_graph.json', '''
{
  "roots": ["a", "member"],
  "packages": [
    {
      "name": "a",
      "version": "1.0.0",
      "dependencies": ["member"]
    },
    {
      "name": "member",
      "version": "1.0.0",
      "dependencies": []
    }
  ]
}
'''),
          d.file('package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    {"name": "a", "rootUri": "../", "packageUri": "lib/"},
    {"name": "member", "rootUri": "../member", "packageUri": "lib/"}
  ]
}
'''),
        ]),
      ]).create();

      final service = _WorkspaceMockService(d.path('fake_pkg'));
      final root = await service.vizRoot(
        includeWorkspace: true,
        flagOutdated: true,
      );
      expect(root.packages['member']!.latestVersion, Version(1, 1, 0));
    });
  });
}

final class _WorkspaceMockService extends Service {
  @override
  final String rootPackageDir;

  _WorkspaceMockService(this.rootPackageDir);

  @override
  Map<String, dynamic> outdated() => {
    'packages': [
      {
        'package': 'member',
        'current': {'version': '1.0.0'},
        'latest': {'version': '1.1.0'},
      },
    ],
  };
}

final class _SimpleMockService extends Service {
  @override
  final String rootPackageDir;

  _SimpleMockService(this.rootPackageDir);

  @override
  Map<String, dynamic> outdated() => {'packages': <void>[]};
}
