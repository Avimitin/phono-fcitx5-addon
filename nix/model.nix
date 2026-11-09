{
  fetchFromHuggingFace,
  lib,
}:

let
  modelRevision = "e9f90e488c1dc41997b5806537be7c43addca850";
in
fetchFromHuggingFace {
  name = "phonop2c-v2.2-base-w8a8-2026-10-28";
  repoId = "afirelily/phonop2c_v2_2_base_w8a8_model";
  rev = modelRevision;
  hash = "sha256-upOZsmP0k8x5xRCVUox85ui/6MX9Pf46ACTLzEi4Bic=";
  backend = "lfs";

  passthru = {
    inherit modelRevision;
  };

  meta = {
    description = "PhonoP2C v2.2 W8A8 model package for Phono";
    platforms = lib.platforms.all;
  };
}
