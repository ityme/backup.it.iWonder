# bit

bit 即为 **backup it** 的简称。

它是一个轻量的本地备份脚本，用来把你指定的文件或目录按“原始绝对路径”保存到本地仓库中，并在需要时一键恢复到原位置。这个工具尤其适合备份以下内容：

- Shell 配置文件
- 编辑器配置目录
- 常用脚本
- 个人环境初始化文件
- 需要跨机器迁移的目录结构

---

## 1. 项目功能概览

bit 的核心目标很简单：

> 备份你关心的文件，保留它们原本所在的路径结构，后续再精确恢复。

主要能力如下：

- **track**：把文件或目录存档到 bit 仓库
- **untrack**：从 bit 仓库中移除某个已存档路径
- **deploy**：把仓库中的全部内容，或指定文件/目录恢复到系统原始路径
- **tree**：查看仓库中的目录结构（Windows 下依赖 eza）
- **im**：查看或修改当前主机唯一标识
- **restore**：清理本机 bit 配置与本地数据目录

脚本会尽量避免直接删除已有文件：

- 在 **Windows / Git Bash** 中，会优先尝试移入回收站
- 在 **Linux / Unix** 中，会移动到 **/tmp** 临时目录

---

## 2. 下载方式

请前往以下地址下载最新发布版本：

- [github latest](https://github.com/ityme/backup.it.iWonder/releases/latest)

发布包通常是一个 zip 文件。解压后，里面会有一个可执行脚本文件：

- `bit`

该文件可直接作为命令使用。

---

## 3. 安装步骤

### 3.1 Windows（推荐在 Git Bash 中使用）

1. 打开发布页并下载最新 zip 包。
2. 解压 zip 文件。
3. 找到解压后的可执行文件 `bit`。
4. 将它放到 **Git Bash 能检测到的 PATH 目录** 中。

常见可选目录示例：

- `C:/Program Files/Git/usr/bin`
- 你自己已经加入 PATH 的某个脚本目录

5. 如果你需要使用 tree 查看树状结构，请额外安装 `eza`。

例如可使用：

```bash
scoop install eza
```

或：

```bash
choco install eza
```

6. 重新打开 Git Bash。
7. 执行：

```bash
bit --help
```

如果成功看到帮助信息，说明安装完成。

### 3.2 Linux

1. 打开发布页并下载最新 zip 包。
2. 解压 zip 文件。
3. 找到其中的 `bit` 文件。
4. 将它放到 shell 可检测的 PATH 目录中，例如：

```bash
sudo cp bit /usr/local/bin/bit
sudo chmod +x /usr/local/bin/bit
```

5. 验证安装：

```bash
bit --help
```

---

## 4. 首次使用前会发生什么

当你第一次执行除帮助以外的命令时，bit 会提示你填写两项信息：

### 4.1 自定义主机唯一标识

比如：

- `office-pc`
- `my-laptop`
- `win-main`

这个值用于区分不同机器的备份数据。

### 4.2 数据目录路径

用于指定 bit 仓库实际保存的位置。

例如：

- Windows / Git Bash：`D:/backup_data`
- Linux：`/home/yourname/data`

之后 bit 会在该目录下维护自己的仓库结构。

---

## 5. 基本使用方法

### 5.1 查看帮助

```bash
bit --help
```

### 5.2 查看当前主机标识

```bash
bit im
```

### 5.3 修改当前主机标识

```bash
bit im office-pc
```

### 5.4 存档一个文件

```bash
bit track ~/.bashrc
```

### 5.5 存档一个目录

```bash
bit track ~/.config/nvim
```

### 5.6 一次存档多个路径

```bash
bit track ~/.vimrc ~/.config/nvim ~/scripts
```

### 5.7 取消存档

```bash
bit untrack ~/.bashrc
```

### 5.8 恢复全部已备份内容到原路径

```bash
bit deploy
```

### 5.9 仅恢复指定文件或目录

恢复单个文件：

```bash
bit deploy ~/.bashrc
```

恢复多个路径：

```bash
bit deploy ~/.bashrc ~/.config/nvim ~/scripts
```

### 5.10 查看仓库树结构

```bash
bit tree
```

查看某个具体路径对应的仓库结构：

```bash
bit tree ~/.config
```

### 5.11 清理本地配置与数据

```bash
bit restore
```

> 该命令会移除当前用户的 bit 配置和本地数据目录，执行前请确认是否真的需要清理。

---

## 6. bit 的工作原理

bit 不只是简单复制文件，而是会尽量保留原路径层级。

例如你执行：

```bash
bit track /etc/hosts
```

那么它会在自己的数据仓库中保存为类似结构：

```text
<数据目录>/.bit/repository/<PC_ID>/root/etc/hosts
```

这样做的好处是：后续执行 `bit deploy` 时，就能把文件恢复回原本的位置。

---

## 7. 典型使用场景

### 场景一：备份开发环境配置

```bash
bit track ~/.gitconfig ~/.vimrc ~/.config/nvim
```

### 场景二：新电脑初始化时恢复配置

```bash
bit deploy
```

### 场景三：删除不再需要维护的路径

```bash
bit untrack ~/.vimrc
```

---

## 8. 注意事项

1. `push` 和 `pull` 目前仍是预留命令，暂未实现。
2. Windows 下建议在 **Git Bash** 中使用；若要使用 `bit tree`，请先安装 **eza**。
3. `deploy` 支持不带参数恢复全部内容，也支持传入一个或多个路径进行定向恢复。
4. `deploy` 在恢复文件前，如果目标位置已有同名内容，会先尝试移走旧文件。
5. 请把数据目录设置在一个你自己清楚且方便备份的位置。
6. 若你把 `bit` 放进 PATH 目录后仍无法识别，请重开终端后再试。

---

## 9. 快速开始示例

假设你刚安装完成，可以按下面步骤体验：

```bash
bit --help
bit im my-laptop
bit track ~/.bashrc
bit track ~/.config/nvim
bit tree
bit deploy ~/.bashrc ~/.config/nvim
bit deploy
```

---

## 10. 许可证

本项目采用仓库中提供的许可证文件，详见 `LICENSE`。

