---
name: email
description: "Search, read, and send email. Reads from IMAP-synced DB (works on any machine via federation) or Apple Mail's local index (macOS fallback); sends via Apple Mail AppleScript — no OAuth, no HAAK dependency. Use when the user wants to find, read, or send email."
---

# /email — Search, read, and send email

Two read surfaces: IMAP-synced DB (primary, works on any machine) and Apple Mail
Envelope Index (macOS fallback). Sends via the bundled `scripts/apple_mail.py`
(AppleScript). No OAuth tokens, no external services.

## Reading (IMAP-synced DB — works on any machine)

The IMAP sync (`imap-mail-sync.py`) runs on the mini, populating SQLite databases
with full message content. Federation replicates these to every machine via
`infra/var/mail-*.db`. This is the primary search surface — use it first.

### Databases
- **Work:** `$HAAK_ROOT/infra/var/mail-gmail-work.db` (zmainen@neuro.fchampalimaud.org)
- **Personal:** `$HAAK_ROOT/infra/var/mail-gmail-personal.db` (zmainen@gmail.com)
- **Proton:** `$HAAK_ROOT/infra/var/mail-proton.db`

If `$HAAK_ROOT` is not set, use `~/Projects/haak`.

### Schema
- `messages` — `id`, `message_id` (UNIQUE), `thread_id`, `sender` (JSON: `{"name":"...","email":"..."}`), `recipients` (JSON array), `subject`, `body`, `timestamp` (DATETIME), `is_read`, `is_outgoing`, `has_attachments`, `attachments` (JSON), `in_reply_to`, `references`, `is_starred`, `last_indexed`

### Search by sender
```sql
sqlite3 "file:infra/var/mail-gmail-work.db?mode=ro" "
  SELECT id, datetime(timestamp,'localtime') ts,
         json_extract(sender,'$.name') name,
         json_extract(sender,'$.email') email, subject
  FROM messages
  WHERE (json_extract(sender,'$.name') LIKE '%QUERY%'
         OR json_extract(sender,'$.email') LIKE '%QUERY%')
  ORDER BY timestamp DESC LIMIT 20"
```
- **By subject:** `WHERE subject LIKE '%QUERY%'`
- **By date:** `WHERE timestamp >= '2026-06-01'`
- **Outgoing only:** `WHERE is_outgoing = 1`
- **Thread:** `WHERE thread_id = (SELECT thread_id FROM messages WHERE id = MSG_ID)`

### Read a body
```sql
sqlite3 "file:infra/var/mail-gmail-work.db?mode=ro" "
  SELECT body FROM messages WHERE id = MSG_ID"
```

Bodies are stored inline — no need for `.emlx` file lookups.

## Reading (Apple Mail — macOS fallback)

When the IMAP-synced DB is empty or unavailable, fall back to Apple Mail's local
Envelope Index. This only works on macOS machines with Mail.app configured.

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
- **Thread:** `WHERE m.conversation_id = CONVERSATION_ID ORDER BY m.date_received ASC`

### Read a body (Apple Mail only)
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
