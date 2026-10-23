# awk -f qr.awk DIR/ADDRESS ...: one JSON line per file, {"address": ADDRESS, "svg": its text}.
FNR == 1 { if (started) done(); started = 1; svg = ""; a = FILENAME; sub(/.*\//, "", a) }
{ svg = svg $0 "\n" }
END { if (started) done() }
function repl(s, x, y,    out, k) {
    out = ""
    while ((k = index(s, x)) > 0) { out = out substr(s, 1, k - 1) y; s = substr(s, k + length(x)) }
    return out s
}
function done() {
    svg = repl(repl(repl(svg, "\\", "\\\\"), "\"", "\\\""), "\n", "\\n")
    gsub(/[\001-\037]/, "", svg)
    print "{\"address\":\"" a "\",\"svg\":\"" svg "\"}"
}
