# git-multi-config

**一条命令配好公司 / 个人多 Git 账号环境。**

公司项目走公司私服、用公司邮箱和公司密钥；个人项目走 GitHub、用个人身份。
不需要手动切换——**目录决定身份**。

```
~/work/my-service   →  git@git.corp.com:team/my-service.git   （dev@corp.com + 公司密钥）
~/personal/dotfiles →  git@github.com:you/dotfiles.git        （you@example.com + 个人密钥）
```

除配置外，它还能**审计存量仓库**的身份是否错配、**改写绕过专用 SSH 别名的 remote**，
并可选安装**提交前拦截钩子**，阻止用未登记邮箱提交。

[English README](README.md) · **完整手册：[中文操作手册](docs/manual.zh-CN.md) / [English manual](docs/manual.md)**

**目录** · [它解决什么](#它解决什么) · [环境要求](#环境要求) · [安装](#安装) · [快速开始](#快速开始) ·
[写入的文件](#它写了哪些文件) · [命令](#命令) · [典型场景](#典型场景) ·
[提交拦截钩子](#提交拦截钩子可选) · [常见问题](#常见问题) · [开发](#开发)

---

## 它解决什么

| 常见事故 | 本工具的做法 |
|---|---|
| 公司仓库的提交作者是个人邮箱 | 按目录自动切换 `user.name` / `user.email` |
| `Permission denied (publickey)`：SSH 挑错了密钥 | 每个身份用 `core.sshCommand` 强制指定密钥 |
| 已有的几十个老仓库本地配置是错的 | `audit --fix` 扫描并批量修复 |

## 环境要求

- `bash` 3.2+（macOS 系统自带即可，无需装新版）
- `git` 2.13+ 支持条件包含；`git` 2.36+ 额外支持按 remote 地址判定
- 两个账号各一份 SSH 密钥

> 零依赖：不需要 Node / Python / Go，也不常驻任何进程。

## 安装

```bash
# 安装到 ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/sabereey/git-multi-config/main/install.sh | bash

# 或克隆后本地安装
git clone https://github.com/sabereey/git-multi-config.git
cd git-multi-config && ./install.sh

# 或直接运行，不安装
./git-multi-config.sh init
```

## 快速开始

```bash
git-multi-config init
```

回答八个问题（公司域名、密钥、姓名邮箱、项目目录；个人密钥、姓名邮箱、项目目录；默认身份），
确认后即完成配置：

```bash
git-multi-config list          # 查看当前配置
git-multi-config doctor --ssh  # 诊断环境
git-multi-config audit --fix   # 审计并修复存量仓库
```

验证：

```bash
cd ~/work/任意仓库 && git config user.email        # → 公司邮箱
cd ~/personal/任意仓库 && git config user.email    # → 个人邮箱
```

---

## 它写了哪些文件

| 路径 | 作用 |
|---|---|
| `~/.ssh/config` | 管理块，每个账号一个 `Host` 条目，强制 `IdentitiesOnly yes` |
| `~/.gitconfig-company` / `~/.gitconfig-personal` | 各身份的 `user.*`、`core.sshCommand`、可选 GPG |
| `~/.config/git-multi-config/includeif.conf` | 全部 `includeIf` 规则，由工具生成 |
| `~/.gitconfig` | 仅一行受管理的 `[include]` 指向上面的文件 |
| `~/.config/git-multi-config/state.conf` | 供 `audit` / `doctor` 使用的最小状态 |
| `~/.config/git-multi-config/hooks/pre-commit` | 可选的提交拦截钩子 |

两个保证可靠性的细节：

1. **include 块永远位于 `~/.gitconfig` 末尾**，因此身份规则优先级高于全局默认身份，无论你把哪个设为默认。
2. **每个目录写两条规则：逻辑路径 + 解析软链后的物理路径。** `gitdir:` 是按物理路径匹配的，
   在 macOS 上（`/tmp`、`/var`、被软链的 home）只写一种形式会静默失效。

每次运行都会把原有 `~/.ssh/config` 和 `~/.gitconfig` 备份为 `*.bak.<时间戳>`。

---

## 命令

| 命令 | 说明 |
|---|---|
| `init` | 交互式配置（默认命令） |
| `audit [--fix] [--depth n]` | 扫描受管目录下的仓库身份；`--fix` 自动修复 |
| `list` | 查看当前配置 |
| `doctor [--ssh]` | 检查 git 版本、文件、密钥权限、钩子，可选测试 SSH 登录 |
| `uninstall [--restore]` | 卸载全部写入内容；`--restore` 同时恢复最近备份 |

选项：`--from-file <文件>`、`-y`、`--lang zh|en`、`--with-hooks`、`--fix`、`--depth`、`--ssh`、`--restore`。

### 用于自动化

```bash
git-multi-config init --from-file answers.conf --yes
```

`audit` 在发现问题时返回非 0，可直接用作 CI 或提交门禁：

```bash
git-multi-config audit || echo "有仓库身份不对"
```

---

## 提交拦截钩子（可选）

启用后会设置全局 `core.hooksPath`，其中的 `pre-commit` 会把当前 `git config user.email`
与两个已登记邮箱比对，不匹配则拒绝提交：

```
[git-multi-config] Refusing to commit with wrong@example.com
[git-multi-config] 拒绝提交：当前身份邮箱 wrong@example.com 不在登记列表中
```

若 `core.hooksPath` 已指向别处（例如使用 Husky），会自动跳过安装，不会破坏现有钩子；
也不会改动任何仓库本地的 `.git/hooks`。

---

## 典型场景

| 你的情况 | 怎么做 |
|---|---|
| 公司 GitLab/Gitea + 个人 GitHub | `init` 填两个目录，完成 |
| 公司和个人都用 github.com | `init` 自动识别并生成 `github-work` 别名 |
| 已有几十个仓库带着错误的本地配置 | `audit --fix` |
| 公司仓库被 clone 到了受管目录之外 | git 2.36+ 由 remote 规则覆盖；否则 `audit` 会报出来 |
| 需要第三套身份（外包/客户项目） | 把仓库放进对应目录并设置本地配置，或用 `GMC_HOME` 跑第二套配置 |
| 错误邮箱已经推到公开仓库 | 先修身份（`audit`），再轮换邮箱地址或重写历史 |
| 换新笔记本 | 带上 `answers.conf`，执行 `init --from-file answers.conf --yes` |

---

## 常见问题

**`~/.ssh/config` 里已经有 `Host github.com` 了怎么办？**
SSH 采用“首个匹配值生效”，老条目可能对直接 clone 生效。但受管目录内的 Git 操作不受影响——
每个身份的 `core.sshCommand` 会强制使用正确密钥，与 SSH 配置无关。`init` 检测到这种情况会给出提示。

**公司和个人都用 github.com？**
公司的 Host 别名会自动设为 `github.com-work`，并额外提供 `github.com-personal`。
`audit --fix` 会把公司目录下 `git@github.com:org/repo` 的 remote 改写为 `git@github.com-work:org/repo`。

**`core.sshCommand` 会影响受管目录里的其他主机吗？**
会——在 `~/work` 内访问任何主机都用公司密钥。这是为了行为确定性；个别场景可用
`GIT_SSH_COMMAND` 覆盖，或把仓库放到别处 clone。

**受管目录之外的仓库用哪个身份？**
你设定的默认身份。git 2.36+ 下，即使仓库 clone 到别处，只要 remote 指向公司服务器，
仍会通过 `hasconfig:remote.*.url:` 规则自动使用公司身份。

**路径里有空格可以吗？** 可以。

**换电脑怎么迁移？** 把 `answers.conf` 带过去（或重新跑一次 `init`）即可，状态没有藏在别处。

## 开发

```bash
make test     # 在临时 HOME 中跑完整冒烟测试
make lint     # shellcheck
make install
```

完整文档见[中文操作手册](docs/manual.zh-CN.md)——包含向导逐项说明、全部命令、场景教程、故障排查表与设计说明。

## 许可证

MIT，见 [LICENSE](LICENSE)。

[English README](README.md) · [English manual](docs/manual.md)

<sub>多个 git 账号 · 按目录切换 git 身份 · includeIf gitdir · hasconfig remote url · 每个账号独立 SSH 密钥 ·
提交邮箱用错 · 公司和个人项目同机管理 · core.sshCommand · 提交前身份校验</sub>

