{
  lib,
  stdenv,
  boost,
  cmake,
  fcitx5,
  gettext,
  libime,
  ninja,
  nlohmann_json,
  phono-core-sdk,
  pkg-config,
  python3,
  qt6Packages,
}:

let
  chineseAddons = qt6Packages.fcitx5-chinese-addons;
in
stdenv.mkDerivation {
  pname = "phono-fcitx5-addon";
  version = "0.1.3";
  src = lib.cleanSource ../.;

  nativeBuildInputs = [
    cmake
    gettext
    ninja
    pkg-config
    python3
  ];
  buildInputs = [
    boost
    fcitx5
    libime
    nlohmann_json
    phono-core-sdk
  ];

  # Nix keeps the SDK in the runtime closure; copying its library is unnecessary.
  cmakeFlags = [ "-DPHONO_BUNDLE_CORE=OFF" ];
  doCheck = true;
  FCITX_DATA_DIRS = "${chineseAddons}/share/fcitx5";
  FCITX_ADDON_DIRS = "${chineseAddons}/lib/fcitx5";

  meta = {
    description = "Phono Chinese Pinyin and Shuangpin input methods for Fcitx5";
    homepage = "https://github.com/phono-project/phono-fcitx5-addon";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
