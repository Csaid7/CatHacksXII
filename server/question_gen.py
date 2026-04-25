import json
import os
import random

_bank: list = []

def _load_bank():
    global _bank
    if not _bank:
        path = os.path.join(os.path.dirname(__file__), "questions.json")
        with open(path) as f:
            _bank = json.load(f)

def generate_question() -> dict:
    _load_bank()
    # Copy so shuffling platforms doesn't mutate the shared bank entry
    q = random.choice(_bank).copy()
    q["platforms"] = list(q["platforms"])
    random.shuffle(q["platforms"])
    q["correct"] = next(p["id"] for p in q["platforms"] if p["isCorrect"])
    return q
