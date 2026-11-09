{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchgit,
  flatbuffers,
  cmake,
  ninja,
  python3,
  uni-algo,
}:

let
  sdk = builtins.fromJSON (builtins.readFile ../ci/core-sdk.json);
  # Matches phono-core v0.1.2's ci/core-dependencies.json.
  executorchSource = fetchgit {
    url = "https://github.com/pytorch/executorch.git";
    rev = "00f06544be6b674f2ce8c1a746b76f23cf585d21";
    hash = "sha256-QnenEW1jRepzfSUjfdxEksg1NybDonMjyM4oWUdsoPk=";
    fetchSubmodules = false;
    postCheckout = ''
      git -C "$out" submodule update --init --recursive --depth 1 --jobs 4 -- \
        backends/xnnpack/third-party/FP16 \
        backends/xnnpack/third-party/FXdiv \
        backends/xnnpack/third-party/XNNPACK \
        backends/xnnpack/third-party/cpuinfo \
        backends/xnnpack/third-party/pthreadpool \
        kernels/optimized/third-party/eigen \
        third-party/flatbuffers third-party/flatcc third-party/gflags \
        third-party/json third-party/pocketfft
    '';
  };
  # ExecuTorch codegen uses torchgen's Python sources and operator schemas.
  pytorchSource = fetchFromGitHub {
    owner = "pytorch";
    repo = "pytorch";
    tag = "v2.14.0";
    hash = "sha256-Qqr8Tpd+XWU5WSuw3rmOl/lMcPYUgVDkxW7N2Zp3HTA=";
  };
  python = python3.withPackages (ps: [
    ps.pyyaml
    ps.typing-extensions
  ]);
  flatc = flatbuffers.overrideAttrs {
    version = "24.3.25";
    src = "${executorchSource}/third-party/flatbuffers";
    doCheck = false;
    cmakeFlags = [ "-DFLATBUFFERS_BUILD_TESTS=OFF" ];
  };
in
stdenv.mkDerivation {
  pname = "phono-core-sdk";
  inherit (sdk) version;

  src = fetchFromGitHub {
    owner = "phono-project";
    repo = "phono-core";
    tag = "v${sdk.version}";
    hash = "sha256-0jVg9p48/bXn+VV2q/kuF9B8+wktGh+Bf26lktHxlWM=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    python
    flatc
  ];
  buildInputs = [ uni-algo ];
  patches = [ ./patches/executorch-torch-headers.patch ];

  postUnpack = ''
    mkdir -p "$sourceRoot/third_party"
    cp -r ${executorchSource} "$sourceRoot/third_party/executorch"
    cp -r ${pytorchSource}/torchgen "$sourceRoot/third_party/torchgen"
    chmod -R u+w "$sourceRoot/third_party"
    mkdir -p "$sourceRoot/third_party/torchgen/packaged/ATen/native"
    cp ${pytorchSource}/aten/src/ATen/native/{native_functions,tags}.yaml \
      "$sourceRoot/third_party/torchgen/packaged/ATen/native/"
    cp -r ${pytorchSource}/aten/src/ATen/templates \
      "$sourceRoot/third_party/torchgen/packaged/ATen/"
  '';

  postPatch = ''
    # Allow space for the terminator when compiling flatcc with GCC 15+.
    substituteInPlace third_party/executorch/third-party/flatcc/include/flatcc/portable/grisu3_print.h \
      --replace-fail 'static char hexdigits[16] = "0123456789ABCDEF";' \
        'static char hexdigits[17] = "0123456789ABCDEF";'
  '';

  preConfigure = ''
    export PYTHONPATH="$PWD/third_party''${PYTHONPATH:+:$PYTHONPATH}"
    export CMAKE_BUILD_PARALLEL_LEVEL="$NIX_BUILD_CORES"
    # These headers are used without libtorch or its optional library backends.
    mkdir -p torch-headers/ATen
    sed -E 's/@[A-Z0-9_]+@/0/g' ${pytorchSource}/aten/src/ATen/Config.h.in \
      > torch-headers/ATen/Config.h
    cmakeFlagsArray+=("-DTORCH_INCLUDE_DIRS=$PWD/torch-headers;${pytorchSource};${pytorchSource}/aten/src;${pytorchSource}/torch/csrc/api/include")
  '';
  cmakeFlags = [
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    "-DPHONO_DTYPE_SELECTIVE_BUILD=OFF"
    "-DBUILD_TESTING=ON"
  ];
  buildFlags = [
    "phono_core_shared"
    "phono_core_tests"
    "phono_capi_tests"
    "phono_engine_tests"
    "phono_ime_editor_tests"
  ];
  doCheck = true;

  installPhase = ''
    runHook preInstall
    cmake --install . --prefix "$out" --component sdk

    mkdir -p "$out/share/licenses/phono-core/third_party/executorch"
    (
      cd ../third_party/executorch
      find . -type f \( -name 'LICENSE*' -o -name 'COPYING*' \) \
        -exec cp --parents '{}' "$out/share/licenses/phono-core/third_party/executorch/" \;
    )
    install -Dm644 ${uni-algo.src}/LICENSE.md \
      "$out/share/licenses/phono-core/third_party/uni-algo/LICENSE"
    runHook postInstall
  '';

  meta = {
    description = "Phono C API SDK built with ExecuTorch and XNNPACK";
    homepage = "https://github.com/phono-project/phono-core";
    license = with lib.licenses; [
      asl20
      bsd3
      bsd2
      mit
      mpl20
    ];
    platforms = [ "x86_64-linux" ];
  };
}
