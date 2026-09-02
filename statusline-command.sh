#!/bin/bash
# Claude Code status line
# Shows: repo name | 5h usage (RGB gradient) | context used (RGB gradient) | model | session tokens
# Separators are printed in dim gray.

input=$(cat)

repo_name=$(printf '%s' "$input" | jq -r '.workspace.repo.name // empty')
if [ -z "$repo_name" ]; then
  cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // empty')
  repo_name=$(basename "${cwd:-$PWD}")
fi

model=$(printf '%s' "$input" | jq -r '.model.display_name')
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')

five_hour=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
context_used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')

tokens_in=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')
tokens_out=$(printf '%s' "$input" | jq -r '.context_window.total_output_tokens // 0')
session_tokens=$(awk -v i="$tokens_in" -v o="$tokens_out" 'BEGIN{print i+o}')

# Formats a raw token count into a compact human-readable string (e.g. 1234 -> 1.2k).
format_tokens() {
  awk -v n="$1" 'BEGIN{
    if (n >= 1000000) printf "%.1fM", n/1000000
    else if (n >= 1000) printf "%.1fk", n/1000
    else printf "%d", n
  }'
}
session_tokens_fmt=$(format_tokens "$session_tokens")

RESET="\033[0m"
DIM_GRAY="\033[38;5;240m"
SEP="${DIM_GRAY} | ${RESET}"
BAR_WIDTH=10

# Builds a fixed-width bar of block characters. Each block's color is
# interpolated along a green -> yellow -> red gradient based on its position,
# and only the leading N blocks (proportional to the percentage) are lit;
# the rest are drawn dim/unfilled. Prints literal "\033[...m" escape text
# (interpreted later by the final `printf %b`), not raw escape bytes.
gradient_bar() {
  local pct="$1"
  local slots
  slots=$(awk -v pct="$pct" -v width="$BAR_WIDTH" 'BEGIN {
    filled = int((pct / 100) * width + 0.5)
    if (filled > width) filled = width
    if (filled < 0) filled = 0
    for (i = 1; i <= width; i++) {
      t = (i - 0.5) / width
      if (t <= 0.5) { r = int(510 * t); g = 255 }
      else { r = 255; g = int(255 * (1 - 2 * (t - 0.5))) }
      b = 0
      lit = (i <= filled) ? 1 : 0
      printf "%d,%d,%d,%d ", r, g, b, lit
    }
  }')
  local out="" slot r g b lit
  for slot in $slots; do
    IFS=',' read -r r g b lit <<< "$slot"
    if [ "$lit" -eq 1 ]; then
      out+="\033[38;2;${r};${g};${b}m█"
    else
      out+="\033[38;2;60;60;60m░"
    fi
  done
  out+="$RESET"
  printf '%s' "$out"
}

parts=("$repo_name")

if [ -n "$five_hour" ]; then
  bar=$(gradient_bar "$five_hour")
  pct=$(awk -v p="$five_hour" 'BEGIN{printf "%.0f", p}')
  parts+=("${DIM_GRAY}5h${RESET} ${bar} ${pct}%")
fi

if [ -n "$context_used" ]; then
  bar=$(gradient_bar "$context_used")
  pct=$(awk -v p="$context_used" 'BEGIN{printf "%.0f", p}')
  parts+=("${DIM_GRAY}ctx${RESET} ${bar} ${pct}%")
fi

if [ -n "$effort" ]; then
  parts+=("${model} ${DIM_GRAY}(${effort})${RESET}")
else
  parts+=("$model")
fi

parts+=("${DIM_GRAY}tokens${RESET} ${session_tokens_fmt}")

output=""
for i in "${!parts[@]}"; do
  if [ "$i" -gt 0 ]; then
    output+="$SEP"
  fi
  output+="${parts[$i]}"
done

printf "%b\n" "$output"
