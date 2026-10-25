# Contributing

Thank you for helping improve OpenCode CLI Setup. Changes should preserve the installer's safety checks, predictable behavior, and compatibility with Windows PowerShell 5.1.

## Before opening a change

1. Search existing issues to avoid duplicate reports.
2. Describe the problem, expected behavior, and a reproducible example.
3. Keep pull requests focused and explain any compatibility or security implications.
4. Do not include credentials, access tokens, private URLs, user data, or local machine paths.

## Development guidelines

- Preserve Windows PowerShell 5.1 compatibility unless a deliberate compatibility change is proposed and documented.
- Keep `OpenCode-CLI-Setup.bat` and `OpenCode-CLI-Setup.ps1` side-by-side.
- Keep `Test-OpenCodeSetup.ps1` in the repository root unless its path assumptions are updated and tested.
- Prefer small, reviewable changes. Do not weaken download validation, trusted-host checks, archive path checks, rollback behavior, or uninstall safeguards to make a test pass.
- Update `README.md` and `CHANGELOG.md` when user-visible behavior changes.
- Run `Test-OpenCodeSetup.ps1` on Windows PowerShell 5.1 when possible and report the exact environment and result.

## Pull requests

Include the reason for the change, a concise summary, test results, and any remaining limitations. For UI or terminal changes, include a screenshot or terminal capture when practical.

By submitting a contribution, you agree that your contribution may be distributed under the project's MIT License. You retain ownership of your contribution.
