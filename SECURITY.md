# Security Policy

## Supported Versions

Only the latest release of Nookisle is supported with security updates.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No |

## Reporting a Vulnerability

Please report suspected security vulnerabilities privately using [GitHub Private Vulnerability Reporting](https://github.com/bavanchun/nookisle/security/advisories/new).

Do not open a public issue, pull request, or discussion for security reports.

Nookisle is maintained by a single person on a best-effort basis. There is no formal SLA or guaranteed response timeline, but reports will be reviewed and addressed as promptly as possible.

## Scope

The following components and surfaces are in scope:
- Shipped helper binaries in `libexec/` (`nookisle-helper`, `nookisle-artwork-decoder`, `nookisle-artwork-fetch`, `nookisle-spectrum`, `nookisle-media-keys`).
- Native messaging host (`nookisle-native-host`) and its local UNIX domain socket.
- Installation, removal, and state paths (`~/.config/nookisle`, `~/.local/state/nookisle`, and `$XDG_RUNTIME_DIR/nookisle*`).

For boundaries, sandboxing, and data handling details, see [Privacy and permissions](README.md#privacy-and-permissions).
