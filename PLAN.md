# Plan: minimal macOS menu bar Pomodoro timer

A native app that lives only in the macOS menu bar. It has no Dock icon and no main window. Every feature below traces back to a research finding (see [Research](#research-what-makes-a-pomodoro-timer-good)). Anything without research behind it is a design guess and is labelled as one.

## Goals

- Start a focus block in one click or one hotkey.
- Keep breaks on a fixed schedule by default. This is the main thing a timer adds compared with no timer.
- Stay out of the way during focus: no mid-block notifications or nags.
- Make it easy to pick work back up after a break.
- Stay small: no account, no cloud, no telemetry.

## Non-goals (for v1)

- Task management or project tracking
- Sync or iOS app
- Detailed analytics or charts
- App Store distribution

## Research: what makes a Pomodoro timer good

The evidence is thinner than productivity blogs suggest. Most of the studies are small and use self-reported measures from students. What it does support:

| Finding | Source | What it means for the app |
|---|---|---|
| Fixed breaks (Pomodoro 24/6 and 12/3) gave lower fatigue and distraction, and higher concentration and motivation, than self-chosen breaks. Task completion was the same, reached in less time. People who chose their own breaks worked in longer stretches. | Biwer et al. 2023, *Br J Educ Psychol*, n=87 | Breaks start automatically by default. Extending a focus block is possible but limited. |
| A later preprint found Pomodoro fatigue rose faster than with self-regulated breaks, again with no difference in output. | Preprint 2025 (Pomodoro vs Flowtime vs self-regulated, n=94) | The evidence is mixed, so durations must be configurable and no single preset should be presented as "optimal". |
| Micro-breaks of 10 minutes or less have small effects on vigor (d≈.36) and fatigue (d≈.35), but no significant effect on performance overall. Longer breaks predicted better performance, and very demanding tasks may need breaks longer than 10 minutes. | Albulescu et al. 2022, *PLOS ONE* meta-analysis, 22 samples, N=2,335 | Ship a 50/10 preset next to 25/5. The long break after 4 rounds defaults to 20 minutes. |
| Breaks spent on a smartphone did not improve mood, while breaks without a phone did. | Rhee & Kim 2016 (survey, n≈400) | The break screen suggests leaving the screen: stand up, look away, walk. It never suggests "check messages". |
| After an interruption, people took about 25 minutes on average to get back to the task, with very large variance. Self-interruptions were about as common as external ones. | Mark, Gonzalez & Harris 2005; Mark, Gudith & Klocke 2008 | The app sends nothing during focus. The block-end alert is the only interruption it makes. |
| Unfinished goals cause intrusive thoughts. Writing down a concrete plan for them removes the interference, without needing to finish them. | Masicampo & Baumeister 2011, *JPSP* | Add a "parking lot" for stray thoughts during focus, plus a "next step" note at block end to make resuming easier. |

Design guesses with no research behind them:

- Showing a live seconds countdown may encourage clock-watching. The default menu bar text shows minutes only, and there is an option to show just an icon.
- A soft chime is less jarring than an alarm. The sound is configurable and can be turned off.

## Features

### v1 (MVP)

1. **Menu bar item.** It shows a state icon and minutes remaining (`25m`, then `24m`, …). Clicking it opens a small popover.
2. **Timer cycle.** Focus → short break, repeated, with a long break after N rounds. All durations are configurable.
   - Presets: **25/5** (classic), **50/10** (deep work), and custom.
   - Defaults: 25/5, long break 20 minutes after 4 rounds.
3. **Controls.** Start, pause, resume, skip, and reset.
4. **Automatic breaks.** When a focus block ends, the break starts by itself. A single **"+5 min"** extension is allowed once per block, which leaves room for flow without slipping back into self-regulated breaks.
5. **End-of-block notification.** One macOS notification and an optional chime. The break notification includes a suggestion to step away from screens.
6. **Today counter.** Number of completed focus blocks today. It resets at midnight.
7. **Keyboard shortcut.** A global hotkey to start or pause (default ⌥⌘P).
8. **Launch at login.** Optional.

### v1.1

- **Parking lot.** A text field in the popover, also reachable by hotkey, for capturing a distracting thought without leaving focus. Items appear at the next break.
- **"Next step" prompt.** At the end of a focus block, an optional one-liner: "What's the next thing to do?" It is shown again when the next block starts.
- Icon-only display mode.

### Later / maybe

- Toggle macOS Focus / Do Not Disturb during blocks, via Shortcuts.
- Simple weekly history.

## Technical design

- **Language/UI:** Swift 5.10 and SwiftUI. Uses `MenuBarExtra` with `.window` style.
- **Target:** macOS 14 Sonoma or later (matches the dev machine; Xcode 15.3).
- **No Dock icon:** `LSUIElement = YES` in Info.plist.
- **Build:** a Swift Package, plus a `scripts/bundle.sh` that wraps the binary into `PomodoroBar.app` with an Info.plist and a bundle id. Notifications need a real `.app` bundle. This setup keeps the repo diffable and buildable from the CLI, with no `.xcodeproj` churn.
- **Timer accuracy:** store the block's **end `Date`**, not a tick counter. The UI refreshes from a 1-second `Timer` but always computes `end - now`. This stays correct across sleep, wake, and App Nap.
- **State machine:** `idle → focus ⇄ paused → break(short|long) → focus …`, kept as one pure `TimerEngine` struct so it can be unit-tested without UI.
- **Persistence:** `UserDefaults` for settings, today's count, and the current block (so a running timer survives an app restart).
- **Notifications:** `UserNotifications` (`UNUserNotificationCenter`). Permission is requested on first start.
- **Sound:** `NSSound` with a bundled soft chime.
- **Hotkey:** a small Carbon `RegisterEventHotKey` wrapper, or the `KeyboardShortcuts` package (decide in M3).
- **Launch at login:** `SMAppService.mainApp`.

### Layout

```
Sources/PomodoroBar/
  PomodoroBarApp.swift     // @main, MenuBarExtra
  TimerEngine.swift        // pure state machine
  TimerController.swift    // ObservableObject: ticking, persistence, notifications
  Settings.swift           // durations, presets, toggles
  Views/PopoverView.swift
  Views/SettingsView.swift
Tests/PomodoroBarTests/
  TimerEngineTests.swift
scripts/bundle.sh
Resources/Info.plist, chime.aiff
```

## Milestones

1. **M1 – Skeleton.** SwiftPM project, menu bar item, `TimerEngine` with tests, start/pause/reset, live countdown.
2. **M2 – Cycle and alerts.** Short and long breaks, automatic breaks, notifications and chime, "+5 min" extension.
3. **M3 – Settings.** Presets and custom durations, global hotkey, launch at login, today counter.
4. **M4 – Resumption aids (v1.1).** Parking lot, next-step note, icon-only mode.
5. **M5 – Ship.** `bundle.sh` into a `.app`, README install steps, GitHub Release with a zipped app (unsigned at first; notarization later if wanted).

## Open questions

- App name (working name: **PomodoroBar**).
- License (MIT?).
- Sign and notarize with an Apple Developer account, or ship unsigned (users right-click → Open the first time)?

## References

- Biwer, F., et al. (2023). Understanding effort regulation: Comparing 'Pomodoro' breaks and self-regulated breaks. Br J Educ Psychol, 93(2), 353–367. doi:10.1111/bjep.12593 https://cris.maastrichtuniversity.nl/en/publications/understanding-effort-regulation-comparing-pomodoro-breaks-and-sel
- Pomodoro vs Flowtime vs self-regulated breaks (preprint, 2025). https://www.preprints.org/manuscript/202503.0845/v1
- Albulescu, P., et al. (2022). "Give me a break!" A systematic review and meta-analysis on the efficacy of micro-breaks. PLOS ONE. https://doaj.org/article/c6f37b6ba159469296b2cb968b65505f
- Rhee, H., & Kim, S. (2016). Smartphone use during lunch breaks. Summary: https://www.psychologicalscience.org/news/minds-business/why-you-should-break-up-with-your-smartphone-during-lunch-breaks.html
- Mark, G., Gudith, D., & Klocke, U. (2008). The cost of interrupted work: more speed and stress. CHI. https://scienceblog.com/t-23-minutes-return-focus-after-interruption/
- Masicampo, E. J., & Baumeister, R. F. (2011). Consider it done! Plan making can eliminate the cognitive effects of unfulfilled goals. JPSP, 101(4), 667–683.
