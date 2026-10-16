# git-multi-config — Operations Manual

Complete reference for installing, configuring, operating and troubleshooting `git-multi-config`.

[中文操作手册](manual.zh-CN.md) · [README](../README.md) · [中文说明](../README.zh-CN.md)

---

## Table of contents

1. [What this tool manages](#1-what-this-tool-manages)
2. [Requirements and supported platforms](#2-requirements-and-supported-platforms)
3. [Install and remove](#3-install-and-remove)
4. [Core concepts](#4-core-concepts)
5. [The setup wizard, question by question](#5-the-setup-wizard-question-by-question)
6. [Command reference](#6-command-reference)
7. [Cookbooks](#7-cookbooks)
8. [Files written and their format](#8-files-written-and-their-format)
9. [The commit guard](#9-the-commit-guard)
10. [Troubleshooting](#10-troubleshooting)
11. [Migrating to a new machine](#11-migrating-to-a-new-machine)
12. [Design notes and limitations](#12-design-notes-and-limitations)

---

## 1. What this tool manages

A developer laptop usually holds two sets of Git credentials. The failure modes are well known:

| Failure | Consequence |
|---|---|
| Commit authored with the wrong email | Personal email inside a corporate audit log, or a work email in a public repository — both permanent in history |
| SSH offers the wrong key | `Permission denied (publickey)` on a repository you definitely have access to |
| Keys tried in sequence instead of pinned | Works by luck today, breaks when a new key is added |
| Dozens of repos carrying their own stale local config | Wrong identity long after you "fixed" the global config |

`git-multi-config` addresses all four:

- **Identity selection is directory-based**, implemented with Git's own conditional includes — no wrapper around `git`, no shell hooks, nothing to remember.
- **Key selection is per-profile**, forced with `core.sshCommand`, so it does not depend on the order keys appear in `~/.ssh/config`.
- **Existing repositories are audited and repaired** with `audit --fix`, rather than assuming they are clean.
- **A commit guard can refuse** commits whose author email is not one of your registered identities.

## 2. Requirements and supported platforms

| Requirement | Detail |
|---|---|
| Shell | `bash` 3.2 or newer. macOS system bash is supported as-is |
| Git | 2.13+ (`includeIf`); 2.36+ additionally enables remote-URL based rules |
| SSH keys | one per account, standard `ssh-keygen` output |
| Optional | `gpg` if you want per-profile commit signing |

Verified platforms: macOS (including the system `bash` 3.2), Linux, WSL.
CI runs the full suite on `ubuntu-latest` and `macos-latest`.

There are no runtime dependencies beyond `bash` and `git` — no Node, Python, Go or background process.

Check your environment at any time:

```bash
git-multi-config doctor
```

## 3. Install and remove

### Option A — installer script

```bash
curl -fsSL https://raw.githubusercontent.com/sabereey/git-multi-config/main/install.sh | bash
```

Installs the script to `~/.local/bin/git-multi-config`. Choose a different location with `PREFIX`:

```bash
curl -fsSL .../install.sh | PREFIX=/usr/local/bin bash
```

### Option B — from a clone

```bash
git clone https://github.com/sabereey/git-multi-config.git
cd git-multi-config
./install.sh          # or: make install
```

### Option C — no installation

```bash
./git-multi-config.sh init
```

Every documented command works this way; nothing is written outside your home directory.

### Removing

```bash
git-multi-config uninstall            # remove all configuration it wrote
git-multi-config uninstall --restore  # also restore the newest *.bak.* backup
```

Removing the binary itself: `make uninstall`, or `rm ~/.local/bin/git-multi-config`.

## 4. Core concepts

**Profile** — a named identity bundle: user name, email, SSH key, optional GPG signing key.
This tool ships with exactly two: *company* and *personal*.

**Managed directory** — a project root assigned to a profile (for example `~/work` for company,
`~/personal` for personal). Every repository below it inherits that profile.

**Default identity** — the profile used outside all managed directories. You choose it during setup.

**How a commit resolves its identity** (highest priority last):

1. repository-local `user.email` in `.git/config` (you could set it manually; `audit` warns about it)
2. global default identity in `~/.gitconfig`
3. conditional rules loaded through the managed `[include]` line at the **end** of `~/.gitconfig`:
   - `includeIf "gitdir:<managed dir>/"` — the primary mechanism
   - `includeIf "hasconfig:remote.*.url:<host>/**"` — git 2.36+, covers repositories located outside managed directories

Because the include block is written last, profile rules always win over the global default.

**How a push authenticates** — each profile config sets:

```ini
[core]
	sshCommand = ssh -i "/path/to/key" -o IdentitiesOnly=yes
```

Inside a managed directory, that key is used for **every host**, regardless of `~/.ssh/config`.
The SSH `Host` entries the tool writes are a convenience for direct `ssh`/`git` use outside managed
directories, not the primary mechanism.

**Rules are written twice per directory** — once with the path you supplied and once with the
resolved physical path (`pwd -P`). `gitdir` matching follows physical paths, so on macOS where
`/tmp`, `/var` and sometimes a home directory are symlinks, a single form silently fails to match.

## 5. The setup wizard, question by question

```bash
git-multi-config init
```

| Prompt | Meaning | Notes |
|---|---|---|
| Company Git host | Domain of the company server | `git.corp.com`, `gitlab.example.com`. If it equals your personal host the tool adds an alias automatically |
| Company SSH private key | Path to the key for that account | `~` is expanded; a missing file is reported but does not abort |
| Company commit user.name | Author name for company commits | Required |
| Company commit user.email | Author email for company commits | Required, format validated |
| Company GPG signing key | Optional key id | Empty disables signing for this profile |
| Company dirs | Project roots, comma separated | Spaces in paths are supported |
| Personal host / key / name / email / GPG / dirs | Same, for the personal account | `PERSONAL_HOST` defaults to `github.com` |
| Default identity | 1 personal, 2 company | Applies outside managed directories |
| Commit guard | Install the pre-commit hook? | Default no; skipped automatically if `core.hooksPath` is already set |

Before writing anything the wizard prints a summary and asks for confirmation. Original
`~/.ssh/config` and `~/.gitconfig` are backed up as `*.bak.<timestamp>`.

Re-running `init` is safe: it is idempotent, previous values become the defaults, and the managed
blocks are replaced rather than duplicated.

## 6. Command reference

### `init`

Interactive setup, or non-interactive with an answer file.

```bash
git-multi-config init
git-multi-config init --from-file answers.conf --yes
git-multi-config init --with-hooks
git-multi-config init --lang en
```

| Option | Effect |
|---|---|
| `--from-file <file>` | read answers from a file, no prompts (implies `--non-interactive`) |
| `-y`, `--yes` | skip confirmation prompts |
| `--non-interactive` | use defaults for anything not supplied |
| `--with-hooks` | install the commit guard without asking |
| `--lang zh\|en` | output language (default `zh`, or `$GMC_LANG`) |
| `--ssh` | run SSH connectivity checks after writing |

### `audit`

Scans every repository under the managed directories and reports identity problems.

```bash
git-multi-config audit            # report only; exit 1 when issues are found
git-multi-config audit --fix      # repair what it finds
git-multi-config audit --depth 6  # look deeper than the default 4 levels
```

Three classes of issue are detected:

| Issue | Detection | Repair with `--fix` |
|---|---|---|
| Local override | `.git/config` sets `user.email` to something else | unsets local `user.email` / `user.name` so the directory rule applies |
| Wrong effective identity | the identity Git resolves is not the expected one | reported (fix the rule or the directory layout) |
| Alias-less remote | same host for both accounts, remote uses the shared host instead of the dedicated alias | rewrites the remote to the alias |

Typical output:

```
[info] Audit
! /Users/you/work/legacy-service
    local user.email overrides the switch rule: old@personal.dev (expect: dev@corp.com)
[ok]     fixed
[info] Repositories scanned: 92
[ok] Issues found: 1
```

Because it exits non-zero on findings, it works as a gate:

```bash
git-multi-config audit || echo "identity mismatch somewhere"
```

### `list`

Prints the active configuration: hosts, identities, managed directories, default profile,
guard status, state file path.

### `doctor`

Checks the environment and the installed configuration.

```bash
git-multi-config doctor
git-multi-config doctor --ssh     # also test SSH authentication for both accounts
```

Verifies: git version and `includeIf`/`hasconfig` support, presence and content of the rule file,
both managed blocks, key existence and `600` permissions, guard wiring, optionally SSH login.
Exits 1 if any check fails — useful right after setting up a new machine.

### `uninstall`

```bash
git-multi-config uninstall
git-multi-config uninstall --restore
```

Removes: the managed block in `~/.ssh/config`, the managed block in `~/.gitconfig`, the rule file,
both profile config files, the commit guard (restoring a previous `core.hooksPath` if there was one)
and the state file. Backups are kept; `--restore` copies the newest ones back.

### General options

| Option | Meaning |
|---|---|
| `--version`, `-V` | print version |
| `help`, `--help`, `-h` | print usage |
| `--lang=zh`, `--lang=en` | output language |

### Environment variables

| Variable | Purpose |
|---|---|
| `GMC_HOME` | override the state/config directory (default `${XDG_CONFIG_HOME:-~/.config}/git-multi-config`) |
| `GMC_SSH_CONFIG` | target a different SSH config file (useful in sandboxes and tests) |
| `GMC_GITCONFIG` | target a different global git config file |
| `GMC_LANG` | default output language |
| `NO_COLOR` | disable colored output |
| `GMC_ALLOW_ANY` | read by the commit guard: `1` bypasses the email check |

## 7. Cookbooks

### 7.1 Company server and personal GitHub on different hosts

The common case.

```bash
git-multi-config init
# company host:  git.corp.com     key: ~/.ssh/id_ed25519_company
# company dirs:  ~/work
# personal host: github.com       key: ~/.ssh/id_ed25519
# personal dirs: ~/personal
# default:       personal
```

On git 2.36+ this also writes remote-URL rules, so a company repository cloned to your Desktop
still gets the company identity.

### 7.2 Both accounts on the same host

Company and personal both on `github.com`: the wizard detects it, gives the company entry the alias
`github.com-work` and adds `github.com-personal` for the personal side.

```bash
git-multi-config audit --fix
```

rewrites company remotes from `git@github.com:org/repo.git` to `git@github-work:org/repo.git`.
Key selection inside managed directories already works without the alias, because `core.sshCommand`
is set per profile.

### 7.3 Several project directories, including paths with spaces

```ini
COMPANY_DIRS=~/work,~/clients/acme,~/work archive/2026
```

Comma, semicolon or colon all work as separators. Spaces are **not** treated as separators, so a
path containing a space survives intact (the tool writes it quoted into the rules file).

### 7.4 Per-profile GPG signing

```bash
git-multi-config init          # supply a signing key id for each profile
```

Each profile file then carries `user.signingkey` and `commit.gpgsign = true`; profiles without a
key get an explicit `gpgsign = false`, so a globally enabled default cannot leak into them.

```bash
cd ~/work/anything && git config --get user.signingkey
```

### 7.5 Repositories outside the managed directories

Three options, in order of preference:

1. Move the repository under a managed directory.
2. With git 2.36+, do nothing — the remote-URL rule covers it.
3. Pin it explicitly:

```bash
cd /some/odd/place/repo
git config --local user.email dev@corp.com
```

`audit` reports local overrides as issues. That is intentional: they are usually leftovers. If the
override is deliberate, exclude that repository by moving it under the right managed directory.

### 7.6 Automation and CI

```bash
git-multi-config init --from-file ci-answers.conf --yes --non-interactive
git-multi-config audit || exit 1
```

`audit` is the useful gate: it fails the job when a repository drifted from its expected identity.

### 7.7 A repository must use one specific identity regardless of location

```bash
cd /anywhere/one-off-repo
git config --local user.name  "Corp User"
git config --local user.email "dev@corp.com"
```

Local configuration always wins. Note the guard may block commits if that email is not registered —
see the next section.

## 8. Files written and their format

| Path | Mode | Content |
|---|---|---|
| `~/.ssh/config` | 600 | managed block: one `Host` entry per account with `IdentityFile` and `IdentitiesOnly yes` |
| `~/.gitconfig` | — | managed block containing a single `[include]` line pointing at the rule file; global default identity keys |
| `~/.gitconfig-company` | 600 | `[user]` name/email/signingkey, `[commit] gpgsign`, `[core] sshCommand` |
| `~/.gitconfig-personal` | 600 | same, for the personal profile |
| `~/.config/git-multi-config/includeif.conf` | 600 | all `includeIf` rules, regenerated on every run |
| `~/.config/git-multi-config/state.conf` | 600 | managed directories, identities, guard bookkeeping |
| `~/.config/git-multi-config/hooks/pre-commit` | 755 | the optional commit guard |

### Where the config directory actually lives

The `~/.config/git-multi-config` shown above is the *default*, not a fixed path. It is resolved as:

```
$GMC_HOME   →   ${XDG_CONFIG_HOME:-~/.config}/git-multi-config   →   ~/.config/git-multi-config
```

If `XDG_CONFIG_HOME` is set in your environment (common on Linux desktops and in CI containers),
everything lands under it instead. That is intentional — but it means a script that only overrides
`HOME` while trying to sandbox this tool will not find the files where it expects them. Either
export `GMC_HOME` explicitly, or unset `XDG_CONFIG_HOME`. `list` and `doctor` always print the
resolved absolute paths, so use those to confirm.

Managed blocks are delimited so they can be replaced safely:

```
# >>> git-multi-config >>>
...
# <<< git-multi-config <<<
```

`includeif.conf` looks like this (two rules per directory, plus remote-URL rules on git 2.36+):

```ini
[includeIf "gitdir:/Users/you/work/"]
	path = /Users/you/.gitconfig-company
[includeIf "gitdir:/private/Users/you/work/"]
	path = /Users/you/.gitconfig-company
[includeIf "hasconfig:remote.*.url:git@git.corp.com:**"]
	path = /Users/you/.gitconfig-company
```

The state file is a plain shell fragment, safe to read and to copy to another machine:

```sh
COMPANY_HOST=git.corp.com
COMPANY_EMAIL=dev@corp.com
COMPANY_DIRS='~/work:~/clients'
```

## 9. The commit guard

Enabled with `--with-hooks` or by answering *yes* in the wizard. It writes a `pre-commit` hook into
the tool's own directory and points the global `core.hooksPath` at it. The hook compares
`git config user.email` with the two registered addresses:

```
[git-multi-config] Refusing to commit with wrong@example.com
[git-multi-config] Registered / 已登记: dev@corp.com you@example.com
[git-multi-config] Fix: git config --local --unset user.email
[git-multi-config] Bypass: GMC_ALLOW_ANY=1 git commit ...
```

| Situation | Behaviour |
|---|---|
| `core.hooksPath` already set (Husky, Lefthook, ...) | guard is skipped with a warning; your setup is untouched |
| repository-local hooks | never modified |
| committing in a repository with an unregistered email | blocked, with instructions |
| intentional one-off | `GMC_ALLOW_ANY=1 git commit ...` |
| uninstall | the previous `core.hooksPath` value is restored |

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` on one account | no `~/.ssh/config` entry, SSH tries keys in sequence | re-run `init`; verify with `doctor --ssh` |
| Commits use the wrong identity | repository-local override, or the directory is not managed | `audit --fix`; then `list` to confirm the directory list |
| The directory rule does not match | the path reaches the directory through a symlink | re-run `init` — two rules are written per directory, including the physical path |
| Rules appear to be ignored entirely | git older than 2.13 | `git --version`; upgrade git |
| Company repository outside the managed tree keeps the personal identity | git older than 2.36, so no remote-URL rule exists | upgrade git and re-run `init`, or move the repository |
| `doctor` reports key permissions | key is group/world readable | `chmod 600 ~/.ssh/<key>` |
| An old `Host github.com` entry exists in `~/.ssh/config` | SSH uses the first match | harmless for Git in managed directories (`core.sshCommand` wins); remove the stale block if you also use plain `ssh` |
| Commit blocked by the guard | email is not one of the registered two | fix the local config, update the tool with the new address, or use `GMC_ALLOW_ANY=1` |
| `init` says "not an interactive terminal" | piped or non-TTY invocation | use `--from-file` |
| Files are not where you expected them | `XDG_CONFIG_HOME` is set, so the config directory resolves elsewhere | export `GMC_HOME`, or unset `XDG_CONFIG_HOME`; check the paths printed by `list` |
| A sandboxed test run only overrides `HOME` and finds nothing | same as above — the tool honours `XDG_CONFIG_HOME` | set `GMC_HOME` in the sandbox too |
| Nothing changed after editing files by hand | `includeif.conf` and `state.conf` are generated | edit the answer file and re-run `init` |

Diagnostics worth keeping in muscle memory:

```bash
git config --show-origin --get-all user.email   # which file provides the identity, and why
git config --show-origin --get-all core.sshCommand
git-multi-config doctor --ssh
```

## 11. Migrating to a new machine

The tool keeps nothing outside your home directory and stores no secrets, so migration is:

```bash
# old machine
cat ~/.config/git-multi-config/state.conf      # or your answers.conf

# new machine
mkdir -p ~/.ssh && chmod 700 ~/.ssh            # copy your keys across
git-multi-config init --from-file answers.conf --yes
git-multi-config doctor --ssh
git-multi-config audit --fix
```

Your SSH keys are yours to move; the tool never generates or copies private keys.

## 12. Design notes and limitations

**Why a generated rule file instead of editing `~/.gitconfig` directly.** All conditional rules live
in one regenerated file, included from a single managed line. Reconfiguration is a file rewrite
rather than surgical editing of a config you also maintain by hand, which is what makes repeated
`init` runs safe.

**Why the include block is last.** Git applies later values over earlier ones. Writing the include at
the end guarantees profile rules beat the global default identity regardless of which profile you
picked as default.

**Why `core.sshCommand` rather than SSH aliases.** Aliases require you to clone with a modified URL
(`git@github-work:...`). Forcing the key per directory requires no discipline and keeps ordinary
URLs working. The cost is that inside a managed directory the profile key is used for every host.

**Deliberate limitations**

- Two profiles (company, personal). Running two personal accounts on one host is not covered.
- SSH keys are never generated, copied or modified.
- HTTPS credentials are out of scope: `credential.helper` and your keychain keep handling them, and
  the tool only affects commit identity for HTTPS repositories.
- `command line pushes that expose my email` and similar server-side protections remain GitHub
  settings; the guard here is local.

**Uninstall is complete.** Every file the tool writes is tracked in the state file, so removal needs
no manual cleanup.
