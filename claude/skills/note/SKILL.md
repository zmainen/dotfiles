---
name: note
description: "Quick note capture to Bear. Jot down a thought during any session — it goes to Bear and syncs across devices via iCloud. Usage: /note <your thought>. Use when the user wants to capture an idea, reminder, or observation."
---

# /note — Quick note capture

Jot down a thought during a session. The note goes to Bear — that's the primary surface. Bear syncs to all devices via iCloud.

## Usage

```
/note <your thought here>
/note tighten the cat monitor pattern to exclude cat >> writes
```

The agent decides whether to create a new note or update an existing one — the user just types `/note`.

## Implementation

**Always use the Bear MCP tools** (`bear_create`, `bear_trash`, `bear_search`, `bear_get`), not URL schemes. The MCP tools work reliably through the Bear SQLite database.

**For appending/editing:** create a new note with the combined content, then `bear_trash` the old one by ID. Do NOT use `bear_append` or `bear_replace` — Bear's UI doesn't reliably refresh when notes are modified in place. Create-and-replace ensures the user sees the updated note immediately.

## Procedure

### New note

1. **Create via Bear MCP:**
   ```
   bear_create(title="<title>", text="<body>", tags="note")
   ```

   **The user's exact words come first, always, in a block quote.** This is the primary record. The agent's structured translation follows under `## Agent translation`.

   ```
   > <user's exact text, verbatim>

   ## Agent translation

   <agent's structured interpretation — headings, bullets,
   connections to existing work>

   ---
   captured: <ISO UTC timestamp>
   source: <text | voice-memo | email>
   ```

2. **Acknowledge briefly:** "Noted: <title>"

### Update existing note (append, correct, continue)

1. **Find the note:** `bear_search(query="<title or topic>")` — get the note ID.
2. **Read current content:** `bear_get(note_id="<id>")`.
3. **Create new note** with combined content (old + new addition). The addition is a new timestamped exchange:
   ```
   <existing content>

   ---

   > <ISO timestamp> — addition:
   > <user's exact words>

   ## Agent translation

   <what this adds or changes>
   ```
4. **Trash the old note:** `bear_trash(note_id="<old-id>")`.
5. **Acknowledge briefly:** "Updated: <title>"

### Which mode?

The agent decides — the user just types `/note`. Pick update when:
- The thought continues a note from this session (same topic, builds on it, corrects it)
- User says "also", "and", "actually", "another thing about..."
- User references something just discussed

Pick new when:
- Different topic from any recent note
- User is clearly starting a fresh thought

When in doubt, update the most recent related note rather than creating a fragment.

## Linking

- **Internal links**: Use `[[note title]]` to link to other Bear notes. Bear resolves these automatically.
- **External links**: Use standard markdown `[text](url)`.
- **When indexing or summarizing multiple notes**: add `[[wiki links]]` to every referenced note.

## Notes

- Bear syncs across all devices via iCloud.
- Default tag is `note` — change it to fit your own tagging scheme.
- Always use Bear MCP tools, not URL schemes — URL schemes open Bear visually and have escaping issues.
- **If Bear MCP tools are unavailable:** write the note to `~/notes/pending/<slug>.md` and tell the user. Do NOT fall back to `open bear://` via bash — that is the banned path with extra steps. Fail visibly, don't improvise with prohibited tools.
