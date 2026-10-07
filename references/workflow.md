# Code map workflow

The shared method behind every code-map adapter. Your agent's `SKILL.md` tells you how to ask the user questions, whether you may use subagents, where your scratch folder is, and how to report cost; everything else lives here. `<skill-dir>` is the folder holding your `SKILL.md`; `assets/` and `references/` sit next to it.

One `markdown` file, mermaid diagrams, minutes not tens of minutes. The reader is an engineer who **will** open the source — give them the map that makes navigation fast.

Paths and identifiers are the point: name the real file, the real class, the real endpoint, so the reader can jump straight to it.

**Non-negotiables:**
- **Never publish an unverified claim.** Every load-bearing statement traces to a file you read or a value in the inventory. Write "not determined from the sources" rather than guessing, and label an inference as one.
- **Markdown is the deliverable.** No HTML, no headless browser, no publish step, no verification harness — unless your adapter offers an explicit publish flag and the user asked for it. Authoring HTML instead of markdown, or publishing uninvited, is out of scope.
- **Spend tokens like they are the user's money.** The scripted inventory before any subagent; no subagent at all on a small repo; never ask a subagent what the inventory already answered.

## Step 1 — Resolve the target, then inventory it

Take the target from the argument, ignoring any flags. No argument, or a flag alone → the working directory, said out loud.

A git URL → `git clone --depth 50 --single-branch <url>` into your scratch folder, never into the user's tree; depth 50 keeps `git shortlog` useful, and label the contributor list as recent activity only. If the clone fails on auth, SSO or network, say so and ask for a path or an archive rather than guessing at the contents. A source you can only read over the web means every path in the code-map table is unverified — label it and mark coverage partial. A folder of repos or a packaged artifact (jar/war/zip/tarball) → `<skill-dir>/references/source-ingestion.md`.

**Ask once, up front**, using the mechanism your adapter names. Before any exploration, ask the questions below in one go. Skip any question the arguments already answer (an explicit output path, "all related repos"), and ask nothing further until Step 4b. A target you cannot resolve unambiguously gets one extra question in the same round.

1. **Scope** — "Create the code map for this repo only, or for this repo and everything it is connected to?"
   - *This repo only (Recommended)* — fastest. Related services show up as edges and as Not determined rows, and can be appended later through Step 4b.
   - *This repo + related repos* — also explores the services, libraries and topics it talks to, using `<skill-dir>/references/source-ingestion.md` ("A folder of repos"). Takes noticeably longer and costs more; say so.
2. **Output path** — "Where should the code map be saved?"
   - *`<repo>/docs/code-map.md` (Recommended)* — reviewed in PRs with the code.
   - *`~/Downloads/<name>-code-map.md`* — outside the repo, nothing to commit.
   - Any custom path the user gives.

Your adapter may add questions (e.g. publishing). For a scratch clone or a repo the user does not own, make Downloads the recommended path instead and say why. State every answer back in one line ("this repo only, docs/code-map.md") and carry it into the final report.

**Related-repos scope.** Discover candidates the same way Step 4b does: sibling checkouts matched by service name, base URL, topic or client interface name, then repos derived from `git remote`. Show the list and confirm it before cloning or inventorying anything, then run the inventory once per repo. The map becomes one file with a landscape diagram up top, and each section notes which repo a row came from. Your adapter's subagent limits apply per deployable, capped in total as it says unless the user agrees to more.

Record the cost start marker as your adapter describes, then run the scripted inventory before reading anything by hand:

```bash
bash <skill-dir>/assets/inventory.sh <target dir> > <scratch>/code-map-facts.md
```

A few seconds buys provenance, size and shape, the source root, technology and versions, config shape with downstream URL keys, entry points, scheduling and messaging, entities and migrations (including ones imported from a shared library), API specs, outbound clients, framework pitfalls, test posture and ownership. Read it yourself before anything else, and never re-read by hand what it already printed (the build file above all).

**Keep the user posted.** Post one short line when each step starts, e.g. "inventory done, 7k lines, no subagents, reading the order flow", "writing docs/code-map.md". A run of several minutes with no update reads as a hang.

## Step 2 — Fill only the gaps

The inventory answers the repo-wide layer. What it cannot answer is behaviour that has to be traced through a call path: the 2-3 end-to-end flows, the business rules, what is retried.

**Under ~10k lines of main source, use no subagents** — your own reading is faster than briefing one. Above that, follow your adapter's subagent rule. Cap every subagent brief:

> Answer in at most 800 words. Aim for 20 file reads or fewer. This feeds a code map: give each claim a `file:line`. Never paste code blocks. Return the flows as ordered node+step lists.

Read in call order, one entry point at a time: controller/listener → service → repository → sender or remote client. Batch several files into one read, skipping imports and doc comments (`grep -v '^\s*\(import\|\*\|/\*\*\)'`), rather than opening them one by one. Every extra turn re-reads the whole context, so fewer, larger reads are the main lever on cost.

Verify each "Framework pitfalls" hit from the inventory at its call site before it goes in Risks & known issues. These are usually the highest-value findings in the map.

## Step 3 — Write the file

Fixed section order. Delete any section the sources do not support — an empty diagram is worse than no diagram.

**Title.** Take the repo name as it is and write it in Title Case, keeping acronyms upper case. Follow it with " — Code Map of the <process> Process", where <process> is the process the service runs, named in business words.

**Business summary.** Directly under the title, add one blockquote that opens with `**What it does for the business:**`. In 3-5 plain sentences, say:
- who triggers the process;
- the main steps, in order, through to the real-world outcome;
- the variants it handles;
- what the business can rely on it for.

Use no class names, file paths or config keys here, because a product owner should be able to read it. Write it only from flows you traced in Step 2, not from the repo's README or its name.

**Path root.** Under the summary, add one line saying which root the paths are relative to, using the inventory's "source root" (e.g. `src/main/kotlin/com/acme/orders/`), so the tables can use short paths.

1. **Overview** — two or three sentences: the job of this service and what it explicitly does not own.
2. **High Level Architecture** — mermaid `flowchart LR`: this service, its inbound callers, its outbound dependencies, its stores. Mark anything unverified with a dashed edge and say so in a caption.
3. **Key flows** — 2-3 mermaid `sequenceDiagram` blocks, the important paths only, each with its error branch. Participants are real components; name the entry point's path in the caption.
4. **Data model** — mermaid `erDiagram`, **only when entities or migrations were found**. Relationships you could not confirm from a mapping annotation or a foreign key are left out, not guessed. When the entities are only imported from a library, drop the ERD and give a short table instead: entity/repository → the file that uses it, and name the owning library.
5. **Module guide** — open with one line such as "Where each part of the codebase lives and what it is responsible for — start here to find your way around." Then a table: one row per module or package, with its responsibility and its path. This is where a newcomer looks to find where to start.
6. **Entry points** — HTTP endpoints, listeners, schedulers: what it is, what triggers it, where it lives.
7. **Tech stack** — table of technology, version and what it is used for. Versions come from the inventory, not from memory.
8. **Risks & known issues** — design risks, TODO/FIXME clusters, swallowed exceptions, disabled tests, anything the inventory flagged. Each row names a consequence, not just a location.
9. **Contacts & source** — owning team and contacts from the inventory's "Contacts and ownership" section (catalog-info owner, CODEOWNERS, main committers); then source path, remote, branch, commit SHA and generation date. End the section with a highlighted **Not determined** callout so gaps cannot be skimmed past. Use a plain blockquote, which renders in GitHub, IntelliJ and Confluence alike:

```markdown
> ⚠️ **Not determined from these sources**
>
> | Gap | Why it is open | Where the answer likely lives |
> |---|---|---|
> | Retry policy of `billing-service` on 5xx | Call leaves this repo via `BillingClient` | `billing-service` repo |
> | Consumer of topic `ocpi-events` | Only the producer side is in this repo | Service subscribed to `ocpi-events` |
```

Each row names the gap, why this repo cannot answer it, and the service, repo or artifact most likely to hold the answer. When nothing is open, write one line saying so instead.

Mermaid hygiene. The rules differ by diagram type:
- **flowchart**: quote any node or edge label containing `(`, `)`, `:`, `,`, `{` or `}`, e.g. `A["Contract Domain<br/>GET /contracts/{id}"]`. Keep labels short, and use `<br/>` for line breaks.
- **sequenceDiagram**: **never** quote a participant alias. `participant OC as v1 OrderController` is right, and a quoted alias renders with the quotes. Message, `alt`, `opt` and `Note` text runs to the end of the line and needs no quoting, but keep `;`, `#` and `-->`-like arrows out of it.
- **erDiagram**: entity names without spaces, and attribute types as single words.

If `mmdc` is already on PATH, pipe each block through it. Otherwise re-read every block against the rules above. Never install a renderer for this. A diagram that fails to parse is a failed run.

## Step 4 — Save and report

Save to the path chosen in Step 1, creating parent folders if needed. Without an answer the default is `docs/code-map.md` inside the target repo; a scratch clone that will be thrown away, or a repo the user does not own → `~/Downloads/<name>-code-map.md`, and say why. Re-runs overwrite the same path. Never write a file without saying what you are replacing. A re-run regenerates the whole file with the current section names, so a map written under an older template picks up renamed headings too.

Report: the absolute path, one line on what the map covers, **the 3-5 most important Risks & known issues rows** (one line each, with their `file:line`, so the user sees what matters without opening the file), the choices from Step 1, and the **Not determined** rows, highlighted the same way as in the map. If the repo keeps a changelog and the file is committed there, follow that repo's convention. Do not commit unless asked.

End the report with the run's cost as your adapter describes, as the very last step. It goes in the report only, never into `code-map.md`. If the script prints that usage is not available, say so in one line rather than estimating by hand.

## Step 4b — Offer to close the gaps

When the Not determined callout has rows, finish the report and then ask once — never before the map is saved:

- **Which gaps** to investigate (several may be picked; one option per gap, up to 4; group the rest under the likeliest owning service).
- **Where to look**:
  - *Local code* — sibling checkouts next to the target (its parent folder, then other clones under the same workspace root), matched by service name, base URL, topic or client interface name. List the directories you found.
  - *Remote repository* — a URL the user gives, or one you derive from this repo's `git remote` (same org/project, the other service's name). Show the derived URL and clone only after the user picks it, following Step 1's clone rules.
  - *Skip* — leave the gaps as documented.

When the user picks a source:
1. Locate the other repo, run `inventory.sh` on it into your scratch folder, and read only what the chosen gaps need — no full second map, and Step 2's subagent limits still apply.
2. Update `code-map.md` in place: move each answered gap into the section it belongs to (flow, diagram edge, Risks & known issues), cite it as `<other-repo>:path:line` with that repo's commit SHA added to Contacts & source, and turn dashed "unverified" edges solid only when the other side confirms them.
3. Leave any gap still unanswered in the callout, with the reason it stayed open.
4. Report which gaps closed and which did not, then re-run the cost step so the follow-up is costed.

A source the clone cannot reach (auth, SSO, network) stays a gap: say so and ask for a path.

## Self-check

- [ ] The up-front questions were asked once (or taken from the arguments) and echoed back before exploring.
- [ ] Inventory ran before any subagent; no subagent was asked what it answered.
- [ ] No subagents on a repo under ~10k lines; above it, only what your adapter allows.
- [ ] Every mermaid block parses; no empty or placeholder diagram survived.
- [ ] ERD present if and only if local entities or migrations exist; library-owned entities get the usage table instead.
- [ ] No sequence-diagram participant alias is quoted.
- [ ] Every "Framework pitfalls" hit was checked at its call site and is in Risks & known issues or dismissed.
- [ ] The path-root line sits under the title; the report lists the top Risks & known issues rows.
- [ ] Not determined is a highlighted callout with gap / why / where columns, repeated in the report, and the user was offered local or remote exploration for it.
- [ ] The user got a progress line at each step.
- [ ] The code-map table's paths are real — spot-check three against the filesystem.
- [ ] Unverified claims are labelled or deleted; Contacts & source lists what is unknown.
- [ ] Contacts & source carries the owner/contacts, remote, branch, commit SHA and date.
- [ ] The report ends with the cost step's output (or its "not available" line), and `code-map.md` does not contain it.
