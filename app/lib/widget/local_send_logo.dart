import 'package:flutter/material.dart';
import 'package:localsend_app/gen/assets.gen.dart';

class LocalSendLogo extends StatelessWidget {
  final bool withText;

  const LocalSendLogo({required this.withText});

  @override
  Widget build(BuildContext context) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(42),
      child: Assets.img.logo512.image(width: 160, height: 160),
    );

    if (withText) {
      return Column(
        children: [
          logo,
          const Text(
            'QuickDrop',
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      return logo;
    }
  }
}
