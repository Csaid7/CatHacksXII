import anthropic
import json
import asyncio
import random

client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from env automatically

TOPICS = [
    "science", "history", "pop culture", "geography",
    "sports", "movies", "music", "food", "technology", "animals"
]

FALLBACK_QUESTION = {
    "question": "What is the capital of France?",
    "correct": "B",
    "platforms": [
        {"id": "A", "label": "London",  "isCorrect": False},
        {"id": "B", "label": "Paris",   "isCorrect": True},
        {"id": "C", "label": "Berlin",  "isCorrect": False},
        {"id": "D", "label": "Madrid",  "isCorrect": False},
    ]
}

async def generate_question(topic: str = None) -> dict:
    """Async wrapper — runs the blocking SDK call in a thread pool."""
    if not topic:
        topic = random.choice(TOPICS)
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _sync_generate, topic)

def _sync_generate(topic: str) -> dict:
    try:
        msg = client.messages.create(
            model="claude-haiku-4-5-20251001",  # fast + cheap for a hackathon
            max_tokens=400,
            messages=[{
                "role": "user",
                "content": f"""Generate a trivia question about: {topic}

Rules:
- Wrong answers must be PLAUSIBLE — players should genuinely debate
- Keep every answer label short (under 4 words)
- Shuffle which id (A/B/C/D) holds the correct answer each time

Return ONLY valid JSON, no markdown, no extra text:
{{
  "question": "...",
  "correct": "C",
  "platforms": [
    {{"id": "A", "label": "...", "isCorrect": false}},
    {{"id": "B", "label": "...", "isCorrect": false}},
    {{"id": "C", "label": "...", "isCorrect": true}},
    {{"id": "D", "label": "...", "isCorrect": false}}
  ]
}}"""
            }]
        )
        return json.loads(msg.content[0].text)
    except Exception as e:
        print(f"[question_gen] Error: {e} — using fallback question")
        return FALLBACK_QUESTION
