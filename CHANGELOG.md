# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.1] - 2026-10-17

Nine issues from an external code review were reproduced on a real machine first, then
fixed. Two of the reported findings did not hold up and are documented as such in the
review response; three of the real ones turned out to be worse than reported.

### Fixed

- **`IdentityFile` is now quoted in `~/.ssh/config`** (all three places, not the two the
  review mentioned). A key path containing a space made ssh report
  `keyword identityfile extra arguments at end of line` and then
  `terminating, 1 bad configuration options` — that aborts the **whole** config file, so
  every unrelated host the user had configured stopped working, not just the two managed
  ones. Paths are passed through unchanged by `expand_path`, so `~/My Keys/id_ed25519`
  reaches the writer verbatim.
- **`audit` no longer dies silently.** `scan_repos` discarded `find`'s stderr, and with
  `pipefail` a `find` that could not read *any* subdirectory aborted `cmd_audit` before it
  printed a single line — zero bytes of output, exit code 1. An unreadable directory under
  a managed folder (a mount point, another user's directory) was enough to trigger it. The
  error is now surfaced per path and the scan continues.
- **`--depth` is validated.** `abc` and `2.5` used to produce empty output with exit code
  1; `0` and `-1` were accepted by BSD `find` and silently scanned nothing. All four now
  fail with a readable message.
- **The commit guard no longer blocks legitimate commits.** It parsed the two registered
  addresses out of `state.conf` with `sed`, which strips quotes but does not undo the
  backslash escaping that `printf '%q'` puts there. Registered addresses containing `!`,
  `'`, a space or `$` were therefore read back mangled and every commit was refused. The
  guard now asks `git config --file` for the two addresses, which uses the ini parser and
  has no quoting problem at all; the comparison is exact instead of a glob match.
  Addresses made only of characters `%q` leaves alone (`+`, `@`, `.`, `-`, `_`) were never
  affected.
- **`PERSONAL_DIRS` is validated.** A value consisting only of separators (`:`, `::`,
  `,,`, `;`) normalised to an empty string *after* the default-value fallback had already
  run, producing zero personal rules while still reporting "auto-switch rules active". It
  now fails with a message that points at the real cause. The completely empty value was
  never the problem — it correctly falls back to `~/personal`.
- **`init` warns when git is older than 2.36.** The `hasconfig:` remote-URL rules were
  skipped without a word; only `doctor` mentioned it. The warning now appears at the end of
  `init`, where the user is actually reading output.
- **`--lang` is position independent.** `audit --depth abc --lang en` reported the error in
  Chinese because arguments were processed left to right. `--lang` is now pre-scanned.

### Security

- **`load_state` parses `state.conf` instead of sourcing it.** Sourcing turned a data file
  into executable code: a planted `state.conf` (reachable through a redirected
  `GMC_HOME`/`XDG_CONFIG_HOME`) ran arbitrary commands with the user's privileges. The file
  is now read line by line, unknown keys are ignored, and values are decoded from
  `printf '%q'` form by a small pure-bash decoder — no `eval`, no `.`. Verified against 20
  values including empty strings, quotes, backticks, `$(...)` and non-ASCII paths.
- **`install.sh` can verify the download.** Set `GMC_SHA256=<hash>` to make the installer
  refuse a mismatch; without it the digest is printed so it can be pinned next time. A
  downloaded file that does not start with a bash shebang is rejected outright.

### Documentation

- Documented how the config directory is resolved (`GMC_HOME` → `XDG_CONFIG_HOME` →
  `~/.config`) and what that means for sandboxed scripts and CI — see manual §8 and the
  troubleshooting table.
- Added an FAQ entry (both READMEs) and a troubleshooting row for the most common false
  alarm: `git config user.email` returning the default identity in a folder under a managed
  directory. A `gitdir:` condition is only evaluated once Git has found a repository, so in
  a plain folder you observe the global default — and identities only matter inside a
  repository anyway.
- Added an indexable bilingual landing page (`docs/index.html`, `docs/zh/index.html`) with
  `og:`/`twitter:` cards, JSON-LD `SoftwareApplication` and `FAQPage` structured data,
  `hreflang` alternates, `robots.txt` and a sitemap, deployed to GitHub Pages by
  `.github/workflows/pages.yml`.

### Tests

- New `scenario D` in the smoke suite pins every one of the fixes above (15 assertions), so
  a regression is caught instead of shipped. Suite is now 63 assertions, green on bash
  3.2.57.

## [2.0.0] - 2026-10-16

The first release intended for public use. A full rewrite of the original
single-file prototype, keeping the same idea — the directory decides your identity.

### Added

- **Interactive wizard** (`init`) that asks for your directories, names, emails and
  SSH keys, then writes everything for you. Repeat runs are idempotent thanks to a
  managed block (`# >>> git-multi-config >>>`) with keyword-based removal.
- **`--answers-file`** for non-interactive setup, so a machine can be provisioned
  from a checked-in answer file. See `examples/answers.conf`.
- **Conditional-include engine** — one generated rules file
  (`~/.config/git-multi-config/includeif.conf`) holding `includeIf "gitdir:<dir>/"`
  rules, plus `hasconfig:remote.*.url:` rules on Git 2.36+ so a repository is matched
  by its remote URL even when it lives outside your managed directories.
- **Physical-path duplication** — each directory gets a second rule for its resolved
  physical path, so macOS symlinked paths (`/tmp` → `/private/tmp`, `/var/folders`)
  match reliably.
- **Dedicated SSH alias per profile** written to `~/.ssh/config` with
  `IdentitiesOnly yes`, and `core.sshCommand` set per profile so the right key is
  forced even when the alias is bypassed.
- **`audit`** — scans every repository under your directories and reports identity or
  remote mismatches. `audit --fix` repairs them. Also flags remotes that talk to your
  company host through the wrong user.
- **Commit guard** (optional) — a global `core.hooksPath` pre-commit hook that refuses
  to commit with an email you never registered. Bypass with `GMC_ALLOW_ANY=1`.
- **`doctor`** — checks git version, includes wired up, SSH keys present, SSH auth,
  hook health, and reports a pass/warn/fail summary.
- **Bilingual interface and docs** — English and Simplified Chinese, auto-detected
  from `LC_ALL` / `LANG`, overridable with `GMC_LANG=en|zh`.
- **`uninstall`** — removes every managed block and restores your previous
  `core.hooksPath`, leaving unrelated config untouched.
- **Timestamped backups** — every file this tool edits is copied to
  `<file>.bak.<timestamp>` before the first write.
- **Test suite** (`tests/smoke.sh`) — 48 assertions across three scenarios, run in an
  isolated `HOME` so your real configuration is never touched.
- **CI** — shellcheck gate (error level) plus the test suite on Ubuntu and macOS,
  including macOS system bash 3.2.
- **Docs** — `README.md`, `README.zh-CN.md`, and full operations manuals at
  `docs/manual.md` / `docs/manual.zh-CN.md`.

### Changed

- Rewritten from a linear prototype into subcommands: `init`, `audit`, `list`,
  `doctor`, `uninstall`, `help`.
- Directory lists in the answer file now accept `,`, `;` and `:` as separators, and
  paths containing spaces are supported.
- The generated `[include]` line is appended **last** in `~/.gitconfig`, so profile
  rules win over your global defaults.

### Fixed

- bash 3.2 compatibility: no associative arrays, no `mapfile`, no `${var^^}`, and
  `printf`-terminated reads so directory lists are never silently truncated by a
  missing trailing newline.
- Re-running `init` no longer overwrites the recorded previous `core.hooksPath`, so
  `uninstall` can restore it.
- Multi-byte characters immediately following a variable no longer break parsing on
  bash 3.2.

[Unreleased]: https://github.com/sabereey/git-multi-config/compare/v2.0.1...HEAD
[2.0.1]: https://github.com/sabereey/git-multi-config/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/sabereey/git-multi-config/releases/tag/v2.0.0
