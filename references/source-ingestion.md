# Source ingestion

For the cases `~/.claude/skills/code-map/assets` cannot just be pointed at. Work inside the scratchpad (`CM=<scratchpad>/code-map`); never write clones or extracted archives into the user's tree.

A local repository needs nothing from this file — run the inventory on it directly.

## A folder of repos (the "landscape" case)

`ls -1` the parent, keep directories containing `.git`. Confirm the list with the user before exploring — a parent folder often holds unrelated clones. Run the inventory once per repo.

Cross-links between services are the point of a multi-repo map, and no single inventory shows them: grep each repo for the others' service names, base URLs, topic names and client interface names. An edge you find in only one direction is still an edge — say which side you saw it from.

## Packaged artifact — jar, war, ear, zip, tgz, whl, nupkg

```bash
mkdir -p "$CM/pkg" && cd "$CM/pkg" && unzip -q <file>     # .tgz → tar xzf
shasum -a 256 <file>                                       # provenance for Contacts & source
```

Read, in order:
- `META-INF/MANIFEST.MF` — name, version, build JDK, Git-Commit / Implementation-Version.
- `META-INF/maven/**/pom.xml` or `pom.properties`, `package.json`, `*.nuspec` — dependencies and coordinates, which give you the tech-stack table and the framework.
- `BOOT-INF/classes/**` (Spring Boot) or `WEB-INF/classes/**`: `application*.yml`, `*.properties`, `logback*.xml`, `openapi*`/`swagger*`, Liquibase/Flyway migrations, message templates. These reveal endpoints, datasources, topics and feature flags without decompiling.
- `BOOT-INF/lib` / `WEB-INF/lib` listing — the real dependency set.
- `unzip -l <file> | grep -E '\.class$'` — the package tree **is** the code-map table here, since there are no source paths to cite. `javap -p -classpath <jar> <fqcn>` gives signatures for the key types. Do not decompile unless the user asks: infer behaviour from config, package structure, resource files and signatures, and mark in Contacts & source that the flows are inferred from a binary.
- `.dll`/`.pdb`, `.so` or minified JS bundles: read the manifest and any bundled config or sourcemaps, then say plainly which sections could not be evidenced.

## Hygiene

- Never print or embed a real secret, token, password, connection string or customer identifier. Name the setting and its file, and mark it as a secret instead.
- Redact internal hostnames and IPs unless the map is explicitly internal-only — ask if unsure.
- Record for Contacts & source: the source's identity + commit or checksum, the date, and anything you could not access.
