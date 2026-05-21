library bitsdojo_window_windows;

import 'package:win32/win32.dart';

import './native_api.dart';
import './window.dart';

const notInitializedMessage = """
 bitsdojo_window is not initalized.  
 """;

class BitsDojoNotInitializedException implements Exception {
  String errMsg() => notInitializedMessage;
}

class WinAppWindow extends WinWindow {
  WinAppWindow._() {
    final isLoaded = isBitsdojoWindowLoaded();
    if (!isLoaded) {
      print(notInitializedMessage);
      throw BitsDojoNotInitializedException;
    }
    _refreshHandle();
    assert(handle != null && handle!.address != 0, "Could not get Flutter window");
  }

  void _refreshHandle() {
    final nativeHandle = HWND(getAppWindow());
    if (nativeHandle.address != 0) {
      super.handle = nativeHandle;
    }
  }

  static final WinAppWindow _instance = WinAppWindow._();

  factory WinAppWindow() {
    _instance._refreshHandle();
    return _instance;
  }
}
