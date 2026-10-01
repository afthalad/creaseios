# python3 tools/arb_to_xcstrings.py ~/Desktop/crease1/lib/l10n > creaseios/Resources/Localizable.xcstrings
import json, re, sys, os

src = sys.argv[1] if len(sys.argv) > 1 else "lib/l10n"
arbs = {l: json.load(open(os.path.join(src, f"app_{l}.arb"), encoding="utf-8")) for l in ("en", "si", "ta")}
en = arbs["en"]
plural = re.compile(r"^\{(\w+), plural, (.*)\}$", re.S)

extras = {
    "ok": {"en": "OK", "si": "හරි", "ta": "சரி"},
    "endInnings": {"en": "End innings", "si": "ඉනිම අවසන් කරන්න", "ta": "இன்னிங்ஸை முடி"},
    "retiredHurt": {"en": "Retired hurt", "si": "තුවාල වී ඉවත් විය", "ta": "காயத்தால் வெளியேறினார்"},
    "targetLabel": {"en": "Target", "si": "ඉලක්කය", "ta": "இலக்கு"},
}

def spec(meta, name):
    return "lld" if meta.get("placeholders", {}).get(name, {}).get("type") == "int" else "@"

def fmt(text, meta):
    order = re.findall(r"\{(\w+)\}", text)
    for i, name in enumerate(order, 1):
        s = spec(meta, name)
        text = text.replace("{" + name + "}", f"%{i}${s}" if len(order) > 1 else f"%{s}", 1)
    return text

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

strings = {}
for key in (k for k in en if not k.startswith("@")):
    meta = en.get("@" + key, {})
    names = re.findall(r"\{(\w+)[,}]", en[key])
    names = list(dict.fromkeys(names))
    swift_key = " ".join([key] + ["%" + spec(meta, n) for n in names])
    locs = {}
    for lang, arb in arbs.items():
        text = arb.get(key, en[key])
        m = plural.match(text)
        if m:
            cases = dict(re.findall(r"(=1|one|other)\{((?:[^{}]|\{\w+\})*)\}", m.group(2)))
            one = cases.get("=1") or cases.get("one") or cases["other"]
            locs[lang] = {"variations": {"plural": {
                "one": unit(one.replace("{" + m.group(1) + "}", "%lld")),
                "other": unit(cases["other"].replace("{" + m.group(1) + "}", "%lld"))}}}
        else:
            locs[lang] = unit(fmt(text, meta))
    strings[swift_key] = {"extractionState": "manual", "localizations": locs}

for key, values in extras.items():
    strings[key] = {"extractionState": "manual", "localizations": {l: unit(v) for l, v in values.items()}}

print(json.dumps({"sourceLanguage": "en", "version": "1.0", "strings": dict(sorted(strings.items()))},
                 ensure_ascii=False, indent=2))
