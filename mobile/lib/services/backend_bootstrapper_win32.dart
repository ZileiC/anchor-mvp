import 'dart:ffi';
import 'dart:io' show pid;

import 'package:flutter/foundation.dart';

/// A Windows job object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so the app and
/// every process it starts die together.
///
/// Why this exists: closing a Flutter Windows window does **not** deliver an exit
/// request or a lifecycle callback to Dart — the process simply ends — so
/// `AppLifecycleListener` / `WidgetsBindingObserver` cannot reliably stop the
/// backend child. A job object makes the operating system do it: this process
/// joins the job before the backend is spawned, the backend inherits it, and when
/// the app process ends the last handle to the job closes, at which point Windows
/// terminates everything left in the job.
///
/// This also covers the packaged backend's process shape: `anchor_backend.exe` is
/// a PyInstaller one-file executable that runs a bootloader process plus the
/// child that actually serves HTTP. Killing only the process we started would
/// leave the server alive; the inherited job takes down the whole tree.
///
/// Everything here is best effort. If any Win32 call fails (older Windows, a
/// sandbox that denies job assignment, a non-Windows host) [keepAppInJob] returns
/// false and the app behaves as if this file did not exist.
class WindowsKillOnCloseJob {
  WindowsKillOnCloseJob._(this._handle);

  static const int _jobObjectExtendedLimitInformation = 9;
  static const int _jobObjectLimitKillOnJobClose = 0x2000;
  static const int _localAllocZeroInit = 0x0040;
  static const int _processTerminate = 0x0001;
  static const int _processSetQuota = 0x0100;

  /// Held for the lifetime of the process on purpose: closing this handle is what
  /// triggers the cleanup, so it must happen when the process ends, not earlier.
  final Pointer<Void> _handle;

  /// True while the job handle is open (always true for a live instance).
  bool get isEngaged => _handle != nullptr;

  /// The job this process joined.
  static WindowsKillOnCloseJob? _appJob;
  static bool _attempted = false;

  /// Puts this process — and therefore every process it starts afterwards — into
  /// a kill-on-close job. Safe to call more than once.
  ///
  /// Call it immediately *before* starting the backend: a child only inherits the
  /// job if it is created after the parent joined it.
  static bool keepAppInJob() {
    if (_appJob?.isEngaged ?? false) return true;
    if (_attempted) return false;
    _attempted = true;
    try {
      _appJob = _createForCurrentProcess();
    } catch (error) {
      debugPrint('Anchor: no kill-on-close job ($error)');
      _appJob = null;
    }
    return _appJob?.isEngaged ?? false;
  }

  static WindowsKillOnCloseJob? _createForCurrentProcess() {
    final kernel32 = _Kernel32.instance();
    final job = kernel32.createJobObject(nullptr, nullptr);
    if (job == nullptr) return null;

    var configured = 0;
    Pointer<Uint8> memory = nullptr;
    try {
      final cbSize = sizeOf<_ExtendedLimitInformation>();
      memory = kernel32.localAlloc(_localAllocZeroInit, cbSize);
      if (memory == nullptr) return null;
      final information = memory.cast<_ExtendedLimitInformation>();
      information.ref.basicLimitInformation.limitFlags =
          _jobObjectLimitKillOnJobClose;
      configured = kernel32.setInformationJobObject(
        job,
        _jobObjectExtendedLimitInformation,
        memory.cast<Void>(),
        cbSize,
      );
    } finally {
      if (memory != nullptr) kernel32.localFree(memory);
    }
    if (configured == 0) {
      kernel32.closeHandle(job);
      return null;
    }

    final process = kernel32.openProcess(
      _processSetQuota | _processTerminate,
      0,
      pid,
    );
    if (process == nullptr) {
      kernel32.closeHandle(job);
      return null;
    }
    final assigned = kernel32.assignProcessToJobObject(job, process);
    kernel32.closeHandle(process);
    if (assigned == 0) {
      kernel32.closeHandle(job);
      return null;
    }
    return WindowsKillOnCloseJob._(job);
  }
}

// -- Win32 layout ----------------------------------------------------------

/// `JOBOBJECT_BASIC_LIMIT_INFORMATION` (64 bytes on x64).
final class _BasicLimitInformation extends Struct {
  @Int64()
  external int perProcessUserTimeLimit;

  @Int64()
  external int perJobUserTimeLimit;

  @Uint32()
  external int limitFlags;

  @UintPtr()
  external int minimumWorkingSetSize;

  @UintPtr()
  external int maximumWorkingSetSize;

  @Uint32()
  external int activeProcessLimit;

  @UintPtr()
  external int affinity;

  @Uint32()
  external int priorityClass;

  @Uint32()
  external int schedulingClass;
}

/// `IO_COUNTERS` (48 bytes).
final class _IoCounters extends Struct {
  @Uint64()
  external int readOperationCount;

  @Uint64()
  external int writeOperationCount;

  @Uint64()
  external int otherOperationCount;

  @Uint64()
  external int readTransferCount;

  @Uint64()
  external int writeTransferCount;

  @Uint64()
  external int otherTransferCount;
}

/// `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` (144 bytes on x64).
final class _ExtendedLimitInformation extends Struct {
  external _BasicLimitInformation basicLimitInformation;

  external _IoCounters ioInfo;

  @UintPtr()
  external int processMemoryLimit;

  @UintPtr()
  external int jobMemoryLimit;

  @UintPtr()
  external int peakProcessMemoryUsed;

  @UintPtr()
  external int peakJobMemoryUsed;
}

// -- kernel32 bindings -----------------------------------------------------

typedef _CreateJobObjectNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _CreateJobObjectDart = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _SetInformationJobObjectNative = Int32 Function(
  Pointer<Void>,
  Int32,
  Pointer<Void>,
  Uint32,
);
typedef _SetInformationJobObjectDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Void>,
  int,
);
typedef _AssignProcessToJobObjectNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _AssignProcessToJobObjectDart = int Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _OpenProcessNative = Pointer<Void> Function(Uint32, Int32, Uint32);
typedef _OpenProcessDart = Pointer<Void> Function(int, int, int);
typedef _CloseHandleNative = Int32 Function(Pointer<Void>);
typedef _CloseHandleDart = int Function(Pointer<Void>);
typedef _LocalAllocNative = Pointer<Uint8> Function(Uint32, IntPtr);
typedef _LocalAllocDart = Pointer<Uint8> Function(int, int);
typedef _LocalFreeNative = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _LocalFreeDart = Pointer<Uint8> Function(Pointer<Uint8>);

class _Kernel32 {
  _Kernel32._(DynamicLibrary library)
    : createJobObject = library
          .lookupFunction<_CreateJobObjectNative, _CreateJobObjectDart>(
            'CreateJobObjectW',
          ),
      setInformationJobObject = library
          .lookupFunction<
            _SetInformationJobObjectNative,
            _SetInformationJobObjectDart
          >('SetInformationJobObject'),
      assignProcessToJobObject = library
          .lookupFunction<
            _AssignProcessToJobObjectNative,
            _AssignProcessToJobObjectDart
          >('AssignProcessToJobObject'),
      openProcess = library
          .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess'),
      closeHandle = library
          .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle'),
      localAlloc = library.lookupFunction<_LocalAllocNative, _LocalAllocDart>(
        'LocalAlloc',
      ),
      localFree = library.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
        'LocalFree',
      );

  static _Kernel32? _cached;

  static _Kernel32 instance() =>
      _cached ??= _Kernel32._(DynamicLibrary.open('kernel32.dll'));

  final _CreateJobObjectDart createJobObject;
  final _SetInformationJobObjectDart setInformationJobObject;
  final _AssignProcessToJobObjectDart assignProcessToJobObject;
  final _OpenProcessDart openProcess;
  final _CloseHandleDart closeHandle;
  final _LocalAllocDart localAlloc;
  final _LocalFreeDart localFree;
}
