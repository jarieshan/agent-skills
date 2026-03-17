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
INSTALL_METHOD="copy"  # default: copy; override with --method symlink
SKILLS=()
SELECTED=()
NON_INTERACTIVE=false
RUN_UPDATE=false

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
    local short_path="${skills/#$HOME/~}"

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

# ─── Conflict resolution ────────────────────────────────────────────
# Compare src and dest, show diff summary, ask user to confirm reinstall
handle_conflict() {
  local skill="$1" src="$2" dest="$3"

  printf "\n  ${YELLOW}!${RESET} ${BOLD}%s${RESET} already exists at ${DIM}%s${RESET}\n\n" "$skill" "$dest"

  # Resolve actual source (follow symlink for comparison)
  local actual_dest="$dest"
  [[ -L "$dest" ]] && actual_dest="$(readlink "$dest")"

  # Collect file changes
  local deleted=() replaced=() added=()

  # Files in dest but not in src → will be deleted
  while IFS= read -r f; do
    local rel="${f#$actual_dest/}"
    if [[ ! -e "$src/$rel" ]]; then
      deleted+=("$rel")
    fi
  done < <(find "$actual_dest" -type f 2>/dev/null | sort)

  # Files in src
  while IFS= read -r f; do
    local rel="${f#$src/}"
    if [[ -e "$actual_dest/$rel" ]]; then
      if ! diff -q "$f" "$actual_dest/$rel" &>/dev/null; then
        replaced+=("$rel")
      fi
    else
      added+=("$rel")
    fi
  done < <(find "$src" -type f 2>/dev/null | sort)

  # Display changes
  local has_changes=false

  if [[ ${#deleted[@]} -gt 0 ]]; then
    has_changes=true
    printf "  ${RED}Delete:${RESET}\n"
    for f in "${deleted[@]}"; do
      printf "    ${RED}-%s${RESET}\n" "$f"
    done
  fi

  if [[ ${#replaced[@]} -gt 0 ]]; then
    has_changes=true
    printf "  ${YELLOW}Replace:${RESET}\n"
    for f in "${replaced[@]}"; do
      printf "    ${YELLOW}~%s${RESET}\n" "$f"
    done
  fi

  if [[ ${#added[@]} -gt 0 ]]; then
    has_changes=true
    printf "  ${GREEN}Add:${RESET}\n"
    for f in "${added[@]}"; do
      printf "    ${GREEN}+%s${RESET}\n" "$f"
    done
  fi

  if ! $has_changes; then
    printf "  ${DIM}No file differences detected.${RESET}\n"
  fi

  printf "\n"

  # Interactive: ask skip, update, or reinstall
  # Return: 0=skip, 1=update, 2=reinstall
  if [[ "$NON_INTERACTIVE" == true ]]; then
    print_warn "$skill — skipped (use interactive mode to reinstall/update)"
    return 0
  fi

  local cursor=0
  local num_opts=3
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
    read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 rest
        case "$rest" in
          '[A') (( cursor > 0 )) && (( cursor-- )) ;;
          '[B') (( cursor < num_opts - 1 )) && (( cursor++ )) ;;
        esac
        ;;
      '') break ;;
    esac
    for (( j=0; j<num_opts; j++ )); do tput cuu1 2>/dev/null; done
    draw_conflict_options "$cursor"
  done

  tput cnorm 2>/dev/null || true
  printf "\n"

  return "$cursor"  # 0=skip, 1=update, 2=reinstall
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

# ─── Registry ────────────────────────────────────────────────────────
# ~/.config/agent-skills/registry.list
# Each line is an install directory path, e.g. /Users/x/.claude/skills
REGISTRY_DIR="$HOME/.config/agent-skills"
REGISTRY_FILE="$REGISTRY_DIR/registry.list"

ensure_registry() {
  mkdir -p "$REGISTRY_DIR"
  [[ -f "$REGISTRY_FILE" ]] || touch "$REGISTRY_FILE"
}

# Add an install dir to registry (deduplicated)
registry_add() {
  local dir="$1"
  ensure_registry
  if ! grep -qxF "$dir" "$REGISTRY_FILE" 2>/dev/null; then
    printf '%s\n' "$dir" >> "$REGISTRY_FILE"
  fi
}

# Remove an install dir from registry
registry_remove() {
  local dir="$1"
  ensure_registry
  local tmp="$REGISTRY_FILE.tmp"
  grep -vxF "$dir" "$REGISTRY_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$REGISTRY_FILE"
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

# Update: copy changed + new files from src into dest, keep extra files in dest
do_update() {
  local src="$1" dest="$2"

  # For symlink dest, remove the link first and copy fresh
  if [[ -L "$dest" ]]; then
    local old_target
    old_target="$(readlink "$dest")"
    rm "$dest"
    cp -R "$old_target" "$dest"
  fi

  # Overlay: copy all files from src into dest
  while IFS= read -r f; do
    local rel="${f#$src/}"
    local dest_file="$dest/$rel"
    mkdir -p "$(dirname "$dest_file")"
    cp "$f" "$dest_file"
  done < <(find "$src" -type f 2>/dev/null)
}

install_skills() {
  local count=0

  for (( i=0; i<${#SKILLS[@]}; i++ )); do
    [[ ${SELECTED[$i]} -eq 0 ]] && continue

    local skill="${SKILLS[$i]}"
    local src="$SCRIPT_DIR/$skill"
    local dest="$INSTALL_DIR/$skill"

    if [[ -e "$dest" || -L "$dest" ]]; then
      # Exact same symlink already exists
      if [[ -L "$dest" && "$INSTALL_METHOD" == "symlink" ]]; then
        local current_target
        current_target="$(readlink "$dest")"
        if [[ "$current_target" == "$src" ]]; then
          print_info "$skill — already linked, skipped"
          (( count++ ))
          continue
        fi
      fi

      # Conflict: ask user (returns 0=skip, 1=update, 2=reinstall)
      local action
      handle_conflict "$skill" "$src" "$dest"
      action=$?

      case $action in
        0) # Skip
          print_info "$skill — skipped"
          ;;
        1) # Update
          do_update "$src" "$dest"
          print_success "$skill — updated"
          (( count++ ))
          ;;
        2) # Reinstall
          rm -rf "$dest"
          do_install "$skill" "$src" "$dest"
          print_success "$skill — reinstalled"
          (( count++ ))
          ;;
      esac
      continue
    fi

    do_install "$skill" "$src" "$dest"
    print_success "$skill — installed"
    (( count++ ))
  done

  # Record install dir in registry
  registry_add "$INSTALL_DIR"

  printf "\n  ${BOLD}${GREEN}Done!${RESET} Installed ${BOLD}${count}${RESET} skill(s) to ${DIM}${INSTALL_DIR}${RESET}\n"
  if [[ "$INSTALL_METHOD" == "symlink" ]]; then
    printf "  ${DIM}Skills are symlinked — git pull to update.${RESET}\n\n"
  else
    printf "  ${DIM}Skills are copied — run with --update to sync latest changes.${RESET}\n\n"
  fi
}

# ─── Update command ──────────────────────────────────────────────────
# Scan registry dirs, match skills against repo, sync changes.
run_update() {
  discover_skills
  ensure_registry
  print_header
  printf "  ${BOLD}Updating skills...${RESET}\n\n"

  if [[ ! -s "$REGISTRY_FILE" ]]; then
    print_warn "Registry is empty. Install skills first."
    printf "\n"
    return
  fi

  local found=0 updated=0

  while IFS= read -r install_dir; do
    [[ -z "$install_dir" || ! -d "$install_dir" ]] && continue

    # Filter by --target / --path if specified
    if [[ -n "$INSTALL_DIR" && "$install_dir" != "$INSTALL_DIR" ]]; then
      continue
    fi

    local short_dir="${install_dir/#$HOME/~}"

    for skill in "${SKILLS[@]}"; do
      local src="$SCRIPT_DIR/$skill"
      local dest="$install_dir/$skill"

      # Skip if not installed in this dir
      [[ -e "$dest" || -L "$dest" ]] || continue

      (( found++ ))

      # Symlinked: nothing to update
      if [[ -L "$dest" ]]; then
        local target
        target="$(readlink "$dest")"
        if [[ -d "$target" ]]; then
          print_info "$skill ($short_dir) — symlinked, git pull to update"
        else
          print_warn "$skill ($short_dir) — symlink broken"
        fi
        continue
      fi

      # Copy: check for diff and sync
      local has_diff=false
      while IFS= read -r f; do
        local rel="${f#$src/}"
        if [[ ! -e "$dest/$rel" ]] || ! diff -q "$f" "$dest/$rel" &>/dev/null; then
          has_diff=true
          break
        fi
      done < <(find "$src" -type f 2>/dev/null)

      if ! $has_diff; then
        print_info "$skill ($short_dir) — up to date"
        continue
      fi

      # Apply update
      do_update "$src" "$dest"
      print_success "$skill ($short_dir) — updated"
      (( updated++ ))
    done
  done < "$REGISTRY_FILE"

  if [[ $found -eq 0 ]]; then
    print_warn "No installed skills found in registered directories."
  else
    printf "\n  ${BOLD}${GREEN}Done!${RESET} ${BOLD}${updated}${RESET}/${BOLD}${found}${RESET} skill(s) updated.\n"
  fi
  printf "\n"
}

# ─── Status command ──────────────────────────────────────────────────
run_status() {
  discover_skills
  ensure_registry
  print_header

  if [[ ! -s "$REGISTRY_FILE" ]]; then
    print_warn "No install directories registered."
    printf "\n"
    return
  fi

  printf "  ${BOLD}Registered directories${RESET} ${DIM}(${REGISTRY_FILE/#$HOME/~})${RESET}\n\n"

  while IFS= read -r install_dir; do
    [[ -z "$install_dir" ]] && continue
    local short_dir="${install_dir/#$HOME/~}"

    if [[ ! -d "$install_dir" ]]; then
      printf "  ${RED}✗${RESET} ${DIM}%s${RESET} — directory missing\n" "$short_dir"
      continue
    fi

    printf "  ${BOLD}%s${RESET}\n" "$short_dir"

    for skill in "${SKILLS[@]}"; do
      local dest="$install_dir/$skill"
      [[ -e "$dest" || -L "$dest" ]] || continue

      if [[ -L "$dest" ]]; then
        local target
        target="$(readlink "$dest")"
        if [[ -d "$target" ]]; then
          printf "    ${GREEN}✓${RESET} %-16s ${DIM}symlink → %s${RESET}\n" "$skill" "${target/#$HOME/~}"
        else
          printf "    ${RED}✗${RESET} %-16s ${DIM}symlink broken${RESET}\n" "$skill"
        fi
      elif [[ -d "$dest" ]]; then
        printf "    ${GREEN}✓${RESET} %-16s ${DIM}copy${RESET}\n" "$skill"
      fi
    done
    printf "\n"
  done < "$REGISTRY_FILE"
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
  --method <type>    Install method: copy (default) or symlink
  --skill <name>     Skill to install (repeatable, default: all)
  --update           Update all copied skills from their source repo
  --status           Show all installed skills and their status
  --list             List available skills and exit
  -h, --help         Show this help

Examples:
  $(basename "$0")                           # Interactive mode
  $(basename "$0") --target cursor           # Install to Cursor skills dir
  $(basename "$0") --method symlink           # Symlink instead of copy
  $(basename "$0") --skill todo-manager      # Non-interactive, single skill
  $(basename "$0") --update                  # Update all copied skills
  $(basename "$0") --update --target claude  # Update only Claude Code skills
  $(basename "$0") --status                  # Show installed skills
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
      --method)
        case "$2" in
          symlink|copy) INSTALL_METHOD="$2" ;;
          *)
            print_error "Unknown method: $2 (supported: symlink, copy)"
            exit 1
            ;;
        esac
        shift 2
        ;;
      --skill)
        explicit_skills+=("$2")
        NON_INTERACTIVE=true
        shift 2
        ;;
      --update)
        RUN_UPDATE=true
        shift
        ;;
      --status)
        detect_targets
        run_status
        exit 0
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

  # Handle --update mode
  if [[ "$RUN_UPDATE" == true ]]; then
    run_update
    exit 0
  fi

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
