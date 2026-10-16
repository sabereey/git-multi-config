# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The smoke suite now isolates `XDG_CONFIG_HOME` and the `GMC_*` variables, not only
  `HOME`. The config directory resolves through `XDG_CONFIG_HOME`, so on a runner that
  presets it the generated files landed outside the throwaway `HOME`; every path
  assertion then missed and an unguarded `grep` aborted the run. CI is green on both
  Ubuntu and macOS again.
- Test failures now print the relevant log and emit a GitHub Actions annotation, so a
  failure is diagnosable without access to the job log.
- Guarded command substitutions in the test suite so a single missing file can no
  longer abort the whole run.

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

[Unreleased]: https://github.com/sabereey/git-multi-config/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/sabereey/git-multi-config/releases/tag/v2.0.0
