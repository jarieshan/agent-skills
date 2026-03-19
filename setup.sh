#!/usr/bin/env bash
set -euo pipefail

# ─── Agent Skills Setup ─────────────────────────────────────────────
# One-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/jarieshan/agent-skills/main/setup.sh)
#
# Subcommands:
#   setup.sh [install]         Interactive install (default)
#   setup.sh update            Update installed skills
#   setup.sh status            Show installed skills
#   setup.sh list              List available skills
#   setup.sh clean-backup      Manage backups

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
REPO_URL="https://github.com/jarieshan/agent-skills.git"
REPO_BRANCH="main"
CACHE_DIR="$HOME/.config/agent-skills/repo"

SCRIPT_DIR=""  # resolved after bootstrap
SKILLS_DIR=""  # $SCRIPT_DIR/skills
DEFAULT_INSTALL_DIR="$HOME/.claude/skills"
INSTALL_DIR=""
INSTALL_METHOD="copy"
SKILLS=()
SELECTED=()
NON_INTERACTIVE=false

REGISTRY_DIR="$HOME/.config/agent-skills"
REGISTRY_FILE="$REGISTRY_DIR/registry.list"
BACKUP_DIR="$REGISTRY_DIR/backup"

# ─── Helpers ─────────────────────────────────────────────────────────
print_header() {
  printf "\n${BOLD}${CYAN}  Agent Skills${RESET}\n"
  printf "${DIM}  ────────────${RESET}\n\n"
}

print_success() { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
print_warn()    { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
print_error()   { printf "  ${RED}✗${RESET} %s\n" "$1"; }
print_info()    { printf "  ${DIM}%s${RESET}\n" "$1"; }

# ─── Bootstrap ───────────────────────────────────────────────────────
# Ensure we have a local copy of the skill repo
bootstrap() {
  local real_script
  real_script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # If running from within a git repo that has skills, use it directly
  local script_parent
  script_parent="$(cd "$(dirname "$0")" && pwd)"
  if [[ -d "$script_parent/.git" ]]; then
    SCRIPT_DIR="$script_parent"
    SKILLS_DIR="$SCRIPT_DIR/skills"
    return
  fi

  # Otherwise, clone/update from remote
  if ! command -v git &>/dev/null; then
    print_error "git is required but not found."
    exit 1
  fi

  if [[ -d "$CACHE_DIR/.git" ]]; then
    print_info "Updating local cache (${CACHE_DIR/#$HOME/~})..."
    if git -C "$CACHE_DIR" fetch --quiet origin "$REPO_BRANCH" 2>/dev/null \
       && git -C "$CACHE_DIR" reset --quiet --hard "origin/$REPO_BRANCH" 2>/dev/null; then
      print_success "Repo updated to latest."
    else
      # Cache is stale (e.g. branch renamed), re-clone
      print_warn "Cache outdated, re-cloning..."
      rm -rf "$CACHE_DIR"
      git clone --quiet --branch "$REPO_BRANCH" "$REPO_URL" "$CACHE_DIR"
      print_success "Repo re-cloned."
    fi
  else
    print_info "Cloning repo to ${CACHE_DIR/#$HOME/~}..."
    mkdir -p "$(dirname "$CACHE_DIR")"
    git clone --quiet --branch "$REPO_BRANCH" "$REPO_URL" "$CACHE_DIR"
    print_success "Repo cloned."
  fi
  printf "\n"

  SCRIPT_DIR="$CACHE_DIR"
  SKILLS_DIR="$SCRIPT_DIR/skills"
}

# ─── Skill discovery ────────────────────────────────────────────────
discover_skills() {
  SKILLS=()
  while IFS= read -r skill_file; do
    local dir
    dir="$(dirname "$skill_file")"
    SKILLS+=("$(basename "$dir")")
  done < <(find "$SKILLS_DIR" -maxdepth 2 -name "SKILL.md" -not -path "*/.git/*" | sort)

  if [[ ${#SKILLS[@]} -eq 0 ]]; then
    print_error "No skills found in $SKILLS_DIR"
    exit 1
  fi
}

get_description() {
  local skill="$1"
  local skill_file="$SKILLS_DIR/$skill/SKILL.md"
  sed -n 's/^description: *"\{0,1\}\(.*\)"\{0,1\}$/\1/p' "$skill_file" | head -1 | cut -c1-60
}

# ─── Interactive TUI components ──────────────────────────────────────

# Generic single-select: draw_func cursor → renders list
# Returns selected index in TUI_RESULT
tui_single_select() {
  local prompt="$1" hint="$2" count="$3" draw_func="$4"
  local cursor="${5:-0}"

  tput civis 2>/dev/null || true
  printf "  ${BOLD}%s${RESET} ${DIM}(%s)${RESET}\n\n" "$prompt" "$hint"
  "$draw_func" "$cursor"

  while true; do
    local key
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 rest
        case "$rest" in
          '[A') [[ $cursor -gt 0 ]] && cursor=$((cursor - 1)) || true ;;
          '[B') [[ $cursor -lt $((count - 1)) ]] && cursor=$((cursor + 1)) || true ;;
        esac
        ;;
      '') break ;;
    esac
    for (( i=0; i<count; i++ )); do tput cuu1 2>/dev/null; done
    "$draw_func" "$cursor"
  done

  tput cnorm 2>/dev/null || true
  printf "\n"
  TUI_RESULT="$cursor"
}

# Multi-select with space toggle, 'a' toggle all
interactive_select_skills() {
  local cursor=0
  SELECTED=()
  for (( i=0; i<${#SKILLS[@]}; i++ )); do
    SELECTED+=(1)
  done

  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true' EXIT

  printf "  ${BOLD}Select skills to install${RESET} ${DIM}(↑↓ move, space toggle, enter confirm)${RESET}\n\n"
  draw_skill_list "$cursor"

  while true; do
    local key
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 rest
        case "$rest" in
          '[A') [[ $cursor -gt 0 ]] && cursor=$((cursor - 1)) || true ;;
          '[B') [[ $cursor -lt $((${#SKILLS[@]} - 1)) ]] && cursor=$((cursor + 1)) || true ;;
        esac
        ;;
      ' ')
        if [[ ${SELECTED[$cursor]} -eq 1 ]]; then
          SELECTED[$cursor]=0
        else
          SELECTED[$cursor]=1
        fi
        ;;
      '')
        break
        ;;
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
    for (( i=0; i<${#SKILLS[@]}; i++ )); do tput cuu1 2>/dev/null; done
    draw_skill_list "$cursor"
  done

  tput cnorm 2>/dev/null || true
  printf "\n"
}

draw_skill_list() {
  local cursor=$1
  for (( i=0; i<${#SKILLS[@]}; i++ )); do
    local marker="${UNCHECKED}"
    [[ ${SELECTED[$i]} -eq 1 ]] && marker="${CHECKED}"

    local prefix="   " style="" end=""
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

# ─── Install targets ────────────────────────────────────────────────
ALL_TARGETS=(
  "claude|Claude Code|$HOME/.claude|$HOME/.claude/skills"
  "cursor|Cursor|$HOME/.cursor|$HOME/.cursor/skills-cursor"
  "antigravity|Antigravity|$HOME/.gemini/antigravity|$HOME/.gemini/antigravity/skills"
  "openclaw|OpenClaw|$HOME/.openclaw|$HOME/.openclaw/skills"
  "gemini|Gemini CLI|$HOME/.gemini|$HOME/.gemini/skills"
  "universal|Universal|$HOME/.agents|$HOME/.agents/skills"
)

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
  TARGETS+=("custom|Custom|NONE|CUSTOM")
}

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

interactive_select_target() {
  local cursor=0
  local num_targets=${#TARGETS[@]}

  tput civis 2>/dev/null || true
  printf "  ${BOLD}Install location${RESET} ${DIM}(↑↓ move, enter confirm)${RESET}\n\n"
  draw_target_list "$cursor"

  while true; do
    local key
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 rest
        case "$rest" in
          '[A') [[ $cursor -gt 0 ]] && cursor=$((cursor - 1)) || true ;;
          '[B') [[ $cursor -lt $((num_targets - 1)) ]] && cursor=$((cursor + 1)) || true ;;
        esac
        ;;
      '') break ;;
    esac
    for (( i=0; i<num_targets; i++ )); do tput cuu1 2>/dev/null; done
    draw_target_list "$cursor"
  done

  tput cnorm 2>/dev/null || true

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
    local short_path="${skills/#$HOME/~}"

    local radio="${UNCHECKED}" prefix="   " style="" end=""
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

# ─── Mode selector (Update / Install) ───────────────────────────────
draw_mode_list() {
  local cursor=$1
  local -a names=("Update" "Install")
  local -a descs=(
    "sync installed skills from source repo"
    "install new skills to a target location"
  )
  for (( j=0; j<${#names[@]}; j++ )); do
    local radio="${UNCHECKED}" prefix="   " style="" end=""
    if [[ $j -eq $cursor ]]; then
      radio="${CHECKED}"
      prefix="  ${CYAN}${POINTER}${RESET}"
      style="${BOLD}"
      end="${RESET}"
    fi
    if [[ $j -eq $cursor ]]; then
      printf "%b ${GREEN}%s${RESET} %b%-12s%b ${DIM}— %s${RESET}\n" \
        "$prefix" "$radio" "$style" "${names[$j]}" "$end" "${descs[$j]}"
    else
      printf "%b ${DIM}%s${RESET} %b%-12s%b ${DIM}— %s${RESET}\n" \
        "$prefix" "$radio" "$style" "${names[$j]}" "$end" "${descs[$j]}"
    fi
  done
}

interactive_select_mode() {
  local cursor=0 num_modes=2
  tput civis 2>/dev/null || true
  printf "  ${BOLD}What would you like to do?${RESET} ${DIM}(↑↓ move, enter confirm)${RESET}\n\n"
  draw_mode_list "$cursor"

  while true; do
    local key
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 rest
        case "$rest" in
          '[A') [[ $cursor -gt 0 ]] && cursor=$((cursor - 1)) || true ;;
          '[B') [[ $cursor -lt $((num_modes - 1)) ]] && cursor=$((cursor + 1)) || true ;;
        esac
        ;;
      '') break ;;
    esac
    for (( j=0; j<num_modes; j++ )); do tput cuu1 2>/dev/null; done
    draw_mode_list "$cursor"
  done

  tput cnorm 2>/dev/null || true
  printf "\n"
  SELECTED_MODE="$cursor"
}

# ─── Conflict resolution ────────────────────────────────────────────
handle_conflict() {
  local skill="$1" src="$2" dest="$3"

  printf "\n  ${YELLOW}!${RESET} ${BOLD}%s${RESET} already exists at ${DIM}%s${RESET}\n\n" "$skill" "$dest"

  if [[ "$NON_INTERACTIVE" == true ]]; then
    print_warn "$skill — skipped (use interactive mode to reinstall/update)"
    CONFLICT_ACTION=0
    return
  fi

  local cursor=0
  local -a opt_names=("Skip" "Update" "Reinstall")
  local -a opt_descs=(
    "keep existing, do nothing"
    "replace changed + add new, keep extra files"
    "remove existing and install fresh"
  )

  tput civis 2>/dev/null || true
  printf "  ${BOLD}Action?${RESET} ${DIM}(↑↓ move, enter confirm)${RESET}\n\n"
  draw_conflict_options "$cursor"

  while true; do
    local key
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 rest
        case "$rest" in
          '[A') [[ $cursor -gt 0 ]] && cursor=$((cursor - 1)) || true ;;
          '[B') [[ $cursor -lt 2 ]] && cursor=$((cursor + 1)) || true ;;
        esac
        ;;
      '') break ;;
    esac
    for (( j=0; j<3; j++ )); do tput cuu1 2>/dev/null; done
    draw_conflict_options "$cursor"
  done

  tput cnorm 2>/dev/null || true
  printf "\n"

  if [[ $cursor -eq 2 ]]; then
    show_file_diff "$src" "$dest"
    printf "  ${BOLD}${RED}This will backup and remove the existing directory, then reinstall.${RESET}\n"
    printf "  ${BOLD}Confirm? [y/N]${RESET} "
    local confirm
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      printf "\n"
      CONFLICT_ACTION=0
      return
    fi
    printf "\n"
    backup_skill "$skill" "$dest"
  fi

  CONFLICT_ACTION="$cursor"
}

draw_conflict_options() {
  local cursor=$1
  local -a opt_names=("Skip" "Update" "Reinstall")
  local -a opt_descs=(
    "keep existing, do nothing"
    "replace changed + add new, keep extra files"
    "remove existing and install fresh"
  )
  for (( j=0; j<${#opt_names[@]}; j++ )); do
    local radio="${UNCHECKED}" prefix="   " style="" end=""
    if [[ $j -eq $cursor ]]; then
      radio="${CHECKED}"
      prefix="  ${CYAN}${POINTER}${RESET}"
      style="${BOLD}"
      end="${RESET}"
    fi
    if [[ $j -eq $cursor ]]; then
      printf "%b ${GREEN}%s${RESET} %b%-12s%b ${DIM}— %s${RESET}\n" \
        "$prefix" "$radio" "$style" "${opt_names[$j]}" "$end" "${opt_descs[$j]}"
    else
      printf "%b ${DIM}%s${RESET} %b%-12s%b ${DIM}— %s${RESET}\n" \
        "$prefix" "$radio" "$style" "${opt_names[$j]}" "$end" "${opt_descs[$j]}"
    fi
  done
}

show_file_diff() {
  local src="$1" dest="$2"
  local actual_dest="$dest"
  [[ -L "$dest" ]] && actual_dest="$(readlink "$dest")"

  local deleted=() replaced=() added=()

  while IFS= read -r f; do
    local rel="${f#$actual_dest/}"
    [[ ! -e "$src/$rel" ]] && deleted+=("$rel")
  done < <(find "$actual_dest" -type f 2>/dev/null | sort)

  while IFS= read -r f; do
    local rel="${f#$src/}"
    if [[ -e "$actual_dest/$rel" ]]; then
      diff -q "$f" "$actual_dest/$rel" &>/dev/null || replaced+=("$rel")
    else
      added+=("$rel")
    fi
  done < <(find "$src" -type f 2>/dev/null | sort)

  local has_changes=false
  if [[ ${#deleted[@]} -gt 0 ]]; then
    has_changes=true
    printf "  ${RED}Delete:${RESET}\n"
    for f in "${deleted[@]}"; do printf "    ${RED}-%s${RESET}\n" "$f"; done
  fi
  if [[ ${#replaced[@]} -gt 0 ]]; then
    has_changes=true
    printf "  ${YELLOW}Replace:${RESET}\n"
    for f in "${replaced[@]}"; do printf "    ${YELLOW}~%s${RESET}\n" "$f"; done
  fi
  if [[ ${#added[@]} -gt 0 ]]; then
    has_changes=true
    printf "  ${GREEN}Add:${RESET}\n"
    for f in "${added[@]}"; do printf "    ${GREEN}+%s${RESET}\n" "$f"; done
  fi
  if ! $has_changes; then
    printf "  ${DIM}No file differences detected.${RESET}\n"
  fi
  printf "\n"
}

# ─── Registry ───────────────────────────────────────────────────────
ensure_registry() {
  mkdir -p "$REGISTRY_DIR"
  [[ -f "$REGISTRY_FILE" ]] || touch "$REGISTRY_FILE"
}

registry_add() {
  local path="$1"
  ensure_registry
  if ! grep -qxF "$path" "$REGISTRY_FILE" 2>/dev/null; then
    printf '%s\n' "$path" >> "$REGISTRY_FILE"
  fi
}

registry_remove() {
  local path="$1"
  ensure_registry
  local tmp="$REGISTRY_FILE.tmp"
  grep -vxF "$path" "$REGISTRY_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$REGISTRY_FILE"
}

# ─── Backup ─────────────────────────────────────────────────────────
backup_skill() {
  local skill="$1" dest="$2"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local backup_path="$BACKUP_DIR/${skill}_${ts}"
  mkdir -p "$BACKUP_DIR"

  if [[ -L "$dest" ]]; then
    local target
    target="$(readlink "$dest")"
    cp -R "$target" "$backup_path"
  else
    cp -R "$dest" "$backup_path"
  fi

  print_info "Backed up to ${backup_path/#$HOME/~}"
}

# ─── Install logic ──────────────────────────────────────────────────
do_install() {
  local skill="$1" src="$2" dest="$3"
  if [[ "$INSTALL_METHOD" == "symlink" ]]; then
    ln -s "$src" "$dest"
  else
    cp -R "$src" "$dest"
  fi
}

do_update() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    local old_target
    old_target="$(readlink "$dest")"
    rm "$dest"
    cp -R "$old_target" "$dest"
  fi

  local tmp_dir="$dest/.tmp"
  mkdir -p "$tmp_dir"

  # Move conflicting dest files to .tmp before overwriting
  while IFS= read -r f; do
    local rel="${f#$src/}"
    local dest_file="$dest/$rel"
    if [[ -e "$dest_file" ]] && ! diff -q "$f" "$dest_file" &>/dev/null; then
      local tmp_file="$tmp_dir/$rel"
      mkdir -p "$(dirname "$tmp_file")"
      mv "$dest_file" "$tmp_file"
    fi
  done < <(find "$src" -type f 2>/dev/null)

  # Copy source files into dest
  while IFS= read -r f; do
    local rel="${f#$src/}"
    local dest_file="$dest/$rel"
    mkdir -p "$(dirname "$dest_file")"
    cp "$f" "$dest_file"
  done < <(find "$src" -type f 2>/dev/null)

  # Restore user files from .tmp back to dest
  if [[ -d "$tmp_dir" ]]; then
    while IFS= read -r f; do
      local rel="${f#$tmp_dir/}"
      local dest_file="$dest/$rel"
      mv "$f" "$dest_file"
    done < <(find "$tmp_dir" -type f 2>/dev/null)
    # Clean up empty .tmp directory
    find "$tmp_dir" -depth -type d -empty -delete 2>/dev/null
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}

install_skills() {
  local count=0

  for (( i=0; i<${#SKILLS[@]}; i++ )); do
    [[ ${SELECTED[$i]} -eq 0 ]] && continue

    local skill="${SKILLS[$i]}"
    local src="$SKILLS_DIR/$skill"
    local dest="$INSTALL_DIR/$skill"

    if [[ -e "$dest" || -L "$dest" ]]; then
      if [[ -L "$dest" && "$INSTALL_METHOD" == "symlink" ]]; then
        local current_target
        current_target="$(readlink "$dest")"
        if [[ "$current_target" == "$src" ]]; then
          print_info "$skill — already linked, skipped"
          count=$((count + 1))
          continue
        fi
      fi

      handle_conflict "$skill" "$src" "$dest"

      case $CONFLICT_ACTION in
        0) print_info "$skill — skipped" ;;
        1)
          do_update "$src" "$dest"
          registry_add "$dest"
          print_success "$skill — updated"
          count=$((count + 1))
          ;;
        2)
          rm -rf "$dest"
          do_install "$skill" "$src" "$dest"
          registry_add "$dest"
          print_success "$skill — reinstalled"
          count=$((count + 1))
          ;;
      esac
      continue
    fi

    do_install "$skill" "$src" "$dest"
    registry_add "$dest"
    print_success "$skill — installed"
    count=$((count + 1))
  done

  printf "\n  ${BOLD}${GREEN}Done!${RESET} Installed ${BOLD}${count}${RESET} skill(s) to ${DIM}${INSTALL_DIR}${RESET}\n"
  if [[ "$INSTALL_METHOD" == "symlink" ]]; then
    printf "  ${DIM}Skills are symlinked — git pull to update.${RESET}\n\n"
  else
    printf "  ${DIM}Skills are copied — run 'setup.sh update' to sync latest changes.${RESET}\n\n"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Subcommands
# ═══════════════════════════════════════════════════════════════════════

# ─── install ─────────────────────────────────────────────────────────
cmd_install() {
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
        shift 2 ;;
      --path)
        INSTALL_DIR="${2/#\~/$HOME}"
        shift 2 ;;
      --method)
        case "$2" in
          symlink|copy) INSTALL_METHOD="$2" ;;
          *) print_error "Unknown method: $2 (supported: symlink, copy)"; exit 1 ;;
        esac
        shift 2 ;;
      --skill)
        explicit_skills+=("$2")
        NON_INTERACTIVE=true
        shift 2 ;;
      *) print_error "Unknown option: $1"; cmd_help; exit 1 ;;
    esac
  done

  discover_skills
  detect_targets

  if [[ ${#explicit_skills[@]} -gt 0 ]]; then
    SELECTED=()
    for (( i=0; i<${#SKILLS[@]}; i++ )); do SELECTED+=(0); done
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

  print_header

  if [[ "$NON_INTERACTIVE" == false ]]; then
    if [[ ! -t 0 ]]; then
      print_error "No TTY detected. Use --skill and --path for non-interactive mode."
      exit 1
    fi
    interactive_select_skills
  fi

  if [[ -z "$INSTALL_DIR" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
      INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    else
      interactive_select_target
    fi
  fi

  mkdir -p "$INSTALL_DIR"

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

# ─── update ──────────────────────────────────────────────────────────
cmd_update() {
  # Parse update-specific flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        if ! resolve_target_name "$2"; then
          local supported
          supported=$(printf '%s\n' "${ALL_TARGETS[@]}" | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
          print_error "Unknown target: $2 (supported: $supported)"
          exit 1
        fi
        shift 2 ;;
      --path)
        INSTALL_DIR="${2/#\~/$HOME}"
        shift 2 ;;
      *) print_error "Unknown option: $1"; cmd_help; exit 1 ;;
    esac
  done

  # Pull latest from remote before comparing
  if [[ -d "$SCRIPT_DIR/.git" ]]; then
    print_info "Pulling latest changes from remote..."
    if git -C "$SCRIPT_DIR" pull --quiet 2>/dev/null; then
      print_success "Repo updated to latest."
    else
      print_warn "Could not pull latest changes. Continuing with local copy."
    fi
    printf "\n"
  fi

  discover_skills
  ensure_registry
  print_header
  printf "  ${BOLD}Checking registered skills...${RESET}\n\n"

  if [[ ! -s "$REGISTRY_FILE" ]]; then
    print_warn "Registry is empty. Run 'setup.sh install' first."
    printf "\n"
    return
  fi

  # Pass 1: scan
  local -a update_dests=() update_srcs=() update_names=()
  local -a uptodate_names=() symlink_names=() warn_msgs=()

  while IFS= read -r dest; do
    [[ -z "$dest" ]] && continue
    local skill_name
    skill_name="$(basename "$dest")"
    local short_dest="${dest/#$HOME/~}"

    if [[ -n "$INSTALL_DIR" ]]; then
      local dest_parent
      dest_parent="$(dirname "$dest")"
      [[ "$dest_parent" != "$INSTALL_DIR" ]] && continue
    fi

    local src="$SKILLS_DIR/$skill_name"
    if [[ ! -d "$src" ]]; then
      warn_msgs+=("$skill_name ($short_dest) — not found in repo, skipped")
      continue
    fi

    if [[ ! -e "$dest" && ! -L "$dest" ]]; then
      warn_msgs+=("$skill_name ($short_dest) — missing")
      continue
    fi

    if [[ -L "$dest" ]]; then
      local target
      target="$(readlink "$dest")"
      if [[ -d "$target" ]]; then
        symlink_names+=("$skill_name ($short_dest) — symlinked, git pull to update")
      else
        warn_msgs+=("$skill_name ($short_dest) — symlink broken")
      fi
      continue
    fi

    local has_diff=false
    while IFS= read -r f; do
      local rel="${f#$src/}"
      if [[ ! -e "$dest/$rel" ]] || ! diff -q "$f" "$dest/$rel" &>/dev/null; then
        has_diff=true
        break
      fi
    done < <(find "$src" -type f 2>/dev/null)

    if $has_diff; then
      update_dests+=("$dest")
      update_srcs+=("$src")
      update_names+=("$skill_name ($short_dest)")
    else
      uptodate_names+=("$skill_name ($short_dest)")
    fi
  done < "$REGISTRY_FILE"

  # Display summary
  local n_warn=${#warn_msgs[@]} n_sym=${#symlink_names[@]}
  local n_ok=${#uptodate_names[@]} n_upd=${#update_names[@]}

  if [[ $n_warn -gt 0 ]]; then
    for msg in "${warn_msgs[@]}"; do print_warn "$msg"; done
  fi
  if [[ $n_sym -gt 0 ]]; then
    for msg in "${symlink_names[@]}"; do print_info "$msg"; done
  fi
  if [[ $n_ok -gt 0 ]]; then
    for name in "${uptodate_names[@]}"; do print_info "$name — up to date"; done
  fi
  if [[ $n_upd -gt 0 ]]; then
    printf "\n  ${BOLD}Will update:${RESET}\n"
    for (( i=0; i<n_upd; i++ )); do
      printf "    ${YELLOW}~${RESET} %s\n" "${update_names[$i]}"
      show_file_diff "${update_srcs[$i]}" "${update_dests[$i]}"
    done
  fi

  local total=$(( n_upd + n_ok + n_sym ))

  if [[ $total -eq 0 ]]; then
    print_warn "No matching skills found in registry."
    printf "\n"
    return
  fi

  if [[ $n_upd -eq 0 ]]; then
    printf "\n  ${BOLD}${GREEN}All skills are up to date.${RESET}\n\n"
    return
  fi

  # Confirm
  printf "  ${BOLD}Proceed with update? [Y/n]${RESET} "
  local confirm
  read -rn1 confirm
  printf "\n\n"

  if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
    print_info "Update cancelled."
    printf "\n"
    return
  fi

  # Pass 2: perform
  local updated=0
  for (( i=0; i<${#update_dests[@]}; i++ )); do
    do_update "${update_srcs[$i]}" "${update_dests[$i]}"
    print_success "${update_names[$i]} — updated"
    updated=$((updated + 1))
  done

  printf "\n  ${BOLD}${GREEN}Done!${RESET} ${BOLD}${updated}${RESET}/${BOLD}${total}${RESET} skill(s) updated.\n\n"
}

# ─── status ──────────────────────────────────────────────────────────
cmd_status() {
  ensure_registry
  print_header

  if [[ ! -s "$REGISTRY_FILE" ]]; then
    print_warn "No skills registered."
    printf "\n"
    return
  fi

  printf "  ${BOLD}Installed skills${RESET} ${DIM}(${REGISTRY_FILE/#$HOME/~})${RESET}\n\n"

  while IFS= read -r dest; do
    [[ -z "$dest" ]] && continue
    local skill_name
    skill_name="$(basename "$dest")"
    local short_dest="${dest/#$HOME/~}"

    if [[ -L "$dest" ]]; then
      local target
      target="$(readlink "$dest")"
      if [[ -d "$target" ]]; then
        printf "  ${GREEN}✓${RESET} %-16s ${DIM}symlink  %s${RESET}\n" "$skill_name" "$short_dest"
      else
        printf "  ${RED}✗${RESET} %-16s ${DIM}broken   %s${RESET}\n" "$skill_name" "$short_dest"
      fi
    elif [[ -d "$dest" ]]; then
      printf "  ${GREEN}✓${RESET} %-16s ${DIM}copy     %s${RESET}\n" "$skill_name" "$short_dest"
    else
      printf "  ${RED}✗${RESET} %-16s ${DIM}missing  %s${RESET}\n" "$skill_name" "$short_dest"
    fi
  done < "$REGISTRY_FILE"

  printf "\n"
}

# ─── list ────────────────────────────────────────────────────────────
cmd_list() {
  discover_skills
  print_header
  printf "  ${BOLD}Available skills${RESET}\n\n"
  for skill in "${SKILLS[@]}"; do
    printf "  %-20s %s\n" "$skill" "$(get_description "$skill")"
  done
  printf "\n"
}

# ─── clean-backup ───────────────────────────────────────────────────
cmd_clean_backup() {
  print_header

  if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
    print_info "No backups found."
    printf "\n"
    return
  fi

  printf "  ${BOLD}Backups${RESET} ${DIM}(${BACKUP_DIR/#$HOME/~})${RESET}\n\n"

  local total_size
  total_size="$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"

  for entry in "$BACKUP_DIR"/*/; do
    [[ -d "$entry" ]] || continue
    local name size
    name="$(basename "$entry")"
    size="$(du -sh "$entry" 2>/dev/null | cut -f1)"
    printf "    %s ${DIM}(%s)${RESET}\n" "$name" "$size"
  done

  printf "\n  ${DIM}Total: %s${RESET}\n\n" "$total_size"

  printf "  ${BOLD}Delete all backups? [y/N]${RESET} "
  local confirm
  read -rn1 confirm
  printf "\n"

  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf "$BACKUP_DIR"
    printf "\n"
    print_success "All backups deleted."
  else
    printf "\n"
    print_info "Backups kept."
  fi
  printf "\n"
}

# ─── help ────────────────────────────────────────────────────────────
cmd_help() {
  cat <<EOF

Usage: $(basename "$0") <command> [options]

Commands:
  install          Install skills (default if no command given)
  update           Update installed skills from source repo
  status           Show all installed skills and their status
  list             List available skills
  clean-backup     List and optionally delete backed-up skills
  help             Show this help

Install options:
  --target <name>  Install target: claude, cursor, antigravity, openclaw, gemini, universal
  --path <dir>     Install to a custom path (overrides --target)
  --method <type>  Install method: copy (default) or symlink
  --skill <name>   Skill to install (repeatable; enables non-interactive mode)

Update options:
  --target <name>  Only update skills installed to this target
  --path <dir>     Only update skills installed to this path

Examples:
  $(basename "$0")                              # Interactive mode
  $(basename "$0") install --target cursor      # Install to Cursor
  $(basename "$0") install --skill todo-manager # Non-interactive install
  $(basename "$0") update                       # Update all copied skills
  $(basename "$0") update --target claude       # Update only Claude Code skills
  $(basename "$0") status                       # Show installed skills

One-line install (no git clone needed):
  bash <(curl -fsSL https://raw.githubusercontent.com/jarieshan/agent-skills/main/setup.sh)
  bash <(curl -fsSL .../setup.sh) update
  bash <(curl -fsSL .../setup.sh) install --skill todo-manager

EOF
  exit 0
}

# ═══════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════
main() {
  bootstrap

  local cmd="${1:-}"

  # No args + registry exists → interactive mode selector
  if [[ -z "$cmd" || "$cmd" == -* ]]; then
    if [[ -f "$REGISTRY_FILE" && -s "$REGISTRY_FILE" ]] && [[ -t 0 ]]; then
      print_header
      interactive_select_mode
      if [[ "$SELECTED_MODE" -eq 0 ]]; then
        cmd_update "$@"
      else
        cmd_install "$@"
      fi
    else
      cmd_install "$@"
    fi
    return
  fi

  shift
  case "$cmd" in
    install)       cmd_install "$@" ;;
    update)        cmd_update "$@" ;;
    status)        cmd_status ;;
    list)          cmd_list ;;
    clean-backup)  cmd_clean_backup ;;
    help|-h|--help) cmd_help ;;
    *)
      print_error "Unknown command: $cmd"
      cmd_help
      ;;
  esac
}

main "$@"
