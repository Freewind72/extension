# Extension

一个基于 [Inno Setup](https://jrsoftware.org/isinfo.php) 的 Windows 安装器：把 **Java / Maven / Node / PHP / Go / Python / Gradle** 的多版本开发工具链装进同一个目录，环境变量只往 `PATH` 里加**一条**，各版本共存、随时切换。

安装包本体只有 **2.8 MB** —— 所有工具都在安装时从镜像下载，所以安装包不会因为多支持几个版本而变大。

```
安装包 2.8 MB  ──►  运行时按清单下载选中的包  ──►  解压就位  ──►  写环境变量 + 生成转发脚本
```

---

## 特性

- **安装包极小**：2.8 MB。载荷全部在线下载，加版本不用重新打包。
- **清单驱动**：版本列表来自一份纯文本清单，增删版本**不用重编译**安装包。
- **三态选择**：勾选框决定"装不装"，下拉框决定"装哪个版本 / 要不要写环境变量"，两者独立。
- **PATH 只加一条**：所有命令通过自动生成的 `.cmd` 转发脚本暴露，`PATH` 永远只有 `{app}\bin` 一条。
- **主备地址 + 校验**：每个包支持 `url` / `url2` / `url3` 三级自动切换，配了 `sha256` 就逐字节校验。
- **自动收尾**：PHP 的 `php.ini` 与扩展、CA 根证书；Python 的 `site` 与 `pip`，全部装完自动配好。
- **卸载干净**：只删自己写过的环境变量和 `PATH` 条目，不动系统里其它配置。

---

## 工作原理

1. **向导初始化**：从清单地址拉取清单（拉不到就用脚本内置的兜底清单），按清单里的节生成每个工具的版本下拉框。
2. **点"安装"后**：只下载被选中的包到临时目录。每个包最多试三组地址，配了 `sha256` 就校验，不匹配视为失败并自动换下一个地址。
3. **解压就位**：先解压到 `{app}\<工具>\.in-<版本>`，再改名成规范目录名（`jdk25` / `node24` …）。多套一层目录的压缩包会自动剥掉外层。
4. **自动收尾**：PHP 生成 `php.ini` 并实测剔除加载不起来的扩展、下 CA 根证书；Python 打开 `site` 并引导安装 `pip`。
5. **写环境变量**：写入各工具的 `*_HOME`，`PATH` 里加入 `{app}\bin`，并在 `{app}\bin` 里为每个命令生成转发脚本。

---

## 安装后的目录结构

```
D:\Extension\
├── bin\                    ← PATH 里唯一的一条，全是自动生成的 .cmd 转发脚本
│   ├── java.cmd  javac.cmd  jshell.cmd  ...
│   ├── mvn.cmd   node.cmd   npm.cmd
│   ├── php.cmd   php-cgi.cmd
│   └── pip.cmd   python.cmd
├── java\jdk25\
├── maven\maven-3.9.16\
├── node\node24\
├── php\PHP85\
├── go\Go1.27.1\
├── python\Python3.14\
└── gradle\Gradle9.7.1\
```

每个工具一个目录，互不干扰；想换版本就是换一个子目录。

---

## 环境变量策略

只写这些，且**只写指向本安装目录的值**：

| 工具 | 变量 |
| --- | --- |
| Java | `JAVA_HOME` |
| Maven | `MAVEN_HOME` |
| Node | `NODE_HOME` |
| PHP | `PHP_HOME` |
| Go | `GOROOT` |
| Python | `PYTHON_HOME` |
| Gradle | `GRADLE_HOME` |

`PATH` 里只加一条 `{app}\bin`，位置在最前面。

几个刻意的决定：

- **不设 `M2_HOME`**：Maven 3.9 用 `MAVEN_HOME`；`M2_HOME` 只在卸载时的清理清单里，用来扫掉历史遗留。
- **不设 `PYTHONHOME`**：它会导致 Python 忽略 `pyvenv.cfg`，**虚拟环境直接失效**，是个经典坑。用 `PYTHON_HOME` 代替。
- **不设 `GOPATH`**：交给 Go 自己的默认值（`%USERPROFILE%\go`）。
- 卸载时会检查并清理的历史变量：`JAVA_HOME` `MAVEN_HOME` `M2_HOME` `NODE_HOME` `PHP_HOME` `PHPRC` `GOROOT` `GOPATH` `PYTHON_HOME` `PYTHONHOME` `GRADLE_HOME`。

---

## 为什么用转发脚本，而不是符号链接

试过三种链接方式，**全部失败**：

| 方式 | 结果 |
| --- | --- |
| 符号链接（symlink） | `java.exe` 直接退出，退出码 `-1073741515`（缺少依赖 DLL） |
| 目录联接（junction） | 报 `could not find java.dll` |
| 硬链接（hardlink） | 同样失败 |

原因是 `java.exe`、`php.exe` 这类程序会去**自己所在目录**找同级的 `jvm.dll`、`php8.dll`，链接过去之后相对位置就变了。

所以最终方案是在 `{app}\bin` 里生成一层 `.cmd` 转发脚本：

```bat
@echo off
"%~dp0..\java\jdk25\bin\java.exe" %*
```

`.cmd` / `.bat` 目标的启动器（比如 Gradle 的 `gradle.bat`）会额外用 `call`，否则拿不到正确的返回码。

---

## 清单格式

清单就是一份纯文本，**文件名和后缀随意**（安装器按内容解析，不看扩展名），只要能通过 HTTP 访问：

```ini
[meta]
default_Java  = jdk25
default_Node  = node24

[Java|jdk25]
url    = https://mirror.example.com/openjdk/25.0.2/openjdk-25.0.2_windows-x64_bin.zip
url2   = https://mirror2.example.com/openjdk/25.0.2/openjdk-25.0.2_windows-x64_bin.zip
size   = 221671696
sha256 = 74784a0c07258f32d36e9224dd79187c566d831c30d47dc06888d4212087331d

[Node|node24]
url    = https://mirror.example.com/nodejs/v24.21.0/node-v24.21.0-win-x64.zip
size   = 37618919
sha256 = 158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541
```

| 字段 | 说明 |
| --- | --- |
| 节名 `[工具\|版本标签]` | 工具名要和脚本里 `ToolSpec` 的第一列对得上；版本标签就是下拉框里显示的文字。有几节就有几个可选版本。 |
| `url` | 主地址，必填。 |
| `url2` / `url3` | 备用地址，主地址失败后依次重试。 |
| `size` | 包大小（字节），用于在选择页实时估算磁盘占用。 |
| `sha256` | 有就校验，不匹配视为下载失败并自动换下一个地址。 |
| `[meta] default_工具名` | 该工具默认选中的版本。 |

> ⚠ **`url2` / `url3` 必须和 `url` 是同一份字节**（同一厂商的不同镜像）。因为 `sha256` 是单值，换到字节不同的备用源会校验失败、看起来像"下载失败"。

清单拉不到时，安装器会退回脚本里内置的那份兜底清单，所以清单服务器临时挂掉不会让安装器直接不可用。

`size` 会出现在选择页的实时容量估计里；`sha256` 强烈建议配上。

---

## 三态选择

这是这个安装器交互上的核心，两个维度完全独立：

| 你的操作 | 结果 |
| --- | --- |
| 勾选框**不打勾** | 这个工具**完全不装**：不下载、不占空间、不写任何环境变量 |
| 勾选框打勾 + 下拉框选**具体版本** | 装这个版本，并写入环境变量、生成转发脚本 |
| 勾选框打勾 + 下拉框选**"（不设置变量）"** | **只装文件**，不写 `*_HOME`、不加 `PATH`、不生成转发脚本（适用于你只想把文件放在那、环境变量自己管的情况） |

选择页底部会实时显示当前选择的磁盘占用，勾选和切换版本都会立刻重算。

---

## 构建

```bat
git clone https://github.com/Freewind72/extension.git
```

1. 安装 [Inno Setup 6.6.1](https://jrsoftware.org/isdl.php) 或更新版本。
2. 改脚本头部这几个宏：

```iss
#define MyAppName     "Extension"
#define MyAppPublisher "Your Name"
#define MyAppURL      "https://example.com/"
#define MyManifestURL "https://example.com/manifest.ini"
```

3. **换掉 `AppId`**（如果你要 fork 出去自己发布）：

```iss
AppId={{60E790EA-91C3-4004-B1E8-C41186BAA668}
```

`AppId` 是安装器的唯一身份。**两个不同的安装器用同一个 `AppId`，会被 Windows 认为是同一个程序** —— 后装的会覆盖前一个的卸载登记项，卸载其中一个会把另一个也带走。用 Inno Setup 菜单里的「工具 → 生成 GUID」换一个新的。

同一个安装器的后续版本**必须保持 `AppId` 不变**，否则升级会变成"装了两份"。

4. 编译：

```bat
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" Extension.iss
```

命令行静默编译、指定输出名：

```bat
ISCC.exe /O"dist" /F"Extension-Online" Extension.iss
```

---

## 两个千万不能删的设置

这两条都是踩坑踩出来的，删掉会以很难排查的方式坏掉：

### 1. `WizardStyle=modern dark windows11`

**删掉这行，在线下载会整体失效**，所有下载都报：

```
内部错误: ... Error adding header: (87) 参数错误
```

原因是 Inno Setup 默认用的安装壳 `Setup.e32` 在某些版本/环境下下载功能是坏的；指定了 `dark` / `windows11` 样式之后会改用 `SetupCustomStyle.e32`，那个是正常的。表现为：安装包能编译、能启动、界面正常，**一到下载就报错**。

### 2. `ArchiveExtraction=full`

解压 `.zip` 必须用 `full`。默认的 `basic` 只支持 `.7z`，遇到 `.zip` 会解压失败。

---

## 扩展：加一个版本 / 加一个工具

### 加一个版本（不用重编译）

往清单里加一节就行：

```ini
[Java|jdk17]
url    = https://mirror.example.com/openjdk/17.0.2/openjdk-17.0.2_windows-x64_bin.zip
size   = 187000000
sha256 = ...
```

下次运行安装器，下拉框里就会多出 `jdk17`。

### 加一个工具（要重编译）

改 `[Code]` 里的 `ToolSpec` 一行，格式是：

```
展示名|环境变量名|子目录|放命令的子目录|要生成转发脚本的扩展名|默认版本
```

例如：

```iss
ToolSpec = 'Java|JAVA_HOME|java|bin|.exe|jdk25;' +
           'Node|NODE_HOME|node||.exe,.cmd|node24;' +
           'Rust|RUSTUP_HOME|rust||.exe|rust1.90';
```

同时把变量名加进 `HomeVarNames`（卸载清理用），再在清单里加上对应的节即可。

---

## 自动收尾做了什么

装完之后安装器会做几件容易漏掉的事：

**PHP**

- 官方 Windows 包里**只有** `php.ini-development` / `php.ini-production` 两个模板，没有 `php.ini`，而且模板里所有 `extension=` 都是注释掉的 —— 直接复制会得到一个不加载任何扩展的"裸"PHP。
- 所以会自动选模板、把扩展行放开，并且**用装好的 `php.exe` 逐个实测**，把加载不起来的扩展重新注释掉。例如：
  - `pdo_firebird`：DLL 在包里，但它依赖的 `fbclient.dll`（官方包从不附带），放开后每次启动都打印警告；
  - `snmp`：能加载，但 net-snmp 找不到 MIB 数据文件，每次启动往 stderr 刷十几行 `Cannot find module ...`。

  判据是"空程序运行成功时本应毫无输出"，一条规则同时覆盖这两类问题，也**不会因为 PHP 升级而失效**（比硬编码黑名单可靠）。
- `extension_dir` 会写成绝对路径。模板里这行是注释掉的，不设的话 PHP 会用编译进去的默认值（官方包的默认值是 `C:\php\ext`），那个目录不存在，于是所有扩展加载失败。
- 下一份 CA 根证书包放进 PHP 目录并写进 `php.ini`（`curl.cainfo` + `openssl.cafile`）。**官方 Windows 包不附带 CA 证书**，不配的话所有 HTTPS 请求都会失败：

  ```
  SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)
  ```

  `file_get_contents` 直接返回 `false`。Composer 之类必然踩到。
- **已经存在的 `php.ini` 完全不动**，保留你自己的改动。

**Python**

清单里用的是 embeddable 版 Python，它有两个坑：

- **不带 `pip`**（连 `ensurepip` 都没有），只能用官方 `get-pip.py` 引导；
- `python3xx._pth` 里 `import site` 是注释掉的，`Lib\site-packages` 根本不在 `sys.path` 上。

所以会自动打开 `site`、跑一次 `get-pip.py`，然后在 `bin` 里补上 `pip` / `pip3` 的转发脚本。

> 注意 `pip.exe` 装在 `Scripts\` 子目录里，转发脚本会额外扫这个目录。用官方推荐的 `python -m pip` 也完全没问题。

---

## 卸载行为

- 删除 `PATH` 里指向本安装目录的条目（只删这一条）。
- 删除值为"本安装目录下"的 `*_HOME` 变量。
- 删除整个安装目录。
- **不会**动系统里其它环境变量、不会动指向别处的同名变量。

---

## 国内镜像参考

实测速度（同一网络、同一时段，单位 MB/s，仅供参考，波动很大）：

| 工具 | 来源 | 速度 |
| --- | --- | --- |
| Go | 南京大学 `mirrors.nju.edu.cn/golang/` | ~58 |
| PHP | `downloads.php.net/~windows/releases/archives/` | ~12 |
| Maven | 腾讯云 `mirrors.cloud.tencent.com/apache/maven/` | ~10–12 |
| Node | `npmmirror.com/mirrors/node/` | ~9–11 |
| Java | 华为云 `mirrors.huaweicloud.com/openjdk/` | ~8 |
| Python | 华为云 `mirrors.huaweicloud.com/python/` | ~8 |
| Gradle | 腾讯云 `mirrors.cloud.tencent.com/gradle/` | ~7–12 |
| PHP | `windows.php.net/downloads/releases/archives/` | ~1.3–3.8 |
| Go | `golang.google.cn/dl/` | ~1.5–3.6 |

结论：

- **PHP 没有国内镜像**（国内镜像站只放源码 tar 包，没有 Windows 二进制），能用的最快就是 `downloads.php.net`。
- **同厂商的不同镜像站速度可能差好几倍**，所以 `url2` 值得配 —— 但必须字节一致。
- 速度随时段波动极大（同一镜像几分钟内能从 0.1 到 8 MB/s），所以**主备切换只在失败时触发，不会因为慢而切换**。

---

## 常见问题

**Q：为什么提示"至少需要 1 GB 的可用磁盘空间"？安装包不是才 2.8 MB 吗？**

因为载荷是在线下载解压的，`[Files]` 段是空的，Inno 自己算出来的"所需空间"只有几 MB（就是卸载程序的大小）。脚本里用 `ExtraDiskSpaceRequired` 把载荷占用补上了：**清单里所有包的 `size` 之和 × 2**（解压后实测约为压缩包的 1.92 倍）。这个数字对应的是"全选"的上限，实际装多少看你在选择页勾了什么 —— 选择页底部有实时估算。

> 清单里增删版本后，这个数字需要重算。

**Q：装完 `java` / `node` 提示找不到命令？**

环境变量是安装时写入注册表的，**已经打开的终端不会自动刷新**。新开一个终端，或者注销重登。

**Q：某个工具下载特别慢或者失败怎么办？**

给清单里那一节加 `url2` / `url3`（必须是同一份字节）。安装器只在**失败**时切换地址，慢不会触发切换。

**Q：想装两个 Java 版本怎么办？**

清单里加两节（`[Java|jdk17]`、`[Java|jdk25]`），下拉框里就能选。装完目录里 `java\jdk17` 和 `java\jdk25` 并存，`JAVA_HOME` 指向你选的那个。想换版本重跑安装器选另一个即可。

**Q：能装到别的盘吗？**

能。改 `DefaultDirName`，或者运行时在"选择目标位置"那一页直接改。

---

## 许可

本项目基于 **GNU General Public License v3.0** 发布，完整条款见仓库根目录的 [`LICENSE`](LICENSE) 文件。

```
Copyright (C) 2026 Freewind72

本程序是自由软件：你可以根据自由软件基金会发布的 GNU 通用公共许可证
（第 3 版，或你选择的任何更新版本）的条款重新分发和/或修改它。

本程序的分发是希望它有用，但不提供任何担保，甚至不提供适销性或
特定用途适用性的默示担保。详见 GNU 通用公共许可证。
```

### 第三方组件

**本项目不分发任何第三方工具**，只是在安装时从各官方站点/镜像下载，因此每个工具仍然受其**原有许可证**约束，与本项目的 GPL-3.0 无关：

| 工具 | 许可证 |
| --- | --- |
| OpenJDK | GPL-2.0 with Classpath Exception |
| Apache Maven | Apache License 2.0 |
| Node.js | MIT |
| PHP | PHP License 3.01 |
| Go | BSD-3-Clause |
| Python | PSF License Agreement |
| Gradle | Apache License 2.0 |

清单里配哪些版本、从哪个镜像下载，由使用者自行决定。再分发这些二进制时请自行确认各自的许可条款（尤其是署名与商标要求）。
