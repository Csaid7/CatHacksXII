import anthropic
import json
import os
import random
from dotenv import load_dotenv

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'), override=True)

client = anthropic.Anthropic(api_key=os.environ.get("API_KEY"))

CATEGORIES = [
    ["Science", "History"],
    ["Geography", "Pop Culture"],
    ["Sports", "Food"],
    ["Movies", "Animals"],
]

def generate_batch(categories: list) -> list:
    cat_str = " and ".join(categories)
    msg = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=4000,
        messages=[{
            "role": "user",
            "content": f"""Generate 10 trivia questions for each of these 2 categories: {cat_str}.
20 questions total. Wrong answers must be plausible — players should genuinely debate.
Return ONLY a valid JSON array, no extra text, no markdown:
[
  {{
    "category": "Science",
    "question": "What is the chemical symbol for gold?",
    "platforms": [
      {{"id": "A", "label": "Go", "isCorrect": false}},
      {{"id": "B", "label": "Gd", "isCorrect": false}},
      {{"id": "C", "label": "Au", "isCorrect": true}},
      {{"id": "D", "label": "Ag", "isCorrect": false}}
    ]
  }}
]"""
        }]
    )

    text = msg.content[0].text.strip()
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"Failed to parse batch {categories}: {e}")
        with open("debug.txt", "w") as f:
            f.write(msg.content[0].text)
        raise SystemExit(1)


def generate_question_bank() -> list:
    all_questions = []
    for i, categories in enumerate(CATEGORIES):
        print(f"Generating batch {i+1}/4: {categories}...")
        batch = generate_batch(categories)
        all_questions.extend(batch)
        print(f"  Got {len(batch)} questions")
    return all_questions


def save_question_bank(questions: list, path: str = "questions.json"):
    with open(path, "w") as f:
        json.dump(questions, f, indent=2)
    print(f"Saved to {path}")


_bank: list = []

def _load_bank():
    global _bank
    if not _bank:
        path = os.path.join(os.path.dirname(__file__), "questions.json")
        with open(path) as f:
            _bank = json.load(f)

async def generate_question() -> dict:
    _load_bank()
    q = random.choice(_bank).copy()
    q["platforms"] = q["platforms"].copy()
    random.shuffle(q["platforms"])
    q["correct"] = next(p["id"] for p in q["platforms"] if p["isCorrect"])
    return q


if __name__ == "__main__":
    print("Generating question bank...")
    questions = generate_question_bank()
    save_question_bank(questions)
    print(f"Done — {len(questions)} questions saved to questions.json")
