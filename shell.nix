{ pkgs ? import <nixpkgs> {}, ... }:
let
  lua = (pkgs.lua5_3.withPackages (ps: with ps; [ luasocket ]));
in
pkgs.stdenv.mkDerivation {
  name = "haproxy+lua53";
  buildInputs = [
    pkgs.haproxy
    lua
    pkgs.entr
  ];
  shellHook = ''
    export LUA_PATH="${lua}/share/lua/5.3/?.lua;./?.lua"
    export LUA_CPATH="${lua}/lib/lua/5.3/?.so"
    echo "LUA_PATH=$LUA_PATH"
    echo "LUA_CPATH=$LUA_CPATH"
    echo "Watching for changes and running haproxy..."
    for i in *; do echo "$i"; done | entr -cr haproxy -f ./haproxy.cfg
    exit
  '';
}
