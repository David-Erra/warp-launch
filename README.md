# Warp Launch

**English** · [Català](README.ca.md)

A menu bar app for macOS that reads, edits and reopens your Warp windows and tabs, each one with its own Claude Code
session. It can open on its own when you log in and offer to open everything with one click.

**Status (November 11, 2026):** it reads Warp, edits the configuration (windows, tabs and how Claude opens in them), opens one window
or all of them in Warp and, if you turn it on, opens at login. The latest published version is 0.33.0 (November 11, 2026), the first
one that updates itself, and it installs with Homebrew. The first real automatic update will come with the next version (see
“Automatic updates”). Instructions for agents: [`CLAUDE.md`](CLAUDE.md).

## Installing it

You need a Mac with Apple silicon (M1 or later) and macOS 26 or later, an administrator account on the Mac,
[Warp](https://www.warp.dev) Stable and [Claude Code](https://docs.claude.com/claude-code). There's nothing to compile.
- **Warp Stable** in `/Applications` (since 0.29.2, in any folder: the app asks macOS where it is; since 0.31.1, if you have
  another copy open, the one that's open counts). **Warp Preview isn't supported:** if there's only Preview, or Preview is open
  and Stable isn't, the app doesn't open anything and says so. Without any Warp, it doesn't either.
- Tested on November 5, 2026 with macOS 27.2, Warp 0.2026.10.21 and Claude Code 2.1.318. It reads internal Warp and Claude Code formats
  that aren't documented, and a new version can break them: the diagnostics (“If something goes wrong”, below) tell you whether
  they still match.

1. **Install it with Homebrew.** You need [Homebrew](https://brew.sh). If you don't want to use it, see “Without Homebrew”, below.
   ```bash
   brew install --cask david-erra/tap/warp-launch
   ```
   It adds the `David-Erra/homebrew-tap` tap and trusts only this cask. It downloads the latest published version, checks its
   sha256, copies it to `/Applications` and removes its downloaded-from-the-internet mark, because it isn't notarized by Apple
   yet. It doesn't open it, doesn't register it at login and doesn't touch any configuration.
2. **Open Warp Launch** from Applications. It shows up as an icon in the menu bar (not in the Dock).
   - **The first time, your permission** (since 0.29.0): the app explains that it has to turn off the Warp setting “Restore
     windows, tabs, and panes on startup” (if you have Settings Sync, on your other Macs too) and that it will turn it on for a
     few seconds when you ask it to read Warp's windows. If you don't accept (“Quit Warp Launch”), it quits without touching
     anything and asks you again next time. Until you accept, it doesn't read or open anything. If you were already using it
     (there's a `configuracio.json` or `estat.json` in `~/.config/warp-launch/`), it doesn't ask, unless you've withdrawn the
     permission (see “Uninstalling”). Since 0.33.0, this screen also says that the app connects to GitHub once a day. Anyone who
     doesn't see it will learn it from this README and from the release notes.
   - **Permission to read Warp's data:** macOS doesn't ask; the first time, the app can't read it and a notification appears
     (“Data Access Blocked”, with a “Manage” button). Turn it on in System Settings › Privacy & Security › Files & Folders ›
     Warp Launch.app › “Data shared by Warp and affiliated apps”, and open the app again.
3. **Create the configuration:** in the editor, **Import from Warp…** with the windows you want already open in Warp.
   It's saved to `~/.config/warp-launch/`. The tabs where Claude was running keep the command it was opened with. The others
   stay terminal only (since 0.29.1; before, it opened `claude` in them): to open Claude in them, check “Open Claude Code in
   this tab” in the inspector, with the options in Settings (⌘,) › “New Tabs”. Tabs in the home folder or in a folder that no
   longer exists also stay without Claude.
4. If you want it to open on its own at login: Settings (⌘,) › General › **Open Warp Launch at login**.
   If you have “Start Warp at login” turned on in Warp, turn it off, so that Warp doesn't open on its own (in one restart, with
   that option turned off, Warp opened anyway, and it isn't known why yet).

**To update it:** `brew upgrade --cask warp-launch`. If the app is open, Homebrew quits it, puts the new version in place and
opens it again. Since 0.33.0, the app updates itself: if you have 0.31.5 or earlier, do this one last time (see “Automatic
updates”).
**To uninstall it:** see “Uninstalling”, below.

### Without Homebrew

With the GitHub tool, `gh`:

1. **Install `gh`** (only the first time), with the package from https://cli.github.com.
   Then sign in to `gh` with a GitHub account and check that it's the one shown as active:
   ```bash
   gh auth login
   gh auth status
   ```
2. **Install Warp Launch** with a single command, from any folder:
   ```bash
   s="$(gh api -H 'Accept: application/vnd.github.raw' repos/David-Erra/warp-launch/contents/scripts/instal%C2%B7la.sh)" && bash -c "$s" instal·la --github --aplica
   ```
   If you get `gh: Not Found (HTTP 404)`, `gh` can't find the repo: check the command and step 1. Don't run it with `sudo`.
   It downloads the latest published version, checks that it's signed with David's certificate (“Warp Launch Dev”) and copies it
   to `/Applications`. It doesn't open it, doesn't register it at login and doesn't touch any configuration. If the app is open,
   it stops and asks you to quit it. Without `--aplica`, it only says what it would do; with `--versio x.y.z` (for example,
   `--versio 0.28.0`), it installs a specific one. The repo has the versions from 0.28.0 on.
3. Continue with “Open Warp Launch” (step 2 above).

**To update it:** quit the app and run the command above again. Since 0.33.0, the app updates itself: if you have 0.31.5 or
earlier, do this one last time (see “Automatic updates”).

### From the source code

To build it yourself (you need `xcode-select --install`):

```bash
git clone https://github.com/David-Erra/warp-launch.git && cd warp-launch
scripts/build-app.sh             # creates “build/Warp Launch.app”; doesn't open it
scripts/instal·la.sh --aplica    # copies it to /Applications (without --aplica, it only says what it would do)
```

The first build downloads Sparkle: you need internet access, even if you only build the CLI. A copy built this way never updates
itself.

### Publishing a version (the author)

Only the author runs `--aplica`, in his own terminal; no agent does. It needs a `GH_TOKEN` from an account that can write to
`David-Erra/warp-launch` and to `David-Erra/homebrew-tap`, passed only to this command.
`scripts/publica.sh` builds the version in `VERSION` with the update address (`build-app.sh --amb-feed`), checks the “Warp
Launch Dev” signature of the app and of the Sparkle parts, and says what it would publish and what change it would make to the
Homebrew cask; with `--aplica`, it signs the zip with the key in the keychain, checks the signature with the public key the app
carries, publishes it on GitHub (`vX.Y.Z`, with `WarpLaunch-X.Y.Z.zip` and `appcast.xml`) and updates the version and the sha256
in the cask (`Casks/warp-launch.rb` in the tap). That's the one that `brew` and the “Without Homebrew” command install.
It only publishes what's in `origin/main`, with nothing left to commit, and a version that isn't there yet. If the cask can't be
written, the version isn't deleted, and the script says what to change by hand.

**0.33.0 (November 11, 2026) is the first one published this way,** with the signed appcast and the cask with `auto_updates true`.
0.31.5 was published with that version's script, without automatic updates.
**Since 0.33.0, publishing can't be undone:** the version reaches every Mac with 0.33.0 or later on its own, within a day. How to
stop a bad version: [`docs/disseny.md`](docs/disseny.md), section 11, part 7.

## Automatic updates

**0.33.0 (November 11, 2026) brings them: it's the first version published with automatic updates.** Checked from outside the same
day: the address the app checks gives 0.33.0, and the zip's signature matches the public key the app carries.
**The first real automatic update will come with the next version.** So far, **they've only been seen working with test
versions,** a local server and a one-time key, on the author's Mac: with a test app (rounds A and B in
[`docs/disseny.md`](docs/disseny.md), section 11) and with Warp Launch (round C, in part). It updates itself without any macOS
dialog, comes back without any window and keeps the Files & Folders permission and the login item. It hasn't been tested for
another user or on another Mac, or with a Mac restart: the author decided not to run more tests (November 10, 2026). What follows
describes how they work.

- **Anyone with 0.31.5 or earlier will have to update by hand one last time** (“To update it”, above): those versions have
  nothing to update themselves or to say so. From then on, it's automatic.
- **Normally you won't see anything.** Once a day, the app checks GitHub for a new version. If there is one, it downloads it
  (about 5 MB), checks its signature and restarts on its own when you're using neither the Mac (2 minutes without keyboard or
  mouse) nor the app (none of its windows open, no recent change, no Warp window opening). The menu bar icon disappears for a
  moment and comes back. **Warp and the Claude sessions aren't closed or touched.** If you quit the app with a version ready, it's
  installed when you quit. If you shut down or restart the Mac, it isn't known yet whether it's installed then or the next time
  you quit.
- **It's on by default.** To turn it off: Settings (⌘,) › “Updates” › “Update automatically”. When it's off, the app doesn't
  connect on its own, and a version that was already ready doesn't restart it: it's installed when you quit. The same tab has
  “Check Now” and, in the icon menu, “Check for Updates…”; with a version ready, both say “Restart and Update”.
- **Privacy: it's the app's first internet connection.** Once a day, and when you ask it to check, a request to GitHub and, if
  there's a new version, the download. **GitHub sees your IP address and the app's version.** No Mac profile or any Warp or
  Claude data is sent, and no other connection has been found in Sparkle's source code (it will be checked in the real tests).
  Before you accept the first-use permission, it doesn't connect.
- **Only published versions in Applications update.** A copy built from the source code, another folder, another Mac user's copy
  or an app opened with `--config` don't; the “Updates” tab says why.
- **If it can't be installed,** the icon may disappear once. When you open the app again, the tab says so, and the app doesn't
  try again on its own with that version.
- **Several Mac users:** if two users have their sessions and the app open, one user's update doesn't quit the other's (read in
  Sparkle's source code, not tested).
- **With Homebrew:** if you run `brew upgrade` with a version already ready, quit the app first, and don't use `--greedy`, which
  would reinstall it. `brew upgrade --cask warp-launch`, with the name, also reinstalls a copy that has already updated itself.
  Not tested.

## Uninstalling

1. **Settings (⌘,) › General › “Stop Using Warp Launch” › Restore Warp and Quit…** (since 0.31.0). Before doing anything, it
   says how Warp's “Restore windows, tabs, and panes on startup” setting will end up: as you had it before Warp Launch; if you
   were already using the app before it asked for permission (0.29.0), turned on, as Warp comes by default; and, if Warp Launch
   has never changed it, as it is. When you confirm, it removes the app from your login items, puts the setting back as it said,
   withdraws the permission and quits. If a step can't be done, it says so and doesn't do the next ones. If you open it again,
   it asks you for permission again. If you've never given it permission, this step isn't needed: without permission, Warp
   Launch doesn't touch Warp.
2. If you installed it with Homebrew, `brew uninstall --cask warp-launch`. If not, drag `/Applications/Warp Launch.app` to the
   Trash.
3. If you don't want to keep the configuration, delete `~/.config/warp-launch/`.
4. With a version that has automatic updates, if you don't want anything left: `~/Library/Caches/cat.davide.warp-launch`,
   `~/Library/HTTPStorages/cat.davide.warp-launch` and `~/Library/Preferences/cat.davide.warp-launch.plist` (it holds the switch
   and the date of the last check).

With a version without the button (before 0.31.0): turn off the login switch, quit the app and, if you want Warp to reopen its
windows when it starts, turn the setting back on in Warp's settings.

## What you should know

- **The app manages Warp's session restore** (`restore_session` in `~/.warp/settings.toml`), with your first-use permission
  (step 2): it always keeps it turned off, because the app is what reopens the windows, with Claude. It only turns it on for a
  few seconds when you choose “Refresh Warp Status”, “Import from Warp” or “Link with Warp”, to read Warp's windows. If you have
  Settings Sync, the setting reaches your other Warp installations. To stop using the app, “Restore Warp and Quit…” puts the
  setting back (see “Uninstalling”). If you don't have `~/.warp/settings.toml` yet (for example, if you've never changed any
  Warp setting), since 0.31.3 the app only creates it when Warp is open with a tab, so that Warp can move its settings into it
  first; until then, Warp uses the default session restore, turned on, and the icon menu says so.
- **Nothing opens without your click.** Opening one window or all of them always goes through a sheet that says how many tabs
  and Claude sessions will open.
- **Claude's background jobs:** quitting Warp can leave them half done, and reopening the tabs doesn't resume them.
- **Default Claude command:** in new configurations, Claude opens without skipping permissions (`claude`, continuing the
  conversation). “Skip permissions”, the effort and “Ultracode” are chosen in Settings (⌘,) › “New Tabs”, or per tab in the
  inspector. Tabs that already had Claude open when imported keep the command it was opened with.
- **If something goes wrong** (since 0.30.0): Settings (⌘,) › General › “Diagnostics” › **Copy Diagnostics** copies a report in
  English, without your user name or folder names, to paste into a GitHub issue. For 8 checks (Warp's terminals; Claude Code's
  session files, transcripts and `~/.claude.json`; the `warp.sqlite` tables; the versions; and Warp's session restore), it says
  whether they still have the shape the app reads. It only reads: it doesn't open, stop or write anything. From the source
  code: `warp-launch diagnostica [--json] [--anonimitza]`.
- **Signature:** published versions carry David's “Warp Launch Dev” certificate, always the same one: macOS should keep the
  permissions when updating (deduced, not tested on another Mac yet). It isn't an Apple certificate: downloaded with the
  browser, macOS wouldn't open it. The Homebrew cask checks its sha256 and removes its downloaded-from-the-internet mark; the
  “Without Homebrew” command checks its signature and removes the mark too. Built from the source code on another Mac,
  `build-app.sh` signs it ad hoc, and then, after each update, macOS may ask again for the Files & Folders permission and the
  login item. Since 0.33.0, automatic updates are only accepted if the zip carries the EdDSA signature of the author's key,
  checked before extracting it: the certificate alone isn't enough. On the author's Mac, with test versions, macOS let the app be
  replaced without any dialog and kept its permissions (rounds B and C); on another Mac, it hasn't been tested yet.

## Development

Swift 6.4 from the Command Line Tools. A single external dependency: [Sparkle](https://sparkle-project.org) 2.10.1, with the
exact version and only in the app, not in the CLI.

```bash
swift build                          # builds
scripts/test.sh                      # tests (swift-testing); `swift test` alone fails intermittently
.build/debug/warp-launch --versio    # CLI
.build/debug/warp-launch llegeix     # windows, tabs and Claude sessions (add --json for the details)
.build/debug/warp-launch importa     # the configuration that Warp would give (writes nothing)
.build/debug/warp-launch diagnostica # whether Warp and Claude Code have the shape the app reads (--anonimitza, for an issue)
```

## Documentation

The documentation is in Catalan.
- [`docs/especificacio.md`](docs/especificacio.md): requirements, decisions made and open, phases.
- [`docs/disseny.md`](docs/disseny.md): design and steps of each phase.
- [`docs/fets-verificats.md`](docs/fets-verificats.md): verified behavior of Warp, Claude Code and the environment.
- [`docs/antecedents.md`](docs/antecedents.md): similar tools that exist and why they don't work for us.
- The previous Python prototype (`espai`), uninstalled, is no longer in the repo: it's in the history, in commit `114c97d`.

## License

[MIT](LICENSE), © 2026 David Erra.

## Third parties

The skills [`.claude/skills/mac-design/`](.claude/skills/mac-design/) and [`.claude/skills/app-icon/`](.claude/skills/app-icon/),
and `scripts/icona-compila.sh`, `scripts/icona-revisa.sh` and `scripts/icona-full.swift`, are derived from
[BAMA](https://github.com/daveebbelaar/bama) (MIT, © 2026 Dave Ebbelaar). The license is in `LICENSE-BAMA`, in each skill.

The app includes [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.1 to update itself. Its license is inside the app,
in `Contents/Resources/LICENSE-Sparkle`.

Independent project: it isn't affiliated with or endorsed by Warp (Denver Technologies, Inc.) or Anthropic. Warp, Claude and
Claude Code are trademarks of their respective owners.
