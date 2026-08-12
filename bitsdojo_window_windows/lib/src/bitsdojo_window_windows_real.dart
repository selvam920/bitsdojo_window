library bitsdojo_window_windows;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import './window.dart';
import './app_window.dart';
import './native_api.dart';

export './window_interface.dart';

T? _ambiguate<T>(T? value) => value;

class BitsdojoWindowWindows extends BitsdojoWindowPlatform {
  BitsdojoWindowWindows() : super();

  Future<void> _waitForNativeWindowHandle() async {
    const maxAttempts = 400;
    var attempts = 0;
    while (attempts < maxAttempts) {
      final hwnd = getAppWindow();
      if (hwnd.address != 0) {
        return;
      }
      attempts += 1;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  // Cap the wait so a stalled raster thread (GPU/driver hiccup, RDP, TDR) can't leave BDW_HIDE_ON_STARTUP hiding the window forever.
  Future<void> _waitForFirstFrameOrTimeout() {
    return _ambiguate(WidgetsBinding.instance)!
        .waitUntilFirstFrameRasterized
        .timeout(const Duration(seconds: 3), onTimeout: () {
      debugPrint(
        'bitsdojo_window: first frame not rasterized within 3s, showing window anyway',
      );
    });
  }

  @override
  void doWhenWindowReady(VoidCallback callback) {
    _waitForFirstFrameOrTimeout().then((value) async {
      await _waitForNativeWindowHandle();
      isInsideDoWhenWindowReady = true;
      setWindowCanBeShown(true);
      callback();
      isInsideDoWhenWindowReady = false;
    });
  }

  @override
  DesktopWindow get appWindow {
    return WinAppWindow();
  }
}
