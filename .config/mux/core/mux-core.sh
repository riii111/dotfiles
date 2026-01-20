#!/usr/bin/env bash
#
# mux-core.sh - Shared library for mux framework
#

set -euo pipefail

#######################################
# Constants & Configuration
#######################################

MUX_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mux"
MUX_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mux"
MUX_LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/mux"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
NC=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'

MUX_LOG_KEEP_SESSIONS="${MUX_LOG_KEEP_SESSIONS:-3}"
MUX_POPUP_WIDTH="${MUX_POPUP_WIDTH:-80%}"
MUX_POPUP_HEIGHT="${MUX_POPUP_HEIGHT:-80%}"

readonly ALLOWED_RUNTIMES="npm yarn pnpm bun cargo bacon"

#######################################
# Lock Management
#######################################

acquire_lock() {
    local project="$1"
    local lock_dir="${MUX_LOCK_DIR}/${project}.lock"

    mkdir -pm 700 "$MUX_LOCK_DIR"

    # Remove stale lock if process is dead
    if [[ -d "$lock_dir" ]]; then
        local lock_pid
        lock_pid=$(cat "${lock_dir}/pid" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -rf "$lock_dir" 2>/dev/null || true
        fi
    fi

    # Atomic lock acquisition
    if ! mkdir -m 700 "$lock_dir" 2>/dev/null; then
        echo -e "${RED}Error: Another mux operation is in progress for ${project}${NC}" >&2
        local lock_pid
        lock_pid=$(cat "${lock_dir}/pid" 2>/dev/null || echo "unknown")
        echo -e "${DIM}Lock held by PID: ${lock_pid}${NC}" >&2
        return 1
    fi

    echo $$ > "${lock_dir}/pid"
    MUX_CURRENT_LOCK="$lock_dir"
}

release_lock() {
    local project="${1:-${PROJECT_NAME:-}}"

    if [[ -n "${MUX_CURRENT_LOCK:-}" && -d "$MUX_CURRENT_LOCK" ]]; then
        rm -rf "$MUX_CURRENT_LOCK" 2>/dev/null || true
        MUX_CURRENT_LOCK=""
        return 0
    fi

    [[ -z "$project" ]] && return 0

    local lock_dir="${MUX_LOCK_DIR}/${project}.lock"
    [[ -d "$lock_dir" ]] && rm -rf "$lock_dir" 2>/dev/null || true
}

#######################################
# YAML Parsing & Config Loading
#######################################

parse_yaml() {
    local file="$1" query="$2" result

    if [[ ! -f "$file" ]]; then
        echo "Error: Config file not found: $file" >&2
        return 1
    fi

    if ! result=$(yq -e "$query" "$file" 2>/dev/null); then
        echo "Error: Failed to parse YAML ($file) with query: $query" >&2
        return 1
    fi

    echo "$result"
}

parse_yaml_allow_null() {
    local file="$1" query="$2"
    [[ ! -f "$file" ]] && echo "" && return 0
    yq "$query" "$file" 2>/dev/null || echo ""
}

# Validate identifier (alphanumeric, hyphen, underscore)
validate_identifier() {
    local name="$1" type="${2:-identifier}"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: Invalid ${type} '${name}'${NC}" >&2
        return 1
    fi
}

validate_service_name() { validate_identifier "$1" "service name"; }

# Validate path (reject $, `)
validate_path() {
    local path="$1" type="${2:-path}"
    if [[ "$path" == *'$'* || "$path" == *'`'* ]]; then
        echo -e "${RED}Error: Invalid ${type} '${path}'${NC}" >&2
        return 1
    fi
    return 0
}

load_config() {
    local project="$1"
    local config_file="${MUX_CONFIG_DIR}/${project}/config.yml"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Error: Config file not found: ${config_file}${NC}" >&2
        return 1
    fi

    PROJECT_NAME=$(parse_yaml "$config_file" '.project.name')
    local raw_root
    raw_root=$(parse_yaml "$config_file" '.project.root')
    PROJECT_ROOT="${raw_root/#\~/$HOME}"
    SESSION_NAME=$(parse_yaml "$config_file" '.project.session_name')

    validate_identifier "$PROJECT_NAME" "project name" || return 1
    validate_identifier "$SESSION_NAME" "session name" || return 1
    validate_path "$PROJECT_ROOT" "project root" || return 1

    DOCKER_ENABLED=$(parse_yaml_allow_null "$config_file" '.docker.enabled // false')
    DOCKER_COMPOSE_FILE=$(parse_yaml_allow_null "$config_file" '.docker.compose_file // "docker-compose.yml"')
    DOCKER_WAIT_TIMEOUT=$(parse_yaml_allow_null "$config_file" '.docker.wait_timeout // 60')

    MUX_LOG_KEEP_SESSIONS=$(parse_yaml_allow_null "$config_file" '.options.log_keep_sessions // 3')
    MUX_POPUP_WIDTH=$(parse_yaml_allow_null "$config_file" '.options.popup_width // "80%"')
    MUX_POPUP_HEIGHT=$(parse_yaml_allow_null "$config_file" '.options.popup_height // "80%"')

    MUX_LOG_BASE_DIR="${MUX_DATA_DIR}/${project}/logs"

    export PROJECT_NAME PROJECT_ROOT SESSION_NAME
    export DOCKER_ENABLED DOCKER_COMPOSE_FILE DOCKER_WAIT_TIMEOUT
    export MUX_LOG_BASE_DIR MUX_LOG_KEEP_SESSIONS

    CONFIG_FILE="$config_file"
    export CONFIG_FILE
}

#######################################
# Service Helpers
#######################################

get_project_name() {
    local script_name
    script_name="$(basename "$(readlink -f "$0" 2>/dev/null || echo "$0")")"

    if [[ "$script_name" == "mux" ]]; then
        echo "${1:-${MUX_PROJECT:-}}"
        return
    fi

    echo "$script_name"
}

get_services() {
    parse_yaml "$CONFIG_FILE" '.services[].name' | tr '\n' ' '
}

get_service_prop() {
    local service="$1" prop="$2" default="${3:-}"
    local result
    result=$(parse_yaml_allow_null "$CONFIG_FILE" ".services[] | select(.name == \"$service\") | .$prop")

    if [[ -z "$result" || "$result" == "null" ]]; then
        echo "$default"
    else
        echo "$result"
    fi
}

get_start_command() {
    local service="$1"
    local runtime command

    runtime=$(get_service_prop "$service" "runtime" "")
    command=$(get_service_prop "$service" "command" "")

    if [[ -n "$runtime" && "$runtime" != "null" ]]; then
        if [[ ! " $ALLOWED_RUNTIMES " =~ " $runtime " ]]; then
            echo -e "${RED}Error: Unknown runtime '${runtime}'${NC}" >&2
            echo -e "${DIM}Allowed: ${ALLOWED_RUNTIMES}${NC}" >&2
            return 1
        fi
        echo "$runtime $command"
    else
        echo "$command"
    fi
}

get_service_dir() {
    local service="$1"
    local dir external
    dir=$(get_service_prop "$service" "dir" ".")
    external=$(get_service_prop "$service" "external" "false")

    # External service or absolute path: use as-is (expand ~)
    if [[ "$external" == "true" || "$dir" == /* || "$dir" == ~* ]]; then
        echo "${dir/#\~/$HOME}"
    else
        echo "${PROJECT_ROOT}/${dir}"
    fi
}

#######################################
# Session & Health Checks
#######################################

session_exists() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

is_window_ready() {
    local window="$1"
    tmux list-panes -t "${SESSION_NAME}:${window}" &>/dev/null
}

wait_for_window() {
    local window="$1"
    local max_attempts=20 attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        is_window_ready "$window" && return 0
        sleep 0.3
        ((attempt++))
    done
    return 1
}

is_service_running() {
    local service="$1"

    session_exists || return 1

    local pane_pid
    pane_pid=$(tmux list-panes -t "${SESSION_NAME}:${service}" -F '#{pane_pid}' 2>/dev/null | head -1)

    if [[ -n "$pane_pid" ]]; then
        local child_count
        child_count=$(pgrep -P "$pane_pid" 2>/dev/null | wc -l | tr -d ' ')
        [[ "$child_count" -gt 0 ]]
    else
        return 1
    fi
}

wait_for_port() {
    local port="$1" timeout="${2:-120}"
    local interval=2 elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        nc -z localhost "$port" 2>/dev/null && return 0
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    return 1
}

wait_for_service() {
    local service="$1"
    local port healthcheck_type healthcheck_path timeout

    port=$(get_service_prop "$service" "port" "")
    healthcheck_type=$(get_service_prop "$service" "healthcheck.type" "tcp")
    healthcheck_path=$(get_service_prop "$service" "healthcheck.path" "/health")
    timeout=$(get_service_prop "$service" "healthcheck.timeout" "120")

    [[ -z "$port" ]] && return 0

    local elapsed=0 interval=2

    echo -e "${DIM}Waiting for ${service} (port ${port})...${NC}"

    while [[ $elapsed -lt $timeout ]]; do
        if ! nc -z localhost "$port" 2>/dev/null; then
            sleep "$interval"
            elapsed=$((elapsed + interval))
            continue
        fi

        if [[ "$healthcheck_type" == "http" ]]; then
            if curl -sf "http://localhost:${port}${healthcheck_path}" >/dev/null 2>&1; then
                echo -e "${GREEN}${service} is ready${NC}"
                return 0
            fi
        else
            echo -e "${GREEN}${service} is ready${NC}"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo -e "${YELLOW}Warning: ${service} health check timed out${NC}"
    return 1
}

is_docker_running() {
    session_exists || return 1

    local pane_pid
    pane_pid=$(tmux list-panes -t "${SESSION_NAME}:docker" -F '#{pane_pid}' 2>/dev/null)
    [[ -n "$pane_pid" ]] && pgrep -P "$pane_pid" >/dev/null 2>&1
}

wait_for_docker() {
    local max_attempts="${DOCKER_WAIT_TIMEOUT:-60}" attempt=0

    echo -e "${DIM}Waiting for Docker containers...${NC}"
    while [[ $attempt -lt $max_attempts ]]; do
        local running_count
        running_count=$(cd "$PROJECT_ROOT" && docker compose ps --status running 2>/dev/null | tail -n +2 | wc -l | tr -d ' ' || echo "0")

        if [[ "$running_count" -ge 1 ]]; then
            sleep 2
            echo -e "${GREEN}Docker containers ready${NC}"
            return 0
        fi

        sleep 1
        ((attempt++))
    done

    echo -e "${YELLOW}Warning: Docker containers may not be fully ready${NC}"
    return 1
}

#######################################
# Logging
#######################################

get_log_dir() {
    local session_id
    session_id=$(tmux show-option -t "$SESSION_NAME" -qv @mux_log_session_id 2>/dev/null)
    [[ -n "$session_id" ]] && echo "${MUX_LOG_BASE_DIR}/${session_id}" || echo ""
}

init_log_dir() {
    local session_id
    session_id=$(date +%Y%m%d_%H%M%S)
    local log_dir="${MUX_LOG_BASE_DIR}/${session_id}"

    mkdir -p "$log_dir"
    tmux set-option -t "$SESSION_NAME" @mux_log_session_id "$session_id"

    # Cleanup old sessions
    if [[ -d "$MUX_LOG_BASE_DIR" ]]; then
        ls -dt "${MUX_LOG_BASE_DIR}"/*/ 2>/dev/null \
            | tail -n +$((MUX_LOG_KEEP_SESSIONS + 1)) \
            | while IFS= read -r dir; do rm -rf "$dir"; done
    fi

    echo -e "${DIM}Log directory: ${log_dir}${NC}"
}

setup_pipe_pane() {
    local log_dir
    log_dir=$(get_log_dir)

    if [[ -z "$log_dir" ]]; then
        echo -e "${YELLOW}Warning: Log directory not initialized${NC}"
        return 1
    fi

    echo -e "${DIM}Setting up log pipes...${NC}"

    local services
    services=$(get_services)

    for service in $services; do
        local pane_pipe
        pane_pipe=$(tmux display-message -t "${SESSION_NAME}:${service}" -p '#{pane_pipe}' 2>/dev/null || echo "0")

        if [[ "$pane_pipe" == "0" ]]; then
            tmux pipe-pane -t "${SESSION_NAME}:${service}" "cat >> '${log_dir}/${service}.log'" 2>/dev/null || true
        fi
    done
}

cleanup_pipe_pane() {
    session_exists || return 0

    local services
    services=$(get_services)

    for service in $services; do
        tmux pipe-pane -t "${SESSION_NAME}:${service}" 2>/dev/null || true
    done
}

#######################################
# Prechecks
#######################################

run_prechecks() {
    local precheck_count
    precheck_count=$(parse_yaml_allow_null "$CONFIG_FILE" '.prechecks | length')

    [[ -z "$precheck_count" || "$precheck_count" == "0" || "$precheck_count" == "null" ]] && return 0

    echo -e "${BOLD}Running prechecks...${NC}"

    local i=0
    while [[ $i -lt $precheck_count ]]; do
        local name command dir on_fail hint
        name=$(parse_yaml "$CONFIG_FILE" ".prechecks[$i].name")
        command=$(parse_yaml "$CONFIG_FILE" ".prechecks[$i].command")
        dir=$(parse_yaml_allow_null "$CONFIG_FILE" ".prechecks[$i].dir")
        on_fail=$(parse_yaml_allow_null "$CONFIG_FILE" ".prechecks[$i].on_fail // \"warn\"")
        hint=$(parse_yaml_allow_null "$CONFIG_FILE" ".prechecks[$i].hint // \"\"")

        local check_dir="${PROJECT_ROOT}"
        [[ -n "$dir" && "$dir" != "null" ]] && check_dir="${PROJECT_ROOT}/${dir}"

        echo -e "${DIM}Checking: ${name}...${NC}"

        if ! (cd "$check_dir" && bash -c "$command") &>/dev/null; then
            if [[ "$on_fail" == "abort" ]]; then
                echo -e "${RED}Precheck failed: ${name}${NC}"
                [[ -n "$hint" && "$hint" != "null" ]] && echo -e "${YELLOW}Hint: ${hint}${NC}"
                return 1
            else
                echo -e "${YELLOW}Warning: ${name} check failed${NC}"
                [[ -n "$hint" && "$hint" != "null" ]] && echo -e "${DIM}Hint: ${hint}${NC}"
            fi
        else
            echo -e "${GREEN}${name}: OK${NC}"
        fi

        ((i++))
    done
}

#######################################
# Service Operations
#######################################

start_service() {
    local service="$1"

    validate_service_name "$service" || return 1

    if ! session_exists; then
        echo -e "${RED}Error: Session not running. Run '${PROJECT_NAME} hello' first.${NC}"
        return 1
    fi

    if ! is_window_ready "$service"; then
        echo -e "${DIM}Waiting for window to be ready...${NC}"
        wait_for_window "$service" || echo -e "${YELLOW}Warning: Window for ${service} not ready${NC}"
    fi

    if is_service_running "$service"; then
        echo -e "${YELLOW}${service} is already running${NC}"
        return 0
    fi

    local cmd service_dir
    cmd=$(get_start_command "$service")
    service_dir=$(get_service_dir "$service")

    echo -e "${CYAN}Starting ${service}...${NC}"
    tmux send-keys -t "${SESSION_NAME}:${service}" "cd '${service_dir}' && ${cmd}" Enter
}

stop_service() {
    local service="$1"

    validate_service_name "$service" || return 1

    if ! session_exists; then
        echo -e "${YELLOW}Session not running${NC}"
        return 0
    fi

    if ! is_service_running "$service"; then
        echo -e "${DIM}${service} is not running${NC}"
        return 0
    fi

    echo -e "${CYAN}Stopping ${service}...${NC}"
    tmux send-keys -t "${SESSION_NAME}:${service}" C-c

    local wait_count=0
    while [[ $wait_count -lt 10 ]] && is_service_running "$service"; do
        sleep 0.5
        ((wait_count++))
    done

    is_service_running "$service" && echo -e "${YELLOW}Warning: ${service} may not have stopped completely${NC}"
}

restart_service() {
    local service="$1"

    validate_service_name "$service" || return 1

    if ! session_exists; then
        echo -e "${RED}Error: Session not running. Run '${PROJECT_NAME} hello' first.${NC}"
        return 1
    fi

    echo -e "${CYAN}Restarting ${service}...${NC}"

    if is_service_running "$service"; then
        tmux send-keys -t "${SESSION_NAME}:${service}" C-c

        local wait_count=0
        while [[ $wait_count -lt 10 ]] && is_service_running "$service"; do
            sleep 0.5
            ((wait_count++))
        done
    fi

    local cmd service_dir
    cmd=$(get_start_command "$service")
    service_dir=$(get_service_dir "$service")

    tmux send-keys -t "${SESSION_NAME}:${service}" "cd '${service_dir}' && ${cmd}" Enter
    echo -e "${GREEN}${service} restarted${NC}"
}

#######################################
# Docker Operations
#######################################

start_docker() {
    [[ "$DOCKER_ENABLED" != "true" ]] && return 0

    if ! session_exists; then
        echo -e "${RED}Error: Session not running.${NC}"
        return 1
    fi

    if is_docker_running; then
        echo -e "${YELLOW}Docker is already running${NC}"
        return 0
    fi

    echo -e "${BLUE}Starting Docker services...${NC}"
    tmux send-keys -t "${SESSION_NAME}:docker" "cd '${PROJECT_ROOT}' && docker compose up" Enter
}

stop_docker() {
    [[ "$DOCKER_ENABLED" != "true" ]] && return 0

    echo -e "${BLUE}Stopping Docker services...${NC}"

    session_exists && { tmux send-keys -t "${SESSION_NAME}:docker" C-c 2>/dev/null || true; sleep 2; }

    [[ -d "$PROJECT_ROOT" ]] && (cd "$PROJECT_ROOT" && docker compose down 2>/dev/null) || true
}

#######################################
# Status & Display
#######################################

show_status() {
    if ! session_exists; then
        echo -e "${RED}Session '${SESSION_NAME}' is not running${NC}"
        echo -e "Run '${CYAN}${PROJECT_NAME} hello${NC}' to start"
        return 1
    fi

    echo -e "${BOLD}${PROJECT_NAME} Service Status${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    if [[ "$DOCKER_ENABLED" == "true" ]]; then
        echo -e "${BOLD}${BLUE}Docker Services${NC}"
        if is_docker_running; then
            echo -e "  docker-compose: ${GREEN}●${NC} running"
        else
            echo -e "  docker-compose: ${RED}○${NC} stopped"
        fi
        echo
    fi

    echo -e "${BOLD}${YELLOW}Services${NC}"
    local services
    services=$(get_services)

    for service in $services; do
        local status_icon group
        group=$(get_service_prop "$service" "group" "")

        if is_service_running "$service"; then
            status_icon="${GREEN}●${NC}"
        else
            status_icon="${RED}○${NC}"
        fi
        printf "  %-25s %b  %s\n" "$service" "$status_icon" "${DIM}[${group}]${NC}"
    done

    echo
    echo -e "${BOLD}Legend:${NC} ${GREEN}●${NC} running  ${RED}○${NC} stopped"
    echo -e "${DIM}Navigate: Ctrl+b w (list) | Ctrl+b ' (enter number)${NC}"
}

list_services() {
    echo -e "${BOLD}Available Services${NC}"
    echo

    if [[ "$DOCKER_ENABLED" == "true" ]]; then
        echo -e "${BOLD}${BLUE}Docker:${NC}"
        echo "  docker"
        echo
    fi

    echo -e "${BOLD}${YELLOW}Services:${NC}"
    local services
    services=$(get_services)

    for service in $services; do
        local port group
        port=$(get_service_prop "$service" "port" "")
        group=$(get_service_prop "$service" "group" "")
        printf "  %-20s %s  %s\n" "$service" "${DIM}:${port:-N/A}${NC}" "${DIM}[${group}]${NC}"
    done
}

focus_logs() {
    local service="$1"

    validate_service_name "$service" || return 1

    if ! session_exists; then
        echo -e "${RED}Session not running${NC}"
        return 1
    fi

    tmux select-window -t "${SESSION_NAME}:${service}"

    [[ -z "${TMUX:-}" ]] && tmux attach-session -t "$SESSION_NAME"
}

follow_service() {
    local service="$1"

    if [[ -z "$service" ]]; then
        echo -e "${RED}Error: Service name required${NC}"
        echo "Usage: ${PROJECT_NAME} follow <service>"
        return 1
    fi

    validate_service_name "$service" || return 1

    if ! session_exists; then
        echo -e "${RED}Session not running${NC}"
        return 1
    fi

    local log_dir
    log_dir=$(get_log_dir)

    if [[ -z "$log_dir" ]]; then
        echo -e "${RED}Error: Log directory not found${NC}"
        return 1
    fi

    local log_file="${log_dir}/${service}.log"

    if [[ ! -f "$log_file" ]]; then
        echo -e "${YELLOW}Warning: Log file not found yet, creating...${NC}"
        touch "$log_file"
    fi

    tmux popup -w "$MUX_POPUP_WIDTH" -h "$MUX_POPUP_HEIGHT" -E \
        "nvim -c 'terminal tail -F ${log_file}'"
}

#######################################
# Cleanup
#######################################

cleanup() {
    local exit_code=$?
    [[ -n "${SESSION_NAME:-}" ]] && cleanup_pipe_pane 2>/dev/null || true
    release_lock 2>/dev/null || true
    exit $exit_code
}

trap cleanup EXIT
