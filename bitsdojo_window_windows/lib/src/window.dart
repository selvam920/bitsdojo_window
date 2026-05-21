import 'dart:ffi' hide Size;

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart';
import 'package:win32/win32.dart';

import './native_api.dart' as native;
import './win32_plus.dart';
import './window_interface.dart';
import './window_util.dart';

var isInsideDoWhenWindowReady = false;

bool isValidHandle(HWND? handle, String operation) {
  if (handle == null || handle.address == 0) {
    print("Could not $operation - handle is null or invalid");
    return false;
  }
  return true;
}

Rect getScreenRectForWindow(HWND handle) {
  HMONITOR monitor = MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST);
  final monitorInfo = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
  final result = GetMonitorInfo(monitor, monitorInfo);
  if (result) {
    return Rect.fromLTRB(monitorInfo.ref.rcWork.left.toDouble(), monitorInfo.ref.rcWork.top.toDouble(),
        monitorInfo.ref.rcWork.right.toDouble(), monitorInfo.ref.rcWork.bottom.toDouble());
  }
  return Rect.zero;
}

class WinWindow extends WinDesktopWindow {
  static const int _defaultDpi = 96;
  static const double _defaultScaleFactor = 1.0;

  static final dpiAware = native.isDPIAware();
  HWND? handle;
  Size? _minSize;
  Size? _maxSize;
  // We use this for reporting size inside doWhenWindowReady
  // as GetWindowRect might not work reliably before window is shown on screen
  Size? _sizeSetFromDart;
  Alignment? _alignment;

  void setWindowCutOnMaximize(int value) {
    native.setWindowCutOnMaximize(value);
  }

  WinWindow() {
    _alignment = Alignment.center;
  }

  HWND? _resolveHandle() {
    final currentHandle = handle;
    if (currentHandle != null && currentHandle.address != 0) {
      return currentHandle;
    }

    final nativeHandle = HWND(native.getAppWindow());
    if (nativeHandle.address != 0) {
      handle = nativeHandle;
      return nativeHandle;
    }
    return currentHandle;
  }

  Rect get rect {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "get rectangle")) return Rect.zero;
    final winRect = calloc<RECT>();
    GetWindowRect(hwnd!, winRect);
    Rect result = winRect.ref.toRect;
    calloc.free(winRect);
    return result;
  }

  set rect(Rect newRect) {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "set rectangle")) return;
    setWindowPos(
        hwnd!, 0, newRect.left.toInt(), newRect.top.toInt(), newRect.width.toInt(), newRect.height.toInt(), 0);
  }

  Size get size {
    final winRect = this.rect;
    final gotSize = getLogicalSize(Size(winRect.width, winRect.height));
    return gotSize;
  }

  Size get sizeOnScreen {
    if (isInsideDoWhenWindowReady == true) {
      if (_sizeSetFromDart != null) {
        final sizeOnScreen = getSizeOnScreen(_sizeSetFromDart!);
        return sizeOnScreen;
      }
    }
    final winRect = this.rect;
    return Size(winRect.width, winRect.height);
  }

  int systemMetric(SYSTEM_METRICS_INDEX metric, {int dpiToUse = 0}) {
    final windowDpi = dpiToUse != 0 ? dpiToUse : this.dpi;
    int result = dpiAware ? GetSystemMetricsForDpi(metric, windowDpi).value : GetSystemMetrics(metric);
    return result;
  }

  double get borderSize {
    return this.systemMetric(SM_CXBORDER).toDouble();
  }

  int get dpi {
    final hwnd = _resolveHandle();
    if (!dpiAware || !isValidHandle(hwnd, "get dpi")) return _defaultDpi;
    final windowDpi = GetDpiForWindow(hwnd!);
    if (windowDpi <= 0) {
      return _defaultDpi;
    }
    return windowDpi;
  }

  double get scaleFactor {
    final result = this.dpi / _defaultDpi;
    if (!result.isFinite || result <= 0) {
      return _defaultScaleFactor;
    }
    return result;
  }

  double get titleBarHeight {
    double scaleFactor = this.scaleFactor;
    int dpiToUse = this.dpi;
    double cyCaption = systemMetric(SM_CYCAPTION, dpiToUse: dpiToUse).toDouble();
    cyCaption = (cyCaption / scaleFactor);
    double cySizeFrame = systemMetric(SM_CYSIZEFRAME, dpiToUse: dpiToUse).toDouble();
    cySizeFrame = (cySizeFrame / scaleFactor);
    double cxPaddedBorder = systemMetric(SM_CXPADDEDBORDER, dpiToUse: dpiToUse).toDouble();
    cxPaddedBorder = (cxPaddedBorder / scaleFactor).ceilToDouble();
    double result = cySizeFrame + cyCaption + cxPaddedBorder;
    if (!result.isFinite || result <= 0) {
      return 32.0;
    }
    return result;
  }

  Size get titleBarButtonSize {
    double height = this.titleBarHeight - this.borderSize;
    double scaleFactor = this.scaleFactor;
    double cyCaption = systemMetric(SM_CYCAPTION).toDouble();
    cyCaption /= scaleFactor;
    double width = cyCaption * 2;
    if (!width.isFinite || width <= 0) {
      width = 46.0;
    }
    if (!height.isFinite || height <= 0) {
      height = 30.0;
    }
    return Size(width, height);
  }

  Size getSizeOnScreen(Size inSize) {
    double scaleFactor = this.scaleFactor;
    double newWidth = inSize.width * scaleFactor;
    double newHeight = inSize.height * scaleFactor;
    return Size(newWidth, newHeight);
  }

  Size getLogicalSize(Size inSize) {
    double scaleFactor = this.scaleFactor;
    double newWidth = inSize.width / scaleFactor;
    double newHeight = inSize.height / scaleFactor;
    return Size(newWidth, newHeight);
  }

  Alignment? get alignment => _alignment;

  /// How the window should be aligned on screen
  set alignment(Alignment? newAlignment) {
    final sizeOnScreen = this.sizeOnScreen;
    _alignment = newAlignment;
    if (_alignment != null) {
      final hwnd = _resolveHandle();
      if (!isValidHandle(hwnd, "set alignment")) return;
      final screenRect = getScreenRectForWindow(hwnd!);
      final rectOnScreen = getRectOnScreen(sizeOnScreen, _alignment!, screenRect);
      this.rect = rectOnScreen;
    }
  }

  set minSize(Size? newSize) {
    _minSize = newSize;
    if (newSize == null) {
      //TODO - add handling for setting minSize to null
      return;
    }
    native.setMinSize(_minSize!.width.toInt(), _minSize!.height.toInt());
  }

  set maxSize(Size? newSize) {
    _maxSize = newSize;
    if (newSize == null) {
      //TODO - add handling for setting maxSize to null
      return;
    }
    native.setMaxSize(_maxSize!.width.toInt(), _maxSize!.height.toInt());
  }

  set size(Size newSize) {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "set size")) return;

    var width = newSize.width;

    if (_minSize != null) {
      if (newSize.width < _minSize!.width) width = _minSize!.width;
    }

    if (_maxSize != null) {
      if (newSize.width > _maxSize!.width) width = _maxSize!.width;
    }

    var height = newSize.height;

    if (_minSize != null) {
      if (newSize.height < _minSize!.height) height = _minSize!.height;
    }

    if (_maxSize != null) {
      if (newSize.height > _maxSize!.height) height = _maxSize!.height;
    }

    Size sizeToSet = Size(width, height);
    _sizeSetFromDart = sizeToSet;
    if (_alignment == null) {
      SetWindowPos(hwnd!, null, 0, 0, sizeToSet.width.toInt(), sizeToSet.height.toInt(), SWP_NOMOVE);
    } else {
      final sizeOnScreen = getSizeOnScreen((sizeToSet));
      final screenRect = getScreenRectForWindow(hwnd!);
      this.rect = getRectOnScreen(sizeOnScreen, _alignment!, screenRect);
    }
  }

  bool get isMaximized {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "get isMaximized")) return false;
    return IsZoomed(hwnd!);
  }

  @Deprecated("use isVisible instead")
  bool get visible {
    return isVisible;
  }

  bool get isVisible {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "get isVisible")) return false;
    return IsWindowVisible(hwnd!);
  }

  Offset get position {
    final winRect = this.rect;
    return Offset(winRect.left, winRect.top);
  }

  set position(Offset newPosition) {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "set position")) return;
    SetWindowPos(hwnd!, null, newPosition.dx.toInt(), newPosition.dy.toInt(), 0, 0, SWP_NOSIZE);
  }

  void show() {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "show")) return;
    setWindowPos(hwnd!, 0, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW);
    forceChildRefresh(hwnd);
  }

  void hide() {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "hide")) return;
    SetWindowPos(hwnd!, null, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_HIDEWINDOW);
  }

  @Deprecated("use show()/hide() instead")
  set visible(bool isVisible) {
    if (isVisible) {
      show();
    } else {
      hide();
    }
  }

  void close() {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "close")) return;
    PostMessage(hwnd!, WM_SYSCOMMAND, WPARAM(SC_CLOSE), LPARAM(0));
  }

  void maximize() {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "maximize")) return;
    PostMessage(hwnd!, WM_SYSCOMMAND, WPARAM(SC_MAXIMIZE), LPARAM(0));
  }

  void minimize() {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "minimize")) return;

    PostMessage(hwnd!, WM_SYSCOMMAND, WPARAM(SC_MINIMIZE), LPARAM(0));
  }

  void restore() {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "restore")) return;
    PostMessage(hwnd!, WM_SYSCOMMAND, WPARAM(SC_RESTORE), LPARAM(0));
  }

  void maximizeOrRestore() {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "maximizeOrRestore")) return;
    if (IsZoomed(hwnd!)) {
      this.restore();
    } else {
      this.maximize();
    }
  }

  set title(String newTitle) {
    final hwnd = _resolveHandle();
    if (!isValidHandle(hwnd, "set title")) return;
    setWindowText(hwnd!, newTitle);
  }

  void startDragging() {
    BitsdojoWindowPlatform.instance.dragAppWindow();
  }
}
