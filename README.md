# SST OpenCode Wrapper for Nix

A self-updating, cross-platform wrapper for [SST OpenCode](https://opencode.ai/) that runs seamlessly on **NixOS (x86_64 & aarch64)** and **macOS (Apple Silicon & Intel)**.

It solves common binary compatibility issues on NixOS (segfaults, missing libraries) by automatically patching the correct interpreter and RPATH, and handles native `.zip` extraction on macOS.

## Quick Start

### Method 1: Run Immediately (No Install)

Use `nix run` to launch the tool instantly. It will fetch the latest version, patch it, and run it.

```bash
# Launch OpenCode
nix run github:bogorad/oc-bin-flake --refresh

# Pass any arguments directly
nix run github:bogorad/oc-bin-flake --refresh -- --help
```

### Method 2: Install System-Wide

Add the flake to your NixOS configuration to install `opencode` as a global command.

**`flake.nix`**:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    opencode.url = "github:bogorad/oc-bin-flake";
  };

  outputs = { self, nixpkgs, opencode, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux"; # or aarch64-linux
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            opencode.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

After rebuilding (`nixos-rebuild switch`), simply run:

```bash
opencode
```

---

## How It Works

This flake acts as a **smart shim** that lives between you and the upstream binary. It ensures you are always running the latest version while maintaining strict compatibility with your OS.

### 1. Auto-Update Logic

On every execution, the wrapper:

1.  Checks the installed version in `${XDG_CACHE_HOME:-$HOME/.cache}/oc-bin-flake/opencode`.
2.  Queries the GitHub API for the latest release tag.
3.  If the versions differ (or if the local binary is broken), it downloads the correct asset for your architecture:
    - **x86_64-linux**: `opencode-linux-x64-musl.tar.gz`
    - **aarch64-linux**: `opencode-linux-arm64-musl.tar.gz`
    - **Darwin (macOS)**: `opencode-darwin-arm64.zip` or `opencode-darwin-x64.zip`

### 2. NixOS Compatibility (The "Musl Fix")

Standard binaries often segfault on NixOS due to glibc mismatches. This wrapper solves this by:

- **Using Musl**: On Linux, it downloads the **musl** static build of OpenCode.
- **Patching Interpreter**: It uses `patchelf` to set the ELF interpreter to the `musl` dynamic loader provided by Nix (`ld-musl-x86_64.so.1`).
- **Fixing RPATH**: It injects the correct paths for `musl` and `libstdc++` (compiled against musl) directly into the binary.

### 3. macOS Support

On Darwin, the wrapper detects it is not on Linux and skips `patchelf`. Instead, it handles the `.zip` extraction natively using `unzip`, ensuring a unified experience across all your machines.

## Troubleshooting

- **"Update required: none -> v1.0.98"**: This is normal on the first run or if the binary was deleted from `${XDG_CACHE_HOME:-$HOME/.cache}/oc-bin-flake/opencode`.
- **Download Hangs**: Ensure you have internet access. The script uses `curl` with a 5-second connection timeout.
- **Architecture Errors**: The flake strictly maps your Nix system (e.g., `aarch64-linux`) to the specific upstream asset. If you are running through Rosetta or QEMU, ensure your Nix system string matches the binary you expect to run.

[1](https://github.com/nixvital/flake-templates)
[2](https://flakestry.dev/flake/github/akirak/flake-templates)
[3](https://github.com/NixOS/templates)
[4](https://thenegation.com/posts/nix-flake-templates/)
[5](https://www.brokenpip3.com/posts/2024-19-03-flake-template-git-repo/)
[6](https://mynixos.com/flake-parts)
[7](https://aige.eu/posts/reproducible-development-environments-with-nix-flakes/)
[8](https://www.reddit.com/r/NixOS/comments/173cb1p/kickstartnixnvim_a_simple_nix_flake_template_for/)
[9](https://git.lerch.org/lobo/nix-flake-examples/src/branch/master/README.md)
[10](https://discourse.haskell.org/t/haskell-nix-template/2585)
