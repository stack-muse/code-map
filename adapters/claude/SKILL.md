---
name: code-map
description: 'Produce a single markdown code-map for a repo or package — high-level design overview, tech stack, mermaid high-level architecture diagram, sequence diagrams read out of the source, an ERD when database entities exist, and a module-responsibility-path table. Renders natively on GitHub, IntelliJ and Confluence. This is a code map, not a design document: file paths and type names are allowed and wanted. Output is markdown by default, with no HTML and no publish step; `--artifact` additionally publishes the finished map as a shareable page. Trigger when user says "code map", "map this repo", "diagram this service", "what does this repo do", "sequence diagram for <service>", or names a repo/jar and asks for an overview.'
argument-hint: '[repo-dir | package path | git URL] [--artifact]'
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Skill, Artifact
---

# Code map generator — Claude Code

`<skill-dir>` is the folder containing this file (normally `~/.claude/skills/code-map`). **Read `<skill-dir>/references/workflow.md` first and follow it**; this file only adds the Claude Code specifics. Your scratch folder is the session scratchpad.

## Asking questions

Ask Step 1's questions in **one `AskUserQuestion` call**, and add a third question:

- **Publish** — "Also publish the finished map as a shareable artifact page?"
  - *No, markdown only (Recommended)* — the file lives in the repo and diffs with the code.
  - *Yes, publish as artifact* — runs the artifact step below after the markdown is saved.

Skip it when `--artifact` was passed. Ignore `--artifact` when resolving the target path. Step 4b's gap question is one more `AskUserQuestion` call, with the gap list as `multiSelect: true`.

## Subagents

Above ~10k lines of main source, use at most 2 `Explore` agents with `model: "sonnet"`, one per deployable, never two sharing a question, each with the brief cap from Step 2. On the related-repos scope the cap is still 2 in total unless the user agrees to more.

## Cost

Before the inventory, record a start marker:

```bash
bash <skill-dir>/assets/usage.sh --agent claude start > <scratchpad>/code-map-start
```

As the very last step of the report (after the artifact step when it runs, so publishing is counted):

```bash
bash <skill-dir>/assets/usage.sh --agent claude "$(cat <scratchpad>/code-map-start)"
```

Paste its `## Run cost` table and total line into the report unchanged — it covers the main session and any subagents, per model. It is an estimate at API list prices; keep its caveat line.

## Optional: `--artifact`

Runs **only** when the argument list carries `--artifact`, the user picked *Yes, publish as artifact*, or asks for a shareable page in so many words. Never on your own initiative — the markdown file lives in the repo, gets reviewed in the PR and diffs with the code; a URL outside the repo goes stale invisibly, which is the worst failure mode for a document whose value is real file paths.

Order matters: save `code-map.md` first, then publish **that** content. The page is a rendering of finished sections, never a second draft. Re-authoring the map in HTML is the one mistake that makes this step expensive.

1. Load the `artifact-design` skill before writing a line of the page.
2. Carry every section across unchanged. Paths, type names and `file:line` references stay — they are the point of the map, and a nicer container does not change that.
3. Mermaid does not render itself in an artifact: load it from `cdn.jsdelivr.net/npm/` and initialise it with a theme that survives both colour schemes. A diagram that silently fails to render is a failed run — the markdown original renders natively, so a broken page is a pure regression.
4. Publish once, then report the URL **and** the markdown path. Do not iterate on styling unless asked.
5. The markdown file stays the source of truth. On a re-run, regenerate it and update the same artifact `url`; never leave two pages for one repo.

Expect this step to cost a multiple of the markdown-only write. If the user seems to want it out of habit rather than need, say what it adds and let them decide.

## Self-check (in addition to workflow.md's)

- [ ] Scope, publish and output path went into one `AskUserQuestion` call (or came from the arguments).
- [ ] At most 2 subagents, all `Explore` on Sonnet, and none under ~10k lines.
- [ ] Nothing was published unless `--artifact` was passed or chosen; the markdown file was written either way, and on `--artifact` both the URL and the path were reported.
- [ ] On `--artifact`: every mermaid block rendered in the page, and the sections match the markdown rather than having been rewritten.
- [ ] The start marker was recorded before the inventory; the report ends with the `usage.sh` run-cost table and total.
