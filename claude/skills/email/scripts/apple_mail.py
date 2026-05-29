#!/usr/bin/env python3
"""Apple Mail interface — send, reply, draft via AppleScript.

Usage:
    python apple_mail.py send --to TO --subject SUBJ --body BODY [--cc CC] [--account work|personal] [--attach FILE...]
    python apple_mail.py reply --message-id ID --body BODY [--account work|personal]
    python apple_mail.py draft --to TO --subject SUBJ --body BODY [--account work|personal]
    python apple_mail.py accounts
"""
import argparse, subprocess, sys, os, sqlite3, json, tempfile

ACCOUNTS = {
    "work": "Gmail",          # zmainen@neuro.fchampalimaud.org
    "personal": "Gmail",       # zmainen@gmail.com — disambiguated by sender address
    "cf": "CF",               # zmainen@fundacaochampalimaud.pt
}

SENDER = {
    "work": "zmainen@neuro.fchampalimaud.org",
    "personal": "zmainen@gmail.com",
    "cf": "zmainen@fundacaochampalimaud.pt",
}

_HAAK_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "..")
DB = {
    "work": os.path.join(_HAAK_DIR, "home", "zach", "data", "gmail", "work", "messages.db"),
    "personal": os.path.join(_HAAK_DIR, "home", "zach", "data", "gmail", "personal", "messages.db"),
}


def escape_as(s):
    """Escape string for AppleScript."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def send_email(to, subject, body, cc=None, account="work", attachments=None):
    """Send email via Apple Mail."""
    sender = SENDER[account]

    # Build recipient blocks
    to_list = [t.strip() for t in to.split(",")]
    to_block = "\n".join(
        f'make new to recipient at end of to recipients with properties {{address:"{escape_as(t)}"}}'
        for t in to_list
    )

    cc_block = ""
    if cc:
        cc_list = [c.strip() for c in cc.split(",")]
        cc_block = "\n".join(
            f'make new cc recipient at end of cc recipients with properties {{address:"{escape_as(c)}"}}'
            for c in cc_list
        )

    attach_block = ""
    if attachments:
        attach_lines = []
        for path in attachments:
            abs_path = os.path.abspath(path)
            attach_lines.append(
                f'make new attachment with properties {{file name:POSIX file "{escape_as(abs_path)}"}}'
            )
        attach_block = "\n".join(attach_lines)

    script = f'''
tell application "Mail"
    set newMsg to make new outgoing message with properties {{subject:"{escape_as(subject)}", content:"{escape_as(body)}", visible:false, sender:"{escape_as(sender)}"}}
    tell newMsg
        {to_block}
        {cc_block}
        {attach_block}
    end tell
    send newMsg
end tell
'''
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr.strip()}", file=sys.stderr)
        return False
    print(f"Sent to {to} from {sender}")
    return True


def create_draft(to, subject, body, cc=None, account="work"):
    """Create draft in Apple Mail (visible, not sent)."""
    sender = SENDER[account]

    to_list = [t.strip() for t in to.split(",")]
    to_block = "\n".join(
        f'make new to recipient at end of to recipients with properties {{address:"{escape_as(t)}"}}'
        for t in to_list
    )

    cc_block = ""
    if cc:
        cc_list = [c.strip() for c in cc.split(",")]
        cc_block = "\n".join(
            f'make new cc recipient at end of cc recipients with properties {{address:"{escape_as(c)}"}}'
            for c in cc_list
        )

    script = f'''
tell application "Mail"
    set newMsg to make new outgoing message with properties {{subject:"{escape_as(subject)}", content:"{escape_as(body)}", visible:true, sender:"{escape_as(sender)}"}}
    tell newMsg
        {to_block}
        {cc_block}
    end tell
end tell
'''
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr.strip()}", file=sys.stderr)
        return False
    print(f"Draft created for {to} from {sender}")
    return True


def reply_email(message_id, body, account="work"):
    """Reply to a message. Looks up original in SQLite, constructs reply via Mail."""
    db_path = DB.get(account)
    if not db_path or not os.path.exists(db_path):
        print(f"No database for account '{account}'", file=sys.stderr)
        return False

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    row = conn.execute(
        "SELECT subject, sender, recipients, thread_id FROM messages WHERE id = ? OR message_id = ?",
        (message_id, message_id)
    ).fetchone()
    conn.close()

    if not row:
        print(f"Message {message_id} not found in {account} DB", file=sys.stderr)
        return False

    sender_data = json.loads(row["sender"])
    reply_to = sender_data.get("email", "")
    subject = row["subject"]
    if not subject.lower().startswith("re:"):
        subject = f"Re: {subject}"

    return send_email(reply_to, subject, body, account=account)


def list_accounts():
    """List Apple Mail accounts."""
    result = subprocess.run(
        ["osascript", "-e", '''
tell application "Mail"
    set accts to {}
    repeat with a in accounts
        set end of accts to (name of a) & " | " & (email addresses of a as string) & " | " & (enabled of a as string)
    end repeat
    return accts
end tell
'''],
        capture_output=True, text=True
    )
    print(result.stdout.strip())


def main():
    p = argparse.ArgumentParser(description="Apple Mail CLI")
    sub = p.add_subparsers(dest="command")

    s = sub.add_parser("send")
    s.add_argument("--to", required=True)
    s.add_argument("--subject", required=True)
    s.add_argument("--body", required=True)
    s.add_argument("--cc")
    s.add_argument("--account", default="work", choices=["work", "personal", "cf"])
    s.add_argument("--attach", nargs="*")

    r = sub.add_parser("reply")
    r.add_argument("--message-id", required=True)
    r.add_argument("--body", required=True)
    r.add_argument("--account", default="work", choices=["work", "personal", "cf"])

    d = sub.add_parser("draft")
    d.add_argument("--to", required=True)
    d.add_argument("--subject", required=True)
    d.add_argument("--body", required=True)
    d.add_argument("--cc")
    d.add_argument("--account", default="work", choices=["work", "personal", "cf"])

    sub.add_parser("accounts")

    args = p.parse_args()

    if args.command == "send":
        send_email(args.to, args.subject, args.body, args.cc, args.account, args.attach)
    elif args.command == "reply":
        reply_email(args.message_id, args.body, args.account)
    elif args.command == "draft":
        create_draft(args.to, args.subject, args.body, args.cc, args.account)
    elif args.command == "accounts":
        list_accounts()
    else:
        p.print_help()


if __name__ == "__main__":
    main()
