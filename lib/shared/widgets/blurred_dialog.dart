import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// How much the screen behind a popup is blurred and dimmed.
const double _blurSigma = 8;
const double _dimAlpha = 0.35;

/// [showModalBottomSheet] with the screen behind the sheet blurred and dimmed,
/// like the app's other popups. Same parameters (the barrier color is fixed).
Future<T?> showBlurredBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  double? elevation,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _BlurredBottomSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      isScrollControlled: isScrollControlled,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      isDismissible: isDismissible,
      modalBarrierColor: Colors.black.withValues(alpha: _dimAlpha),
      enableDrag: enableDrag,
      useSafeArea: useSafeArea,
    ),
  );
}

class _BlurredBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _BlurredBottomSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.constraints,
    super.modalBarrierColor,
    super.isDismissible,
    super.enableDrag,
    super.useSafeArea,
  });

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    final anim = animation;
    if (anim == null) return barrier;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: AnimatedBuilder(
            animation: anim,
            // ClipRect bounds the blur to this layer instead of letting the
            // GPU sample the whole backdrop on high-res tablet screens.
            builder: (_, _) => ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _blurSigma * anim.value,
                  sigmaY: _blurSigma * anim.value,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        barrier,
      ],
    );
  }
}

/// Opens [builder]'s widget as a dialog over a blurred, dimmed screen, with the
/// card fading and springing in — the look shared by the app's white popups
/// (loading, results, confirmations). Tapping outside closes it when
/// [barrierDismissible] (returning null).
Future<T?> showBlurredDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    useRootNavigator: useRootNavigator,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) {
      final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      return Stack(
        children: [
          // IgnorePointer so taps reach the dialog route's own barrier
          // (which handles barrierDismissible).
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8 * fade.value,
                    sigmaY: 8 * fade.value,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35 * fade.value),
                  ),
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(
                CurvedAnimation(
                  parent: anim,
                  curve: Curves.easeOutBack,
                  reverseCurve: Curves.easeIn,
                ),
              ),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}
