{
  description = "Blue RDMA Driver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ rust-overlay.overlays.default ];
        pkgs = import nixpkgs { inherit system overlays; };
        kernel = pkgs.linuxPackages_6_6.kernel;
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };
        dtld-rdma-core = pkgs.rdma-core.overrideAttrs (old: {
          src = ./dtld-ibverbs;
          sourceRoot = "dtld-ibverbs/rdma-core-55.0";
        });

      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            rustToolchain
            cargo-nextest

            dtld-rdma-core
            cmake
            docutils
            pandoc
            pkg-config
            python3
            ethtool
            iproute2
            libnl
            perl
            udev

            gnumake
            gcc
            kernel.dev
          ];

          KERNEL_SRC = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
        };
      }
    );
}
