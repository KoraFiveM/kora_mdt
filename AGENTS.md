# kora_mdt agent guide

`kora_mdt` is a Kora records terminal for police, judge and medical jobs (`/mdt`), plus the Ammu-Nation weapon licence range and firearm registry. Layout: `fxmanifest.lua`, `config.lua` (`Config.mdt`), `shared/required.lua` (required-field rules shared by client and server), `server/schema.lua` and `server/boot.lua` (tables and startup), `server/main.lua` (callbacks, events, role checks, range and analysis logic), `client/terminal.lua` (the `kora_lib` NUI app), `client/main.lua` (command, range, targets, clerk ped), `test/` (offline Lua smoke tests, `./test/run.sh`) and `tests/` (kora_qa feature files).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first (overview and documentation map). Layout: `installation.md` (dependencies, start order, database wait, requirements, tests), `how-to-use.md` (opening the terminal, role checks and audit log, records, firearm licensing, weapon licence range, ballistic analysis), `commands.md` (`/mdt`), and topic pages `features.md`, `configuration.md`, `permissions.md`, `firearms-and-licences.md`, `events.md`, `database.md`, `troubleshooting.md`. The resource has no exports, so there is no `api/` section. Update the page that matches the change.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
