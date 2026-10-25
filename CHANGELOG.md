# Changelog

All notable project changes are documented here. This project follows a simple versioned release history.

## [1.0.0] - 2026-10-25

### First public release

- Publish the Windows installer, updater, uninstaller, and installation discovery workflow.
- Support stable OpenCode CLI 2 and CLI 1 release selection from official sources.
- Validate package integrity where published, archive paths, executable architecture, and version output.
- Add rollback handling for failed executable replacement.
- Include offline logic tests and public project documentation.
- Establish the project identity, attribution, and repository contribution/security guidance.

### Notes

- This release targets Windows x64 and built-in Windows PowerShell 5.1 or newer.
- The CLI executable's code signature is not checked.
