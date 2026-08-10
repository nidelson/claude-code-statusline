#!/usr/bin/env bash
# ~/.claude/statusline-command.sh
# Status line para Claude Code — estilo Starship (nidelson)

input=$(cat)

user=$(whoami)
host=$(hostname -s)
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir=$(pwd)
basename_dir=$(basename "$dir")

model=$(echo "$input" | jq -r '.model.display_name // empty')

# Contexto: percentual restante (só exibe após primeira resposta)
ctx_remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
ctx_part=""
if [ -n "$ctx_remaining" ]; then
  ctx_int=$(printf "%.0f" "$ctx_remaining")
  if [ "$ctx_int" -le 20 ]; then
    ctx_part=" \033[0;31mctx:${ctx_int}%\033[0m"
  elif [ "$ctx_int" -le 50 ]; then
    ctx_part=" \033[0;33mctx:${ctx_int}%\033[0m"
  else
    ctx_part=" \033[0;32mctx:${ctx_int}%\033[0m"
  fi
fi

# Branch git (via worktree ou workspace)
branch=$(echo "$input" | jq -r '.worktree.branch // .workspace.git_worktree // empty')
branch_part=""
if [ -n "$branch" ]; then
  branch_part=" \033[0;35m[$branch]\033[0m"
else
  # Tenta ler do git diretamente, sem travar
  git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$git_branch" ] && branch_part=" \033[0;35m[$git_branch]\033[0m"
fi

# PR aberto
pr=$(echo "$input" | jq -r '.pr.number // empty')
pr_part=""
if [ -n "$pr" ]; then
  pr_state=$(echo "$input" | jq -r '.pr.review_state // "open"')
  pr_part=" \033[0;36mPR#${pr}(${pr_state})\033[0m"
fi

# Repo owner/name
repo=$(echo "$input" | jq -r '.workspace.repo | if . then .owner + "/" + .name else empty end')
repo_part=""
[ -n "$repo" ] && repo_part=" \033[0;34m${repo}\033[0m"

# Monta linha
# %b interpreta os \033 embutidos nas partes condicionais
printf "\033[1;32m%s@%s\033[0m \033[1;34m%s\033[0m%b%b%b" \
  "$user" "$host" "$basename_dir" "$branch_part" "$repo_part" "$pr_part"

[ -n "$model" ] && printf " \033[0;90m| %s\033[0m" "$model"
printf "%b\n" "$ctx_part"
