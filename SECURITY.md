# Security Policy

## Supported release

Security reports are welcome for the latest published release of OpenCode CLI Setup. Older releases may not receive fixes.

## Reporting a vulnerability

Please do **not** publish exploitable vulnerability details in a public issue. Contact the repository owner privately through the contact method listed on the GitHub profile or repository page. Include:

- A concise description and potential impact.
- Reproduction steps and affected version.
- Relevant logs or screenshots with secrets and personal information removed.
- A suggested mitigation, if known.

Please allow reasonable time to investigate before public disclosure. Do not include API keys, authentication tokens, or private user data in a report.

## Security design notes

The installer validates downloads and archive paths, prefers published integrity metadata, and attempts to restore the prior executable if replacement fails. These safeguards reduce risk but do not guarantee that downloaded software is safe. The installer does not currently verify the downloaded executable's code signature.
