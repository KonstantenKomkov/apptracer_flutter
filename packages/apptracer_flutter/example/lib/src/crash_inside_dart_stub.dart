/// Web has no `dart:ffi` and no `libapp.so`; there is nothing to crash into.
Never crashInsideDartCode() {
  throw UnsupportedError('crashInsideDartCode is not available on the web');
}
