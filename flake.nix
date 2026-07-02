{
  description = "Free CUPS driver for HZD950-PRO / HERO TSPL thermal label printers (by Run The Wall - https://constly.com)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "armv7l-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      packages = forAll (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "hzd950-cups-driver";
          version = "1.0.0";
          src = self;
          nativeBuildInputs = [ pkgs.cups ];   # provides cups-config
          buildInputs = [ pkgs.cups ];
          dontConfigure = true;
          installPhase = ''
            runHook preInstall
            install -Dm0755 src/rastertohzd    $out/lib/cups/filter/rastertohzd
            install -Dm0755 backend/hzd950     $out/lib/cups/backend/hzd950
            install -Dm0644 ppd/HZD950-PRO.ppd $out/share/cups/model/HZD950-PRO.ppd
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "CUPS raster->TSPL driver for HZD950-PRO / HERO label printers";
            homepage = "https://github.com/RunTheWall/hzd950-cups-driver";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };
      });

      # NixOS: services.printing.drivers = [ self.packages.${system}.default ];
    };
}
