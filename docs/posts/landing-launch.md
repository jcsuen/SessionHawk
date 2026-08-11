# Landing-page launch — post drafts

Drafts for the founder to publish (or not) when the landing page goes live at
paulobuilds.com/sessionhawk/. Attach `docs/screenshots/needs-you-demo.gif`
(synthetic data — safe to post).

---

## LinkedIn

SessionHawk now has a home: paulobuilds.com/sessionhawk

The problem it solves is simple and a little embarrassing: I run several AI
coding agents at once, and at any given moment at least one of them is done
working and silently waiting for me to say "yes". The agent is idle, I'm
oblivious, and the whole "parallel agents" productivity story quietly falls
apart.

SessionHawk is a macOS menu-bar app that watches every Claude Code, Codex and
Gemini CLI session and pings me the second one needs input. Waiting sessions
jump to the top. If I leave one hanging 10 minutes, it reminds me. One click
focuses the exact terminal window.

It also shows the thing every heavy Claude user actually wants to know: how
much of my 5-hour and weekly limit is left, when it resets, and whether I'm
burning faster than the window ("12% over pace" is a very effective way to
make me stop and think).

Honest scope: it's live-only (no history), local-only (no cloud, no account),
and free & open source.

One command to install — no Homebrew needed:
curl -fsSL https://raw.githubusercontent.com/jcsuen/SessionHawk/main/install.sh | bash

If you're running more than one agent, tell me what your dashboard shows —
mine says the bottleneck was never the AI.

#buildinpublic #ai #claudecode #devtools #macos

---

## X

My AI agents were "working in parallel".

Reality: at any moment, one of them was done and silently waiting for me to
type "yes". For minutes. Sometimes longer.

So I built SessionHawk — a macOS menu-bar app that pings you the second any
Claude Code / Codex / Gemini session needs input. Waiting sessions jump to
the top. Plus live 5h/weekly Claude limit gauges with pace tracking.

Free, open source, local-only, one-command install:
paulobuilds.com/sessionhawk

The bottleneck was never the AI.
