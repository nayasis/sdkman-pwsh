# SDKMAN! for PowerShell

English | [한국어](README.ko.md)

A PowerShell port of [SDKMAN!](https://sdkman.io) for managing SDK versions on Windows without bash or Cygwin.

- Supports Windows PowerShell 5.1 and PowerShell 7+.
- Uses the official SDKMAN API and can share an existing `~/.sdkman` directory.
- Includes tab completion and project environments via `.sdkmanrc`.

## Install

```powershell
git clone https://github.com/nayasis/sdkman-pwsh.git
cd sdkman-pwsh
.\install.ps1
```

Use `-SdkmanDir <path>` to specify the installation directory.

- Defaults to `$env:SDKMAN_DIR` or `~/.sdkman`.

If installation fails due to the execution policy, run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Usage

```powershell
sdk list                        # List SDKs
sdk list java                   # List available Java versions
sdk install java                # Install the recommended version
sdk use java <version>          # Switch for the current shell
sdk default java <version>      # Set the default for new shells
sdk current                     # Show active versions
sdk uninstall java <version>    # Remove a version
sdk help                        # Show all commands
```

Replace `<version>` with an identifier from `sdk list java`. To register a local SDK, use `sdk install java 17-local C:\jdks\jdk-17`.

Pin SDK versions for a project:

```powershell
sdk env init       # Create .sdkmanrc from active versions
sdk env install    # Install versions listed in .sdkmanrc
sdk env            # Apply the project environment
sdk env clear      # Restore defaults
```

Commands set `$LASTEXITCODE` to `0` on success or `1` on failure. `sdk home <candidate> <version>` returns the installation path as a pipeline value.

## Configuration

Run `sdk config` to edit `~/.sdkman/etc/config`. Common settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| `sdkman_auto_answer` | `false` | Answer yes to confirmation prompts |
| `sdkman_auto_complete` | `true` | Enable tab completion |
| `sdkman_auto_env` | `false` | Apply `.sdkmanrc` when changing directories |
| `sdkman_checksum_enable` | `true` | Verify checksums provided by the API |
| `sdkman_colour_enable` | `true` | Enable colored output |

For automatic environments with Oh My Posh or Starship, place the SDKMAN `Import-Module` line after the prompt setup in your profile.

## Compatibility and updates

The port uses directory junctions for `current` and requires Windows `tar.exe` for tar archives.

If an existing Git Bash installation stores `current` as a copied directory, run `sdk default <candidate> <version>` to replace it with a junction.

`sdk selfupdate` and bash `ext/` scripts are unsupported. Update the checkout and rerun `.\install.ps1` to update the module.

## Uninstall

Run `.\uninstall.ps1` to remove the module and profile setup while keeping installed SDKs.

Add `-RemoveSdkmanDir` to delete the entire SDKMAN directory, including SDKs, configuration, and caches.

## Tests

The smoke test installs, switches, and removes Apache Ant through the live API in a temporary `SDKMAN_DIR`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Sdkman.ps1
pwsh -NoProfile -File tests\Test-Sdkman.ps1
```
