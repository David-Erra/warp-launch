# Security

## Reporting a vulnerability

Please report security issues privately through GitHub: open the **Security** tab of this repository and choose
**Report a vulnerability**. Do not open a public issue for a security problem.

You will get an answer within 7 days. Fixes are published as a new version, which reaches every copy of the app through
its automatic updates within a day.

## What the app touches

Warp Launch is a menu bar app that reopens Warp windows and tabs, each with its Claude Code session. It is designed to
touch as little as possible:

- **Reads** Warp's data (its windows database, read-only) and Claude Code's session files and transcripts under
  `~/.claude` (read-only).
- **Writes** its own files under `~/.config/warp-launch/`, temporary launch configurations in
  `~/.warp/launch_configurations/` (marked as its own and deleted after use), and one line of Warp's settings:
  `restore_session` in `~/.warp/settings.toml`. It asks for your permission before it ever touches that line, and
  **Settings › General › Restore Warp and Quit…** puts it back as it was.
- **Opens** Warp windows and Claude Code sessions only when you click a button, never by itself.
- **Network:** the only connection is the update check (Sparkle), once a day, to GitHub. GitHub sees your IP address and
  the app version. You can turn automatic updates off in **Settings › Updates**.

## Updates

Updates are signed with an EdDSA key held only by the author, and every download is checked against the public key
built into the app before it is installed. A download with a missing or wrong signature is refused.

## Supported versions

Only the latest published version gets fixes. Copies at 0.31.5 or earlier do not update themselves and need one manual
update (see the README).
