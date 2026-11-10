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
ACTIVE_STEP_PID=""

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
# Терминал и выполнение этапов
# ----------------------------------------------------------------------------
restore_terminal() {
    printf '\r\033[K'
    tput cnorm 2>/dev/null || true
}

trap 'restore_terminal' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Этап выполняется в одном фоновом процессе. Spinner рисуется самим
# родительским Bash, поэтому не нужно создавать/убивать отдельный процесс
# анимации и вызывать wait для него (это устраняет race condition wait_for).
run_step() {
    local title="$1"
    shift
    local status=0
    local pid
    local i=0
    local -a chars=( '|' '/' '-' '\\' )

    {
        printf '\n===== %s =====\n' "$title"
        printf 'Started: %s\n' "$(date --iso-8601=seconds)"
    } >> "$LOG_FILE"

    (
        set -Eeuo pipefail
        "$@"
    ) >> "$LOG_FILE" 2>&1 &
    pid=$!
    ACTIVE_STEP_PID="$pid"

    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[K %s... [%s]' "$title" "${chars[i]}"
        i=$(( (i + 1) % ${#chars[@]} ))
        sleep 0.1
    done

    if wait "$pid"; then
        status=0
    else
        status=$?
    fi
    ACTIVE_STEP_PID=""

    printf '\r\033[K'
    tput cnorm 2>/dev/null || true

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
