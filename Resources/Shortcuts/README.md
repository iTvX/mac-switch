# Do Not Disturb helpers

These readable property lists are the source for the two app-specific shortcuts.
`Scripts/build_release.sh` signs them with Apple's `shortcuts sign --mode anyone`
and bundles the signed installers. Re-signing each release avoids shipping an
expired shortcut certificate. No external download service is required at setup.

The workflows take optional text input. Nonempty input requests a read-only
Current Focus query; no input sets Do Not Disturb to the helper's explicit target.
They return `mac-switch-dnd-v1|enable|<Focus name>` or the `disable` equivalent.
An empty name means no Focus is active. The app calibrates the localized DND name
with an enable/disable round trip before allowing normal use. It refuses to
replace a different active Focus because the Mode model cannot restore that mode.

Both branches use **Stop and Output**. Implicitly returning a final Text action
can leave `shortcuts run` running after the workflow finishes on macOS 26.
Conditional inputs use a Variable wrapper; output text uses WFTextTokenString.
Keep these native serialization shapes when editing the property lists.

For live validation on an interactive Mac, install both signed helpers with
Focus off and run:

```sh
MAC_SWITCH_LIVE_DND_TEST=1 swift test --filter DoNotDisturbBehaviorTests/testLiveModeActivationAndRestoration
```

This verifies setup and Mode activation/restoration with DND initially off and
initially on, then leaves DND off. Normal test runs do not change system Focus.
