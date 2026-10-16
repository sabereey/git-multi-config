# Contributing

Thanks for taking a look. This project is deliberately small: a single bash script,
no build step, no runtime dependencies. Please keep it that way.

## Ground rules

1. **bash 3.2 must keep working.** macOS ships bash 3.2 and we support it. That means:
   - no associative arrays (`declare -A`)
   - no `mapfile` / `readarray`
   - no `${var^^}` / `${var,,}`
   - `"${arr[@]}"` on an empty array explodes under `set -u`
   - always terminate lines you feed to a `read` loop with `printf '%s\n'`
2. **No new dependencies.** No Node, Python, Go, `jq`, or `perl`. `awk`, `sed`, `grep`
   and core utils only.
3. **Every write is reversible.** If you touch a user file, back it up with
   `backup_file` first and make removal idempotent via the managed block.
4. **Never touch a user file outside the managed block.** Unrelated lines in
   `~/.gitconfig` or `~/.ssh/config` must survive byte-for-byte.

## Getting started

```bash
git clone https://github.com/sabereey/git-multi-config.git
cd git-multi-config

make test        # run the suite against whatever bash you have
make lint        # shellcheck, error level
make test-bash32 # force macOS system bash 3.2 if you have it
```

The test suite runs inside an isolated `HOME` created with `mktemp -d`, so it will not
read or modify your real `~/.gitconfig` or `~/.ssh/config`. If you find a test that
escapes that sandbox, that is a bug worth filing.

## What makes a good pull request

- **A failing test first.** `tests/smoke.sh` is a plain bash script with `assert_*`
  helpers and numbered scenarios. Add a scenario that fails before your fix and passes
  after. Assertion count is printed at the end — keep `failed: 0`.
- **Small and focused.** One behaviour change per PR.
- **Docs updated.** If you add a command, flag or environment variable, add it to
  `README.md`, `README.zh-CN.md`, `docs/manual.md` and `docs/manual.zh-CN.md`.
  Keep the English and Chinese versions in sync — they are maintained as a pair.
- **No personal data.** Do not put real names, real email addresses, real hostnames or
  real company identifiers into the script, tests, docs or examples. Use the
  placeholders already in the repo: `dev@corp.example.com`, `you@example.com`,
  `git.corp.com`, `gitlab.example.com`.

## Adding a language

Translations live in the `msg` / `msg_zh` style tables near the top of
`git-multi-config.sh`, as `key|English text` pairs. Adding a language means adding a
parallel table and a branch in the lookup function. Please also add the corresponding
`README.<lang>.md` and `docs/manual.<lang>.md`.

## Reporting a bug

Please include:

- output of `git-multi-config doctor`
- `bash --version` and `git --version`
- your OS
- what you expected vs what happened

**Redact your real email addresses, names and hostnames before pasting.**

## Scope

In scope: identity/key/remote handling per directory, auditing, hooks, portability,
documentation.

Out of scope: becoming a general-purpose Git wrapper, managing GitHub API tokens,
GUI applications, or anything requiring a daemon.

## License

By contributing you agree your work is released under the [MIT License](LICENSE).
