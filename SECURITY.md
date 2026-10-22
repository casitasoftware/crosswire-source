# Security Policy

## Supported Versions

Only the current release receives security updates. Crosswire is developed by a
single maintainer and does not backport fixes to older versions.

| Version                    | Supported          |
| -------------------------- | ------------------ |
| Current release            | :white_check_mark: |
| Any earlier release        | :x:                |

The current release is whatever is published at
[casitasoftware.com](https://casitasoftware.com). Crosswire updates itself through Sparkle,
so if you have left automatic updates on you are already on it. If you are not,
update before reporting: the issue may already be fixed.

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Email **security@casitasoftware.com** with the subject line `[Crosswire] Security Vulnerability`.
Include a description of the issue, steps to reproduce, and any relevant logs or screenshots.

You can expect an acknowledgement within 48 hours. We will keep you informed as we
investigate and will let you know when a fix is released or if we determine the report
is out of scope.

Crosswire runs Windows software on macOS using Wine. Security reports most relevant to
this project include:

- Sandbox or privilege escalation issues in the engine installation or update flow
- Signature verification bypass in the engine manifest (Ed25519 / SHA-256 checks)
- Path traversal or arbitrary file write during engine extraction
- Issues in bottle isolation that could allow a Windows process to affect the host system

Reports for vulnerabilities in Wine itself should be directed upstream to the
[Wine project](https://www.winehq.org/security).
