import 'package:flutter/material.dart';

/// Custom page route with a fade transition for smoother game transitions.
class FadePageRoute<T> extends PageRouteBuilder<T> {
  FadePageRoute({required this.child})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
        );

  final Widget child;
}
