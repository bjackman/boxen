______________________________________________________________________

## name: investigate_mailing_list_history description: Investigates the history of review and discussion on the Linux kernel mailing list for a given commit across all series versions, including recursively discovered previous versions.

# Instructions

This skill helps you investigate the review history of a Linux kernel commit on the mailing list. It goes beyond a simple `b4 dig` by finding all iterations of the patchset, fetching them, and recursively discovering previous versions or critical context threads mentioned in the discussions.

## Workflow

1. **Find Versions**: Run `b4 dig -c <commit> --all-series` to discover all known versions of the series (`v2`, `v3`, `v4`, `v5`, etc.).

   If `b4` is not available, or the version doesn't include the `dig` command,
   STOP and ask the user what to do.
1. **Fetch Versions**: Download series mboxes for all versions found. Use `b4 mbox -o <outdir> <msgid>` for each version's series message ID.
1. **Recursively Discover Missing Versions**:
   - Parse the downloaded mbox files.
   - Read the cover letter or patches of the latest version.
   - Look for explicit links to previous series (e.g., `v1` links in cover letter text, or `https://lore.kernel.org/bpf/...` links).
   - If you find links to un-fetched versions (e.g., `v1`), fetch and parse them too.
1. **Detect References to Other Context Threads**:
   - While messages are parsed, look for URLs in email bodies (e.g., references to past discussions that are not part of the series versions).
   - Note these URLs. If a reference is critical to understand the current review (e.g., "as discussed in thread X"), fetch and read that thread proactively. Otherwise, just add it to a "References" section in the output.
1. **Output Generation**:
   - Generate a single Markdown file containing the history.
   - Order the versions chronologically or from oldest to newest.
   - For each version, include headers for each message and extract the body.
   - Format it as a tree or threaded list where replies are nested under their parent messages.

## Script Usage

A helper script is provided in `scripts/investigate_series.py` which automates steps 1-3 and generates an LLM-friendly Markdown output.

To run the script:

```bash
python3 scripts/investigate_series.py <commit_hash> <output_path>
```

## References

- `b4` tool documentation: https://people.kernel.org/kabi/using-b4-for-kernel-development
- public-inbox documentation: https://public-inbox.org/
