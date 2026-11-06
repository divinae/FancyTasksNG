## What does this PR do?

<!-- Short description of the change and why it's needed. Link related issues, e.g. "fixes #123". -->

## How was this tested?

<!-- e.g. `make preview` or `make update` on Plasma 6.x, Wayland/X11, `make test` for the helper, or manual steps. -->

## Checklist

- [ ] Tested locally (`make preview`, or `make update` if the change needs the real panel) and `make test` passes
- [ ] Ran `qmllint` on changed `.qml` files - no new warnings
- [ ] Updated `CHANGELOG.md` under `[Unreleased]` if this is a user-visible change
- [ ] New/changed UI strings use `Wrappers.i18n(...)`, not hardcoded text
- [ ] Targets Plasma 6.5+ / Qt6 (no `PlasmaCore` or other deprecated APIs)
