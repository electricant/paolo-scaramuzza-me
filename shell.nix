{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    buildInputs = [
      pkgs.zola
    ];

    shellHook = ''
      serve() {
        zola serve
      }
      build() {
        zola build
      }
      echo "Run 'serve' to preview the site at http://127.0.0.1:1111"
      echo "Run 'build' to build the production site into public/"
    '';
  }
