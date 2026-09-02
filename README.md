# Perfex Pulse

Omarchy bar widget: outstanding receivables from a Perfex CRM (via its MCP
connector), overdue invoices in a click-open panel, and a hard on/off switch
for polling. Private plugin, id `karamble.perfex-pulse`.

## Bar

The Perfex mark (drawn as vector paths, tinted to the bar like every other
icon) followed by the outstanding receivables - unpaid + partially paid +
overdue, in the currency with the largest outstanding amount (`+1` when
another currency exists). Active: the bar's theme colour. Polling off: a
darker shade of it, like an inactive NetBird icon. Overdue is signalled in
the tooltip and the panel, never by a colour change in the bar.

| state | label |
|---|---|
| live | mark `€2,500` |
| amount in bar off | the mark alone; hover for the numbers |
| paused (switch off) | the mark alone, greyed (a darker shade of the bar colour, as NetBird does when inactive) - nothing else |
| stale (last poll failed) | mark `€2,500 󰅤` - last known number, hover for the cause |
| no key | mark `set key` - click opens the setup terminal |
| key rejected twice | mark `key rejected` - click opens setup |

Left click: panel (or setup while no key works). Right click: refresh now.
Middle click: toggle polling.

## The switch

`querying` is a boolean on the widget's entry in `~/.config/omarchy/shell.json`
(default **off**). Off means zero requests: the poll timer is not running,
opening the panel never fetches, an in-flight request is aborted, and the
fetch script itself checks shell.json before it opens the key file - a
hand-run script, a keybind or a QML regression still makes no request.

Flip it from the panel (hero switch, DISPLAY row, or `q`), by middle-click,
from a script:

    omarchy bar set karamble.perfex-pulse querying false --json   # --json, or it stores the string "false"
    omarchy-shell -q karamble.perfex-pulse toggleQuerying          # also queryingOn / queryingOff / querying
    omarchy-shell karamble.perfex-pulse state                      # JSON: settings, error, data age, next poll

Editing files under the plugin directory hot-reloads it, but the old widget
instance can keep the IPC target: after edits, `omarchy-restart-shell` (never
`omarchy-refresh-shell`, which resets shell.json) and read the fresh
instance's log with `qs log -i <id>` (ids under $XDG_RUNTIME_DIR/quickshell/by-id).

## Setup

Click `CRM: set key` (or run `perfex-pulse-setup`). It asks for the MCP
endpoint and the key, makes ONE announced request to verify them, writes
`~/.config/perfex-pulse/{endpoint,api_key}` with 0700/0600, and offers to
switch polling on. `--check` prints the state; `--forget` removes everything.

Use a dedicated read-only staff member ("Bar Monitor": global view on
invoices, payments, customers) with its own key - attributable audit rows,
independent revocation, read-only blast radius. Mint one on the server:

    php index.php mcp_connector mcp_cli create_key <staff_id> omarchy-bar

## Requests

Per poll: `invoices_list` for statuses 1, 3, 4, then `invoices_get` per open
invoice (cap 25; beyond it balances are approximate and the bar shows `≈`),
plus `customers_list` once a day and `payments_list` when "Paid this month"
is on. Default interval 600 s (`pollSeconds`, floor 120). Backoff doubles up
to 1 h on failures; a 403 (IP not whitelisted) backs off harder; two 401s in
a row halt polling until the key is set up again.

Overdue is decided client-side as `duedate < today`, so the bar can be a day
ahead of Perfex's cron badge.

## Keybinds (`~/.config/hypr/bindings.lua`)

    o.bind("SUPER + ALT + C",         "Perfex panel",          "omarchy-shell shell toggle karamble.perfex-pulse")
    o.bind("SUPER + ALT + SHIFT + C", "Perfex polling on/off", "omarchy-shell -q karamble.perfex-pulse toggleQuerying")

## Files

`PerfexPulse.qml` (bar widget, state machine, the only network path),
`Panel.qml`, `Model.js` (pure formatting/state helpers), `perfex-pulse-fetch`
(bash + curl + jq; one line of JSON out, exit 0 always; set
`PERFEX_PULSE_FIXTURE_DIR` to a directory of `<tool>.json` responses to run
it without the network), `perfex-pulse-setup`.

Caches in `~/.cache/perfex-pulse/` (0700): `last.json` (last good result,
60 s TTL), `currencies.json`, `customers.json`.

## Removal

`perfex-pulse-setup --forget`, then `omarchy plugin remove karamble.perfex-pulse`.
