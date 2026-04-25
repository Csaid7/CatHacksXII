import google.generativeai as genai
import json
import asyncio
import os
import random

# Reads GEMINI_API_KEY from environment — set this before running the server
genai.configure(api_key=os.environ["GEMINI_API_KEY"])
model = genai.GenerativeModel("gemini-2.0-flash")

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
        response = model.generate_content(
            f"""Generate a trivia question about: {topic}

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
        )
        # Gemini sometimes wraps output in ```json ... ``` — strip it if present
        text = response.text.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()
        return json.loads(text)
    except Exception as e:
        print(f"[question_gen] Error: {e} — using fallback question")
        return FALLBACK_QUESTION
