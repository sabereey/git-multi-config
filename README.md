# git-multi-config

[![CI](https://github.com/sabereey/git-multi-config/actions/workflows/ci.yml/badge.svg)](https://github.com/sabereey/git-multi-config/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![bash 3.2+](https://img.shields.io/badge/bash-3.2%2B-blue.svg)](#requirements)

**One command to set up company / personal multi-account Git on one machine.**

Company work goes to your company Git server with your company email and company SSH key.
Side projects go to GitHub with your personal identity.
You never switch anything by hand — the directory decides.

```
~/work/my-service   →  git@git.corp.com:team/my-service.git   (dev@corp.com, company key)
~/personal/dotfiles →  git@github.com:you/dotfiles.git        (you@example.com, personal key)
```

It also **audits existing repositories** for identity mismatches, **rewrites remotes** that bypass
your dedicated SSH alias, and can install a **pre-commit guard** that refuses to commit with an
unregistered email.

English | [中文说明](README.zh-CN.md) · **Manual: [English](docs/manual.md) / [中文操作手册](docs/manual.zh-CN.md)**

**Contents** · [Why](#why) · [Requirements](#requirements) · [Install](#install) · [Quick start](#quick-start) ·
[What it writes](#what-it-writes) · [Commands](#commands) · [Use cases](#use-cases) ·
[Commit guard](#the-commit-guard-optional) · [Comparison](#how-it-compares) · [FAQ](#faq)

---

## Why

Two accounts on one laptop cause three classic accidents:

| Accident | What this tool does |
|---|---|
| Company commit authored with your personal email | switches `user.name` / `user.email` by directory |
| `Permission denied (publickey)` because SSH picked the wrong key | forces the right key per profile via `core.sshCommand` |
| 30 older repos already have the wrong local config | `audit --fix` scans and repairs them |

---

## Requirements

- `bash` 3.2+ (macOS system bash works out of the box)
- `git` 2.13+ for conditional includes; `git` 2.36+ additionally enables remote-URL based rules
- Two SSH keys, one per account

> Nothing else. No Node, no Python, no Go, no daemon.

---

## Install

```bash
# install to ~/.local/bin (or $PREFIX)
curl -fsSL https://raw.githubusercontent.com/sabereey/git-multi-config/main/install.sh | bash

# or from a clone
git clone https://github.com/sabereey/git-multi-config.git
cd git-multi-config && ./install.sh

# or just run it in place, no install needed
./git-multi-config.sh init
```

## Quick start

```bash
git-multi-config init
```

You answer eight questions: company host, company key, company name/email, company dirs,
personal key, personal name/email, personal dirs, default identity. Then:

```
  Company server   git.corp.com  (alias: git.corp.com)
  Company identity Corp User <dev@corp.com>
  Company dirs     /Users/you/work
  Personal server  github.com
  Personal identity Personal User <you@example.com>
  Personal dirs    /Users/you/personal
  Default identity personal
  Commit guard     yes
```

```bash
git-multi-config list        # show what is configured
git-multi-config doctor --ssh
git-multi-config audit --fix
```

Verify inside a repo:

```bash
cd ~/work/anything && git config user.email   # → dev@corp.com
cd ~/personal/anything && git config user.email  # → you@example.com
```

---

## What it writes

| Path | Purpose |
|---|---|
| `~/.ssh/config` | managed block with one `Host` entry per account, `IdentitiesOnly yes` |
| `~/.gitconfig-company`, `~/.gitconfig-personal` | per-profile `user.*`, `core.sshCommand`, optional GPG |
| `~/.config/git-multi-config/includeif.conf` | all `includeIf` rules, generated |
| `~/.gitconfig` | one managed `[include]` line pointing at the file above |
| `~/.config/git-multi-config/state.conf` | minimal state (dirs, emails) used by `audit` / `doctor` |
| `~/.config/git-multi-config/hooks/pre-commit` | optional commit guard |

Two details that make it robust:

1. **The include block is always the last thing in `~/.gitconfig`**, so profile rules win over the
   global default identity no matter which one you picked.
2. **Each directory gets two rules: the logical path and the resolved physical path.** `gitdir:`
   matching follows physical paths, so on macOS (`/tmp`, `/var`, symlinked homes) one form alone
   silently fails to match.

Original `~/.ssh/config` and `~/.gitconfig` are backed up as `*.bak.<timestamp>` on every run.

---

## Commands

| Command | Description |
|---|---|
| `init` | interactive setup (default command) |
| `audit [--fix] [--depth n]` | scan managed dirs for identity mismatches; `--fix` repairs them |
| `list` | show current configuration |
| `doctor [--ssh]` | check git version, files, key permissions, hooks, optionally SSH login |
| `uninstall [--restore]` | remove everything it installed; `--restore` also reverts the newest backups |

Options: `--from-file <file>`, `-y`, `--lang zh\|en`, `--with-hooks`, `--fix`, `--depth`, `--ssh`, `--restore`.

### Automating it

```bash
cat > answers.conf <<'EOF'
COMPANY_HOST=git.corp.com
COMPANY_KEY=~/.ssh/id_ed25519_company
COMPANY_NAME=Corp User
COMPANY_EMAIL=dev@corp.com
COMPANY_DIRS=~/work:~/clients
PERSONAL_KEY=~/.ssh/id_ed25519
PERSONAL_NAME=Personal User
PERSONAL_EMAIL=you@example.com
PERSONAL_DIRS=~/personal
DEFAULT_ID=personal
INSTALL_HOOKS=1
EOF

git-multi-config init --from-file answers.conf --yes
```

`audit` exits non-zero when it finds issues, so it can be used as a CI/pre-commit gate:

```bash
git-multi-config audit || echo "wrong identity somewhere"
```

---

## The commit guard (optional)

When enabled, it sets the global `core.hooksPath` to a directory containing a `pre-commit` hook
that compares `git config user.email` against your two registered emails and refuses anything else:

```
[git-multi-config] Refusing to commit with wrong@example.com
[git-multi-config] Registered / 已登记: dev@corp.com you@example.com
[git-multi-config] Bypass: GMC_ALLOW_ANY=1 git commit ...
```

It is skipped automatically if `core.hooksPath` already points somewhere else (so Husky etc. keep
working), and it never touches repository-local hooks.

---

## Use cases

| Situation | What you do |
|---|---|
| Company GitLab/Gitea plus personal GitHub | `init`, two dirs, done |
| Both accounts on github.com | `init` detects it and creates the `github-work` alias |
| Dozens of existing repos with stale local config | `audit --fix` |
| Company repos cloned by accident outside the managed tree | git 2.36+ remote-URL rules, or `audit` reports them |
| Freelance / client work needs a third identity | put the repo under the client directory and point local config at it, or run a second configuration with `GMC_HOME` |
| Wrong email already reached a public repo | fix identity first (`audit`), then rotate the address or rewrite history |
| Setting up a new laptop | carry `answers.conf` and run `init --from-file answers.conf --yes` |

---

## How it compares

| | git-multi-config | plain `includeIf` | other account switchers |
|---|---|---|---|
| Zero dependencies | ✅ bash only | ✅ | often Go / Rust / Node |
| Directory auto-switch | ✅ | ✅ manual edit | ✅ |
| Right SSH key per directory | ✅ `core.sshCommand` | ❌ | ✅ mostly via host aliases |
| Audit + repair existing repos | ✅ | ❌ | rarely |
| Commit guard | ✅ opt-in | ❌ | rarely |
| Symlinked / physical path handling | ✅ | ❌ easy to get wrong | rarely |
| Interactive wizard | ✅ | ❌ | sometimes |

If you are comfortable hand-writing 10 lines of `.gitconfig`, do that — this tool exists for the
cases where you are not, or where you already have dozens of repos to fix.

---

## FAQ

**I already have a `Host github.com` block in `~/.ssh/config`.**
SSH uses the *first* matching value, so an older entry may win for direct clones. Your Git
operations in managed directories are unaffected: the per-profile `core.sshCommand` forces the
correct key regardless of SSH config. `init` warns when it detects this.

**Both my company and personal accounts are on github.com.**
Then the company entry gets the alias `github.com-work` (and `github.com-personal` is added for the
personal side). `audit --fix` rewrites `git@github.com:org/repo` remotes in company directories to
`git@github.com-work:org/repo` so the right key is always used.

**Does `core.sshCommand` affect other hosts inside a managed directory?**
Yes — inside `~/work`, any host is contacted with the company key. That is intentional and gives
deterministic behaviour; use `GIT_SSH_COMMAND` or a one-off clone elsewhere if you need otherwise.

**Which identity applies outside the managed directories?**
The one you chose as default. Repos cloned outside still get the right identity for the company
server on git 2.36+, thanks to `hasconfig:remote.*.url:` rules.

**Does it work with paths containing spaces?**
Yes.

**How do I move my setup to a new machine?**
Copy `answers.conf` (or run `init` again) — no state is hidden elsewhere. SSH keys are yours.

---

## Development

```bash
make test     # runs tests/smoke.sh in a throwaway HOME
make lint     # shellcheck
make install
```

The smoke suite covers the wizard, identity switching, the commit guard, audit + repair, idempotent
re-runs and uninstall, on both a private-server and a shared-host layout.

Full documentation: [Operations Manual](docs/manual.md) — wizard walkthrough, every command,
cookbooks, troubleshooting table, design notes.

## License

MIT — see [LICENSE](LICENSE).

English | [中文说明](README.zh-CN.md) · [中文操作手册](docs/manual.zh-CN.md)

<sub>git multiple accounts · git config per directory · includeIf gitdir · hasconfig remote url ·
separate SSH key per account · switch git identity automatically · wrong email in commits ·
company and personal git on one machine · core.sshCommand · git commit guard</sub>

