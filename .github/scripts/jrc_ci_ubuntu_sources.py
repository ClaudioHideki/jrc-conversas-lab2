"""Prepare only owned Ubuntu CI source URLs; APT still verifies signed metadata."""
import json
import os
from pathlib import Path
import platform
import re
import sys
from urllib.parse import urlsplit

MIRRORS = frozenset({"https://archive.ubuntu.com/ubuntu", "https://azure.archive.ubuntu.com/ubuntu",
                     "https://mirrors.edge.kernel.org/ubuntu"})
SUITES = frozenset({"noble", "noble-updates", "noble-backports", "noble-security"})
URL = re.compile(r"https?://[^\s]+")
REGIONAL = re.compile(r"[a-z0-9-]+\.ec2\.archive\.ubuntu\.com")
HOSTS = frozenset({"archive.ubuntu.com", "azure.archive.ubuntu.com", "security.ubuntu.com", "mirrors.edge.kernel.org"})
INSECURE = frozenset({"trusted", "allow-insecure", "allow-weak", "allow-downgrade-to-insecure"})


class SourceError(ValueError):
    pass


def ubuntu_uri(uri):
    parsed = urlsplit(uri)
    return parsed.hostname in HOSTS or bool(REGIONAL.fullmatch(parsed.hostname or ""))


def replace_uri(match, mirror):
    uri = match.group(0)
    parsed = urlsplit(uri)
    if not ubuntu_uri(uri):
        if (parsed.hostname or "").endswith(".ubuntu.com"):
            raise SourceError("unreviewed_ubuntu_host")
        return uri
    if parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path.rstrip("/") != "/ubuntu":
        raise SourceError("unsupported_ubuntu_source_uri")
    return mirror + ("/" if parsed.path.endswith("/") else "")


def split_comment(line):
    match = re.search(r"(^|[ \t])#", line)
    if not match:
        return line, ""
    position = match.end() - 1
    return line[:position], line[position:]


def rewrite_text(text, mirror):
    if mirror not in MIRRORS:
        raise SourceError("unreviewed_https_mirror")
    lines = []
    for line in text.splitlines(keepends=True):
        body, comment = split_comment(line)
        lines.append(URL.sub(lambda match: replace_uri(match, mirror), body) + comment)
    return "".join(lines)


def records(text, suffix):
    if suffix == ".list":
        for line in text.splitlines():
            active = split_comment(line)[0].strip()
            match = re.match(r"^(deb|deb-src)\s+(?:\[([^]]*)\]\s+)?(\S+)\s+(\S+)", active)
            if match:
                yield {"uris": match[3], "suites": match[4], "options": match[2] or ""}
        return
    for block in re.split(r"\n\s*\n", text):
        row = {}
        key = None
        for line in block.splitlines():
            active = split_comment(line)[0].rstrip()
            if not active.strip():
                continue
            if active[0].isspace() and key:
                row[key] += " " + active.strip()
            elif ":" in active:
                key, value = active.split(":", 1)
                key = key.lower()
                row[key] = value.strip()
        if row.get("enabled", "yes").lower() != "no" and row:
            yield row


def mirror_file(uri, root, texts):
    if not uri.startswith("mirror+file:"):
        return None
    parsed = urlsplit(uri[len("mirror+"):])
    if parsed.netloc or parsed.query or parsed.fragment:
        raise SourceError("unsupported_mirror_list")
    try:
        relative = Path(parsed.path).relative_to("/etc/apt")
    except ValueError:
        raise SourceError("mirror_list_outside_apt") from None
    target = root / relative
    if target.parent != root or not target.match("apt-mirrors*.txt") or target not in texts:
        raise SourceError("unreviewed_mirror_list")
    return [split_comment(line)[0].split()[0] for line in texts[target].splitlines() if split_comment(line)[0].strip()]


def validate_sources(texts, root, mirror):
    suites = set()
    count = 0
    for path, text in texts.items():
        if path.suffix not in {".list", ".sources"}:
            continue
        for row in records(text, path.suffix):
            uris = row.get("uris", "").split()
            ubuntu = "ubuntu-archive-keyring" in (row.get("signed-by", "") + row.get("options", ""))
            ubuntu |= any(ubuntu_uri(uri) or uri.startswith("mirror+file:") for uri in uris)
            if not ubuntu:
                continue
            disabled = {"no", "false", "0", "off"}
            insecure = any(key in row and row[key].lower() not in disabled for key in INSECURE)
            options = re.findall(r"(?:trusted|allow-insecure|allow-weak|allow-downgrade-to-insecure)\s*=\s*(\S+)",
                                 row.get("options", ""), re.I)
            insecure |= any(value.lower() not in disabled for value in options)
            if insecure or not uris:
                raise SourceError("insecure_or_missing_ubuntu_source")
            for uri in uris:
                effective = mirror_file(uri, root, texts) if uri.startswith("mirror+file:") else [uri]
                if not effective or any(value.rstrip("/") != mirror for value in effective):
                    raise SourceError("ubuntu_source_does_not_use_selected_https_mirror")
            configured = set(row.get("suites", "").split())
            if not configured or not configured <= SUITES:
                raise SourceError("unreviewed_ubuntu_suite")
            suites.update(configured)
            count += 1
    if suites != SUITES:
        raise SourceError("all_four_ubuntu_suites_are_required")
    return {"selected_mirror": mirror, "suites": sorted(suites), "ubuntu_source_records": count}


def prepare(root, mirror):
    root = Path(root).resolve()
    paths = [root / "sources.list", *(root / "sources.list.d").glob("*.list"),
             *(root / "sources.list.d").glob("*.sources"), *root.glob("apt-mirrors*.txt")]
    paths = sorted({path for path in paths if path.is_file()})
    if any(not path.resolve().is_relative_to(root) for path in paths):
        raise SourceError("source_outside_apt")
    before = {path: path.read_text(encoding="utf-8") for path in paths}
    after = {path: rewrite_text(text, mirror) for path, text in before.items()}
    result = validate_sources(after, root, mirror)
    # Validate every source before the first write. Keyrings, suites and options are retained.
    changed = [path for path in paths if before[path] != after[path]]
    for path in changed:
        path.write_text(after[path], encoding="utf-8", newline="\n")
    return {**result, "files_changed": len(changed)}


def main():
    expected = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted",
                "GITHUB_REPOSITORY": "ClaudioHideki/jrc-conversas-lab2", "RUNNER_OS": "Linux"}
    if platform.system() != "Linux" or any(os.environ.get(key) != value for key, value in expected.items()):
        raise SourceError("owned_disposable_linux_runner_required")
    release = Path("/etc/os-release").read_text(encoding="utf-8")
    if not re.search(r"^ID=ubuntu$", release, re.M) or not re.search(r"^VERSION_CODENAME=noble$", release, re.M):
        raise SourceError("ubuntu_noble_required")
    if len(sys.argv) != 2:
        raise SourceError("one_reviewed_mirror_required")
    print(json.dumps(prepare(Path("/etc/apt"), sys.argv[1])))


if __name__ == "__main__":
    try:
        main()
    except SourceError as error:
        print("Ubuntu source preparation refused: " + str(error), file=sys.stderr)
        raise SystemExit(1) from None
    except UnicodeError:
        print("Ubuntu source preparation refused: invalid_source_encoding", file=sys.stderr)
        raise SystemExit(1) from None
