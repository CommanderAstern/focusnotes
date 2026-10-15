# Contributing

Thanks for considering a contribution to focusnotes. The project targets macOS 14 or later and uses Swift 6.4. For substantial changes, open a GitHub issue first to agree on scope.

## Before submitting

- Keep each change focused and explain the problem it solves.
- Include or update checks for behavior that changes.
- Do not include secrets, signing credentials, private notes, screenshots or captures from your own vault, downloaded model files, or build output.
- Do not copy code or assets from another project unless you have the right to contribute them. Preserve their license and attribution notices.

## License and third-party material

The project is licensed under the MIT License in the root `LICENSE` file. MIT permits commercial use, modification, redistribution, sublicensing, and sale, provided that the copyright and permission notices remain with all copies or substantial portions of the software.

Some included and downloaded components have their own licenses and attribution requirements. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); the root MIT license does not replace those upstream terms.

By submitting a contribution, you confirm that you created it or have permission to submit it, and you agree to license it under the same MIT License as the project. You retain copyright in your contribution; no separate contributor license agreement or copyright assignment is required. If an employer or another rights holder owns the contribution, obtain authorization before submitting it.

## Build and checks

Run the checks that cover your change from the repository root:

```sh
swift build
swift run CoreChecks
swift run OverlayGallery --check
scripts/check-name.sh
bash scripts/test-app-path-safety.sh
```

The checks do not require Accessibility or Screen Recording permissions. For changes to capture behavior that depend on macOS privacy permissions or focus handling, also consult the manual steps in [`docs/manual-tests.md`](docs/manual-tests.md) and describe what you verified. `scripts/build-app.sh` builds the app bundle without installing or launching it.

For CaptureKit changes, run `swift run CaptureChecks`. For semantic-search changes, follow the model-backed `EmbedChecks` procedure in [`docs/semantic-search.md`](docs/semantic-search.md); it uses the optional downloaded models and runtime.

In a pull request, describe the behavior changed, the checks you ran, and any manual checks that need a signed macOS host.

## Security reports

See [SECURITY.md](SECURITY.md) for the project's security scope and vulnerability reporting guidance. Do not post vulnerability details, exploit code, or sensitive reproduction steps in a public issue or pull request.
