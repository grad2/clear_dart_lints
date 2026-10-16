import 'package:flutter/widgets.dart';

class GoodScreen extends StatelessWidget {
  const GoodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return const Text('Block bodies in Flutter builders');
      },
    );
  }
}

String shortLabel() => 'Short arrows are allowed outside builders';
