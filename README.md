# PageDuel Live Visitors

Omarchy bar widget showing how many visitors are on your PageDuel-tracked
sites right now — total across every site, plus a per-site breakdown in a
popup. Backed by PageDuel's public v1 Read API (`GET /api/v1/live`).

## Setup

```bash
python3 ~/.config/omarchy/plugins/nichovski.pageduel-live-visitors/setup.py
```

Paste a PageDuel API key (Settings → API keys — a read-only key is enough).
The widget picks it up automatically on the next poll.

## How it works

- `fetch.sh` calls `GET /api/v1/live` with the saved key every
  `pollIntervalSeconds` (default 60s — see below) and writes the result to
  `~/.config/omarchy/pageduel/live_visitors.json`.
- `BarWidget.qml` watches that file and renders the total count; clicking it
  opens the per-site breakdown.
- On an error (bad key, rate limit, network) the widget shows the error
  message in its tooltip/popup and backs off instead of hot-looping.

## Poll interval and the API's daily budget

Each poll spends one request from the API key's daily budget — 2,000/day on
Starter, 5,000/day on Growth. 60 seconds (1,440 requests/day) fits both
plans; anything under ~35s can exceed Starter's budget. The widget clamps
`pollIntervalSeconds` to a minimum of 30s regardless of what's configured.

Change it in the widget's settings in Omarchy's bar/plugin configuration, or
directly in `~/.config/omarchy/shell.json` under this widget's entry
(`nichovski.pageduel-live-visitors`).

## Requirements

`GET /api/v1/live` must exist on the PageDuel deployment this points at
(default `https://pageduel.com/api/v1`). As of 2026-09-21 it's shipped on
branch `claude/multi-site-visitor-plugin-216cd8` (PR #255) but not yet merged
or deployed — until then the widget will show a fetch error, which is
expected and not a bug in this plugin.
