# Mac Switch

![Mac Switch overview](docs/images/dashboard.png)

## [Download Latest Release](https://github.com/%69%54%76%58/mac-switch/releases/latest)

Download the current notarized Mac Switch build from GitHub Releases.

Mac Switch is a native macOS menu bar utility for the small system controls you reach for every day. Keep the app tucked away in the menu bar, open one compact panel, and toggle common Mac actions without digging through System Settings.

## Highlights

- Fast access to essential Mac toggles from one menu bar panel.
- Real system actions, not placeholder UI.
- Customizable dashboard visibility and drag-to-reorder menu items.
- Lightweight native SwiftUI/AppKit app built for macOS 14 and later.
- Source published for transparency and review, not as a public build or redistribution guide.

## Controls

Mac Switch currently includes:

| Everyday toggles | System utilities |
| --- | --- |
| Keep Awake | Screen Saver |
| Stage Manager | Display Sleep |
| Hide Widgets | Screen Resolution |
| Mute Microphone | Screen Cleaning |
| Hide Desktop Icons | Lock Keyboard |
| Dark Mode | Lock Screen |
| Bluetooth Audio | Xcode Cache Clean |
| Do Not Disturb | Empty Trash |
| Night Shift | Eject Disk |
| True Tone, when available | Empty Pasteboard |
| Play Music | Hide Windows |
| Show Hidden Files | Hide Dock |
| Low Power Mode | Energy Mode |

Software Update checks are included for official builds distributed through the app's update feed.

## Customize

![Mac Switch customize preferences](docs/images/preferences.png)

Choose which switches appear in the menu, hide what you do not use, and drag visible menu items directly in the dashboard to match your workflow. Preferences include General, Customize, and About panels, with per-switch options where a control needs extra setup.

## Permissions

Mac Switch only asks for macOS permissions needed by the features you use:

- Apple Events: Dark Mode, Play Music, Empty Trash, and fallback Lock Screen actions.
- Accessibility/Input Monitoring: Lock Keyboard and Screen Cleaning event suppression.
- Bluetooth: paired audio device listing and connection.
- Location: sunrise/sunset Dark Mode scheduling.

## Official Releases

Official downloads are published through the repository's GitHub Releases and the in-app update feed. The public source tree is intended to let users inspect what the app does; it is not permission to publish alternate builds, package-manager releases, app-store submissions, forked editions, or third-party update feeds.

## License

Mac Switch is source-available under the Mac Switch Source Available License 1.0. You may inspect the source for review and personal understanding. Commercial use, redistribution, binary releases, app-store submissions, package-manager distribution, publishing forked or rebranded versions, and operating an update feed require prior written permission from the copyright holder.

See [LICENSE](LICENSE).

## Trademark Notice

Apple, Mac, macOS, Stage Manager, Night Shift, and True Tone are trademarks of Apple Inc., registered in the U.S. and other countries and regions. Mac Switch is not affiliated with or endorsed by Apple Inc.
