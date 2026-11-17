"""Turn ntc.js's name list into lib/data/color_names.dart.

Usage: python -I gen_color_names.py <path/to/ntc.js> <out.dart>
Only extracts ["RRGGBB", "Name"] pairs; nothing in the input is executed.
"""
import json
import re
import sys

src, out = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
pairs = re.findall(r'\["([0-9A-Fa-f]{6})",\s*"([^"\\]*)"\]', text)
if not 1500 <= len(pairs) <= 1700:
    sys.exit(f"unexpected number of names: {len(pairs)}")
for hex_, name in pairs:
    if not re.fullmatch(r"[A-Za-z0-9 '\-\.,&()/]+", name):
        sys.exit(f"unexpected characters in name: {name!r}")

lines = [
    "// GENERATED from Name that Color (ntc.js) by Chirag Mehta, http://chir.ag/projects/ntc",
    "// Licensed under Creative Commons Attribution 2.5: http://creativecommons.org/licenses/by/2.5/",
    "// The same list thecolorapi.com uses, so names match what earlier app versions showed.",
    "// Regenerate with scripts/gen_color_names.py; do not edit by hand.",
    "",
    "/// (hex, name) pairs; hex is 6 uppercase digits.",
    "const List<(String, String)> ntcColorNames = [",
]
for hex_, name in pairs:
    lines.append(f"  ({json.dumps(hex_.upper())}, {json.dumps(name)}),")
lines.append("];")
lines.append("")
open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print(f"wrote {len(pairs)} names to {out}")
