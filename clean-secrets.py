#!/usr/bin/env python3
"""Manage and beautify sourced shell secrets files."""

import difflib
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

import click

DEFAULT_PATH = Path.home() / ".secrets"
GENERIC_HEADS = {"API", "SECRET", "DEFAULT", "MY", "THE", "APP", "DB"}
VALID_NAME = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
EXPORT_RE = re.compile(r'^export\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)')


# ── Parsing ──────────────────────────────────────────────────────────

def parse_lines(text):
    for lineno, line in enumerate(text.splitlines(), 1):
        stripped = line.rstrip()
        if not stripped:
            yield ("blank", lineno)
        elif stripped.startswith("#"):
            yield ("comment", stripped, lineno)
        else:
            m = EXPORT_RE.match(stripped)
            if m:
                name, value = m.group(1), m.group(2)
                yield ("export", infer_prefix(name), name, value, stripped, lineno)
            else:
                yield ("other", stripped, lineno)


def infer_prefix(name):
    parts = name.split("_")
    if len(parts) >= 2 and parts[0] in GENERIC_HEADS:
        return "_".join(parts[:2])
    return parts[0]


# ── Linting ──────────────────────────────────────────────────────────

class Diagnostic:
    __slots__ = ("level", "line", "msg")

    def __init__(self, level, line, msg):
        self.level = level  # "error", "warn"
        self.line = line
        self.msg = msg

    def __str__(self):
        tag = click.style(f"  {self.level}", fg="red" if self.level == "error" else "yellow")
        loc = click.style(f"L{self.line}", fg="white", bold=True)
        return f"{tag} {loc}: {self.msg}"


def lint(text):
    """Return list of Diagnostics."""
    diags = []
    records = list(parse_lines(text))

    # track all exports: name -> [(value, lineno), ...]
    seen = {}
    for rec in records:
        if rec[0] == "export":
            _, _, name, value, _, lineno = rec
            seen.setdefault(name, []).append((value, lineno))

    for rec in records:
        if rec[0] == "other":
            _, raw, lineno = rec
            # shebang is fine
            if lineno == 1 and raw.startswith("#!"):
                continue
            # bare assignment without export
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)', raw)
            if m:
                diags.append(Diagnostic("warn", lineno,
                    f"bare assignment `{m.group(1)}=...` — missing `export`?"))
                continue
            # something that looks like a broken export
            if raw.startswith("export"):
                diags.append(Diagnostic("error", lineno,
                    f"malformed export: `{raw}`"))
                continue
            # unset — valid shell, but worth noting
            um = re.match(r'^unset\s+([A-Za-z_][A-Za-z0-9_]*)', raw)
            if um:
                diags.append(Diagnostic("warn", lineno,
                    f"`unset {um.group(1)}` — intentional?"))
                continue
            # source / eval / conditional — acceptable shell
            if re.match(r'^(source |\.|\[|if |fi$|then$|else$|elif |for |done$|do$|case |esac$|eval )', raw):
                continue
            diags.append(Diagnostic("warn", lineno,
                f"unrecognised line: `{raw}`"))

        elif rec[0] == "export":
            _, _, name, value, _, lineno = rec
            # quoting issues
            for q in ('"', "'"):
                count = value.count(q)
                if count % 2 != 0:
                    diags.append(Diagnostic("error", lineno,
                        f"`{name}`: unmatched {q} in value"))
            # unquoted value with spaces
            if " " in value and not (value.startswith('"') or value.startswith("'")):
                # allow $(...) and ${...} and heredoc-style
                if not re.match(r'^\$[\({]', value):
                    diags.append(Diagnostic("warn", lineno,
                        f"`{name}`: unquoted value contains spaces"))
            # empty value
            if value in ('', '""', "''"):
                diags.append(Diagnostic("warn", lineno,
                    f"`{name}`: empty value"))

    # duplicates
    for name, occurrences in seen.items():
        if len(occurrences) < 2:
            continue
        values = set(v for v, _ in occurrences)
        lines = [ln for _, ln in occurrences]
        if len(values) > 1:
            diags.append(Diagnostic("error", lines[-1],
                f"`{name}`: conflicting values on lines {', '.join(map(str, lines))}"))
        else:
            diags.append(Diagnostic("warn", lines[-1],
                f"`{name}`: duplicate export on lines {', '.join(map(str, lines))}"))

    diags.sort(key=lambda d: d.line)
    return diags


# ── Grouping ─────────────────────────────────────────────────────────

def group_exports(records):
    all_records = list(records)

    # deduplicate: last export of each name wins
    last_index = {}
    for i, rec in enumerate(all_records):
        if rec[0] == "export":
            last_index[rec[2]] = i

    dupes = 0
    deduped = []
    for i, rec in enumerate(all_records):
        if rec[0] == "export" and last_index[rec[2]] != i:
            dupes += 1
            continue
        deduped.append(rec)

    groups = []
    comments, exports, prefix = [], [], None

    def flush():
        nonlocal comments, exports, prefix
        if exports or comments:
            groups.append({"comments": comments, "exports": exports, "prefix": prefix})
        comments, exports, prefix = [], [], None

    for rec in deduped:
        if rec[0] == "blank":
            flush()
        elif rec[0] == "comment":
            if exports:
                flush()
            comments.append(rec[1])
        elif rec[0] == "export":
            p = rec[1]
            if prefix is not None and p != prefix:
                flush()
            prefix = p
            exports.append(rec)
        elif rec[0] == "other":
            flush()
            groups.append({"other": rec[1]})
    flush()
    return groups, dupes


# ── Sorting ──────────────────────────────────────────────────────────

def sort_groups(groups):
    header, export_groups, other = [], [], []
    for g in groups:
        if "other" in g:
            other.append(g)
        elif not g.get("exports"):
            (header if not export_groups else export_groups).append(g)
        else:
            export_groups.append(g)
    export_groups.sort(key=lambda g: (g.get("prefix") or "zzz").lower())
    return header + export_groups + other


# ── Rendering ────────────────────────────────────────────────────────

def render_group(group, align):
    if "other" in group:
        return [group["other"]]
    lines = list(group.get("comments", []))
    exports = sorted(group.get("exports", []), key=lambda r: r[2])
    if not exports:
        return lines
    width = max(len(r[2]) for r in exports) if align else 0
    for rec in exports:
        name, value = rec[2], rec[3]
        n = name.ljust(width) if align else name
        lines.append(f"export {n}={value}")
    return lines


def render_all(groups, align):
    blocks = ["\n".join(render_group(g, align)) for g in groups if render_group(g, align)]
    return "\n\n".join(blocks) + "\n"


# ── Mutation helpers ─────────────────────────────────────────────────

def write_with_backup(path, content):
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = path.with_suffix(f".{ts}.bak")
    shutil.copy2(path, backup)
    os.chmod(str(backup), 0o600)
    path.write_text(content)
    os.chmod(str(path), 0o600)
    return backup


def set_export(text, name, value, quote=True):
    """Set or update an export in raw text. Returns (new_text, action)."""
    if quote and not (value.startswith('"') or value.startswith("'")):
        value = f'"{value}"'
    new_line = f"export {name}={value}"
    lines = text.splitlines()

    # find existing — replace last occurrence
    last_idx = None
    for i, line in enumerate(lines):
        m = EXPORT_RE.match(line.strip())
        if m and m.group(1) == name:
            last_idx = i

    if last_idx is not None:
        lines[last_idx] = new_line
        return "\n".join(lines) + "\n", "updated"

    # append: find the right group by prefix, or add at end
    prefix = infer_prefix(name)
    insert_after = None
    for i, line in enumerate(lines):
        m = EXPORT_RE.match(line.strip())
        if m and infer_prefix(m.group(1)) == prefix:
            insert_after = i

    if insert_after is not None:
        lines.insert(insert_after + 1, new_line)
    else:
        # append with blank line separator
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(new_line)

    return "\n".join(lines) + "\n", "added"


def remove_export(text, name):
    """Remove all lines that set or unset name. Returns (new_text, count_removed)."""
    bare_re = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)=')
    unset_re = re.compile(r'^unset\s+([A-Za-z_][A-Za-z0-9_]*)')
    lines = text.splitlines()
    kept, removed = [], 0
    for line in lines:
        s = line.strip()
        m = EXPORT_RE.match(s) or bare_re.match(s) or unset_re.match(s)
        if m and m.group(1) == name:
            removed += 1
            continue
        kept.append(line)
    return "\n".join(kept) + "\n", removed


# ── Stats ────────────────────────────────────────────────────────────

def count_exports(text):
    return len(re.findall(r'^export\s+', text, re.MULTILINE))


def stat_line(orig, result, dupes, n_groups):
    parts = [f"{count_exports(result)} exports"]
    if dupes:
        parts.append(f"{dupes} duplicates removed")
    parts.append(f"{n_groups} groups")
    return ", ".join(parts)


# ── Shared context ───────────────────────────────────────────────────

def build_context(path, do_sort, align):
    original = path.read_text()
    groups, dupes = group_exports(parse_lines(original))
    if do_sort:
        groups = sort_groups(groups)
    result = render_all(groups, align)
    n_groups = sum(1 for g in groups if g.get("exports"))
    return dict(path=path, original=original, result=result,
                groups=groups, dupes=dupes, n_groups=n_groups,
                sort=do_sort, align=align)


# ── CLI ──────────────────────────────────────────────────────────────

@click.group(invoke_without_command=True)
@click.option("--file", "-f", type=click.Path(exists=True), default=str(DEFAULT_PATH),
              help="File to process.")
@click.option("--sort/--no-sort", default=True, help="Sort groups by prefix.")
@click.option("--align/--no-align", default=True, help="Align = signs within groups.")
@click.pass_context
def cli(ctx, file, sort, align):
    """Manage and beautify sourced shell secrets files.

    Groups related exports by prefix, sorts alphabetically, aligns =
    signs, removes duplicates (last wins), normalizes whitespace.
    Creates a timestamped backup before any write.

    \b
    Examples:
        secrets                      # preview cleaned output
        secrets diff                 # unified diff
        secrets apply                # write (with backup)
        secrets lint                 # check for syntax errors
        secrets list                 # show groups and var names
        secrets set KEY "value"      # add or update a secret
        secrets rm KEY               # remove a secret
        secrets grep vertex          # find vars by substring
        secrets check                # exit 1 if dirty
        secrets -f .env lint         # lint a different file
    """
    ctx.ensure_object(dict)
    ctx.obj.update(path=Path(file), sort=sort, align=align)

    if ctx.invoked_subcommand is None:
        o = build_context(ctx.obj["path"], sort, align)
        click.secho(f"── {stat_line(o['original'], o['result'], o['dupes'], o['n_groups'])} ──", fg="cyan")
        click.echo()
        click.echo(o["result"])
        click.secho("── run `secrets apply` to write, `secrets diff` to compare ──", fg="cyan")


@cli.command()
@click.pass_context
def diff(ctx):
    """Show unified diff of changes."""
    o = build_context(ctx.obj["path"], ctx.obj["sort"], ctx.obj["align"])
    d = list(difflib.unified_diff(
        o["original"].splitlines(keepends=True),
        o["result"].splitlines(keepends=True),
        fromfile=str(o["path"]),
        tofile=f"{o['path']} (cleaned)",
    ))
    click.echo("".join(d) if d else click.style("No changes.", fg="green"))


@cli.command()
@click.pass_context
def apply(ctx):
    """Write cleaned file (creates timestamped backup)."""
    o = build_context(ctx.obj["path"], ctx.obj["sort"], ctx.obj["align"])
    if o["original"] == o["result"]:
        click.secho("Already clean.", fg="green")
        return
    backup = write_with_backup(o["path"], o["result"])
    click.secho(f"Backup:  {backup}", fg="yellow")
    click.secho(f"Written: {o['path']}", fg="green")
    click.echo(f"  {stat_line(o['original'], o['result'], o['dupes'], o['n_groups'])}")


@cli.command()
@click.pass_context
def check(ctx):
    """Exit 1 if file would change (CI-friendly)."""
    o = build_context(ctx.obj["path"], ctx.obj["sort"], ctx.obj["align"])
    if o["original"] != o["result"]:
        click.echo(f"Dirty: {stat_line(o['original'], o['result'], o['dupes'], o['n_groups'])}")
        sys.exit(1)
    click.secho("Clean.", fg="green")


@cli.command("lint")
@click.pass_context
def lint_cmd(ctx):
    """Check for syntax errors, bad quoting, conflicts, and duplicates."""
    text = ctx.obj["path"].read_text()
    diags = lint(text)
    if not diags:
        n = count_exports(text)
        click.secho(f"OK — {n} exports, no issues.", fg="green")
        return
    errors = sum(1 for d in diags if d.level == "error")
    warns = sum(1 for d in diags if d.level == "warn")
    for d in diags:
        click.echo(str(d))
    click.echo()
    summary = []
    if errors:
        summary.append(click.style(f"{errors} error{'s' * (errors != 1)}", fg="red"))
    if warns:
        summary.append(click.style(f"{warns} warning{'s' * (warns != 1)}", fg="yellow"))
    click.echo(", ".join(summary))
    if errors:
        sys.exit(1)


@cli.command("list")
@click.option("--names", is_flag=True, help="Show variable names only.")
@click.pass_context
def list_cmd(ctx, names):
    """List groups and their variables (names only, no values)."""
    o = build_context(ctx.obj["path"], ctx.obj["sort"], ctx.obj["align"])
    for g in o["groups"]:
        if "other" in g:
            continue
        exports = g.get("exports", [])
        if not exports:
            for c in g.get("comments", []):
                click.echo(c)
            continue
        prefix = g.get("prefix", "?")
        var_names = sorted(r[2] for r in exports)
        if names:
            for n in var_names:
                click.echo(n)
        else:
            click.secho(f"{prefix} ({len(var_names)})", fg="cyan", bold=True)
            for n in var_names:
                click.echo(f"  {n}")


@cli.command("grep")
@click.argument("pattern")
@click.pass_context
def grep_cmd(ctx, pattern):
    """Show variables matching a pattern (names only, no values).

    Searches exports, bare assignments, and unset lines.
    """
    text = ctx.obj["path"].read_text()
    pat = pattern.lower()
    bare_re = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)=')
    unset_re = re.compile(r'^unset\s+([A-Za-z_][A-Za-z0-9_]*)')
    for line in text.splitlines():
        stripped = line.strip()
        m = EXPORT_RE.match(stripped)
        if m and pat in m.group(1).lower():
            click.echo(m.group(1))
            continue
        m = bare_re.match(stripped)
        if m and pat in m.group(1).lower():
            click.echo(click.style(m.group(1), fg="yellow") + "  (bare)")
            continue
        m = unset_re.match(stripped)
        if m and pat in m.group(1).lower():
            click.echo(click.style(m.group(1), fg="red") + "  (unset)")
            continue


@cli.command("set")
@click.argument("name")
@click.argument("value")
@click.option("--no-quote", is_flag=True, help="Don't auto-quote the value.")
@click.pass_context
def set_cmd(ctx, name, value, no_quote):
    """Add or update an export. Quotes value by default.

    \b
    Examples:
        secrets set OPENAI_API_KEY sk-abc123
        secrets set MY_FLAG true --no-quote
    """
    if not VALID_NAME.match(name):
        click.secho(f"Invalid variable name: {name}", fg="red", err=True)
        sys.exit(1)
    path = ctx.obj["path"]
    text = path.read_text()
    new_text, action = set_export(text, name, value, quote=not no_quote)
    backup = write_with_backup(path, new_text)
    click.secho(f"Backup:  {backup}", fg="yellow")
    colour = "green" if action == "added" else "cyan"
    click.secho(f"{action.capitalize()}: {name}", fg=colour)


@cli.command("rm")
@click.argument("names", nargs=-1, required=True)
@click.option("--dry-run", is_flag=True, help="Show what would be removed.")
@click.pass_context
def rm_cmd(ctx, names, dry_run):
    """Remove one or more exports by name.

    \b
    Examples:
        secrets rm OLD_API_KEY
        secrets rm KEY_A KEY_B KEY_C
        secrets rm OLD_KEY --dry-run
    """
    path = ctx.obj["path"]
    text = path.read_text()
    total = 0
    for name in names:
        text, removed = remove_export(text, name)
        if removed:
            label = f"  remove {name}" + (f" ({removed} occurrences)" if removed > 1 else "")
            click.echo(label)
            total += removed
        else:
            click.secho(f"  not found: {name}", fg="yellow")
    if not total:
        click.secho("Nothing to remove.", fg="yellow")
        return
    if dry_run:
        click.secho(f"\nDry run — {total} export(s) would be removed.", fg="cyan")
        return
    backup = write_with_backup(path, text)
    click.secho(f"\nBackup:  {backup}", fg="yellow")
    click.secho(f"Removed: {total} export(s)", fg="green")


@cli.command("dupes")
@click.option("--fix", is_flag=True, help="Remove duplicates (keep last, resolve conflicts interactively).")
@click.pass_context
def dupes_cmd(ctx, fix):
    """Show duplicate exports. With --fix, resolve them.

    Exact duplicates (same value): keeps last, removes earlier.
    Conflicts (different values): prompts which to keep.
    """
    path = ctx.obj["path"]
    text = path.read_text()
    records = list(parse_lines(text))

    # collect: name -> [(value, lineno, raw_line), ...]
    seen = {}
    for rec in records:
        if rec[0] == "export":
            _, _, name, value, raw, lineno = rec
            seen.setdefault(name, []).append((value, lineno, raw))

    duped = {k: v for k, v in seen.items() if len(v) > 1}
    if not duped:
        click.secho("No duplicates.", fg="green")
        return

    conflicts, exact = {}, {}
    for name, occ in sorted(duped.items()):
        values = set(v for v, _, _ in occ)
        if len(values) > 1:
            conflicts[name] = occ
        else:
            exact[name] = occ

    if exact:
        click.secho(f"\nExact duplicates ({len(exact)}):", fg="yellow", bold=True)
        for name, occ in sorted(exact.items()):
            lines = ", ".join(f"L{ln}" for _, ln, _ in occ)
            click.echo(f"  {name}  ({lines})")

    if conflicts:
        click.secho(f"\nConflicts ({len(conflicts)}):", fg="red", bold=True)
        for name, occ in sorted(conflicts.items()):
            click.echo(f"  {name}:")
            for val, ln, _ in occ:
                click.echo(f"    L{ln}: {val}")

    if not fix:
        total = sum(len(v) - 1 for v in duped.values())
        click.echo(f"\n{total} redundant export(s). Run with --fix to resolve.")
        return

    # fix: exact dupes — keep last automatically
    lines = text.splitlines()
    drop = set()
    for name, occ in exact.items():
        for _, ln, _ in occ[:-1]:
            drop.add(ln)

    # fix: conflicts — prompt
    for name, occ in sorted(conflicts.items()):
        click.secho(f"\n{name} has conflicting values:", fg="red")
        for i, (val, ln, _) in enumerate(occ, 1):
            click.echo(f"  [{i}] L{ln}: {val}")
        choice = click.prompt("Keep which? (number, or 'a' for all, 's' to skip)",
                              default=str(len(occ)))
        if choice.lower() == "s":
            continue
        if choice.lower() == "a":
            continue
        try:
            keep_idx = int(choice) - 1
            for i, (_, ln, _) in enumerate(occ):
                if i != keep_idx:
                    drop.add(ln)
        except (ValueError, IndexError):
            click.secho("  Skipping.", fg="yellow")

    if not drop:
        click.secho("Nothing to change.", fg="green")
        return

    new_lines = [l for i, l in enumerate(lines, 1) if i not in drop]
    new_text = "\n".join(new_lines) + "\n"
    backup = write_with_backup(path, new_text)
    click.secho(f"\nBackup:  {backup}", fg="yellow")
    click.secho(f"Dropped: {len(drop)} line(s)", fg="green")


if __name__ == "__main__":
    cli()
