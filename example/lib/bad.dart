import 'package:flutter/widgets.dart';

// Expected: one builder diagnostic, with no duplicate length diagnostic.
class BadScreen extends StatelessWidget {
  const BadScreen({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Text(
      'A long build expression still produces only one diagnostic for this arrow function',
    ),
  );
}

// Expected: one diagnostic for each callback (three in total).
Widget badCallbacks() {
  return Builder(
    builder: (context) => ListView.builder(
      itemCount: 1,
      itemBuilder: (context, index) => AnimatedBuilder(
        animation: const AlwaysStoppedAnimation(0),
        builder: (context, child) => const SizedBox(),
      ),
    ),
  );
}

// Expected: length diagnostic. Both forms have the same potential line length.
String longSingleLine() =>
    createLabel('firstArgumentWithAVeryLongName', 'secondArgumentWithAVeryLongName');
String longWrappedCall() =>
    createLabel('firstArgumentWithAVeryLongName', 'secondArgumentWithAVeryLongName');
String createLabel(String first, String second) => '$first $second';
