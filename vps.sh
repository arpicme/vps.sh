#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# VPS Bootstrap — Debian
#
# Устанавливает и настраивает:
#   • системные пакеты и обновления
#   • UTC
#   • micro
#   • Starship + Gruvbox Rainbow
#   • JetBrainsMono Nerd Font
#   • Zsh + Zinit
#   • zsh-completions
#   • zsh-autocomplete + FZF Tab
#   • zsh-autosuggestions
#   • zsh-syntax-highlighting
#   • zoxide
#   • cron для автоматических обновлений с flock
#
# Скрипт рассчитан на запуск от root на Debian.
# Повторный запуск безопасен: существующие конфиги сохраняются в backup.
# ============================================================================

set -Eeuo pipefail

LOG_FILE="/tmp/vps_setup.log"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"
SPINNER_PID=""

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${HOME}/.local/bin:${PATH:-}"

# ----------------------------------------------------------------------------
# Проверка окружения
# ----------------------------------------------------------------------------
check_environment() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "❌ Этот скрипт необходимо запускать от root."
        return 1
    fi

    if [[ ! -r /etc/os-release ]]; then
        echo "❌ Не найден /etc/os-release."
        return 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "debian" ]]; then
        echo "❌ Поддерживается только Debian. Обнаружено: ${PRETTY_NAME:-unknown}"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# Spinner
# ----------------------------------------------------------------------------
spin_loop() {
    local title="$1"
    local chars=( '|' '/' '-' '\\' )
    local delay=0.1
    local i=0

    tput civis 2>/dev/null || true

    while true; do
        # Всегда перерисовываем одну и ту же строку.
        # \r возвращает курсор в начало строки, а ESC[K очищает её.
        printf '\r\033[K %s... [%s]' "$title" "${chars[i]}"
        i=$(( (i + 1) % ${#chars[@]} ))
        sleep "$delay"
    done
}

start_spinner() {
    spin_loop "$1" &
    SPINNER_PID=$!
}

stop_spinner() {
    if [[ -n "${SPINNER_PID}" ]]; then
        kill "${SPINNER_PID}" 2>/dev/null || true
        wait "${SPINNER_PID}" 2>/dev/null || true
        SPINNER_PID=""
    fi

    # Убираем последнюю рамку spinner'а и восстанавливаем курсор.
    printf '\r\033[K'
    tput cnorm 2>/dev/null || true
}

trap 'stop_spinner' EXIT INT TERM

# ----------------------------------------------------------------------------
# Выполнение этапа
#
# Каждый этап запускается в отдельном subshell с собственным errexit.
# Это важно: функции, вызванные непосредственно внутри if/while, могут
# иначе наследовать подавленный errexit.
# ----------------------------------------------------------------------------
run_step() {
    local title="$1"
    shift
    local status
    local pid

    start_spinner "$title"

    {
        printf '\n===== %s =====\n' "$title"
        printf 'Started: %s\n' "$(date --iso-8601=seconds)"
    } >> "$LOG_FILE"

    set +e
    (
        set -Eeuo pipefail
        "$@"
    ) >> "$LOG_FILE" 2>&1 &
    pid=$!
    wait "$pid"
    status=$?
    set -e

    stop_spinner

    if [[ "$status" -eq 0 ]]; then
        echo -e "\r\033[K✅ $title — готово"
        return 0
    fi

    echo -e "\r\033[K❌ $title — ошибка"
    echo
    echo "Последние строки лога:"
    tail -n 40 "$LOG_FILE" || true
    echo
    echo "Полный лог: $LOG_FILE"
    return "$status"
}

# ----------------------------------------------------------------------------
# Подготовка каталогов
# ----------------------------------------------------------------------------
prepare_environment() {
    mkdir -p \
        "$HOME/.config" \
        "$HOME/.local/bin" \
        "$HOME/.local/share" \
        "$HOME/.local/share/zsh"

    chmod 700 \
        "$HOME/.config" \
        "$HOME/.local" \
        "$HOME/.local/share" \
        "$HOME/.local/bin" \
        "$HOME/.local/share/zsh"
}

# ----------------------------------------------------------------------------
# Очистка старых completion-кэшей
# ----------------------------------------------------------------------------
pre_clean_zsh() {
    rm -rf \
        "$HOME/.local/share/zinit/completions" \
        "$HOME/.local/share/zinit/plugins/marlonrichert---zsh-autocomplete" \
        "$HOME/.zcompdump"*
}

# ----------------------------------------------------------------------------
# Backup существующей конфигурации
# ----------------------------------------------------------------------------
backup_existing_config() {
    local backup_dir="$HOME/.vps_setup_backup/$BACKUP_SUFFIX"

    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"

    [[ -f "$HOME/.zshrc" ]] && cp -a "$HOME/.zshrc" "$backup_dir/.zshrc"
    [[ -f "$HOME/.config/starship.toml" ]] && cp -a "$HOME/.config/starship.toml" "$backup_dir/starship.toml"
    [[ -f "$HOME/.config/micro/settings.json" ]] && cp -a "$HOME/.config/micro/settings.json" "$backup_dir/micro-settings.json"
    [[ -f "$HOME/.config/micro/bindings.json" ]] && cp -a "$HOME/.config/micro/bindings.json" "$backup_dir/micro-bindings.json"

    echo "Backup: $backup_dir"
}

# ----------------------------------------------------------------------------
# APT
# ----------------------------------------------------------------------------
apt_update() {
    if apt-get update; then
        return 0
    fi

    echo "APT update не прошёл с текущим сетевым стеком. Повторяю через IPv4..."
    printf 'Acquire::ForceIPv4 "true";\n' > /etc/apt/apt.conf.d/99force-ipv4
    apt-get update
}

apt_upgrade() {
    apt-get full-upgrade -yq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
}

install_base_packages() {
    apt-get install -yq \
        ca-certificates \
        curl \
        wget \
        git \
        unzip \
        sudo \
        micro \
        nano \
        zsh \
        cron \
        socat \
        net-tools \
        btop \
        fzf \
        zoxide \
        zstd \
        fontconfig \
        fonts-font-awesome \
        ufw
}

# ----------------------------------------------------------------------------
# Часовой пояс
# ----------------------------------------------------------------------------
setup_timezone() {
    if command -v timedatectl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        timedatectl set-timezone UTC
        return 0
    fi

    [[ -e /usr/share/zoneinfo/UTC ]] || return 1
    ln -sfn /usr/share/zoneinfo/UTC /etc/localtime
    printf 'UTC\n' > /etc/timezone
}

# ----------------------------------------------------------------------------
# micro
# ----------------------------------------------------------------------------
setup_micro() {
    mkdir -p "$HOME/.config/micro"

    cat > "$HOME/.config/micro/bindings.json" <<'MICRO_BINDINGS'
{
    "Alt-/": "lua:comment.comment",
    "CtrlUnderscore": "lua:comment.comment",
    "Ctrl-c": "Copy",
    "Ctrl-v": "Paste"
}
MICRO_BINDINGS

    cat > "$HOME/.config/micro/settings.json" <<'MICRO_SETTINGS'
{
    "clipboard": "terminal"
}
MICRO_SETTINGS

    chmod 600 \
        "$HOME/.config/micro/bindings.json" \
        "$HOME/.config/micro/settings.json"
}

# ----------------------------------------------------------------------------
# Starship
# ----------------------------------------------------------------------------
install_starship() {
    if command -v starship >/dev/null 2>&1; then
        return 0
    fi

    curl -fsSL https://starship.rs/install.sh | sh -s -- -y
    command -v starship >/dev/null 2>&1
}

setup_starship_preset() {
    mkdir -p "$HOME/.config"
    starship preset gruvbox-rainbow --force -o "$HOME/.config/starship.toml"
    chmod 600 "$HOME/.config/starship.toml"
}

# ----------------------------------------------------------------------------
# JetBrainsMono Nerd Font
# ----------------------------------------------------------------------------
install_jetbrains_mono_nerd_font() {
    local font_dir="$HOME/.local/share/fonts/JetBrainsMono"
    local work_dir="/tmp/jetbrains-mono-nerd-font"
    local archive="$work_dir/JetBrainsMono.zip"
    local existing_font=""

    mkdir -p "$font_dir"

    existing_font="$(find "$font_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit)"
    if [[ -n "$existing_font" ]]; then
        return 0
    fi

    rm -rf "$work_dir"
    mkdir -p "$work_dir"

    curl -fsSL \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
        -o "$archive"

    [[ -s "$archive" ]]

    unzip -q -o "$archive" -d "$work_dir/unpacked"

    find "$work_dir/unpacked" \
        -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
        -exec cp -f {} "$font_dir/" \;

    existing_font="$(find "$font_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit)"
    [[ -n "$existing_font" ]]

    fc-cache -f "$font_dir"
    rm -rf "$work_dir"
}

# ----------------------------------------------------------------------------
# Zinit
# ----------------------------------------------------------------------------
install_zinit() {
    local zinit_root="${XDG_DATA_HOME:-$HOME/.local/share}/zinit"
    local zinit_dir="$zinit_root/zinit.git"

    mkdir -p "$zinit_root"

    if [[ -f "$zinit_dir/zinit.zsh" ]]; then
        # Обновление best-effort: существующая рабочая версия не должна
        # блокировать повторный запуск bootstrap.
        git -C "$zinit_dir" pull --ff-only >/dev/null 2>&1 || true
        return 0
    fi

    rm -rf "$zinit_dir"
    git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$zinit_dir"
    [[ -f "$zinit_dir/zinit.zsh" ]]
}

# ----------------------------------------------------------------------------
# Zsh configuration
# ----------------------------------------------------------------------------
generate_zshrc() {
    local zinit_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

    [[ -f "$zinit_dir/zinit.zsh" ]]

    cat > "$HOME/.zshrc" <<ZSHRC
# ============================================================================
# Zsh configuration generated by VPS bootstrap
# Generated: $(date --iso-8601=seconds)
# ============================================================================

# PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$HOME/.local/bin:\$PATH"

# Editors
export EDITOR="micro"
export VISUAL="micro"

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
HISTSIZE=5000
SAVEHIST=5000
HISTFILE="\$HOME/.zsh_history"

setopt append_history
setopt share_history
setopt inc_append_history
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt extended_history

# ---------------------------------------------------------------------------
# Directory history (cdr)
# ---------------------------------------------------------------------------
mkdir -p "\$HOME/.local/share/zsh"
touch "\$HOME/.local/share/zsh/chpwd-recent-dirs"
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs

# ---------------------------------------------------------------------------
# Keymap
# ---------------------------------------------------------------------------
bindkey -e

# ---------------------------------------------------------------------------
# Zinit
# ---------------------------------------------------------------------------
ZINIT_HOME="${zinit_dir}"
source "\${ZINIT_HOME}/zinit.zsh"

# ---------------------------------------------------------------------------
# Completion configuration
#
# zsh-autocomplete управляет compinit сам. Не вызываем compinit вручную:
# это избавляет от двойной инициализации completion subsystem.
# ---------------------------------------------------------------------------
zstyle '*:compinit' arguments -D -i -u -C -w
zstyle ':completion:*' list-colors "\${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# zsh-autocomplete использует FZF для Tab.
zstyle ':autocomplete:tab:*' fzf yes

# ---------------------------------------------------------------------------
# System FZF shell integration
# Должна быть загружена до zsh-autocomplete, чтобы его FZF-режим был
# доступен при инициализации.
# ---------------------------------------------------------------------------
if [[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
fi
if [[ -r /usr/share/doc/fzf/examples/completion.zsh ]]; then
    source /usr/share/doc/fzf/examples/completion.zsh
fi

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------
zinit ice depth=1
zinit light zsh-users/zsh-completions

zinit ice depth=1
zinit light marlonrichert/zsh-autocomplete

zinit ice depth=1
zinit light zsh-users/zsh-autosuggestions

zinit snippet OMZ::plugins/git/git.plugin.zsh

# Syntax highlighting — загружаем последним из основных plugins.
zinit ice depth=1
zinit light zsh-users/zsh-syntax-highlighting

# ---------------------------------------------------------------------------
# FZF history
# ---------------------------------------------------------------------------
if (( \${+widgets[fzf-history-widget]} )); then
    bindkey '^R' fzf-history-widget
fi

# Prefix history search
bindkey '^P' history-search-backward
bindkey '^N' history-search-forward

# ---------------------------------------------------------------------------
# zoxide
# ---------------------------------------------------------------------------
if command -v zoxide >/dev/null 2>&1; then
    eval "\$(zoxide init zsh)"
fi

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
alias ls='ls --color=auto'
alias rr='/usr/local/bin/remnawave_reverse'
alias rwe='docker exec -it remnawave cli'
alias up='apt-get update && apt-get full-upgrade -y'
alias upw='up && rwu'
alias mi='micro'
alias mzh='micro ~/.zshrc'
alias szh='source ~/.zshrc'
alias cl='clear'
alias mds='motd-set'
alias scu='bash <(wget -qO- https://raw.githubusercontent.com/arpicme/vps.sh/refs/heads/main/vps.sh)'
alias zup='zinit self-update -q && zinit update --all -q'

# ---------------------------------------------------------------------------
# Remnawave helpers
# ---------------------------------------------------------------------------
rwr() {
    local dir=""

    if [[ -d /opt/remnanode ]]; then
        dir=/opt/remnanode
    elif [[ -d /opt/remnawave ]]; then
        dir=/opt/remnawave
    else
        echo 'Ошибка: ни одна из папок (/opt/remnanode или /opt/remnawave) не найдена.'
        return 1
    fi

    cd "\$dir" || return 1
    docker compose down && docker compose up -d && docker compose logs -f -t
}

rwu() {
    local dir=""

    if [[ -d /opt/remnanode ]]; then
        dir=/opt/remnanode
    elif [[ -d /opt/remnawave ]]; then
        dir=/opt/remnawave
    else
        echo 'Ошибка: ни одна из папок (/opt/remnanode или /opt/remnawave) не найдена.'
        return 1
    fi

    cd "\$dir" || return 1
    docker compose pull && docker compose down && docker compose up -d && docker compose logs -f -t
}

# ---------------------------------------------------------------------------
# Starship
# ---------------------------------------------------------------------------
if command -v starship >/dev/null 2>&1; then
    eval "\$(starship init zsh)"
fi
ZSHRC

    chmod 600 "$HOME/.zshrc"
}

# ----------------------------------------------------------------------------
# Проверка Zsh-конфига и первичная загрузка plugins
# ----------------------------------------------------------------------------
validate_zsh() {
    zsh -n "$HOME/.zshrc"

    zsh -lic '
        whence -w zinit >/dev/null || exit 1
        whence -w zoxide >/dev/null || exit 1
        whence -w starship >/dev/null || exit 1
        whence -w fzf >/dev/null || exit 1
        (( $+widgets[fzf-history-widget] )) || true
        exit 0
    '
}

# ----------------------------------------------------------------------------
# Shell по умолчанию
# ----------------------------------------------------------------------------
set_zsh_default() {
    local zsh_path
    zsh_path="$(command -v zsh)"

    [[ -x "$zsh_path" ]]
    chsh -s "$zsh_path" root
}

# ----------------------------------------------------------------------------
# Cron / автоматическое обновление APT
# ----------------------------------------------------------------------------
setup_cron() {
    local updater="/usr/local/sbin/apt-autoupdate"
    local cron_job="0 19 * * 4 $updater"
    local tmp

    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        systemctl enable cron --now
    elif command -v service >/dev/null 2>&1; then
        service cron start || true
    elif [[ -x /etc/init.d/cron ]]; then
        /etc/init.d/cron start || true
    fi

    cat > "$updater" <<'UPDATER'
#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE=/var/log/apt_autoupdate.log
LOCK_FILE=/run/lock/apt-autoupdate.lock

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

printf '\n===== %s =====\n' "$(date --iso-8601=seconds)" >> "$LOG_FILE"
export DEBIAN_FRONTEND=noninteractive

/usr/bin/apt-get update >> "$LOG_FILE" 2>&1
/usr/bin/apt-get full-upgrade -yq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    >> "$LOG_FILE" 2>&1
UPDATER

    chmod 750 "$updater"

    touch /var/log/apt_autoupdate.log
    chmod 600 /var/log/apt_autoupdate.log

    tmp="$(mktemp)"

    crontab -l 2>/dev/null | grep -Fv -- "$cron_job" > "$tmp" || true
    printf '%s\n' "$cron_job" >> "$tmp"
    crontab "$tmp"

    rm -f "$tmp"
}

# ----------------------------------------------------------------------------
# Финальная проверка
# ----------------------------------------------------------------------------
final_checks() {
    local font_file
    font_file="$(find "$HOME/.local/share/fonts/JetBrainsMono" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit)"

    command -v zsh >/dev/null 2>&1
    command -v git >/dev/null 2>&1
    command -v curl >/dev/null 2>&1
    command -v fzf >/dev/null 2>&1
    command -v zoxide >/dev/null 2>&1
    command -v starship >/dev/null 2>&1

    [[ -f "$HOME/.zshrc" ]]
    [[ -f "$HOME/.config/starship.toml" ]]
    [[ -f "$HOME/.local/share/zinit/zinit.git/zinit.zsh" ]]
    [[ -x /usr/local/sbin/apt-autoupdate ]]
    [[ -n "$font_file" ]]

    zsh -n "$HOME/.zshrc"
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
    : > "$LOG_FILE"
    chmod 600 "$LOG_FILE"

    echo
    echo "🚀 Начинаем настройку Debian VPS..."
    echo

    run_step "Проверка окружения" check_environment
    run_step "Подготовка каталогов и окружения" prepare_environment
    run_step "Очистка старого кэша Zsh" pre_clean_zsh
    run_step "Backup существующей конфигурации" backup_existing_config

    run_step "Обновление списка пакетов" apt_update
    run_step "Обновление системы (full-upgrade)" apt_upgrade
    run_step "Установка базовых пакетов" install_base_packages

    run_step "Настройка часового пояса UTC" setup_timezone
    run_step "Конфигурация редактора micro" setup_micro
    run_step "Установка Starship" install_starship
    run_step "Установка JetBrainsMono Nerd Font" install_jetbrains_mono_nerd_font
    run_step "Установка Zinit" install_zinit
    run_step "Генерация ~/.zshrc" generate_zshrc
    run_step "Проверка Zsh и первичная загрузка plugins" validate_zsh
    run_step "Применение темы Gruvbox Rainbow" setup_starship_preset
    run_step "Установка Zsh по умолчанию" set_zsh_default
    run_step "Настройка автоматических обновлений Cron" setup_cron
    run_step "Финальная проверка установки" final_checks

    echo
    echo "================================================================"
    echo "🎉 Настройка успешно завершена!"
    echo
    echo "Лог:    $LOG_FILE"
    echo "Backup: $HOME/.vps_setup_backup/$BACKUP_SUFFIX"
    echo "Cron:   каждый четверг в 19:00 UTC"
    echo
    echo "После выхода из текущей сессии будет использоваться Zsh."
    echo "Для немедленного запуска: exec zsh -l"
    echo "================================================================"
    echo

    tput cnorm 2>/dev/null || true
    exec zsh -l
}

main "$@"
