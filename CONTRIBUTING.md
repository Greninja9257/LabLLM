# Contributing to LabLLM

Thanks for helping make LabLLM better. Small, focused contributions are easiest to review and the most likely to land quickly.

## Good First Contributions

- Fix a crash or confusing error message.
- Improve dataset import behavior.
- Add a training recipe.
- Improve documentation or images.
- Polish a rough UI state.
- Add a focused test or reproducible bug case.

## Before You Open a Pull Request

1. Check existing issues and pull requests so you do not duplicate work.
2. Open an issue for larger changes before writing a big patch.
3. Keep the PR focused on one thing.
4. Build locally with:

```bash
swift build
```

5. Explain what changed, why it changed, and how you tested it.

## Development Notes

- macOS 14+ and Apple Silicon are the target environment.
- The app uses SwiftUI and Apple's MLX through `mlx-swift`.
- Keep Simple mode beginner-friendly. It should hide complexity, not remove useful workflows.
- Avoid adding cloud requirements. LabLLM should remain useful without an account.
- Be careful with generated release artifacts. `dist/` is ignored and should not be committed.

## All Contributors

This repo follows the [All Contributors](https://allcontributors.org/) specification. If you contribute code, docs, design, tests, ideas, bug reports, tutorials, or review help, you can be credited.

To add a contributor with the CLI:

```bash
npx all-contributors add USERNAME code,doc,ideas
npx all-contributors generate
```

You can also ask in your pull request and a maintainer can add you.

## Pull Request Checklist

- [ ] The change is focused and explained.
- [ ] `swift build` passes, or the reason it cannot run is documented.
- [ ] UI changes include an image or short recording when useful.
- [ ] New behavior is documented where users would expect to find it.
- [ ] You added yourself to All Contributors, or asked a maintainer to do it.
