# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Sys::Mmap, please report it
responsibly.

- **Email**: Report via the [CPAN Security Group](https://security.metacpan.org/)
  at cpan-security@perl.org
- **GitHub**: Open a [security advisory](https://github.com/cpan-authors/Sys-Mmap/security/advisories/new)
  on the repository (private by default)

Please do **not** open a public GitHub issue for security vulnerabilities.

## Scope

Sys::Mmap provides low-level memory mapping via the POSIX `mmap` system call.
Misuse of the API (invalid addresses, double-munmap, use-after-munmap) can
cause segfaults. These are documented behaviors, not security vulnerabilities.
Reports should concern unexpected memory safety violations or privilege
escalation in normal usage.

## Response

We aim to acknowledge reports within 7 days and provide a fix or mitigation
plan within 30 days.
