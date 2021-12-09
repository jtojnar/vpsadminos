# Deployment

## Netboot
vpsAdminOS is designed for netboot deployment where each machine has its own
image hosted on a netboot server. Machine runs the image from *RAM* and imports
*ZFS* pool with container data and *osctld* configs.

See [vpsfree-cz-configuration] for example *NixOps* deployment.


## Direct NixOps
If you'd like to deploy *vpsAdminOS* machines directly using *NixOps*, i.e. not
exclusively using netboot, you need a patched version of *NixOps* which supports
*vpsAdminOS*.

You can install the [modified NixOps] e.g. using an [overlay]:

```nix
self: super:
let
  git = super.fetchFromGitHub {
      owner = "vpsfreecz";
      repo = "nixops";

      # You might need to change rev and sha256 in case the docs is outdated
      rev = "510485dee43cc959eb758ce61b38fc94c3e9a29e";
      sha256 = "1sn4j3wyz5y1s0nnk5ahwym3qppqm03ygd78cixwdbic0kij6p1i";
    };

  release = (import "${git}/release.nix" { nixpkgs = self.path; });
in
{
  nixops = release.build.x86_64-linux;
}
```

Our version of *NixOps* supports special options which let you specify *Nix paths*
and OS type per machine. This makes it possible to mix *NixOS* and *vpsAdminOS*
machines within a single deployment.

```nix
let
  nixpkgsUrl = "https://github.com/vpsfreecz/nixpkgs/archive/vpsadminos.tar.gz";
  nixpkgs = builtins.fetchTarball nixpkgsUrl;

  vpsadminosUrl = "https://github.com/vpsfreecz/vpsadminos/archive/staging.tar.gz";
  vpsadminos = builtins.fetchTarball vpsadminosUrl;
in
{
  network.description = "Some infrastructure";

  # Set per-machine OS type and Nix path. This is required for vpsAdminOS
  # machines and optional for NixOS machines.
  network.machines = {
    # All vpsAdminOS machines must be configured in this way
    vpsadminos-node = {
      spin = "vpsAdminOS";
      path = "${vpsadminos}";
      nixPath = [
        { prefix = "nixpkgs"; path = "${nixpkgs}"; }
        { prefix = "vpsadminos"; path = "${vpsadminos}"; }
      ];
    };

    # Machines default to `spin = "NixOS"` and the nixpkgs that NixOps was
    # launched with
    # nixos-node = {
    #   spin = "NixOS";
    #   nixPath = [ ... ];
    # };
  };

  # Define managed machines
  vpsadminos-node =
    { config, pkgs, lib, ... }:
    {
      imports = [
        <vpsadminos/os/configs/common.nix>
      ];

      networking.dhcp = true;
      networking.dhcpd = true;
      networking.lxcbr = true;
      networking.nat = true;

      time.timeZone = "Europe/Prague";

      environment.systemPackages = with pkgs; [
        htop
        vim
      ];

      services.openssh.enable = true;

      users.extraUsers.root.openssh.authorizedKeys.keys = [
        "your ssh pubkey"
      ];
    };

  nixos-node =
    { config, pkgs, lib, ... }:
    { ...configuration... };
}
```

[vpsfree-cz-configuration]: https://github.com/vpsfreecz/vpsfree-cz-configuration
[modified NixOps]: https://github.com/vpsfreecz/nixops
[overlay]: https://nixos.org/nixpkgs/manual/#sec-overlays-install
