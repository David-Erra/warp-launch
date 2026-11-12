# Changelog

Published versions of Warp Launch. Versions in between were never published: their changes are listed under the next
published one. Dates are when the version was published on GitHub.

## Unreleased

- The app speaks 10 languages: Catalan, English, Spanish, French, German, Italian, Brazilian Portuguese, Japanese,
  Simplified Chinese and Korean. It follows the language of your Mac, and you can choose another one in Settings.
  English is used when your Mac's language isn't one of them. (In progress.)

## 0.34.0

- **Tabs without Claude are no longer opened twice.** A terminal-only tab opened by Warp Launch is recognized while
  its shell is alive, so opening the window again doesn't duplicate it. After a restart, or once you close it, it opens
  again as before.
- `warp-launch obre <window> --obre` has been tested with real windows.

## 0.33.0 — 2026-11-11

- **Automatic updates.** Once a day the app checks GitHub for a new version, downloads it, verifies its signature and
  restarts by itself when you aren't using the Mac or the app. Warp and your Claude sessions are never touched.
  **Settings › Updates** shows the status, has **Check Now**, and lets you turn it off. GitHub sees your IP address and
  the app version: it's the app's only network connection.
- Copies at 0.31.5 or earlier need one last manual update (see the README).
- The same command has the same name in every menu ("Refresh Warp Status").

## 0.31.5 — 2026-11-09

- When Warp and Claude disagree about a tab's folder and Claude is running, Claude's folder wins, with a note to review.
- Importing again leaves tabs without a running Claude as terminal-only.
- "Open" creates `~/.warp/launch_configurations` when it's missing.
- The open sheets warn that closing Warp can leave Claude's background jobs unfinished.

## 0.31.4 — 2026-11-09

- **Your permission first.** Before touching Warp's "Restore windows, tabs, and panes on startup" setting, the app
  explains why and asks. Without it, the app doesn't read or open anything.
- **Restore Warp and Quit…** (Settings › General) puts Warp's setting back as it was and removes the app from Login Items.
- New configurations leave tabs without Claude as terminal-only.
- Warp Stable can live in any folder; Warp Preview isn't supported, and the app says so.
- A read-only **diagnostic** (Settings › General, or `warp-launch diagnostica`) checks that Warp and Claude Code still
  have the formats the app reads.
- Settings split into "General" and "New Tabs".
- Safer handling of `~/.warp/settings.toml`: the app never edits it while Warp is writing it, and refuses anything
  ambiguous.

## 0.28.0 — 2026-11-07

- First public version: read, edit and reopen Warp windows and tabs, each with its Claude Code session; open everything
  at login with one click.
- New tabs start Claude without skipping permissions and without ultracode; both can be turned on in Settings or per tab.
