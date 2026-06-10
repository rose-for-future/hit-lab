#!/usr/bin/env bash
#
# hit-lab / install.sh
#
# Symlinks the 15 sub-skills into Claude Code and/or Codex skill directories so
# agents can find them globally. Re-runnable safely (overwrite after confirmation).
#
# After install, in any content project directory: open Claude Code → say "初始化"
# → /hit-init runs the onboarding.
#
# To uninstall: bash uninstall.sh
#
# Usage:
#   bash install.sh                    # Claude Code install, symlink mode (default)
#   bash install.sh --copy             # Claude Code install, copy mode
#   bash install.sh --codex            # Codex install into ~/.codex/skills/
#   bash install.sh --all              # install for Claude Code and Codex
#   bash install.sh --codex --copy     # Codex install, copy mode
#   bash install.sh --reinstall-hooks <project-dir>
#                                      # rewrite hook scripts in an existing user project's .hit-hooks/
#                                      # (use after git pull when CHANGELOG mentions hook script changes;
#                                      #  does NOT touch .hit-state.json or any user data)

set -euo pipefail

SUB_SKILLS=(
  hit-init
  hit-learn-from
  hit-seed
  hit-score
  hit-score-blind
  hit-predict
  hit-shoot
  hit-publish
  hit-retro
  hit-persona
  hit-bump
  hit-recommend
  hit-trends
  hit-status
  hit-migrate
)

CLAUDE_SKILLS=("${SUB_SKILLS[@]}")
CODEX_SKILLS=(hit-lab "${SUB_SKILLS[@]}")

# Resolve the directory containing THIS script (the source root) — needed early for both modes
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

MODE="symlink"
TARGET_AGENT="claude"

# --- --reinstall-hooks branch: rewrite a user project's hook scripts only ---
if [[ "${1:-}" == "--reinstall-hooks" ]]; then
  PROJECT_DIR="${2:-}"
  if [[ -z "$PROJECT_DIR" ]]; then
    echo "❌ Usage: bash install.sh --reinstall-hooks <path-to-user-project>"
    echo "   The user project must already have been initialized via /hit-init."
    exit 1
  fi
  if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "❌ Project dir not found: $PROJECT_DIR"
    exit 1
  fi
  if [[ ! -f "$PROJECT_DIR/.hit-state.json" ]]; then
    echo "❌ $PROJECT_DIR is not a hit-lab project (no .hit-state.json)."
    echo "   Run /hit-init in that directory first."
    exit 1
  fi

  HOOK_DST="$PROJECT_DIR/.hit-hooks"
  mkdir -p "$HOOK_DST"

  echo ""
  echo "Reinstalling hook scripts in: $PROJECT_DIR"
  echo "  source: $SCRIPT_DIR/hooks/"
  echo ""

  for hook_script in prediction-immutability.sh session-start.sh log-event.sh; do
    if [[ -f "$SCRIPT_DIR/hooks/$hook_script" ]]; then
      cp "$SCRIPT_DIR/hooks/$hook_script" "$HOOK_DST/$hook_script"
      chmod +x "$HOOK_DST/$hook_script"
      echo "  ✓ updated: .hit-hooks/$hook_script"
    else
      echo "  ⚠️  missing in source: hooks/$hook_script (skipped)"
    fi
  done

  echo ""
  echo "✅ Hook scripts reinstalled."
  echo ""
  echo "Note: This did NOT touch:"
  echo "  - .hit-state.json (your data)"
  echo "  - .claude/settings.json (hook registration — should still point at .hit-hooks/)"
  echo "  - rubric_notes.md / predictions/ / videos/ (your work)"
  echo ""
  echo "If schema also changed (CHANGELOG marks BREAKING), additionally run /hit-migrate"
  echo "in Claude Code from your project directory."
  echo ""
  exit 0
fi

for arg in "$@"; do
  case "$arg" in
    --copy)
      MODE="copy"
      ;;
    --claude)
      TARGET_AGENT="claude"
      ;;
    --codex)
      TARGET_AGENT="codex"
      ;;
    --all)
      TARGET_AGENT="all"
      ;;
    --help|-h)
      sed -n '1,35p' "$0"
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $arg"
      echo "   Usage: bash install.sh [--copy] [--claude|--codex|--all]"
      exit 1
      ;;
  esac
done

# Sanity check: confirm we're in the hit-lab root
if [[ ! -f "$SCRIPT_DIR/SKILL.md" ]]; then
  echo "❌ Missing: $SCRIPT_DIR/SKILL.md"
  echo "   Are you running install.sh from the hit-lab root?"
  exit 1
fi

for s in "${SUB_SKILLS[@]}"; do
  if [[ ! -f "$SCRIPT_DIR/skills/$s/SKILL.md" ]]; then
    echo "❌ Missing: $SCRIPT_DIR/skills/$s/SKILL.md"
    echo "   Are you running install.sh from the hit-lab root?"
    exit 1
  fi
done

skill_source() {
  local skill="$1"
  if [[ "$skill" == "hit-lab" ]]; then
    echo "$SCRIPT_DIR"
  else
    echo "$SCRIPT_DIR/skills/$skill"
  fi
}

detect_conflicts() {
  local target_dir="$1"
  shift
  local warned=0

  for s in "$@"; do
    local src
    src=$(skill_source "$s")
    local target="$target_dir/$s"
    if [[ -e "$target" || -L "$target" ]]; then
      if [[ -L "$target" ]]; then
        local existing
        existing=$(readlink "$target")
        if [[ "$existing" != "$src" ]]; then
          echo "⚠️  $target already symlinked to: $existing"
          warned=1
        fi
      else
        echo "⚠️  $target exists (not a symlink) — will be overwritten"
        warned=1
      fi
    fi
  done

  return "$warned"
}

install_skills() {
  local label="$1"
  local target_dir="$2"
  shift 2

  mkdir -p "$target_dir"

  echo ""
  echo "Installing hit-lab for $label (mode: $MODE)"
  echo "  source: $SCRIPT_DIR"
  echo "  target: $target_dir/"
  echo ""

  for s in "$@"; do
    local src
    src=$(skill_source "$s")
    local dst="$target_dir/$s"

    if [[ -e "$dst" || -L "$dst" ]]; then
      rm -rf "$dst"
    fi

    if [[ "$MODE" == "symlink" ]]; then
      ln -s "$src" "$dst"
      echo "  ✓ symlinked: $s"
    else
      # copy mode: skills reference shared assets via relative paths
      # (../../shared-references, templates/, starter-rubrics/, hooks/) —
      # copying a skill dir alone breaks every one of those references.
      # So copy mode = snapshot the WHOLE repo into .hit-lab-dist/ once,
      # then symlink each skill into the frozen snapshot.
      local rel="${src#"$SCRIPT_DIR"}"
      local snap_src="$DIST_DIR${rel}"
      ln -s "$snap_src" "$dst"
      echo "  ✓ copied (via snapshot): $s"
    fi
  done
}

make_snapshot() {
  local target_dir="$1"
  DIST_DIR="$target_dir/.hit-lab-dist"
  rm -rf "$DIST_DIR"
  mkdir -p "$DIST_DIR"
  ( cd "$SCRIPT_DIR" && tar --exclude .git --exclude '__pycache__' --exclude .claude -cf - . ) \
    | ( cd "$DIST_DIR" && tar -xf - )
  echo "  ✓ snapshot: $DIST_DIR (frozen copy of the repo)"
}

WARNED=0
if [[ "$TARGET_AGENT" == "claude" || "$TARGET_AGENT" == "all" ]]; then
  detect_conflicts "$HOME/.claude/skills" "${CLAUDE_SKILLS[@]}" || WARNED=1
fi
if [[ "$TARGET_AGENT" == "codex" || "$TARGET_AGENT" == "all" ]]; then
  detect_conflicts "$HOME/.codex/skills" "${CODEX_SKILLS[@]}" || WARNED=1
fi

if [[ $WARNED -eq 1 ]]; then
  echo ""
  read -p "Continue and overwrite? (y/N) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
fi

if [[ "$TARGET_AGENT" == "claude" || "$TARGET_AGENT" == "all" ]]; then
  if [[ "$MODE" == "copy" ]]; then make_snapshot "$HOME/.claude/skills"; fi
  install_skills "Claude Code" "$HOME/.claude/skills" "${CLAUDE_SKILLS[@]}"
fi

if [[ "$TARGET_AGENT" == "codex" || "$TARGET_AGENT" == "all" ]]; then
  if [[ "$MODE" == "copy" ]]; then make_snapshot "$HOME/.codex/skills"; fi
  install_skills "Codex" "$HOME/.codex/skills" "${CODEX_SKILLS[@]}"
fi

echo ""
echo "✅ Install complete!"
echo ""
echo "Next steps:"
echo "  1. cd into your content project (or create one):"
echo "       mkdir ~/my-channel && cd ~/my-channel"
echo ""
echo "  2. Open Claude Code or Codex in that directory"
echo ""
echo "  3. In the chat, say:"
echo "       初始化"
echo "       (or: 初始化 hit-lab)"
echo ""
if [[ "$TARGET_AGENT" == "claude" || "$TARGET_AGENT" == "all" ]]; then
  echo "Verify Claude install: ls -la ~/.claude/skills/ | grep hit"
fi
if [[ "$TARGET_AGENT" == "codex" || "$TARGET_AGENT" == "all" ]]; then
  echo "Verify Codex install:  ls -la ~/.codex/skills/ | grep hit"
  echo "Note: restart Codex if the new skills do not appear in the current session."
fi
echo ""
if [[ "$MODE" == "symlink" ]]; then
  echo "ℹ️  Mode: symlink — edits to source SKILL.md files take effect immediately."
  if [[ "$TARGET_AGENT" == "codex" ]]; then
    echo "   To switch to frozen copy: bash install.sh --codex --copy"
  elif [[ "$TARGET_AGENT" == "all" ]]; then
    echo "   To switch to frozen copy: bash install.sh --all --copy"
  else
    echo "   To switch to frozen copy: bash install.sh --copy"
  fi
else
  echo "ℹ️  Mode: copy — repo snapshot frozen at install time in skills/.hit-lab-dist/. Re-run install.sh to update."
fi
echo ""
