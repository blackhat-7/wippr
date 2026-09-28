"""Deterministic pre-pass for spoken formatting commands, run on the ASR text before the cleanup LLM.

Small models (S1-mini, Qwen3.5-2B) often leave "new line" / "bullet point" / "number one" as words.
ASR adds its own punctuation around the command words ("Friday period. New line, thanks"), so each
command also swallows the punctuation next to it. Mirrored in ios/App/Prepass.swift; keep them in sync.
"""

import re

# Spoken command -> text. Longest first, so "question mark" wins over a bare "mark".
# \x01 / \x02 stand for an opening / closing quote until the spacing is fixed up.
PUNCT = {
    "new paragraph": "\n\n", "next paragraph": "\n\n", "new line": "\n", "next line": "\n",
    "question mark": "?", "exclamation point": "!", "exclamation mark": "!",
    "open quote": "\x01", "close quote": "\x02", "end quote": "\x02", "unquote": "\x02",
    "open parenthesis": "(", "close parenthesis": ")", "open paren": "(", "close paren": ")",
    "semicolon": ";", "colon": ":", "comma": ",", "full stop": ".", "period": ".",
}
# "period"/"colon"/"comma" are also nouns; don't convert right after these words.
NOUN_BEFORE = {"the", "a", "an", "this", "that", "each", "per", "trial", "grace", "waiting", "time", "same",
               "my", "your", "his", "her", "our", "their", "its", "one", "first", "last", "next", "oxford"}
NOUNS = {"period", "colon", "comma"}
EDGE = r"[ \t,.;:!?]*"  # ASR punctuation hugging a command word (never a newline we produced)
ORDINAL = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
_ALT = "|".join(k.replace(" ", r"[\s-]+") for k in sorted(PUNCT, key=len, reverse=True))
_CMD = re.compile(rf"(?:(\b[\w']+)\s+)?{EDGE}(?<![\w'])({_ALT})(?![\w']){EDGE}", re.I)


def _commands(text):
    """One left-to-right pass, so a command never eats the output of the one before it."""
    def sub(m):
        before, spoken = m.group(1), re.sub(r"[\s-]+", " ", m.group(2).lower())
        if before and before.lower() in NOUN_BEFORE and spoken in NOUNS:
            return m.group(0)
        return (f"{before} " if before else " ") + PUNCT[spoken] + " "

    return _CMD.sub(sub, text)


def _lists(text):
    # "bullet point X bullet point Y" -> "- X\n- Y"
    if len(re.findall(r"\bbullet(?:\s+point)?\b", text, re.I)) >= 2:
        head, *items = re.split(rf"{EDGE}\bbullet(?:\s+point)?\b{EDGE}", text, flags=re.I)
        head = head.strip().rstrip(",.") + (":" if head.strip() and not head.strip().endswith(":") else "")
        text = head + "\n" + "\n".join(f"- {i.strip(' ,.;')[:1].upper()}{i.strip(' ,.;')[1:]}" for i in items if i.strip())
    # "number one X number two Y" -> "1. X\n2. Y" (needs both one and two, so "my number one priority" stays)
    if re.search(r"\bnumber\s+(one|1)\b", text, re.I) and re.search(r"\bnumber\s+(two|2)\b", text, re.I):
        alt = "|".join(ORDINAL + [str(i) for i in range(1, 11)])
        head, *rest = re.split(rf"{EDGE}\bnumber\s+({alt}){EDGE}", text, flags=re.I)
        items = rest[1::2]
        head = head.strip().rstrip(",.")
        head = head + (":" if head and not head.endswith(":") else "")
        text = head + "\n" + "\n".join(f"{n}. {i.strip(' ,.;')[:1].upper()}{i.strip(' ,.;')[1:]}"
                                       for n, i in enumerate(items, 1))
    return text


def lists(text):
    """Only the list rules (bullet point / number one), untouched otherwise. This is what the app ships
    (ios/App/Prepass.swift, checked identical on every bench input)."""
    return _lists(text)


def prepass(text):
    text = _lists(_commands(text))
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r" +([,.;:!?)])", r"\1", text)
    text = re.sub(r"\s*\x01\s*", ' "', text)
    text = re.sub(r"\s*\x02", '"', text)
    text = re.sub(r"\( +", "(", text)
    text = re.sub(r"([,.;:!?])(?=[^\s\d\"')])", r"\1 ", text)  # "Friday.Thanks" -> "Friday. Thanks"
    text = re.sub(r"([,;:])\1+|\.\.+(?!\.)", lambda m: m.group(0)[0], text)
    text = re.sub(r"(^|[.!?]\s+|\n)([a-z])", lambda m: m.group(1) + m.group(2).upper(), text.strip())
    return text


if __name__ == "__main__":
    tests = {
        "dear team comma new line new line the office will be closed on friday period new line thanks comma new line alex":
            "Dear team,\n\nThe office will be closed on friday.\nThanks,\nAlex",
        "Dear team, comma. New line, new line. The office will be closed on Friday, period. New line. Thanks, comma, new line, Alex.":
            "Dear team,\n\nThe office will be closed on Friday.\nThanks,\nAlex.",
        "is everyone okay with that question mark let me know by end of day exclamation point":
            "Is everyone okay with that? Let me know by end of day!",
        "the password must contain open quote at least one symbol close quote and a number":
            'The password must contain "at least one symbol" and a number',
        "note colon the server restarts at midnight open parenthesis utc close parenthesis":
            "Note: the server restarts at midnight (utc)",
        "grocery list bullet point apples bullet point oat milk bullet point coffee beans bullet point spinach":
            "Grocery list:\n- Apples\n- Oat milk\n- Coffee beans\n- Spinach",
        "things to pack for the trip number one passport number two charger number three sunscreen":
            "Things to pack for the trip:\n1. Passport\n2. Charger\n3. Sunscreen",
            "Things to pack for the trip number 1 passport number 2 charger number 3 sunscreen.":
            "Things to pack for the trip:\n1. Passport\n2. Charger\n3. Sunscreen",
        "Grocery list: Bullet point apples, Bullet Point Oat Milk, Bullet Point Coffee Beans, Bullet Point Spinach.":
            "Grocery list:\n- Apples\n- Oat Milk\n- Coffee Beans\n- Spinach",
        # must stay unchanged apart from capitalization
        "the trial period ends on friday": "The trial period ends on friday",
        "my number one priority is the launch": "My number one priority is the launch",
        "put a comma after the name": "Put a comma after the name",
    }
    bad = 0
    for raw, want in tests.items():
        got = prepass(raw)
        if got != want:
            bad += 1
            print(f"FAIL {raw!r}\n  got  {got!r}\n  want {want!r}")
    print(f"{len(tests) - bad}/{len(tests)} ok")
