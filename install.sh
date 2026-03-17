#!/usr/bin/env bash
set -euo pipefail

# ─── Colors & Symbols ───────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'
POINTER='❯'
CHECKED='◉'
UNCHECKED='○'

# ─── Globals ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_INSTALL_DIR="$HOME/.claude/skills"
INSTALL_DIR=""
SKILLS=()
SELECTED=()
NON_INTERACTIVE=false

# ─── Helpers ─────────────────────────────────────────────────────────
print_header() {
  printf "\n${BOLD}${CYAN}  Agent Skills Installer${RESET}\n"
  printf "${DIM}  ─────────────────────${RESET}\n\n"
}

print_success() { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
print_warn()    { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
print_error()   { printf "  ${RED}✗${RESET} %s\n" "$1"; }
print_info()    { printf "  ${DIM}%s${RESET}\n" "$1"; }

# Discover skills: directories containing SKILL.md
discover_skills() {
  SKILLS=()
  while IFS= read -r skill_file; do
    local dir
    dir="$(dirname "$skill_file")"
    SKILLS+=("$(basename "$dir")")
  done < <(find "$SCRIPT_DIR" -maxdepth 2 -name "SKILL.md" -not -path "*/.git/*" | sort)

  if [[ ${#SKILLS[@]} -eq 0 ]]; then
    print_error "No skills found in $SCRIPT_DIR"
    exit 1
  fi
}

# Get skill description from SKILL.md frontmatter
get_description() {
  local skill="$1"
  local skill_file="$SCRIPT_DIR/$skill/SKILL.md"
  sed -n 's/^description: *"\{0,1\}\(.*\)"\{0,1\}$/\1/p' "$skill_file" | head -1 | cut -c1-60
}

# ─── Interactive multi-select ───────────────────────────────────────
# Arrow keys to move, Space to toggle, Enter to confirm
interactive_select_skills() {
  local cursor=0
  SELECTED=()
  for (( i=0; i<${#SKILLS[@]}; i++ )); do
    SELECTED+=(1)  # default: all selected
  done

  # Hide cursor
  tput civis 2>/dev/null || true

  # Restore cursor on exit
  trap 'tput cnorm 2>/dev/null || true' EXIT

  printf "  ${BOLD}Select skills to install${RESET} ${DIM}(↑↓ move, space toggle, enter confirm)${RESET}\n\n"

  # Draw initial list
  draw_skill_list "$cursor"

  while true; do
    # Read single keypress
    local key
    read -rsn1 key

    case "$key" in
      # Arrow key escape sequence
      $'\x1b')
        read -rsn2 rest
        case "$rest" in
          '[A') # Up
            (( cursor > 0 )) && (( cursor-- ))
            ;;
          '[B') # Down
            (( cursor < ${#SKILLS[@]} - 1 )) && (( cursor++ ))
            ;;
        esac
        ;;
      # Space: toggle selection
      ' ')
        if [[ ${SELECTED[$cursor]} -eq 1 ]]; then
          SELECTED[$cursor]=0
        else
          SELECTED[$cursor]=1
        fi
        ;;
      # Enter: confirm
      '')
        break
        ;;
      # 'a' to toggle all
      'a')
        local all_selected=true
        for s in "${SELECTED[@]}"; do
          [[ $s -eq 0 ]] && all_selected=false && break
        done
        for (( i=0; i<${#SKILLS[@]}; i++ )); do
          if $all_selected; then SELECTED[$i]=0; else SELECTED[$i]=1; fi
        done
        ;;
    esac

    # Move cursor up to redraw
    for (( i=0; i<${#SKILLS[@]}; i++ )); do
      tput cuu1 2>/dev/null
    done

    draw_skill_list "$cursor"
  done

  # Show cursor
  tput cnorm 2>/dev/null || true
  printf "\n"
}

draw_skill_list() {
  local cursor=$1
  for (( i=0; i<${#SKILLS[@]}; i++ )); do
    local marker="${UNCHECKED}"
    [[ ${SELECTED[$i]} -eq 1 ]] && marker="${CHECKED}"

    local prefix="   "
    local style=""
    local end=""
    if [[ $i -eq $cursor ]]; then
      prefix="  ${CYAN}${POINTER}${RESET}"
      style="${BOLD}"
      end="${RESET}"
    fi

    local desc
    desc="$(get_description "${SKILLS[$i]}")"

    if [[ ${SELECTED[$i]} -eq 1 ]]; then
      printf "%b ${GREEN}%s${RESET} %b%s%b ${DIM}— %s${RESET}\n" \
        "$prefix" "$marker" "$style" "${SKILLS[$i]}" "$end" "$desc"
    else
      printf "%b ${DIM}%s${RESET} %b%s%b ${DIM}— %s${RESET}\n" \
        "$prefix" "$marker" "$style" "${SKILLS[$i]}" "$end" "$desc"
    fi
  done
}

# ─── Interactive path input ─────────────────────────────────────────
interactive_input_path() {
  printf "  ${BOLD}Install location${RESET} ${DIM}(enter for default)${RESET}\n"
  printf "  ${CYAN}${POINTER}${RESET} ${DIM}[${DEFAULT_INSTALL_DIR}]${RESET} "
  local input
  read -r input
  INSTALL_DIR="${input:-$DEFAULT_INSTALL_DIR}"
  # Expand ~ manually
  INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
  printf "\n"
}

# ─── Install logic ──────────────────────────────────────────────────
install_skills() {
  local count=0

  for (( i=0; i<${#SKILLS[@]}; i++ )); do
    [[ ${SELECTED[$i]} -eq 0 ]] && continue

    local skill="${SKILLS[$i]}"
    local src="$SCRIPT_DIR/$skill"
    local dest="$INSTALL_DIR/$skill"

    if [[ -e "$dest" ]]; then
      if [[ -L "$dest" ]]; then
        local current_target
        current_target="$(readlink "$dest")"
        if [[ "$current_target" == "$src" ]]; then
          print_info "$skill — already linked, skipped"
          (( count++ ))
          continue
        fi
      fi
      print_warn "$skill — $dest already exists, skipping (remove it first to reinstall)"
      continue
    fi

    ln -s "$src" "$dest"
    print_success "$skill — installed"
    (( count++ ))
  done

  printf "\n  ${BOLD}${GREEN}Done!${RESET} Installed ${BOLD}${count}${RESET} skill(s) to ${DIM}${INSTALL_DIR}${RESET}\n"
  printf "  ${DIM}Skills are symlinked — git pull to update.${RESET}\n\n"
}

# ─── CLI argument parsing (non-interactive mode) ────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Interactive installer for agent skills.

Options:
  --path <dir>       Install location (default: $DEFAULT_INSTALL_DIR)
  --skill <name>     Skill to install (repeatable, default: all)
  --list             List available skills and exit
  -h, --help         Show this help

Examples:
  $(basename "$0")                           # Interactive mode
  $(basename "$0") --path ~/.claude/skills   # Interactive, custom path
  $(basename "$0") --skill todo-manager      # Non-interactive, single skill
EOF
  exit 0
}

parse_args() {
  local explicit_skills=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        INSTALL_DIR="${2/#\~/$HOME}"
        shift 2
        ;;
      --skill)
        explicit_skills+=("$2")
        NON_INTERACTIVE=true
        shift 2
        ;;
      --list)
        discover_skills
        printf "\nAvailable skills:\n"
        for skill in "${SKILLS[@]}"; do
          printf "  %-20s %s\n" "$skill" "$(get_description "$skill")"
        done
        printf "\n"
        exit 0
        ;;
      -h|--help) usage ;;
      *)
        print_error "Unknown option: $1"
        usage
        ;;
    esac
  done

  # If skills specified via --skill, validate and set selection
  if [[ ${#explicit_skills[@]} -gt 0 ]]; then
    SELECTED=()
    for (( i=0; i<${#SKILLS[@]}; i++ )); do
      SELECTED+=(0)
    done

    for es in "${explicit_skills[@]}"; do
      local found=false
      for (( i=0; i<${#SKILLS[@]}; i++ )); do
        if [[ "${SKILLS[$i]}" == "$es" ]]; then
          SELECTED[$i]=1
          found=true
          break
        fi
      done
      if ! $found; then
        print_error "Unknown skill: $es"
        exit 1
      fi
    done
  fi
}

# ─── Main ────────────────────────────────────────────────────────────
main() {
  discover_skills
  parse_args "$@"

  print_header

  # Skill selection
  if [[ "$NON_INTERACTIVE" == false ]]; then
    if [[ ! -t 0 ]]; then
      print_error "No TTY detected. Use --skill and --path for non-interactive mode."
      printf "  Run with ${BOLD}--help${RESET} for usage.\n\n"
      exit 1
    fi
    interactive_select_skills
  fi

  # Install path
  if [[ -z "$INSTALL_DIR" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
      INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    else
      interactive_input_path
    fi
  fi

  # Ensure target directory exists
  mkdir -p "$INSTALL_DIR"

  # Confirm
  local selected_names=()
  for (( i=0; i<${#SKILLS[@]}; i++ )); do
    [[ ${SELECTED[$i]} -eq 1 ]] && selected_names+=("${SKILLS[$i]}")
  done

  if [[ ${#selected_names[@]} -eq 0 ]]; then
    print_warn "No skills selected."
    exit 0
  fi

  printf "  ${DIM}Installing:${RESET} ${BOLD}%s${RESET}\n" "${selected_names[*]}"
  printf "  ${DIM}Into:${RESET}       ${BOLD}%s${RESET}\n\n" "$INSTALL_DIR"

  install_skills
}

main "$@"
