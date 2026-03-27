# Contributing to Sys::Mmap

Thank you for considering contributing to Sys::Mmap!

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork and create a topic branch
3. Build and test:

```sh
perl Makefile.PL
make
make test
```

## Submitting Changes

- Open a pull request against the `main` branch
- Include a clear description of what the change does and why
- Add or update tests for any behavior changes
- Keep commits focused — one logical change per commit

## Reporting Bugs

Please open an issue on the
[GitHub issue tracker](https://github.com/cpan-authors/Sys-Mmap/issues).

For security vulnerabilities, see [SECURITY.md](SECURITY.md).

## Code Style

- Follow existing code conventions in Mmap.xs and Mmap.pm
- Use ANSI C function declarations (no K&R style)
- Add POD documentation for new public API

## License

By contributing, you agree that your contributions will be licensed under the
same terms as Perl itself. See the [Artistic](Artistic) and [Copying](Copying)
files.
