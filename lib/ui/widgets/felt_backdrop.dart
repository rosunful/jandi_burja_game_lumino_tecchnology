import 'package:flutter/material.dart';

/// The felt table surface, stretched rather than tiled, with a vignette that
/// darkens the top and bottom so overlaid text stays readable.
///
/// Shared by the betting and roll screens so the two always look like the same
/// table.
class FeltBackdrop extends StatelessWidget {
  const FeltBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    // Its own layer, and that is the entire point. A full-screen image and
    // gradient in the same layer as the table means every chip placed repaints
    // all of it; isolated once, it is rastered when the screen appears and then
    // left alone.
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/felt/felt.png'),
            fit: BoxFit.cover,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xAA05170F),
              Color(0x3305170F),
              Color(0xCC05170F),
            ],
            stops: <double>[0, 0.45, 1],
          ),
        ),
      ),
    );
  }
}
