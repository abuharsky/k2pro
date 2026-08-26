import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/model/gravimetry.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Prefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
  });

  test('граммовый набор свой у каждого режима', () async {
    prefs.runMode = WorkMode.brew;
    prefs.gravimetry = prefs.gravimetry.copyWith(
      stopOnYield: true,
      targetG: 220,
    );

    prefs.runMode = WorkMode.heatAndBrew;
    expect(
      prefs.gravimetry.stopOnYield,
      isFalse,
      reason: 'отсечка включена только в том режиме, где её включали',
    );
    expect(prefs.gravimetry.targetG, 36);

    prefs.gravimetry = prefs.gravimetry.copyWith(targetG: 40);

    prefs.runMode = WorkMode.brew;
    expect(prefs.gravimetry.stopOnYield, isTrue);
    expect(prefs.gravimetry.targetG, 220, reason: 'набор режима не затёрт');
  });

  test('набор прежних версий становится сидом для всех режимов', () async {
    SharedPreferences.setMockInitialValues({
      'gravimetry': const Gravimetry(targetG: 44, stopOnYield: true).encode(),
    });
    prefs = await Prefs.load();

    for (final m in WorkMode.values) {
      expect(prefs.gravimetryFor(m).targetG, 44);
      expect(prefs.gravimetryFor(m).stopOnYield, isTrue);
    }

    prefs.runMode = WorkMode.heat;
    prefs.gravimetry = prefs.gravimetry.copyWith(targetG: 12);
    expect(prefs.gravimetryFor(WorkMode.brew).targetG, 44);
  });
}
