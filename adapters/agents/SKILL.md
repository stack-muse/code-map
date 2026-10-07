---
name: code-map
description: 'Produce a single markdown code-map for a repo or package — high-level design overview, tech stack, mermaid high-level architecture diagram, sequence diagrams read out of the source, an ERD when database entities exist, and a module-responsibility-path table. Renders natively on GitHub, IntelliJ and Confluence. This is a code map, not a design document: file paths and type names are allowed and wanted. Output is markdown only, with no HTML and no publish step. Trigger when user says "code map", "map this repo", "diagram this service", "what does this repo do", "sequence diagram for <service>", or names a repo/jar and asks for an overview.'
---

# Code map generator — Codex, Cursor and other Agent Skills hosts

`<skill-dir>` is the folder containing this file (normally `~/.agents/skills/code-map`). **Read `<skill-dir>/references/workflow.md` first and follow it**; this file only adds the specifics for agents other than Claude Code.

Your scratch folder is `${TMPDIR:-/tmp}/code-map-<repo name>`; create it with `mkdir -p` before the first write.

## Asking questions

Ask Step 1's questions (scope, output path) once, in a single plain chat message: number them, list the options under each with the recommended one marked, and say "reply with your choices, or 'go' for the recommended defaults". Then stop and wait for the reply — do not start exploring in the same turn. Skip any question the user's request already answers; when it answers all of them, echo the answers and go straight on. Step 4b's gap question works the same way, with the gaps as a numbered list the user can pick several from.

## Subagents

Under ~10k lines of main source, use none. Above that, if your agent can start subagents (Cursor can), use at most 2, one per deployable, never two sharing a question, each with the brief cap from Step 2; on the related-repos scope the cap is still 2 in total unless the user agrees to more. If it cannot (Codex), trace only the 2-3 most important flows yourself, one deployable at a time, and say in the report which deployables were not traced.

## Cost

Use `--agent codex` when you are running in Codex and `--agent cursor` when you are running in Cursor. Before the inventory, record a start marker:

```bash
bash <skill-dir>/assets/usage.sh --agent <codex|cursor> start > <scratch>/code-map-start
```

As the very last step of the report:

```bash
bash <skill-dir>/assets/usage.sh --agent <codex|cursor> "$(cat <scratch>/code-map-start)"
```

Paste its output into the report unchanged: a `## Run cost` table with its caveat line in Codex, a one-line "not available" notice in Cursor. In any other agent, skip both commands and say in one line that run cost is not available.

## No publishing

There is no artifact step here. If the user asks for a shareable page, say that the markdown file renders as it is on GitHub, IntelliJ and Confluence, and leave it there.

## Self-check (in addition to workflow.md's)

- [ ] The questions went out in one chat message (or were answered by the request), and exploring started only after that.
- [ ] No subagents under ~10k lines; at most 2 above it, and none in an agent without them.
- [ ] The report ends with the `usage.sh` output, or the one-line "not available" notice.
