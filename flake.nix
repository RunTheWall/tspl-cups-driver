{
  description = "Free CUPS driver for TSPL/TSPL2 thermal label printers (by Run The Wall - https://constly.com)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "armv7l-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      packages = forAll (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "tspl-cups-driver";
          version = "1.3.0";
          src = self;
          nativeBuildInputs = [ pkgs.cups ];   # provides cups-config
          buildInputs = [ pkgs.cups ];
          dontConfigure = true;
          installPhase = ''
            runHook preInstall
            install -Dm0755 src/rastertotspl    $out/lib/cups/filter/rastertotspl
            install -Dm0755 backend/tspl     $out/lib/cups/backend/tspl
            install -Dm0644 ppd/tspl-label.ppd $out/share/cups/model/tspl-label.ppd
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "CUPS raster->TSPL driver for TSPL thermal label printers";
            homepage = "https://github.com/RunTheWall/tspl-cups-driver";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };
      });

      # NixOS: services.printing.drivers = [ self.packages.${system}.default ];
    };
}
