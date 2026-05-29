---
name: email
description: "Search, read, and send email. Reads Apple Mail's local index (macOS, always live); sends via Apple Mail AppleScript — no OAuth, no HAAK dependency. Use when the user wants to find, read, or send email."
---

# /email — Search, read, and send email

Self-contained: reads from Apple Mail's local SQLite index, sends via the bundled
`scripts/apple_mail.py` (AppleScript). No OAuth tokens, no external services.

## Reading (Apple Mail — always live, no sync)

Apple Mail syncs all IMAP/Exchange accounts locally. The Envelope Index is a SQLite
DB with metadata for every message; `.emlx` files on disk hold full bodies + attachments.

- **DB:** `~/Library/Mail/V10/MailData/Envelope Index` (the `V*` number varies by macOS — `ls ~/Library/Mail/` to confirm)
- **Open read-only:** `sqlite3 "file:$HOME/Library/Mail/V10/MailData/Envelope Index?mode=ro"`
- **Never write** to these DBs.

### Tables
- `messages` — one row/message. `sender`, `subject` are FKs (→ `addresses.ROWID`, `subjects.ROWID`). `date_received` = Unix epoch. `conversation_id` groups threads.
- `addresses` — `ROWID`, `address`, `comment` (display name)
- `subjects` — `ROWID`, `subject`
- `attachments` — `ROWID`, `message` (FK), `name`

### Search by subject
```sql
sqlite3 "file:$HOME/Library/Mail/V10/MailData/Envelope Index?mode=ro" "
  SELECT m.ROWID, datetime(m.date_received,'unixepoch') ts,
         a.comment sender_name, a.address sender_email, s.subject, m.conversation_id
  FROM messages m
  JOIN addresses a ON m.sender=a.ROWID
  JOIN subjects  s ON m.subject=s.ROWID
  WHERE s.subject LIKE '%QUERY%'
  ORDER BY m.date_received DESC LIMIT 20"
```
- **By sender:** `WHERE (a.comment LIKE '%NAME%' OR a.address LIKE '%EMAIL%')`
- **By date:** `WHERE m.date_received >= strftime('%s','2026-01-01')`
- **Attachments:** join `attachments att ON att.message=m.ROWID WHERE att.name LIKE '%.pdf%'`
- **Thread:** `WHERE m.conversation_id = CONVERSATION_ID ORDER BY m.date_received ASC`

### Read a body
Bodies are in `.emlx` files, not the index:
```bash
find ~/Library/Mail/V10 -name "ROWID.emlx" 2>/dev/null
```

## Sending (bundled AppleScript — no OAuth)

Use the skill's own script:
```bash
python3 ~/.claude/skills/email/scripts/apple_mail.py send \
    --to "recipient@example.com" --subject "Subject" --body "Body" \
    --account work --attach /path/to/file.pdf
```
- `draft` — same args as `send`, but opens in Mail.app instead of sending.
- `reply --message-id <id> --body <b> --account <a>` — replies in-thread. **Note:** `reply` looks up the original in a per-account message DB; if that DB isn't present it will error — compose a new `send` instead.
- `accounts` — list configured accounts.

**Accounts** (`--account`): `work` = zmainen@neuro.fchampalimaud.org · `personal` = zmainen@gmail.com · `cf` = zmainen@fundacaochampalimaud.pt. Default: `work`.

**CONFIRMATION REQUIRED — no exceptions.** Before any send/reply/forward, show the user the full rendered email (To, Cc, Subject, Body, Attachments) and the sending account, then wait for explicit "yes" / "send it". Never send speculatively.

### Alternative send path
If `google-workspace` MCP is available and the account is Gmail, `send_gmail_message`
also works (needs one-time OAuth). Prefer the bundled AppleScript path — it covers all
three accounts with no auth.

## Email markdown format

For display, saving, and source references.

```markdown
---
type: email
message_id: "19c8c1152c94a064"
account: work
date: 2026-02-23
---

**From:** Name <addr>
**To:** addr
**Date:** 2026-02-23 19:53
**Subject:** ...

---

Body text.
```

**Source reference** when citing in a note:
`[Sender, "Subject", 2026-02-23](email:19c8c1152c94a064)` — resolve via
`SELECT * FROM messages WHERE ROWID = <id>`.

## Principles
- Reads are free (local SQLite, instant). Prefer Apple Mail index for all metadata search.
- Writes via Apple Mail AppleScript — no tokens, no expiry, all accounts.
- Always preview + confirm before sending.
