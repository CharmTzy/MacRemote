# Contributing to Mac Remote

Thanks for helping improve Mac Remote. The project favors small, focused
changes that preserve its local-only, encrypted design.

## Development setup

1. Install Xcode 15 or later and XcodeGen.
2. Clone the repository.
3. Choose unique bundle identifiers in `project.yml` if you will use physical
   devices.
4. Run `xcodegen generate` and open `MacRemote.xcodeproj`.
5. Grant Screen Recording and Accessibility only to builds you trust.

## Before opening a pull request

- Explain the user problem and the intended behavior.
- Keep unrelated formatting or refactors out of the change.
- Run the shared test suite:

  ```bash
  xcodebuild test \
    -project MacRemote.xcodeproj \
    -scheme MacRemoteHost \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO
  ```

- Build both the macOS and iOS targets.
- Add tests for protocol, geometry, crypto, or state-machine changes.
- Never commit signing certificates, provisioning profiles, device IDs,
  private keys, pairing codes, IP addresses, or captured user content.

## Security reports

Do not open a public issue for a vulnerability that could expose screen,
input, pairing, or cryptographic data. Follow the private-reporting guidance
in [SECURITY.md](SECURITY.md).

By contributing, you agree that your contribution will be licensed under the
project's [MIT License](LICENSE).
