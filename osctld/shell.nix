let
  pkgs = import <nixpkgs> { overlays = (import ../os/overlays/common.nix); };
  lib = pkgs.lib;
  stdenv = pkgs.stdenv;

  path = with pkgs; [
    apparmor-parser
    coreutils
    iproute
    glibc.bin
    gzip
    lxc
    nettools
    gnutar
    openssh
    shadow
    util-linux
    zfs
  ];

  pathJoined = lib.concatMapStringsSep ":" (s: "${s}/bin") path;

  apparmorPaths = [ pkgs.apparmor-profiles ];

  osctldConfig = {
    apparmor_paths = map (s: "${s}/etc/apparmor.d") apparmorPaths;

    ctstartmenu = "${pkgs.ctstartmenu}/bin/ctstartmenu";
  };

  jsonConfigFile = pkgs.writeText "osctld-config.json" (builtins.toJSON osctldConfig);

in stdenv.mkDerivation rec {
  name = "osctld";

  buildInputs = [
    pkgs.ruby
    pkgs.git
    pkgs.lxc
    pkgs.zlib
    pkgs.openssl
  ];

  shellHook = ''
    mkdir -p /tmp/dev-ruby-gems
    export GEM_HOME="/tmp/dev-ruby-gems"
    export GEM_PATH="$GEM_HOME:$PWD/lib"
    export PATH="$GEM_HOME/bin:$PATH:${pathJoined}"

    BUNDLE="$GEM_HOME/bin/bundle"

    [ ! -x "$BUNDLE" ] && ${pkgs.ruby}/bin/gem install bundler

    export BUNDLE_PATH="$GEM_HOME"
    export BUNDLE_GEMFILE="$PWD/Gemfile"

    $BUNDLE install

    export RUBYOPT=-rbundler/setup

    run-osctld() {
      bundle exec bin/osctld --config ${jsonConfigFile}
    }
  '';
}
