#!/usr/bin/python3

# Looks in mailbox for "recipient doesn't exist" mails (identified via some
# criteria AI found that I haven't evaluated), does some heuristic
# canonicalisation, and prints them. 
#
# Set the not-dead tag to disable the detection of a message as a dead recipient
# notification. Set the dead-sender tag to manually mark the sender of an email
# as dead.
#
# Pass --cache to use a cached value if that's available.
# Pass --refresh to update the cache value from the current mailbox.

import argparse
import email
import email.policy
import os
import subprocess
import sys
import tempfile
from email.utils import getaddresses
from pathlib import Path


def default_cache_path():
    base = os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache"
    return Path(base) / "notmuch-get-dead-addresses" / "addresses"


def notmuch(*args):
    out = subprocess.run(
        ["notmuch", *args], capture_output=True, text=True, check=True
    ).stdout
    return out.splitlines()


def original_recipients(msg):
    """Addresses the bounced message was addressed to."""
    for part in msg.walk():
        if part.get_content_type() != "message/rfc822":
            continue
        payload = part.get_payload()
        if not payload:
            continue
        inner = payload[0]
        headers = inner.get_all("to", []) + inner.get_all("cc", [])
        return {a.lower() for _, a in getaddresses(map(str, headers)) if a}
    return set()


def canonicalize(rcpt, originals):
    """Undo alias expansion, e.g. foo@ant.amazon.com -> foo@amazon.co.uk.

    A DSN reports the address the failure happened at, which for a forwarded
    address is not the one worth filtering out of a reply.
    """
    if rcpt in originals:
        return rcpt
    local = rcpt.split("@")[0]
    matches = {a for a in originals if a.split("@")[0] == local}
    if len(matches) == 1:
        return matches.pop()
    return rcpt


def bounced_addresses(path):
    try:
        with open(path, "rb") as f:
            msg = email.message_from_binary_file(f, policy=email.policy.default)
    except Exception as e:
        print(f"{path}: {e}", file=sys.stderr)
        return
    originals = original_recipients(msg)
    for part in msg.walk():
        if part.get_content_type() != "message/delivery-status":
            continue
        for block in part.get_payload():
            action = (block.get("Action") or "").strip().lower()
            status = (block.get("Status") or "").strip()
            # Class 5 is permanent and subject 1 is "addressing"; the rest are
            # policy rejections and transient failures, which say nothing about
            # whether the address exists.
            if action != "failed" or not status.startswith("5.1."):
                continue
            rcpt = block.get("Original-Recipient") or block.get("Final-Recipient") or ""
            rcpt = rcpt.split(";", 1)[-1].strip().strip("<>").lower()
            if rcpt:
                yield canonicalize(rcpt, originals)


def harvest():
    dead = set()
    for path in notmuch(
        "search",
        "--output=files",
        "mimetype:message/delivery-status and not tag:not-dead",
    ):
        dead.update(bounced_addresses(path))
    for line in notmuch(
        "address", "--output=sender", "--deduplicate=address", "tag:dead-sender"
    ):
        dead.update(a.lower() for _, a in getaddresses([line]) if a)
    return sorted(dead)


def read_cache(path):
    try:
        content = path.read_text()
    except OSError:
        return None
    return [line for line in content.splitlines() if line]


def write_cache(path, addresses):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Readers get either the old file or the new one, never a partial write.
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("".join(a + "\n" for a in addresses))
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cache",
        action="store_true",
        help="print the cache, harvesting only if it is absent",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="harvest and write the cache",
    )
    parser.add_argument(
        "--cache-path",
        type=Path,
        default=default_cache_path(),
        help="where the cache lives (default: %(default)s)",
    )
    args = parser.parse_args()

    if args.refresh:
        addresses = harvest()
        write_cache(args.cache_path, addresses)
    elif args.cache:
        addresses = read_cache(args.cache_path)
        if addresses is None:
            addresses = harvest()
            write_cache(args.cache_path, addresses)
    else:
        addresses = harvest()

    print("\n".join(addresses))


if __name__ == "__main__":
    main()
