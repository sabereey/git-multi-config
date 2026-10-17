# git-multi-config 操作手册

`git-multi-config` 的完整参考：安装、配置、日常操作与故障排查。

[English manual](manual.md) · [中文说明](../README.zh-CN.md) · [English README](../README.md)

---

## 目录

1. [这个工具管什么](#1-这个工具管什么)
2. [环境要求与支持平台](#2-环境要求与支持平台)
3. [安装与卸载](#3-安装与卸载)
4. [核心概念](#4-核心概念)
5. [配置向导逐项说明](#5-配置向导逐项说明)
6. [命令参考](#6-命令参考)
7. [场景教程](#7-场景教程)
8. [写入的文件与格式](#8-写入的文件与格式)
9. [提交拦截钩子](#9-提交拦截钩子)
10. [故障排查](#10-故障排查)
11. [换机迁移](#11-换机迁移)
12. [设计说明与已知边界](#12-设计说明与已知边界)

---

## 1. 这个工具管什么

一台笔记本上通常有两套 Git 凭据，出问题的姿势就那么几种：

| 问题 | 后果 |
|---|---|
| 提交作者邮箱用错 | 个人邮箱进了公司审计日志，或公司邮箱进了公开仓库——两者都会永久留在历史里 |
| SSH 递错了密钥 | `Permission denied (publickey)`，明明有权限却推不上去 |
| 密钥靠"逐个尝试"而非固定绑定 | 今天恰好能通，加一把新密钥后就崩 |
| 几十个老仓库各自带着过期的本地配置 | 你"改好了全局配置"，它们照旧用错身份 |

`git-multi-config` 四件事都解决：

- **身份按目录自动选择**，用的是 Git 原生的条件包含——不包装 `git` 命令、不挂钩子、无需记忆
- **密钥按身份固定**，由 `core.sshCommand` 强制指定，不依赖 `~/.ssh/config` 里的顺序
- **存量仓库会被审计和修复**（`audit --fix`），不假设它们本来就是对的
- **提交前可拦截**，邮箱不在登记列表中直接拒绝提交

## 2. 环境要求与支持平台

| 要求 | 说明 |
|---|---|
| Shell | `bash` 3.2+，macOS 系统自带版本即可 |
| Git | 2.13+ 支持 `includeIf`；2.36+ 额外支持按 remote 地址判定 |
| 密钥 | 每个账号一份 `ssh-keygen` 生成的密钥 |
| 可选 | `gpg`，用于每个身份独立签名 |

已验证平台：macOS（含系统自带 bash 3.2）、Linux、WSL。CI 在 `ubuntu-latest` 与 `macos-latest` 上跑完整测试。

除 `bash` 与 `git` 外无任何运行时依赖——不需要 Node、Python、Go，也没有常驻进程。

随时体检：

```bash
git-multi-config doctor
```

## 3. 安装与卸载

### 方式 A —— 安装脚本

```bash
curl -fsSL https://raw.githubusercontent.com/sabereey/git-multi-config/main/install.sh | bash
```

默认装到 `~/.local/bin/git-multi-config`，可指定目录：

```bash
curl -fsSL .../install.sh | PREFIX=/usr/local/bin bash
```

### 方式 B —— 克隆安装

```bash
git clone https://github.com/sabereey/git-multi-config.git
cd git-multi-config
./install.sh          # 或者 make install
```

### 方式 C —— 不安装，直接跑

```bash
./git-multi-config.sh init
```

所有命令都支持这种用法，且写入范围不超出你的家目录。

### 卸载

```bash
git-multi-config uninstall            # 移除工具写入的全部配置
git-multi-config uninstall --restore  # 同时恢复最近的 *.bak.* 备份
```

只删可执行文件：`make uninstall`，或 `rm ~/.local/bin/git-multi-config`。

## 4. 核心概念

**身份（profile）** —— 一组命名的配置：user.name、user.email、SSH 密钥、可选 GPG 签名密钥。本工具固定两个：公司、个人。

**受管目录（managed directory）** —— 分配给某个身份的项目根目录（例如公司 `~/work`、个人 `~/personal`）。其下所有仓库都继承该身份。

**默认身份** —— 在所有受管目录之外使用的身份，配置时由你选定。

**一次提交的身份判定顺序**（越靠后优先级越高）：

1. 仓库本地的 `.git/config` 里的 `user.email`（你可以手工设，`audit` 会把它报为问题）
2. `~/.gitconfig` 里的全局默认身份
3. 通过 `~/.gitconfig` **末尾**那行受管理的 `[include]` 加载的条件规则：
   - `includeIf "gitdir:<受管目录>/"` —— 主机制
   - `includeIf "hasconfig:remote.*.url:<主机>/**"` —— git 2.36+，覆盖放在受管目录之外的仓库

因为 include 块写在最后，身份规则永远压过全局默认身份。

**推送时用哪把钥匙** —— 每个身份配置文件里都有：

```ini
[core]
	sshCommand = ssh -i "/path/to/key" -o IdentitiesOnly=yes
```

在受管目录内，**这把钥匙会被用于所有主机**，与 `~/.ssh/config` 无关。工具写入的 `Host` 条目是为了让目录外的直接 `ssh`/`git` 也能用，属于辅助手段。

**每个目录写两条规则** —— 一条用你提供的路径，一条用解析软链后的物理路径（`pwd -P`）。`gitdir` 是按物理路径匹配的，在 macOS 上 `/tmp`、`/var` 乃至被软链的家目录，只写一种形式会静默失效。

## 5. 配置向导逐项说明

```bash
git-multi-config init
```

| 提问 | 含义 | 注意 |
|---|---|---|
| 公司 Git 域名 | 公司服务器地址 | 如 `git.corp.com`。若与个人域名相同，工具会自动加别名 |
| 公司 SSH 私钥 | 该账号的私钥路径 | 支持 `~`；文件不存在会提示但不会中断 |
| 公司 user.name | 公司提交的作者名 | 必填 |
| 公司 user.email | 公司提交的邮箱 | 必填，会做格式校验 |
| 公司 GPG 签名密钥 | 可选 | 留空则本身份不签名 |
| 公司项目目录 | 项目根目录，逗号分隔 | 路径可含空格 |
| 个人域名 / 密钥 / 姓名 / 邮箱 / GPG / 目录 | 同上，个人账号 | `PERSONAL_HOST` 默认 `github.com` |
| 默认身份 | 1 个人、2 公司 | 作用于受管目录之外 |
| 提交拦截钩子 | 是否安装 | 默认不装；若 `core.hooksPath` 已指向别处会自动跳过 |

写入前会打印摘要并请你确认。原有的 `~/.ssh/config` 与 `~/.gitconfig` 会备份为 `*.bak.<时间戳>`。

重复执行 `init` 是安全的：幂等、旧值自动成为默认值、管理块是替换而非追加。

## 6. 命令参考

### `init`

交互式配置，或用答案文件无人值守。

```bash
git-multi-config init
git-multi-config init --from-file answers.conf --yes
git-multi-config init --with-hooks
git-multi-config init --lang en
```

| 选项 | 作用 |
|---|---|
| `--from-file <文件>` | 从文件读取答案，不再提问（隐含 `--non-interactive`） |
| `-y`、`--yes` | 跳过确认提示 |
| `--non-interactive` | 未提供的一律用默认值 |
| `--with-hooks` | 直接安装提交拦截钩子，不再询问 |
| `--lang zh\|en` | 输出语言（默认 `zh`，可用 `$GMC_LANG` 覆盖） |
| `--ssh` | 写入后顺便测试 SSH 连通性 |

### `audit`

扫描受管目录下的所有仓库并报告身份问题。

```bash
git-multi-config audit            # 仅报告；发现问题返回 1
git-multi-config audit --fix      # 自动修复
git-multi-config audit --depth 6  # 扫得更深（默认 4 层）
```

检测三类问题：

| 问题 | 判定方式 | `--fix` 的处理 |
|---|---|---|
| 本地覆盖 | `.git/config` 里的 `user.email` 与预期不符 | 删除本地 `user.email` / `user.name`，让目录规则接管 |
| 生效身份错误 | Git 最终解析出的身份不是预期值 | 报告（需修正规则或目录归属） |
| remote 未用别名 | 公司和个人同域名，remote 用了共用域名而非专用别名 | 改写 remote 为别名 |

典型输出：

```
[info] 审计
! /Users/you/work/legacy-service
    本地 user.email 覆盖了自动切换规则（expect: dev@corp.com）: old@personal.dev
[ ok ]    已修复
[info] 已扫描仓库: 92
[ ok ] 发现问题: 1
```

因为发现问题时返回非 0，可以直接当门禁：

```bash
git-multi-config audit || echo "有仓库身份不对"
```

### `list`

打印当前配置：两端域名、身份、受管目录、默认身份、钩子状态、状态文件路径。

### `doctor`

体检环境与配置。

```bash
git-multi-config doctor
git-multi-config doctor --ssh     # 顺便测试两个账号的 SSH 认证
```

检查项：git 版本及其 `includeIf` / `hasconfig` 支持、规则文件是否存在、两个管理块、密钥是否存在且权限为 600、钩子接线是否正确、可选的 SSH 登录测试。任一检查失败返回 1——新机器配好后建议立刻跑一次。

### `uninstall`

```bash
git-multi-config uninstall
git-multi-config uninstall --restore
```

移除内容：`~/.ssh/config` 管理块、`~/.gitconfig` 管理块、规则文件、两个身份配置文件、提交钩子（若有旧 `core.hooksPath` 会还原）、状态文件。备份保留；加 `--restore` 会把最近的备份复制回去。

### 通用选项

| 选项 | 说明 |
|---|---|
| `--version`、`-V` | 打印版本 |
| `help`、`--help`、`-h` | 打印用法 |
| `--lang=zh`、`--lang=en` | 输出语言 |

### 环境变量

| 变量 | 用途 |
|---|---|
| `GMC_HOME` | 覆盖状态/配置目录（默认 `${XDG_CONFIG_HOME:-~/.config}/git-multi-config`） |
| `GMC_SSH_CONFIG` | 指定其他 SSH 配置文件（沙箱与测试用） |
| `GMC_GITCONFIG` | 指定其他全局 git 配置文件 |
| `GMC_LANG` | 默认输出语言 |
| `NO_COLOR` | 关闭彩色输出 |
| `GMC_ALLOW_ANY` | 供提交钩子读取：设为 `1` 可跳过邮箱校验 |

## 7. 场景教程

### 7.1 公司私服与个人 GitHub 不同域名（最常见）

```bash
git-multi-config init
# 公司域名:  git.corp.com     密钥: ~/.ssh/id_ed25519_company
# 公司目录:  ~/work
# 个人域名:  github.com       密钥: ~/.ssh/id_ed25519
# 个人目录:  ~/personal
# 默认身份:  个人
```

git 2.36+ 下还会写入 remote 规则，所以即使公司仓库被 clone 到桌面，也仍然是公司身份。

### 7.2 公司和个人都用同一个域名

两个账号都在 `github.com` 时，向导会检测到，给公司条目别名 `github.com-work`，并为个人侧补一个 `github.com-personal`。

```bash
git-multi-config audit --fix
```

会把公司目录下的 remote 从 `git@github.com:org/repo.git` 改写成 `git@github-work:org/repo.git`。注意：受管目录内的密钥选择本身不依赖别名，`core.sshCommand` 已经保证了唯一正确性。

### 7.3 多个项目目录，含带空格的路径

```ini
COMPANY_DIRS=~/work,~/clients/acme,~/work archive/2026
```

逗号、分号、冒号都可作分隔符。**空格不是分隔符**，所以路径里的空格不会被拆开（工具写入规则时会正确引用）。

### 7.4 每个身份独立 GPG 签名

```bash
git-multi-config init          # 分别为两个身份填签名密钥 ID
```

各自的身份配置文件会带上 `user.signingkey` 与 `commit.gpgsign = true`；没有配密钥的身份会显式写 `gpgsign = false`，防止全局开启的签名设置泄漏进去。

```bash
cd ~/work/任意仓库 && git config --get user.signingkey
```

### 7.5 放在受管目录之外的仓库

按推荐程度排序，三种做法：

1. 把仓库挪进受管目录
2. git 2.36+ 下什么都不用做——remote 规则已经覆盖
3. 显式钉住：

```bash
cd /某个奇怪的位置/repo
git config --local user.email dev@corp.com
```

`audit` 会把本地覆盖报为问题。这是有意设计：本地覆盖通常是历史遗留。若确实是故意的，更稳妥的做法是把该仓库归入合适的受管目录。

### 7.6 自动化与 CI

```bash
git-multi-config init --from-file ci-answers.conf --yes --non-interactive
git-multi-config audit || exit 1
```

`audit` 是最有用的门禁：仓库身份一旦漂移就让流水线失败。

### 7.7 某个仓库必须固定用某个身份，与位置无关

```bash
cd /anywhere/one-off-repo
git config --local user.name  "Corp User"
git config --local user.email "dev@corp.com"
```

本地配置优先级最高。注意：若该邮箱不在登记列表中，提交拦截钩子会拦下来——见下一节。

## 8. 写入的文件与格式

| 路径 | 权限 | 内容 |
|---|---|---|
| `~/.ssh/config` | 600 | 管理块：每个账号一个 `Host` 条目，含 `IdentityFile` 与 `IdentitiesOnly yes` |
| `~/.gitconfig` | — | 管理块内一行 `[include]` 指向规则文件；另有全局默认身份的键值 |
| `~/.gitconfig-company` | 600 | `[user]` 姓名/邮箱/签名密钥、`[commit] gpgsign`、`[core] sshCommand` |
| `~/.gitconfig-personal` | 600 | 同上，个人身份 |
| `~/.config/git-multi-config/includeif.conf` | 600 | 全部 `includeIf` 规则，每次运行整文件重写 |
| `~/.config/git-multi-config/state.conf` | 600 | 受管目录、身份、钩子记账信息 |
| `~/.config/git-multi-config/hooks/pre-commit` | 755 | 可选的提交拦截钩子 |

### 配置目录究竟落在哪里

上表里的 `~/.config/git-multi-config` 是**默认值**，不是固定路径。实际解析顺序为：

```
$GMC_HOME   →   ${XDG_CONFIG_HOME:-~/.config}/git-multi-config   →   ~/.config/git-multi-config
```

如果你的环境里设了 `XDG_CONFIG_HOME`（Linux 桌面、CI 容器里很常见），所有文件都会落到它下面。
这是有意为之 —— 但也意味着：**只覆盖 `HOME` 来做沙箱的脚本，会在预期位置找不到这些文件。**
请显式导出 `GMC_HOME`，或先 `unset XDG_CONFIG_HOME`。`list` 与 `doctor` 始终打印解析后的绝对路径，
可以用它们确认。

管理块用标记包裹，便于安全替换：

```
# >>> git-multi-config >>>
...
# <<< git-multi-config <<<
```

`includeif.conf` 形如（每个目录两条规则，git 2.36+ 另有 remote 规则）：

```ini
[includeIf "gitdir:/Users/you/work/"]
	path = /Users/you/.gitconfig-company
[includeIf "gitdir:/private/Users/you/work/"]
	path = /Users/you/.gitconfig-company
[includeIf "hasconfig:remote.*.url:git@git.corp.com:**"]
	path = /Users/you/.gitconfig-company
```

状态文件是普通的 shell 片段，可以直接阅读、也可以拷到别的机器：

```sh
COMPANY_HOST=git.corp.com
COMPANY_EMAIL=dev@corp.com
COMPANY_DIRS='~/work:~/clients'
```

## 9. 提交拦截钩子

用 `--with-hooks` 或在向导里选"是"即可启用。它会把 `pre-commit` 写进工具自己的目录，并把全局 `core.hooksPath` 指过去。钩子把当前 `git config user.email` 与登记的两个邮箱比对。这两个邮箱是用 `git config --file` 从 `~/.gitconfig-company` 和 `~/.gitconfig-personal` 读的 —— 不经过 `state.conf`，且是精确比较，所以邮箱里含 `'`、`!`、`$` 或空格都不会出问题。

```
[git-multi-config] Refusing to commit with wrong@example.com
[git-multi-config] 拒绝提交：当前身份邮箱 wrong@example.com 不在登记列表中
[git-multi-config] Fix: git config --local --unset user.email
```

| 情况 | 行为 |
|---|---|
| `core.hooksPath` 已被占用（Husky、Lefthook 等） | 带警告跳过安装，不影响你现有钩子 |
| 仓库本地的 `.git/hooks` | 从不改动 |
| 在邮箱未登记的仓库里提交 | 拦截并给出修复指引 |
| 有意的一次性提交 | `GMC_ALLOW_ANY=1 git commit ...` |
| 卸载 | 还原此前的 `core.hooksPath` 值 |

## 10. 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 某个账号 `Permission denied (publickey)` | 没有 `~/.ssh/config` 条目，SSH 在按顺序试密钥 | 重跑 `init`；用 `doctor --ssh` 确认 |
| 提交身份不对 | 仓库有本地覆盖，或该目录不在受管列表里 | `audit --fix`；再用 `list` 核对目录列表 |
| 在受管目录里 `git config user.email` 却是默认身份 | 当前不在 git 仓库内——`gitdir:` 条件只有在 Git 找到 `.git` 目录后才会被求值 | `cd` 进真正的仓库，或用 `git rev-parse --show-toplevel` 检查 |
| 目录规则不生效 | 到达该目录的路径经过了软链 | 重跑 `init`——每个目录会写逻辑路径与物理路径两条规则 |
| 规则完全不生效 | git 低于 2.13 | `git --version`，升级 git |
| 目录外的公司仓库仍是个人身份 | git 低于 2.36，没有 remote 规则 | 升级 git 后重跑 `init`，或把仓库挪进受管目录 |
| `doctor` 报密钥权限 | 密钥同组/其他用户可读 | `chmod 600 ~/.ssh/<密钥>` |
| `~/.ssh/config` 里有旧的 `Host github.com` | SSH 采用首个匹配 | 对受管目录内的 Git 操作无影响（`core.sshCommand` 优先）；如果也直接用 `ssh`，建议删掉旧块 |
| 提交被钩子拦下 | 邮箱不在登记的两个之内 | 修正本地配置、把新邮箱加进工具，或 `GMC_ALLOW_ANY=1` |
| `init` 提示非交互终端 | 管道或非 TTY 环境 | 改用 `--from-file` |
| 文件不在预期位置 | 环境里设了 `XDG_CONFIG_HOME`，配置目录解析到了别处 | 导出 `GMC_HOME`，或 `unset XDG_CONFIG_HOME`；用 `list` 打印的路径确认 |
| 只覆盖 `HOME` 的沙箱测试什么都找不到 | 同上——工具会遵循 `XDG_CONFIG_HOME` | 沙箱里同时设置 `GMC_HOME` |
| 手工改了文件却没生效 | `includeif.conf` 与 `state.conf` 是生成物 | 改答案文件后重跑 `init` |

值得记住的诊断命令：

```bash
git config --show-origin --get-all user.email   # 身份来自哪个文件、为什么
git config --show-origin --get-all core.sshCommand
git-multi-config doctor --ssh
```

## 11. 换机迁移

工具不往家目录之外写任何东西，也不保存密钥，所以迁移就是：

```bash
# 旧机器
cat ~/.config/git-multi-config/state.conf      # 或你自己的 answers.conf

# 新机器
mkdir -p ~/.ssh && chmod 700 ~/.ssh            # 把密钥拷过去
git-multi-config init --from-file answers.conf --yes
git-multi-config doctor --ssh
git-multi-config audit --fix
```

密钥是你自己的资产，工具不会生成、不会复制私钥。

## 12. 设计说明与已知边界

**为什么用生成规则文件，而不是直接改 `~/.gitconfig`。** 所有条件规则集中在一个可整文件重写的文件里，`~/.gitconfig` 里只挂一行受管理的 include。重新配置变成"重写文件"，而不是在你也会手工维护的配置里做外科手术——这正是重复运行 `init` 安全的原因。

**为什么 include 块放在最后。** Git 后出现的值覆盖先出现的。把 include 放在文件末尾，就能保证无论你选哪个身份作默认，身份规则都优先。

**为什么用 `core.sshCommand` 而不是 SSH 别名。** 别名要求你用改过的 URL 来 clone（`git@github-work:...`），需要人为自律；按目录强制密钥则不需要任何额外习惯，普通 URL 照常工作。代价是：受管目录内访问任何主机都会用该身份的密钥。

**有意为之的边界**

- 只支持两个身份（公司、个人），不覆盖"同一主机上两个个人账号"的场景
- 从不生成、复制或修改 SSH 密钥
- HTTPS 凭据不在范围内：仍由 `credential.helper` 与钥匙串处理，工具只影响 HTTPS 仓库的提交身份
- "阻止暴露邮箱的命令行推送"等属于 GitHub 服务端设置；本工具的钩子只是本地防线

**卸载是彻底的。** 工具写过的每个文件都记在状态文件里，移除时无需人工清理。
