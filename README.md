# SST OpenCode Wrapper for NixOS

A robust, self-updating Nix flake for [SST OpenCode](https://opencode.ai/). This wrapper automatically fetches the latest release, patches it for NixOS compatibility (using Musl), and runs it seamlessly.

## Features

*   **Auto-Updating**: Checks the latest GitHub release on every run. If a new version is available, it downloads and patches it automatically.
*   **NixOS Native**: Fixes `DT_RPATH` and interpreter paths using `patchelf`, ensuring the binary runs without FHS emulation or Docker.
*   **Musl-Based**: Uses the `musl` build of OpenCode to avoid Glibc ABI incompatibilities and missing shared libraries (like `libstdc++` or `openssl` mismatches).
*   **Zero Config**: Just run it. The binary is managed in `/tmp/opencode` to keep your store clean and updates fast.

## Usage

### 1. Run Directly (Ad-Hoc)

You can run the latest version immediately without installing anything:

```
# Run the tool (arguments are passed through)
nix run github:yourusername/oc-bin-flake -- --help

# Start the agent
nix run github:yourusername/oc-bin-flake -- start
```

### 2. Install via NixOS Configuration

Add the flake to your system configuration to make the `opencode` command available globally.

**`flake.nix`**

```
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Add the input
    opencode.url = "github:yourusername/oc-bin-flake";
  };

  outputs = { self, nixpkgs, opencode, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          # Add to system packages
          environment.systemPackages = [ 
            opencode.packages.x86_64-linux.default 
          ];
        })
      ];
    };
  };
}
```

After rebuilding, simply type:

```
opencode start
```

## How It Works

1.  **Wrapper Script**: The package installs a shell script wrapper named `opencode`.
2.  **Version Check**: On execution, it queries the GitHub API for the latest tag and compares it against the installed binary in `/tmp/opencode`.
3.  **Patching**: 
    *   If an update is needed, it downloads the `linux-x64-musl` tarball.
    *   It sets the ELF interpreter to `ld-musl-x86_64.so.1`.
    *   It sets the `RPATH` to include `pkgs.musl` and `pkgs.pkgsMusl.stdenv.cc.cc.lib` (Musl-compatible `libstdc++`).
4.  **Execution**: Finally, it `exec`s the binary, passing all user arguments transparently.

## Troubleshooting

**"Existing binary is broken. Forcing update."**
The wrapper automatically detects if the current installation segfaults or fails to run ` --version`. It will force a re-download on the next run to fix itself.

**Why Musl?**
The standard Glibc release of OpenCode often segfaults on NixOS due to mismatches in system libraries (OpenSSL, ICU, Libstdc++). The Musl build is statically linked for most things and only requires a clean `musl` runtime, which we provide via Nix.
```

[1](https://github.com/nixvital/flake-templates)
[2](https://github.com/liyangau/flake-templates)
[3](https://flakestry.dev/flake/github/akirak/flake-templates)
[4](https://www.reddit.com/r/NixOS/comments/173cb1p/kickstartnixnvim_a_simple_nix_flake_template_for/)
[5](https://thenegation.com/posts/nix-flake-templates/)
[6](https://heywoodlh.io/nix-deployments-everywhere)
[7](https://discourse.nixos.org/t/devos-template-repo-for-nixos-configurations-using-flakes/5325)
[8](https://github.com/mrcjkb/flakes)
[9](https://dev.to/arnu515/getting-started-with-nix-and-nix-flakes-mml)
[10](https://gitlab.sintef.no/nix-flakes/gtsam/-/blob/e11f564c7d42c42060c3a715ae015f1b4943c329/cmake/example_project/README.md)
