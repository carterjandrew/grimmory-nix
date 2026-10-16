{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_12,
  nodejs_24,
  gradle-packages,
  jdk25_headless,
  makeWrapper,
  ffmpeg-headless,
  kepubify,
  libarchive,
}:

let
  pnpm = pnpm_12;
  gradleUnwrapped = gradle-packages.mkGradle {
    version = "9.7.1";
    hash = "sha256-rNU/HtrwLxqP+Zh5+KNLMCZhoFfZsGOunjW1UvgE0go=";
    defaultJava = jdk25_headless;
    updateScriptMajorVersion = null;
  };
  gradle = gradleUnwrapped.wrapped;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "grimmory";
  version = "3.5.0";

  src = fetchFromGitHub {
    owner = "grimmory-tools";
    repo = "grimmory";
    rev = "v${finalAttrs.version}";
    hash = "sha256-j9VXtqWLc13qVn89T1OmLQcAlhTP4w8AmOZINqhtNa4=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-+JaCMYB8+TOXp5XiaMI12GS3RteOgu3CpB9UYploMik=";
  };

  mitmCache = gradle.fetchDeps {
    pkg = finalAttrs.finalPackage;
    data = ./deps.json;
  };

  nativeBuildInputs = [
    gradle
    jdk25_headless
    makeWrapper
    nodejs_24
    pnpm
    pnpmConfigHook
  ];

  __darwinAllowLocalNetworking = true;

  # These are consumed by gradle.fetchDeps when regenerating deps.json. The
  # real build below supplies the already-built frontend explicitly.
  gradleFlags = [
    "-p"
    "backend"
  ];
  gradleBuildTask = "bootJar -x test";

  buildPhase = ''
    runHook preBuild

    pnpm --dir frontend run build:prod
    gradle --no-daemon \
      -PfrontendDistDir="$PWD/frontend/dist/grimmory/browser" \
      -PtargetPlatform="linux/${if stdenv.hostPlatform.isAarch64 then "arm64" else "amd64"}" \
      -PtargetArch="${if stdenv.hostPlatform.isAarch64 then "arm64" else "amd64"}" \
      bootJar -x test

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 backend/build/libs/backend-*.jar \
      "$out/share/grimmory/grimmory.jar"

    makeWrapper ${jdk25_headless}/bin/java "$out/bin/grimmory" \
      --add-flags "--enable-native-access=ALL-UNNAMED" \
      --add-flags "--enable-preview" \
      --add-flags "-jar $out/share/grimmory/grimmory.jar" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg-headless kepubify ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libarchive stdenv.cc.cc ]}

    runHook postInstall
  '';

  meta = {
    description = "Self-hosted digital library with a built-in reader";
    homepage = "https://grimmory.org";
    changelog = "https://github.com/grimmory-tools/grimmory/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "grimmory";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
      binaryNativeCode
    ];
  };
})
