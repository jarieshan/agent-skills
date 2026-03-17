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

# ─── Install targets ─────────────────────────────────────────────────
# Known targets: "cli_name|display_name|detect_dir|skills_path"
#   detect_dir  — if this directory exists, the tool is considered installed
#   skills_path — where skills should be symlinked into
ALL_TARGETS=(
  "claude|Claude Code|$HOME/.claude|$HOME/.claude/skills"
  "cursor|Cursor|$HOME/.cursor|$HOME/.cursor/skills-cursor"
  "antigravity|Antigravity|$HOME/.gemini/antigravity|$HOME/.gemini/antigravity/skills"
  "openclaw|OpenClaw|$HOME/.openclaw|$HOME/.openclaw/skills"
  "gemini|Gemini CLI|$HOME/.gemini|$HOME/.gemini/skills"
  "universal|Universal|$HOME/.agents|$HOME/.agents/skills"
)

# Populated at runtime with only detected targets + Custom
TARGETS=()

detect_targets() {
  TARGETS=()
  for entry in "${ALL_TARGETS[@]}"; do
    local cli_name display detect skills
    IFS='|' read -r cli_name display detect skills <<< "$entry"
    if [[ -d "$detect" ]]; then
      TARGETS+=("$entry")
    fi
  done
  # Always append Custom option
  TARGETS+=("custom|Custom|NONE|CUSTOM")
}

# Resolve --target name to install path
resolve_target_name() {
  local name="$1"
  for entry in "${ALL_TARGETS[@]}"; do
    local cli_name display detect skills
    IFS='|' read -r cli_name display detect skills <<< "$entry"
    if [[ "$cli_name" == "$name" ]]; then
      INSTALL_DIR="$skills"
      return 0
    fi
  done
  return 1
}

# ─── Interactive single-select for install target ────────────────────
interactive_select_target() {
  local cursor=0
  local num_targets=${#TARGETS[@]}

  tput civis 2>/dev/null || true

  printf "  ${BOLD}Install location${RESET} ${DIM}(↑↓ move, enter confirm)${RESET}\n\n"

  draw_target_list "$cursor"

  while true; do
    local key
    read -rsn1 key

    case "$key" in
      $'\x1b')
        read -rsn2 rest
        case "$rest" in
          '[A') (( cursor > 0 )) && (( cursor-- )) ;;
          '[B') (( cursor < num_targets - 1 )) && (( cursor++ )) ;;
        esac
        ;;
      '')
        break
        ;;
    esac

    for (( i=0; i<num_targets; i++ )); do
      tput cuu1 2>/dev/null
    done

    draw_target_list "$cursor"
  done

  tput cnorm 2>/dev/null || true

  # Extract the selected path
  local selected_entry="${TARGETS[$cursor]}"
  local cli_name display detect skills
  IFS='|' read -r cli_name display detect skills <<< "$selected_entry"

  if [[ "$skills" == "CUSTOM" ]]; then
    printf "\n  ${CYAN}${POINTER}${RESET} Path: "
    local input
    read -r input
    INSTALL_DIR="${input/#\~/$HOME}"
  else
    INSTALL_DIR="$skills"
  fi

  printf "\n"
}

draw_target_list() {
  local cursor=$1
  for (( i=0; i<${#TARGETS[@]}; i++ )); do
    local entry="${TARGETS[$i]}"
    local cli_name display detect skills
    IFS='|' read -r cli_name display detect skills <<< "$entry"

    # Show short path for display
    local short_path="${skills/#$HOME/\~}"

    local radio="${UNCHECKED}"
    local prefix="   "
    local style="" end=""
    if [[ $i -eq $cursor ]]; then
      radio="${CHECKED}"
      prefix="  ${CYAN}${POINTER}${RESET}"
      style="${BOLD}"
      end="${RESET}"
    fi

    if [[ $i -eq $cursor ]]; then
      printf "%b ${GREEN}%s${RESET} %b%-14s%b ${DIM}%s${RESET}\n" \
        "$prefix" "$radio" "$style" "$display" "$end" "$short_path"
    else
      printf "%b ${DIM}%s${RESET} %b%-14s%b ${DIM}%s${RESET}\n" \
        "$prefix" "$radio" "$style" "$display" "$end" "$short_path"
    fi
  done
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
  --target <name>    Install target (default: claude)
                     Supported: claude, cursor, antigravity, openclaw, gemini, universal
  --path <dir>       Install to a custom path (overrides --target)
  --skill <name>     Skill to install (repeatable, default: all)
  --list             List available skills and exit
  -h, --help         Show this help

Examples:
  $(basename "$0")                           # Interactive mode
  $(basename "$0") --target cursor           # Install to Cursor skills dir
  $(basename "$0") --skill todo-manager      # Non-interactive, single skill
  $(basename "$0") --path ~/my-skills        # Custom path
EOF
  exit 0
}

parse_args() {
  local explicit_skills=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        if ! resolve_target_name "$2"; then
          local supported
          supported=$(printf '%s\n' "${ALL_TARGETS[@]}" | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
          print_error "Unknown target: $2 (supported: $supported)"
          exit 1
        fi
        shift 2
        ;;
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
  detect_targets
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
      interactive_select_target
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
