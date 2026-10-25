# OpenCode CLI Setup v1.0.0

The first public release of OpenCode CLI Setup, an independent Windows utility for installing, updating, detecting, and uninstalling OpenCode CLI.

## Highlights

- Guided install/update workflow for stable CLI 2 and CLI 1 versions.
- Official-source downloads with integrity checks when published, archive validation, executable checks, and version verification.
- Rollback attempt if replacing an existing executable fails.
- Installation discovery and a deeper all-drive scan.
- Optional user-level `PATH` integration.
- Offline logic tests and repository documentation.

## Requirements

- Windows x64
- Windows PowerShell 5.1 or newer
- HTTPS access to official release sources for install/update

## Important notes

- This utility manages the OpenCode CLI only, not OpenCode Desktop.
- The downloaded executable's code signature is not currently checked.
- Read `README.md` for installation, usage, limitations, and troubleshooting.
