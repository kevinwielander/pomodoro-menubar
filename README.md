# PomodoroBar

A minimal, native Pomodoro timer for the macOS menu bar. Its defaults come from research on breaks and interruptions; see [PLAN.md](PLAN.md) for the reasoning and sources.

- Lives only in the menu bar (no Dock icon), showing minutes left
- 25/5 and 50/10 presets plus custom durations; long break after N rounds
- Breaks start automatically; a focus block can be extended by 5 min once
- No notifications during focus, one notification and chime when a block ends
- **Parking lot** to jot down distracting thoughts without leaving focus
- **Next step** note to make it easier to resume after a break
- Global shortcut ⌥⌘P to start/pause, launch at login, today's count

Requires macOS 14 Sonoma or later.

## Install

```sh
git clone https://github.com/kevinwielander/pomodoro-menubar.git
cd pomodoro-menubar
scripts/bundle.sh --install   # builds a universal app and copies it to /Applications
open /Applications/PomodoroBar.app
```

Building needs Xcode 15.3+ (or its command line tools). The app is ad-hoc signed and not notarized.

## Develop

```sh
swift test                                   # timer engine tests
swift run                                    # run unbundled (no notifications)
scripts/bundle.sh                            # build/PomodoroBar.app
open --env POMODOROBAR_FAST=1 build/PomodoroBar.app   # minutes become seconds
```

The timer logic is a pure state machine in `Sources/PomodoroCore/TimerEngine.swift`. The app in `Sources/PomodoroBar` connects it to the clock, `UserDefaults`, notifications and the UI. Running blocks store their end date, so the timer stays correct across sleep and restarts.
