import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivesafe/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('DriveSafeApp launches with splash screen and loads HomeScreen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DriveSafeApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify app title and welcome text are present.
    expect(find.text('DriveSafe AI'), findsWidgets);
    expect(find.text('Drive smarter. Stay focused.'), findsOneWidget);
    expect(find.text('Auto GPS'), findsOneWidget);
    expect(find.text('Simulate'), findsOneWidget);
  });
}
