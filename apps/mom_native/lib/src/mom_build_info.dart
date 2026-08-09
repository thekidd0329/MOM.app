class MomBuildInfo {
  const MomBuildInfo._();

  // Keep this in lockstep with apps/mom_native/pubspec.yaml.
  static const String version = '0.5.0';
  static const int build = 7;

  static const String displayVersion = 'Version $version';
  static const String fullVersion = 'Version $version ($build)';
}
