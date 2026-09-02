.pragma library

// Pure helpers shared by PerfexPulse.qml and Panel.qml. No network, no
// state - every function derives its answer from the arguments alone, so
// the bar text and panel labels can be reasoned about (and tested) in
// isolation.

var GLYPH_PAUSE = "󰏤"      // nf-md-pause
var GLYPH_OFFLINE = "󰅤"    // nf-md-cloud_off_outline
var GLYPH_CASH = "󰄔"       // nf-md-cash
var GLYPH_KEY = "󰌆"        // nf-md-key

function num(v) {
  var n = Number(v)
  return isFinite(n) ? n : 0
}

function money(amount, symbol, cents) {
  var n = num(amount)
  var sign = n < 0 ? "-" : ""
  var s = Math.abs(n).toLocaleString(Qt.locale("en_US"), "f", cents ? 2 : 0)
  return sign + (symbol || "") + s
}

function fmtTime(epoch) {
  if (!epoch) return ""
  return Qt.formatTime(new Date(num(epoch) * 1000), "HH:mm")
}

function fmtDayTime(epoch) {
  if (!epoch) return ""
  var d = new Date(num(epoch) * 1000)
  var today = new Date()
  var sameDay = d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth() && d.getDate() === today.getDate()
  return sameDay ? Qt.formatTime(d, "HH:mm") : Qt.formatDateTime(d, "ddd HH:mm")
}

function fmtCountdown(ms) {
  var s = Math.max(0, Math.round(ms / 1000))
  var m = Math.floor(s / 60)
  var r = s % 60
  return m + ":" + (r < 10 ? "0" : "") + r
}

function fmtDuration(ms) {
  var s = Math.max(0, Math.round(ms / 1000))
  if (s < 90) return s + " s"
  var m = Math.round(s / 60)
  if (m < 90) return m + "m"
  return Math.round(m / 60) + "h"
}

function headline(data) {
  return data && data.currencies && data.currencies.length > 0 ? data.currencies[0] : null
}

function overdueCount(data) {
  var c = 0
  if (!data || !data.currencies) return 0
  for (var i = 0; i < data.currencies.length; i++) c += num(data.currencies[i].overdue ? data.currencies[i].overdue.count : 0)
  return c
}

function amountLabel(data, showAmount, showCents) {
  var h = headline(data)
  if (!h) return ""
  if (!showAmount) return ""
  var text = (data.approx ? "≈" : "") + money(h.outstanding, h.symbol, showCents)
  if (data.currencies.length > 1) text += " +" + (data.currencies.length - 1)
  return text
}

function needsSetup(s) {
  return s.halted || s.error === "no_key" || s.error === "key_perms" || s.error === "bad_endpoint"
}

// s: {querying, halted, error, data, showAmount, showCents}
// -> [{text, dim}] text segments shown after the mark, all in the bar's
// theme colour. Empty while polling is off (the greyed mark alone is the
// paused state) and while "amount in bar" is off (the mark alone; the
// tooltip and panel carry the numbers). Setup states always show their
// word, since they need a click.
function barSegments(s) {
  if (s.halted) return [{ text: "key rejected", dim: false }]
  if (s.error === "no_key" || s.error === "bad_endpoint") return [{ text: "set key", dim: false }]
  if (s.error === "key_perms") return [{ text: "key perms", dim: false }]
  if (!s.querying || !s.showAmount) return []
  var h = headline(s.data)
  if (!h) {
    if (s.error !== "") return [{ text: GLYPH_OFFLINE, dim: true }]
    return [{ text: "…", dim: true }]
  }
  var segs = [{ text: amountLabel(s.data, s.showAmount, s.showCents), dim: false }]
  if (s.error !== "") segs.push({ text: GLYPH_OFFLINE, dim: true })
  return segs
}

// Text lines under the mark in a vertical bar: "key" when setup is needed,
// the overdue count when there is one and "amount in bar" is on, otherwise
// nothing.
function verticalLines(s) {
  if (needsSetup(s)) return ["key"]
  if (!s.querying || !s.showAmount) return []
  var overdue = overdueCount(s.data)
  return overdue > 0 ? [String(overdue)] : []
}

function errorSentence(error, detail, http, host) {
  switch (error) {
  case "": return ""
  case "off": return "Querying is off"
  case "no_key": return "No API key saved - click to set it up"
  case "key_perms": return "Key file is readable by others - click to re-save it locked down"
  case "bad_endpoint": return "Endpoint file is missing or malformed - click to set it up"
  case "auth": return "Perfex rejected the key (401)"
  case "forbidden": return "CRM refused this IP (403) - on another network?"
  case "rate_limited": return "Rate limited (429) - retrying shortly"
  case "unreachable": return "Could not reach " + (host || "the CRM")
  case "server": return "CRM answered with an error" + (http ? " (HTTP " + http + ")" : "")
  case "tool_error": return "CRM tool error" + (detail ? ": " + detail : "")
  case "protocol": return "Unexpected reply from the CRM" + (detail ? ": " + detail : "")
  case "parse_failed": return "Could not read the fetch result"
  case "deadline": return "Poll took too long and was stopped"
  case "watchdog": return "Poll hung and was killed"
  case "cancelled": return "Poll cancelled"
  default: return "Error: " + error
  }
}

// s: {querying, halted, error, errorDetail, errorHttp, errorSince, data, lastUpdated, host, nextPollAt, now, showAmount, showCents}
function tooltip(s) {
  var h = headline(s.data)
  if (s.halted) return "Perfex rejected the key twice - polling stopped. Click to set it up again."
  if (s.error === "no_key" || s.error === "bad_endpoint") return "Click to set up the API key"
  if (s.error === "key_perms") return errorSentence(s.error)
  var age = s.lastUpdated ? fmtDayTime(s.lastUpdated) : ""
  if (!s.querying) {
    return "Querying is off - no requests are made." + (age ? " Showing " + age + " numbers." : "") + " Middle-click or use the panel switch to resume."
  }
  if (!h) {
    if (s.error !== "") return errorSentence(s.error, s.errorDetail, s.errorHttp, s.host) + " - nothing loaded yet"
    return "Loading Perfex receivables…"
  }
  var parts = []
  parts.push("Outstanding " + money(h.outstanding, h.symbol, true))
  var overdue = overdueCount(s.data)
  if (overdue > 0) parts.push(overdue + " overdue (" + money(h.overdue.total, h.symbol, true) + ")")
  for (var i = 1; i < s.data.currencies.length; i++) parts.push("also " + money(s.data.currencies[i].outstanding, s.data.currencies[i].symbol, true))
  if (s.data.approx) parts.push("some balances approximate (" + num(s.data.skipped_gets) + " lookups skipped)")
  if (s.error !== "") parts.push(errorSentence(s.error, s.errorDetail, s.errorHttp, s.host) + " since " + fmtDayTime(s.errorSince) + " - showing " + age + " numbers")
  else if (age) parts.push("updated " + age)
  if (s.nextPollAt && s.now) parts.push("next poll in " + fmtDuration(s.nextPollAt - s.now))
  parts.push("click for details")
  return parts.join(" · ")
}

function trimSlash(url) {
  return String(url || "").replace(/\/+$/, "")
}

function invoiceUrl(base, id) {
  return trimSlash(base) + "/admin/invoices/list_invoices/" + id
}

function adminUrl(base) {
  return trimSlash(base) + "/admin"
}

function hostOf(url) {
  var m = String(url || "").match(/^https?:\/\/([^\/]+)/)
  return m ? m[1] : ""
}

function pill(s) {
  if (s.halted) return "KEY"
  if (s.error === "no_key" || s.error === "key_perms" || s.error === "bad_endpoint") return "KEY"
  if (!s.querying) return "PAUSED"
  if (s.error === "forbidden") return "403"
  if (s.error !== "" && s.data) return "STALE"
  if (s.error !== "") return "ERROR"
  if (s.data && s.data.approx) return "≈"
  return s.data ? "LIVE" : "…"
}
