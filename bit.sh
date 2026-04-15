#!/usr/bin/env bash

# bit = backup it
#
# 项目定位：
#   将任意文件或目录按“原始绝对路径”映射保存到 bit 仓库中，
#   便于后续进行统一备份、迁移与恢复。
#
# 发布说明：
#   仓库源码文件名为 bit.sh；发布包中通常提供可直接执行的 bit 文件。

SCRIPT_NAME="$(basename "$0")"


# ==============================
# 日志模块：统一输出格式
# ==============================
# 所有日志统一为：
#   [bit][INFO]    普通信息
#   [bit][OK]      成功信息
#   [bit][WARN]    警告信息
#   [bit][ERROR]   错误信息
log() {
    local level="$1"
    shift
    printf '[bit][%s] %s\n' "$level" "$*"
}

log_info() {
    log "INFO" "$*"
}

log_success() {
    log "OK" "$*"
}

log_warn() {
    log "WARN" "$*"
}

log_error() {
    log "ERROR" "$*"
}


# ==============================
# 帮助模块：展示用法说明
# ==============================
# 注意：帮助信息不依赖任何本地配置，因此用户首次执行
#   bit --help
# 也能直接看到完整说明，而不会被交互式输入打断。
usage() {
    cat <<EOF
bit = backup it

用法:
  $SCRIPT_NAME <command> [args ...]

命令:
  help | -h | --help     显示帮助信息
  im [PC_ID]             查看或设置当前主机唯一标识
  track <path...>        将文件/目录纳入 bit 仓库
  untrack <path...>      从 bit 仓库移除文件/目录
  deploy [path...]       恢复全部内容，或仅恢复指定文件/目录
  tree [path]            查看仓库中指定路径的树状结构
  restore                清理当前用户配置与本地仓库数据
  push                   预留命令，暂未实现
  pull                   预留命令，暂未实现

首次使用说明:
  除 help 外，首次执行命令时会提示输入：
  1. 自定义主机唯一标识
  2. 数据目录路径（例如 D:/data 或 /d/data）

示例:
  $SCRIPT_NAME im
  $SCRIPT_NAME im OFFICE-PC
  $SCRIPT_NAME track ~/.config/nvim
  $SCRIPT_NAME track /etc/hosts ./notes
  $SCRIPT_NAME untrack ~/.config/nvim
  $SCRIPT_NAME deploy
  $SCRIPT_NAME deploy ~/.bashrc ~/.config/nvim
  $SCRIPT_NAME tree
  $SCRIPT_NAME tree ~/.config

说明:
  Windows 下 tree 命令依赖 eza；若未安装会给出提示。
EOF
}


# ==============================
# 基础工具模块
# ==============================

# 如果目标路径已存在，则先重命名为带时间戳的备份名，
# 避免后续移动或复制时发生同名冲突。
rename_if_target_exists() {
    local target="$1"

    if [[ ! -e "$target" ]]; then
        return 0
    fi

    local timestamp
    timestamp="$(date +%Y%m%d%H%M%S%3N 2>/dev/null || date +%Y%m%d%H%M%S)"
    local target_bak="${target}.${timestamp}"

    if mv "$target" "$target_bak"; then
        log_warn "检测到同名目标，已重命名备份: $target -> $target_bak"
        return 0
    fi

    log_error "重命名已有目标失败: $target"
    return 1
}


# Windows 专用删除策略：通过 PowerShell 将文件/目录移入回收站，
# 尽量避免直接永久删除。
windows_mv_to_trash() {
    local arg="$1"
    local unix_abs_path
    unix_abs_path="$(realpath "$arg")"
    local win_abs_path
    win_abs_path="$(cygpath -w "$unix_abs_path")"

    if powershell.exe -NoProfile -Command "
        Add-Type -AssemblyName Microsoft.VisualBasic;
        if (Test-Path '$win_abs_path' -PathType Container) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('$win_abs_path', 'OnlyErrorDialogs', 'SendToRecycleBin')
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('$win_abs_path', 'OnlyErrorDialogs', 'SendToRecycleBin')
        }" >/dev/null 2>&1; then
        log_success "已移入 Windows 回收站: $arg"
        return 0
    fi

    log_error "移入 Windows 回收站失败: $arg"
    return 1
}


# Unix/Linux 的简化删除策略：移动到 /tmp，
# 便于后续自行检查与处理。
unix_mv_to_trash() {
    local trash_dir="/tmp"
    local arg="$1"
    local file_name
    file_name="$(basename "$arg")"
    local dst_abs
    dst_abs="$(realpath -m "${trash_dir}/${file_name}")"

    if rename_if_target_exists "$dst_abs"; then
        if mv "$arg" "$trash_dir"; then
            log_success "已移动到临时回收区: $arg -> $dst_abs"
            return 0
        fi
    fi

    log_error "移动到临时回收区失败: $arg"
    return 1
}


# 统一的“删除入口”：
# - Windows 使用回收站
# - 其他系统移动到 /tmp
move_to_trash() {
    local delete_it="unix_mv_to_trash"

    if [[ "${OS:-}" == "Windows_NT" ]]; then
        delete_it="windows_mv_to_trash"
    fi

    local arg
    for arg in "$@"; do
        if [[ "$arg" == -* ]]; then
            continue
        fi

        if [[ ! -e "$arg" ]]; then
            log_info "跳过不存在的路径: $arg"
            continue
        fi

        "$delete_it" "$arg"
    done
}


# 检查某个配置文件是否存在且非空；若为空，则提示用户交互输入。
# 这里用于首次初始化：
# - 主机唯一标识 PC_ID
# - 数据目录 DATA_DIR_PATH
field_file_checker() {
    local f_abs="$1"
    local f_desc="$2"

    if [[ ! -s "$f_abs" ]]; then
        printf '未检测到%s，请输入：' "$f_desc"
        read -r user_input

        # 仅去除首尾空白，保留路径内部空格。
        user_input="$(printf '%s' "$user_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        if [[ -n "$user_input" ]]; then
            echo "$user_input" > "$f_abs"
            log_success "$f_desc 已保存至: $f_abs"
        else
            log_error "输入内容不能为空。"
            exit 1
        fi
    fi
}


# 初始化运行环境：
# 负责准备用户配置目录、仓库存储目录以及 ROOT_DIR 根映射目录。
init_runtime() {
    USER_INFO_DIR="$(realpath -m "$HOME/.bit/tmp/user_info")"
    mkdir -p "$USER_INFO_DIR"

    PC_ID_FILE_PATH="$(realpath -m "$USER_INFO_DIR/PC_ID")"
    field_file_checker "$PC_ID_FILE_PATH" "自定义主机唯一标识"

    DATA_DIR_PATH="$(realpath -m "$USER_INFO_DIR/DATA_DIR_PATH")"
    field_file_checker "$DATA_DIR_PATH" "数据目录路径(格式示例: D:/aa/bb 或 /d/aa/bb)"

    DATA_DIR="$(realpath -m "$(cat "$DATA_DIR_PATH")/.bit")"
    PC_ID="$(cat "$PC_ID_FILE_PATH")"
    REPOSITORY_DIR="$(realpath -m "$DATA_DIR/repository")"

    # ROOT_DIR 用来模拟真实文件系统根路径。
    # 例如原文件是 /home/user/.bashrc，仓库中就会映射到：
    #   <DATA_DIR>/.bit/repository/<PC_ID>/root/home/user/.bashrc
    ROOT_DIR="$(realpath -m "$REPOSITORY_DIR/$PC_ID/root")"
    mkdir -p "$ROOT_DIR"
}


# ==============================
# 核心命令模块
# ==============================

# track：存档文件或目录
# 行为说明：
# - 保留源路径的绝对路径层级
# - 如果仓库中已有同名内容，会先移走旧内容再复制新内容
track() {
    local src="$1"

    if [[ ! -e "$src" ]]; then
        log_error "待存档路径不存在: $src"
        return 1
    fi

    local src_abs
    src_abs="$(realpath "$src")"
    local src_dir
    src_dir="$(dirname "$src_abs")"

    local dst_dir
    dst_dir="$(realpath -m "$ROOT_DIR/$src_dir")"
    local dst_abs
    dst_abs="$(realpath -m "$ROOT_DIR/$src_abs")"

    mkdir -p "$dst_dir"

    if [[ -e "$dst_abs" ]]; then
        log_warn "仓库中已存在同路径内容，准备覆盖: $dst_abs"
        move_to_trash "$dst_abs"
    fi

    if cp -rf "$src_abs" "$dst_dir"; then
        log_success "已存档: $src_abs -> $dst_dir/$(basename "$src_abs")"
        return 0
    fi

    log_error "存档失败: $src_abs"
    return 1
}


# untrack：从 bit 仓库中移除某个已存档路径。
# 说明：
# - 即使原始路径已不存在，也允许根据路径字符串在仓库中删除映射内容
# - 删除后会顺带清理空目录，保持仓库整洁
untrack() {
    local src="$1"
    local src_abs
    src_abs="$(realpath -m "$src")"
    local dst_abs
    dst_abs="$(realpath -m "$ROOT_DIR/$src_abs")"

    if [[ -e "$dst_abs" ]]; then
        log_warn "准备从仓库中移除: $dst_abs"
        move_to_trash "$dst_abs"

        local tmp_dir
        tmp_dir="$(dirname "$dst_abs")"
        while [[ "$tmp_dir" != "$ROOT_DIR" ]]; do
            if [[ -d "$tmp_dir" && -z "$(ls -A "$tmp_dir")" ]]; then
                log_info "清理空目录: $tmp_dir"
                move_to_trash "$tmp_dir"
                tmp_dir="$(dirname "$tmp_dir")"
            else
                break
            fi
        done

        log_success "已取消存档: $src"
        return 0
    fi

    log_warn "仓库中未找到对应路径: $dst_abs"
    return 1
}


# 根据仓库中的某个映射实体，恢复到原始绝对路径。
# 既支持文件，也支持目录，还支持空目录。
restore_repo_entry() {
    local repo_abs="$1"
    local target_path
    target_path="${repo_abs#$ROOT_DIR}"
    local target_dir
    target_dir="$(dirname "$target_path")"

    log_info "正在恢复: $repo_abs -> $target_path"
    mkdir -p "$target_dir"

    if [[ -e "$target_path" ]]; then
        log_warn "目标路径已有内容，先移走旧版本: $target_path"
        move_to_trash "$target_path"
    fi

    if cp -af "$repo_abs" "$target_path"; then
        log_success "恢复完成: $target_path"
        return 0
    fi

    log_error "恢复失败: $target_path"
    return 1
}


# 按用户指定路径恢复。
# 传入的是“原始路径”，函数内部会自动映射到仓库中的对应位置。
restore_selected_path() {
    local requested_path="$1"
    local target_abs
    target_abs="$(realpath -m "$requested_path")"
    local repo_abs
    repo_abs="$(realpath -m "$ROOT_DIR/$target_abs")"

    if [[ ! -e "$repo_abs" ]]; then
        log_warn "仓库中未找到待恢复路径: $requested_path"
        return 1
    fi

    restore_repo_entry "$repo_abs"
}


# deploy：将仓库中的内容恢复到系统原始路径。
# - 不带参数：恢复全部已存档内容
# - 带参数：仅恢复指定的一个或多个文件/目录
deploy() {
    if [[ $# -eq 0 ]]; then
        find "$ROOT_DIR" \( -type f -o \( -type d -empty \) \) | while read -r src_file; do
            if [[ "$src_file" == "$ROOT_DIR" ]]; then
                continue
            fi
            restore_repo_entry "$src_file"
        done
        return 0
    fi

    local item
    for item in "$@"; do
        restore_selected_path "$item"
    done
}


# tree：查看仓库中的映射结构。
# - 不传参数时展示整个仓库树
# - 传路径时只展示该路径对应的仓库子树
# - Windows 下依赖 eza 展示更好的树状结构
tree_view() {
    local src_abs=""
    if [[ $# -ge 1 && -n "$1" ]]; then
        src_abs="$(realpath -m "$1")"
    fi

    local dst_abs
    dst_abs="$(realpath -m "$ROOT_DIR/$src_abs")"

    if [[ ! -e "$dst_abs" ]]; then
        log_error "仓库中不存在该路径: $dst_abs"
        return 1
    fi

    if [[ "${OS:-}" == "Windows_NT" ]]; then
        if command -v eza >/dev/null 2>&1; then
            eza --tree "$dst_abs"
        else
            log_error "Windows 下 tree_view 依赖 eza，请先安装 eza。"
            log_info "安装参考: https://eza.rocks/"
            return 1
        fi
    else
        if command -v tree >/dev/null 2>&1; then
            tree "$dst_abs"
        else
            find "$dst_abs"
        fi
    fi
}


# ==============================
# 主流程模块
# ==============================
main() {
    # 帮助命令优先处理，避免首次查看帮助时触发交互输入。
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    case "$1" in
        help|-h|--help)
            usage
            exit 0
            ;;
    esac

    init_runtime

    case "$1" in
        im)
            if [[ $# -lt 2 ]]; then
                echo "$PC_ID"
                exit 0
            fi

            move_to_trash "$PC_ID_FILE_PATH"
            echo "$2" > "$PC_ID_FILE_PATH"
            log_success "新的自定义主机唯一标识已保存至: $PC_ID_FILE_PATH"
            exit 0
            ;;
        restore)
            move_to_trash "$USER_INFO_DIR" "$DATA_DIR"
            log_success "本地配置与数据目录已清理完成。"
            exit 0
            ;;
        track)
            if [[ $# -lt 2 ]]; then
                log_error "track 命令至少需要一个文件或目录参数。"
                usage
                exit 1
            fi

            shift
            for item in "$@"; do
                track "$item"
            done
            ;;
        untrack)
            if [[ $# -lt 2 ]]; then
                log_error "untrack 命令至少需要一个文件或目录参数。"
                usage
                exit 1
            fi

            shift
            for item in "$@"; do
                untrack "$item"
            done
            exit 0
            ;;
        push)
            log_warn "push 命令暂未实现。"
            exit 0
            ;;
        pull)
            log_warn "pull 命令暂未实现。"
            exit 0
            ;;
        deploy)
            shift
            deploy "$@"
            exit $?
            ;;
        tree)
            shift
            tree_view "$@"
            exit $?
            ;;
        *)
            log_error "未知命令: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"

