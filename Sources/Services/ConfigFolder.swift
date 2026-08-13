import AppKit

/// SessionHawk's config lives in plain files under ~/.sessionhawk. This opens
/// that folder from the app, dropping a CONFIG.md cheat-sheet in first so the
/// options are discoverable without reading the repo.
public enum ConfigFolder {
    public static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sessionhawk")
    }

    @discardableResult
    public static func prepare() -> URL {
        let dir = url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Always rewritten: CONFIG.md is generated documentation, and stale
        // docs are worse than no docs. User config lives in the other files.
        let readme = dir.appendingPathComponent("CONFIG.md")
        try? template.write(to: readme, atomically: true, encoding: .utf8)
        return dir
    }

    public static func open() {
        NSWorkspace.shared.open(prepare())
    }

    static let template = """
    # SessionHawk configuration

    All configuration is plain files and environment variables — no settings UI.

    ## Files in this folder (~/.sessionhawk)

    - `leaderboard` — opt in to the public daily leaderboard: put your nickname
      in this file (`echo yourname > ~/.sessionhawk/leaderboard`). Delete the
      file to opt out. Nickname only; no other identity is sent.
    - `limits.json` — cached Claude usage limits (written by the feeder; don't edit).
    - `heh/` — nightly human-equivalent-hours audit files, one JSON per day.
    - `history/` — local session history, one plain-JSON file per day
      (sessions, per-state time, token/turn totals). Stays on this Mac, is
      never sent anywhere, and days older than 90 are deleted at app launch.
      Delete the folder anytime to wipe history.
    - `id` — anonymous stable id used by the leaderboard (auto-generated).

    ## Environment variables

    - `SESSIONHAWK_NO_NOTIFY=1` — disable all notifications (app-wide kill switch).
    - `SESSIONHAWK_NO_TELEMETRY=1` — skip the anonymous install ping (installer only).
    - `SH_CONTEXT_LIMIT=<tokens>` — override the detected context window size
      (default: 200k, or 1M when a `[1m]` model is configured).

    ## Related

    - Claude Code hooks live in `~/.claude/settings.json` (installed by
      `install-hooks.sh`, timestamped backups are made next to it).
    - Terminal statusline (separate tool): https://github.com/jcsuen/claude-limits-statusline
      — style switch: `echo bars > ~/.claude-limits-statusline/style`.
    """
}
