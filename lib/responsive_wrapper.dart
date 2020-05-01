import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A wrapper that helps child widgets resize/scale
/// to different screen dimensions.
///
/// This class automatically resizes/scales child widgets
/// on [ResponsiveBreakpoint]s. Computed [MediaQueryData]
/// and [ResponsiveWrapperData] with correct
/// dimensions are passed to child widgets.
///
/// The default Flutter behavior for layout changes
/// is resizing. To easily adapt to a wide variety of
/// screen sizes, [ResponsiveWrapper] can proportionally scale
/// a layout. This eliminates the need to manually adapt
/// layouts to [MOBILE], [TABLET], and [DESKTOP].
///
/// To understand the difference between resizing
/// and scaling, take the following example.
/// An [AppBar] looks correct on a phone. When
/// viewed on a desktop however, the AppBar is
/// too short and the title looks too small. This is
/// because Flutter does not scale widgets by default.
/// Here is what happens with each behavior:
/// 1. Resizing (default) - the AppBar's width is
/// double.infinity so it stretches to fill the available
/// width. The [kToolbarHeight] is fixed and stays 56dp.
/// 2. Scaling - the AppBar's width stretches to fill
/// the available width. The height scales proportionally
/// using an aspect ratio automatically calculated
/// from the nearest [ResponsiveBreakpoint]. As the
/// width increases, the height increases proportionally.
///
/// An arbitrary number of breakpoints can be set.
/// Resizing/scaling behavior can be mixed and
/// matched as below.
/// 1400+: scale on extra large 4K displays so
/// text is still legible and widgets are not spaced
/// too far apart.
/// 1400-800: resize on desktops to use available space.
/// 800-600: scale on tablets to avoid elements
/// appearing too small.
/// 600-350: resize on phones for native widget sizes.
/// below 350: resize on small screens to avoid
/// cramp and overflow errors.
class ResponsiveWrapper extends StatefulWidget {
  final Widget child;
  final List<ResponsiveBreakpoint> breakpoints;
  final double minWidth;
  final double maxWidth;
  final String defaultName;
  final bool defaultScale;
  final double defaultScaleFactor;
  final Widget background;
  final MediaQueryData mediaQueryData;
  final bool shrinkWrap;
  final bool debugLog;

  /// A wrapper widget that makes child widgets responsive.
  const ResponsiveWrapper({
    Key key,
    @required this.child,
    this.breakpoints,
    this.minWidth = 450,
    this.maxWidth,
    this.defaultName,
    this.defaultScale = false,
    this.defaultScaleFactor = 1,
    this.background,
    this.mediaQueryData,
    this.shrinkWrap = true,
    this.debugLog = false,
  })  : assert(minWidth != null),
        assert(defaultScale != null),
        assert(defaultScaleFactor != null),
        super(key: key);

  @override
  _ResponsiveWrapperState createState() => _ResponsiveWrapperState();

  static Widget builder(
    Widget child, {
    List<ResponsiveBreakpoint> breakpoints,
    double minWidth = 450,
    double maxWidth,
    String defaultName,
    bool defaultScale = false,
    double defaultScaleFactor = 1,
    Widget background,
    MediaQueryData mediaQueryData,
    bool debugLog = false,
  }) {
    return ResponsiveWrapper(
      child: child,
      breakpoints: breakpoints,
      minWidth: minWidth,
      maxWidth: maxWidth,
      defaultName: defaultName,
      defaultScale: defaultScale,
      defaultScaleFactor: defaultScaleFactor,
      background: background,
      mediaQueryData: mediaQueryData,
      shrinkWrap: false,
      debugLog: debugLog,
    );
  }

  static ResponsiveWrapperData of(BuildContext context, {bool nullOk = false}) {
    assert(context != null);
    assert(nullOk != null);
    final InheritedResponsiveWrapper data = context
        .dependOnInheritedWidgetOfExactType<InheritedResponsiveWrapper>();
    if (data != null) return data.data;
    if (nullOk) return null;
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary(
          'ResponsiveWrapper.of() called with a context that does not contain a ResponsiveWrapper.'),
      ErrorDescription(
          'No Responsive ancestor could be found starting from the context that was passed '
          'to ResponsiveWrapper.of(). Place a ResponsiveWrapper at the root of the app '
          'or supply a ResponsiveWrapper.builder.'),
      context.describeElement('The context used was')
    ]);
  }
}

class _ResponsiveWrapperState extends State<ResponsiveWrapper>
    with WidgetsBindingObserver {
  double devicePixelRatio = 1;
  double getDevicePixelRatio() {
    return widget.mediaQueryData?.devicePixelRatio ??
        MediaQuery.of(context).devicePixelRatio;
  }

  double windowWidth = 0;
  double getWindowWidth() {
    return widget.mediaQueryData?.size?.width ??
        MediaQuery.of(context).size.width;
  }

  double windowHeight = 0;
  double getWindowHeight() {
    return widget.mediaQueryData?.size?.height ??
        MediaQuery.of(context).size.height;
  }

  List<ResponsiveBreakpoint> breakpoints;
  List<_ResponsiveBreakpointSegment> breakpointSegments;

  /// Get screen width calculation.
  double screenWidth = 0;
  double getScreenWidth() {
    // Special 0 width condition.
    activeBreakpointSegment = getActiveBreakpointSegment(windowWidth);
    if (activeBreakpointSegment.responsiveBreakpoint.breakpoint == 0) return 0;
    // Check if screenWidth exceeds maxWidth.
    if (widget.maxWidth != null && windowWidth > widget.maxWidth) {
      // Check if there is an active breakpoint with autoScale set to true.
      if (activeBreakpointSegment.breakpoint >= widget.maxWidth &&
          activeBreakpointSegment.responsiveBreakpoint.isAutoScale) {
        return widget.maxWidth +
            (windowWidth -
                activeBreakpointSegment.responsiveBreakpoint.breakpoint);
      } else {
        // Max Width reached. Return Max Width because no breakpoint is active.
        return widget.maxWidth;
      }
    }

    return windowWidth;
  }

  /// Get screen height calculations.
  double screenHeight = 0;
  double getScreenHeight() {
    // Special 0 height condition.
    if (activeBreakpointSegment.responsiveBreakpoint.breakpoint == 0) return 0;
    // Check if screenWidth exceeds maxWidth.
    if (widget.maxWidth != null) if (windowWidth > widget.maxWidth) {
      // Check if there is an active breakpoint with autoScale set to true.
      if (activeBreakpointSegment.breakpoint > widget.maxWidth &&
          activeBreakpointSegment.responsiveBreakpoint.isAutoScale) {
        // Scale screen height by the amount the width was scaled.
        return windowHeight / (screenWidth / widget.maxWidth);
      }
    }

    // Return default window height as height.
    return windowHeight;
  }

  _ResponsiveBreakpointSegment activeBreakpointSegment;

  /// Simulated content width calculations.
  ///
  /// The [scaledWidth] is computed with the
  /// following algorithm:
  /// 1. Find the active breakpoint and resize using
  /// that breakpoint's logic.
  /// 2. If no breakpoint is found, check if the [screenWidth]
  /// is smaller than the smallest breakpoint. If so,
  /// follow [widget.defaultScale] behavior to resize.
  /// 3. There are no breakpoints set. Resize using
  /// [widget.defaultScale] behavior and [widget.minWidth].
  double scaledWidth = 0;
  double getScaledWidth() {
    // If widget should resize, use screenWidth.
    if (activeBreakpointSegment.responsiveBreakpoint.isResize)
      return screenWidth /
          activeBreakpointSegment.responsiveBreakpoint.scaleFactor;

    // Screen is larger than max width. Scale from max width.
    if (widget.maxWidth != null) if (activeBreakpointSegment.breakpoint >
        widget.maxWidth)
      return widget.maxWidth /
          activeBreakpointSegment.responsiveBreakpoint.scaleFactor;

    // Return width from breakpoint with scale factor applied.
    return activeBreakpointSegment.responsiveBreakpoint.breakpoint /
        activeBreakpointSegment.responsiveBreakpoint.scaleFactor;
  }

  /// Simulated content height calculations.
  ///
  /// The [scaledHeight] is dependent upon the
  /// [screenWidth] and [breakpoints].
  /// If the widget is scaled, the height is computed
  /// to preserve the scaled aspect ratio.
  /// The [scaledHeight] is computed with the
  /// following algorithm:
  /// 1. Find the active breakpoint. If the widget should
  /// resize, nothing more needs to be done.
  /// 2. If the widget should scale, calculate the screen
  /// aspect ratio and return the proportional height.
  /// 3. If there are no active breakpoints and [widget.defaultScale]
  /// is resize, nothing more needs to be done.
  /// 4. Return calculated proportional height with
  /// [widget.minWidth].
  double scaledHeight = 0;
  double getScaledHeight() {
    // If widget should resize, use screenHeight.
    if (activeBreakpointSegment.responsiveBreakpoint.isResize)
      return screenHeight /
          activeBreakpointSegment.responsiveBreakpoint.scaleFactor;

    // Screen is larger than max width. Calculate height
    // from max width.
    if (widget.maxWidth != null) if (activeBreakpointSegment.breakpoint >
        widget.maxWidth) {
      return screenHeight /
          activeBreakpointSegment.responsiveBreakpoint.scaleFactor;
    }

    // Find width adjustment scale to proportionally scale height.
    // If screenWidth is scaled 1.5x larger than the breakpoint,
    // decrease screenHeight by 33.33% to proportionally scale content.
    double widthScale =
        screenWidth / activeBreakpointSegment.responsiveBreakpoint.breakpoint;
    // Scale height with width scale and scale factor applied.
    return screenHeight /
        widthScale /
        activeBreakpointSegment.responsiveBreakpoint.scaleFactor;
  }

  double get activeScaleFactor =>
      activeBreakpointSegment.responsiveBreakpoint.scaleFactor;

  /// Fullscreen is enabled if maxWidth is not set.
  /// Default fullscreen enabled.
  get fullscreen => widget.maxWidth == null;

  /// Calculate updated dimensions.
  void setDimensions() {
    devicePixelRatio = getDevicePixelRatio();
    windowWidth = getWindowWidth();
    windowHeight = getWindowHeight();
    screenWidth = getScreenWidth();
    screenHeight = getScreenHeight();
    scaledWidth = getScaledWidth();
    scaledHeight = getScaledHeight();
  }

  /// Set [activeBreakpointSegment].
  /// Active breakpoint segment is the first breakpoint segment
  /// smaller or equal to the [windowWidth].
  _ResponsiveBreakpointSegment getActiveBreakpointSegment(double windowWidth) {
    _ResponsiveBreakpointSegment activeBreakpointSegment =
        breakpointSegments.reversed.firstWhere(
            (element) => windowWidth >= element.breakpoint && !element.isTag);
    return activeBreakpointSegment;
  }

  @override
  void initState() {
    super.initState();
    breakpoints = widget.breakpoints ?? [];
    ResponsiveBreakpoint defaultBreakpoint = ResponsiveBreakpoint._(
        breakpoint: widget.minWidth,
        name: widget.defaultName,
        behavior: widget.defaultScale
            ? _ResponsiveBreakpointBehavior.AUTOSCALE
            : _ResponsiveBreakpointBehavior.RESIZE,
        scaleFactor: widget.defaultScaleFactor);
    breakpointSegments = getBreakpointSegments(breakpoints, defaultBreakpoint);

    // Log breakpoints to console.
    if (widget.debugLog) printDebugLogBreakpoints(breakpointSegments);

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setDimensions();
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // When physical dimensions change, update state.
    // The required MediaQueryData is only available
    // on the next frame for physical dimension changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setDimensions();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(ResponsiveWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When [ResponsiveWrapper]'s constructor is
    // used directly in the widget tree and a parent
    // MediaQueryData changes, update state.
    // The screen dimensions are passed immediately.
    setDimensions();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return (screenWidth ==
            0) // Initialization check. Window measurements not available until postFrameCallback.
        ? SizedBox.shrink()
        : InheritedResponsiveWrapper(
            data: ResponsiveWrapperData.fromResponsiveWrapper(this),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                widget.background ?? Container(),
                MediaQuery(
                  data: calculateMediaQueryData(),
                  child: SizedBox(
                    width: screenWidth,
                    child: FittedBox(
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: scaledWidth,
                        height: (widget.shrinkWrap == true &&
                                widget.mediaQueryData == null)
                            ? null
                            : scaledHeight,
                        // Shrink wrap height if no MediaQueryData is passed.
                        alignment: Alignment.center,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
  }

  /// Return updated [MediaQueryData] values.
  ///
  /// If [widget.mediaQueryData] exists, update
  /// existing values. Else, find [mediaQueryData]
  /// ancestor in the widget tree and update.
  MediaQueryData calculateMediaQueryData() {
    // Update passed in MediaQueryData.
    if (widget.mediaQueryData != null) {
      return widget.mediaQueryData.copyWith(
          size: Size(scaledWidth, scaledHeight),
          devicePixelRatio: devicePixelRatio * activeScaleFactor);
    }

    return MediaQuery.of(context).copyWith(
        size: Size(scaledWidth, scaledHeight),
        devicePixelRatio: devicePixelRatio * activeScaleFactor);
  }

  List<_ResponsiveBreakpointSegment> getBreakpointSegments(
      List<ResponsiveBreakpoint> breakpoints,
      ResponsiveBreakpoint defaultBreakpoint) {
    List<_ResponsiveBreakpointSegment> breakpointSegments = [];
    // No breakpoints. Create segment from default breakpoint behavior.
    if (breakpoints.length == 0) {
      breakpointSegments.add(_ResponsiveBreakpointSegment(
          breakpoint: 0,
          responsiveBreakpointBehavior: defaultBreakpoint.behavior,
          responsiveBreakpoint: defaultBreakpoint));
      return breakpointSegments;
    }
    // Order breakpoints from smallest to largest.
    // Perform ordering operation to allow breakpoints
    // to be accepted in any order.
    breakpoints.sort((a, b) {
      // If breakpoints are equal, return autoScaleDown
      // breakpoints first.
      if (a.breakpoint == b.breakpoint && a.isAutoScaleDown) {
        if (a.isAutoScaleDown) {
          return -1;
        }

        return 0;
      }

      return a.breakpoint.compareTo(b.breakpoint);
    });

    ResponsiveBreakpoint initialBreakpoint =
        breakpoints.firstWhere((element) => !element.isTag, orElse: null);
    ResponsiveBreakpoint breakpointHolder;
    // Construct breakpoint segments for initial and minWidth special cases.
    if (initialBreakpoint == null ||
        (initialBreakpoint.breakpoint > widget.minWidth &&
            !initialBreakpoint.isAutoScaleDown)) {
      // Construct two segments. 1. From 0 to the minWidth. 2. From minWidth to the next breakpoint.
      breakpointHolder = ResponsiveBreakpoint._(
          breakpoint: widget.minWidth,
          name: defaultBreakpoint.name,
          behavior: defaultBreakpoint.behavior,
          scaleFactor: defaultBreakpoint.scaleFactor);
      breakpointSegments.insert(
          0,
          _ResponsiveBreakpointSegment(
              breakpoint: 0,
              responsiveBreakpointBehavior: breakpointHolder.behavior,
              responsiveBreakpoint: breakpointHolder));
      breakpointHolder = ResponsiveBreakpoint._(
          breakpoint: widget.minWidth,
          name: defaultBreakpoint.name,
          behavior: defaultBreakpoint.behavior,
          scaleFactor: defaultBreakpoint.scaleFactor);
      breakpointSegments.insert(
          1,
          _ResponsiveBreakpointSegment(
              breakpoint: widget.minWidth,
              responsiveBreakpointBehavior: breakpointHolder.behavior,
              responsiveBreakpoint: breakpointHolder));
    } else {
      // Construct initial segment that starts from 0.
      breakpointHolder = ResponsiveBreakpoint._(
          breakpoint: initialBreakpoint.breakpoint,
          name: defaultBreakpoint.name,
          // Special condition: return autoScale if initial
          // breakpoint is autoScaleDown.
          behavior: (initialBreakpoint.isAutoScaleDown)
              ? _ResponsiveBreakpointBehavior.AUTOSCALE
              : defaultBreakpoint.behavior,
          scaleFactor: defaultBreakpoint.scaleFactor);
      breakpointSegments.insert(
          0,
          _ResponsiveBreakpointSegment(
              breakpoint: 0,
              responsiveBreakpointBehavior: breakpointHolder.behavior,
              responsiveBreakpoint: breakpointHolder));
    }

    // Convert breakpoints into internal breakpoint segments.
    for (int i = 0; i < breakpoints.length; i++) {
      // Convenience variable.
      ResponsiveBreakpoint breakpoint = breakpoints[i];
      // Segment calculation holder.
      _ResponsiveBreakpointSegment breakpointSegmentHolder;
      switch (breakpoint.behavior) {
        case _ResponsiveBreakpointBehavior.RESIZE:
        case _ResponsiveBreakpointBehavior.AUTOSCALE:
          breakpointSegmentHolder = _ResponsiveBreakpointSegment(
              breakpoint: breakpoint.breakpoint,
              responsiveBreakpointBehavior: breakpoint.behavior,
              responsiveBreakpoint: breakpoint);
          // Update holder with active breakpoint
          breakpointHolder = breakpoint;
          break;
        case _ResponsiveBreakpointBehavior.AUTOSCALEDOWN:
          if (breakpointHolder.isAutoScaleDown) {
            breakpointSegmentHolder = _ResponsiveBreakpointSegment(
                breakpoint: breakpointHolder.breakpoint,
                responsiveBreakpointBehavior: breakpoint.behavior,
                responsiveBreakpoint: ResponsiveBreakpoint._(
                    breakpoint: breakpoint.breakpoint,
                    name: breakpoint.name,
                    behavior: _ResponsiveBreakpointBehavior.AUTOSCALE,
                    scaleFactor: breakpoint.scaleFactor));
          } else {
            // Split AutoScale behavior between autoScale and autoScaleDown.
            if (breakpointHolder.isAutoScale) {
              // Construct midway breakpoint segment.
              _ResponsiveBreakpointSegment midwayBreakpointSegment =
                  _ResponsiveBreakpointSegment(
                      breakpoint: (breakpoint.breakpoint -
                                  breakpointHolder.breakpoint) /
                              2 +
                          breakpointHolder.breakpoint,
                      responsiveBreakpointBehavior:
                          _ResponsiveBreakpointBehavior.AUTOSCALEDOWN,
                      responsiveBreakpoint: ResponsiveBreakpoint._(
                          breakpoint: breakpoint.breakpoint,
                          name: breakpointHolder.name,
                          behavior: _ResponsiveBreakpointBehavior.AUTOSCALE,
                          scaleFactor: breakpoint.scaleFactor));
              breakpointSegments.add(midwayBreakpointSegment);
            }
            // AutoScaleDown overrides resize behavior.
            if (breakpointHolder.isResize) {
              // Construct override breakpoint segment.
              int overrideBreakpointIndex = breakpointSegments.lastIndexWhere(
                  (element) =>
                      element.breakpoint == breakpointHolder.breakpoint &&
                      element.isResize);
              _ResponsiveBreakpointSegment overrideBreakpointSegment =
                  breakpointSegments[overrideBreakpointIndex];
              overrideBreakpointSegment = overrideBreakpointSegment.copyWith(
                  responsiveBreakpoint:
                      overrideBreakpointSegment.responsiveBreakpoint.copyWith(
                          breakpoint: breakpoint.breakpoint,
                          behavior: _ResponsiveBreakpointBehavior.AUTOSCALE));
              breakpointSegments[overrideBreakpointIndex] =
                  overrideBreakpointSegment;
              // Remap all tags with override behavior.
              breakpointSegments = breakpointSegments.map((element) {
                if (element.breakpoint >= breakpointHolder.breakpoint &&
                    element.isTag) {
                  return element.copyWith(
                      responsiveBreakpointBehavior:
                          _ResponsiveBreakpointBehavior.AUTOSCALE,
                      responsiveBreakpoint: element.responsiveBreakpoint
                          .copyWith(
                              breakpoint: breakpoint.breakpoint,
                              behavior:
                                  _ResponsiveBreakpointBehavior.AUTOSCALE));
                }
                return element;
              }).toList();
            }
            // Construct autoScaleDown breakpoint.
            breakpointSegmentHolder = _ResponsiveBreakpointSegment(
                breakpoint: breakpoint.breakpoint,
                responsiveBreakpointBehavior: breakpoint.behavior,
                responsiveBreakpoint: ResponsiveBreakpoint._(
                    breakpoint: breakpoint.breakpoint,
                    name: breakpoint.name,
                    behavior: _ResponsiveBreakpointBehavior.AUTOSCALE,
                    scaleFactor: breakpoint.scaleFactor));
          }
          // Update holder with active breakpoint
          breakpointHolder = breakpoint;
          break;
        case _ResponsiveBreakpointBehavior.TAG:
          breakpointHolder = breakpointHolder.copyWith(name: breakpoint.name);
          breakpointSegmentHolder = _ResponsiveBreakpointSegment(
            breakpoint: breakpoint.breakpoint,
            // Tag inherits behavior from previous breakpoint.
            responsiveBreakpointBehavior: breakpoint.behavior,
            responsiveBreakpoint: breakpointHolder,
          );
          break;
      }
      breakpointSegments.add(breakpointSegmentHolder);
    }

    return breakpointSegments;
  }

  String printDebugLogBreakpoints(
      List<_ResponsiveBreakpointSegment> breakpointSegments) {
    print("Breakpoints: $breakpointSegments");
    return breakpointSegments.toString();
  }
}

// Device Type Constants.
const String MOBILE = 'MOBILE';
const String TABLET = 'TABLET';
const String PHONE = 'PHONE';
const String DESKTOP = 'DESKTOP';

/// Responsive data about the current screen.
///
/// Resized and scaled values can be accessed
/// such as [ResponsiveWrapperData.scaledWidth].
@immutable
class ResponsiveWrapperData {
  final double screenWidth;
  final double screenHeight;
  final double scaledWidth;
  final double scaledHeight;
  final List<ResponsiveBreakpoint> breakpoints;
  final List<_ResponsiveBreakpointSegment> breakpointSegments;
  final ResponsiveBreakpoint activeBreakpoint;
  final bool isMobile;
  final bool isPhone;
  final bool isTablet;
  final bool isDesktop;

  /// Creates responsive data with explicit values.
  ///
  /// Consider using [ResponsiveWrapperData.fromResponsiveWrapper]
  /// to create data based on the [ResponsiveWrapper] state.
  const ResponsiveWrapperData({
    this.screenWidth,
    this.screenHeight,
    this.scaledWidth,
    this.scaledHeight,
    this.breakpoints,
    this.breakpointSegments,
    this.activeBreakpoint,
    this.isMobile,
    this.isPhone,
    this.isTablet,
    this.isDesktop,
  });

  /// Creates data based on the [ResponsiveWrapper] state.
  static ResponsiveWrapperData fromResponsiveWrapper(
      _ResponsiveWrapperState state) {
    return ResponsiveWrapperData(
      screenWidth: state.screenWidth,
      screenHeight: state.screenHeight,
      scaledWidth: state.scaledWidth,
      scaledHeight: state.scaledHeight,
      breakpoints: state.breakpoints,
      breakpointSegments: state.breakpointSegments,
      activeBreakpoint: state.activeBreakpointSegment.responsiveBreakpoint,
      isMobile:
          state.activeBreakpointSegment.responsiveBreakpoint.name == MOBILE,
      isPhone: state.activeBreakpointSegment.responsiveBreakpoint.name == PHONE,
      isTablet:
          state.activeBreakpointSegment.responsiveBreakpoint.name == TABLET,
      isDesktop:
          state.activeBreakpointSegment.responsiveBreakpoint.name == DESKTOP,
    );
  }

  @override
  String toString() =>
      'ResponsiveWrapperData(' +
      'screenWidth: ' +
      screenWidth?.toString() +
      ', screenHeight: ' +
      screenHeight?.toString() +
      ', scaledWidth: ' +
      scaledWidth?.toString() +
      ', scaledHeight: ' +
      scaledHeight?.toString() +
      ', breakpoints: ' +
      breakpoints?.asMap().toString() +
      ', breakpointSegments: ' +
      breakpointSegments.toString() +
      ', activeBreakpoint: ' +
      activeBreakpoint.toString() +
      ', isMobile: ' +
      isMobile?.toString() +
      ', isPhone: ' +
      isPhone?.toString() +
      ', isTablet: ' +
      isTablet?.toString() +
      ', isDesktop: ' +
      isDesktop?.toString() +
      ')';

  bool equals(String name) => activeBreakpoint.name == name;

  /// Is the [scaledWidth] larger than or equal to [name]?
  /// Defaults to false if the [name] cannot be found.
  bool isLargerThan(String name) {
    // No breakpoints to match.
    if (breakpoints.length == 0) return false;

    // Breakpoint is active breakpoint.
    if (activeBreakpoint.name == name) return false;

    // Single breakpoint is active and screen width
    // is larger than default breakpoint.
    if (breakpoints.length == 1 && screenWidth >= breakpoints[0].breakpoint) {
      return true;
    }
    // Find first breakpoint end boundary that is larger
    // than screen width. Breakpoint names could be
    // chained so perform a full search from largest to smallest.
    for (var i = breakpoints.length - 2; i >= 0; i--) {
      if (breakpoints[i].name == name &&
          breakpoints[i + 1].name != name &&
          screenWidth >= breakpoints[i + 1].breakpoint) return true;
    }

    return false;
  }

  /// Is the [screenWidth] smaller than the [name]?
  /// Defaults to false if the [name] cannot be found.
  bool isSmallerThan(String name) =>
      screenWidth <
          breakpointSegments
              .firstWhere(
                  (element) => element.responsiveBreakpoint.name == name,
                  orElse: null)
              ?.breakpoint ??
      0;
}

/// Creates an immutable widget that exposes [ResponsiveWrapperData]
/// to child widgets.
///
/// Access values such as the [ResponsiveWrapperData.scaledWidth]
/// property through [ResponsiveWrapper.of]
/// `ResponsiveWrapper.of(context).scaledWidth`.
///
/// Querying this widget with [ResponsiveWrapper.of]
/// creates a dependency that causes an automatic
/// rebuild whenever the [ResponsiveWrapperData]
/// changes.
///
/// If no [ResponsiveWrapper] is in scope then the
/// [MediaQuery.of] method will throw an exception,
/// unless the `nullOk` argument is set to true, in
/// which case it returns null.
@immutable
class InheritedResponsiveWrapper extends InheritedWidget {
  final ResponsiveWrapperData data;

  /// Creates a widget that provides [ResponsiveWrapperData] to its descendants.
  ///
  /// The [data] and [child] arguments must not be null.
  InheritedResponsiveWrapper(
      {Key key, @required this.data, @required Widget child})
      : assert(child != null),
        assert(data != null),
        super(key: key, child: child);

  @override
  bool updateShouldNotify(InheritedResponsiveWrapper oldWidget) =>
      data != oldWidget.data;
}

enum _ResponsiveBreakpointBehavior {
  RESIZE,
  AUTOSCALE,
  AUTOSCALEDOWN,
  TAG,
}

@immutable
class ResponsiveBreakpoint {
  final double breakpoint;
  final String name;
  final _ResponsiveBreakpointBehavior behavior;
  final double scaleFactor;

  const ResponsiveBreakpoint._(
      {@required this.breakpoint,
      this.name,
      this.behavior,
      this.scaleFactor = 1});

  const ResponsiveBreakpoint.resize(this.breakpoint,
      {this.name, this.scaleFactor = 1})
      : this.behavior = _ResponsiveBreakpointBehavior.RESIZE,
        assert(breakpoint != null && breakpoint >= 0,
            'Breakpoints cannot be negative. To control behavior from 0, set `default` parameters in `ResponsiveWrapper`.');

  const ResponsiveBreakpoint.autoScale(this.breakpoint,
      {this.name, this.scaleFactor = 1})
      : this.behavior = _ResponsiveBreakpointBehavior.AUTOSCALE,
        assert(breakpoint != null && breakpoint >= 0,
            'Breakpoints cannot be negative. To control behavior from 0, set `default` parameters in `ResponsiveWrapper`.');

  const ResponsiveBreakpoint.autoScaleDown(this.breakpoint,
      {this.name, this.scaleFactor = 1})
      : this.behavior = _ResponsiveBreakpointBehavior.AUTOSCALEDOWN,
        assert(breakpoint != null && breakpoint >= 0,
            'Breakpoints cannot be negative. To control behavior from 0, set `default` parameters in `ResponsiveWrapper`.');

  const ResponsiveBreakpoint.tag(this.breakpoint, {@required this.name})
      : this.behavior = _ResponsiveBreakpointBehavior.TAG,
        this.scaleFactor = 1,
        assert(breakpoint != null && breakpoint >= 0,
            'Breakpoints cannot be negative. To control behavior from 0, set `default` parameters in `ResponsiveWrapper`.'),
        assert(name != null, 'Breakpoint tags must be named.');

  get isResize => behavior == _ResponsiveBreakpointBehavior.RESIZE;

  get isAutoScale => behavior == _ResponsiveBreakpointBehavior.AUTOSCALE;

  get isAutoScaleDown =>
      behavior == _ResponsiveBreakpointBehavior.AUTOSCALEDOWN;

  get isTag => behavior == _ResponsiveBreakpointBehavior.TAG;

  ResponsiveBreakpoint copyWith({
    double breakpoint,
    String name,
    _ResponsiveBreakpointBehavior behavior,
    double scaleFactor,
  }) =>
      ResponsiveBreakpoint._(
        breakpoint: breakpoint ?? this.breakpoint,
        name: name ?? this.name,
        behavior: behavior ?? this.behavior,
        scaleFactor: scaleFactor ?? this.scaleFactor,
      );

  @override
  String toString() =>
      'ResponsiveBreakpoint(' +
      'breakpoint: ' +
      breakpoint.toString() +
      ', name: ' +
      name.toString() +
      ', behavior: ' +
      behavior.toString() +
      ', scaleFactor: ' +
      scaleFactor.toString() +
      ')';
}

class _ResponsiveBreakpointSegment {
  final double breakpoint;
  final _ResponsiveBreakpointBehavior responsiveBreakpointBehavior;
  final ResponsiveBreakpoint responsiveBreakpoint;

  const _ResponsiveBreakpointSegment(
      {@required this.breakpoint,
      @required this.responsiveBreakpointBehavior,
      @required this.responsiveBreakpoint});

  get isResize =>
      responsiveBreakpointBehavior == _ResponsiveBreakpointBehavior.RESIZE;

  get isAutoScale =>
      responsiveBreakpointBehavior == _ResponsiveBreakpointBehavior.AUTOSCALE;

  get isAutoScaleDown =>
      responsiveBreakpointBehavior ==
      _ResponsiveBreakpointBehavior.AUTOSCALEDOWN;

  get isTag =>
      responsiveBreakpointBehavior == _ResponsiveBreakpointBehavior.TAG;

  _ResponsiveBreakpointSegment copyWith({
    double breakpoint,
    _ResponsiveBreakpointBehavior responsiveBreakpointBehavior,
    ResponsiveBreakpoint responsiveBreakpoint,
  }) =>
      _ResponsiveBreakpointSegment(
        breakpoint: breakpoint ?? this.breakpoint,
        responsiveBreakpointBehavior:
            responsiveBreakpointBehavior ?? this.responsiveBreakpointBehavior,
        responsiveBreakpoint: responsiveBreakpoint ?? this.responsiveBreakpoint,
      );

  @override
  String toString() =>
      'ResponsiveBreakpointSegment(' +
      'breakpoint: ' +
      breakpoint.toString() +
      ', responsiveBreakpointBehavior: ' +
      responsiveBreakpointBehavior.toString() +
      ', responsiveBreakpoint: ' +
      responsiveBreakpoint.toString() +
      ')';
}
