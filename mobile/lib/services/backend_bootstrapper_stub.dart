import 'backend_bootstrapper.dart';

/// Web/unsupported build: there is no `dart:io`, so there is no local process to
/// start and no executable path to resolve. The app simply carries on.
BackendBootstrapper createPlatformBackendBootstrapper() => BackendBootstrapper(
  supported: false,
  healthProbe: const DisabledBackendHealthProbe(),
  launcher: const DisabledBackendProcessLauncher(),
  locateExecutable: () => '',
  fileExists: (String _) => false,
);
