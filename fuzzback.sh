#!/usr/bin/env bash
# shellcheck disable=SC2001

# Strict mode
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -uo pipefail
IFS=$'\n\t'

# Pull in helpers
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

fuzzback::fzf_cmd() {
  fzf-tmux --delimiter=":" \
           --ansi \
           --with-nth="2.." \
           --no-multi \
           --no-sort \
           --no-preview \
           --print-query
}

fuzzback::search_cmd() {
  if hash rg 2>/dev/null; then
    rg -N --column "$@"
  elif hash ag 2>/dev/null; then
    ag --column "$@"
  fi
}

# Move cursor up in scrollback buffer, used when goto_line fails and we have to
# correct
fuzzback::cursor_up() {
  local line_number
  line_number="$1"
  tmux send-keys -X -N "$line_number" cursor-up
}

# Get columns position of search query
fuzzback::query_column() {
  local query="$1"
  local result_line="$2"
  local column zero_index

  column=$(echo "$result_line" | fuzzback::search_cmd "$query" | cut -d':' -f1)
  zero_index=$((column - 1))
  echo "$zero_index"
}

# maximum line number that can be reached via tmux 'jump'
# https://github.com/tmux-plugins/tmux-copycat/blob/e95528ebaeb6300d8620c8748a686b786056f374/scripts/copycat_jump.sh#L159
fuzzback::get_max_jump() {
  local max_jump max_lines window_height
  local max_lines="$1"
  local window_height="$2"
  max_jump=$((max_lines - window_height))
  # max jump can't be lower than zero
  if [ "$max_jump" -lt "0" ]; then
    max_jump="0"
  fi
  echo "$max_jump"
}

# Goto line in scrollback buffer
fuzzback::goto_line() {
  local line_number="$1"
  tmux send-keys -X goto-line "$line_number"
}

# Center result on screen
# https://github.com/tmux-plugins/tmux-copycat/blob/e95528ebaeb6300d8620c8748a686b786056f374/scripts/copycat_jump.sh#L127
fuzzback::center() {
  local number_of_lines="$1"
  local maximum_padding="$2"
  local padding

  # Padding should not be greater than half pane height
  # (it wouldn't be centered then).
  if [ "$number_of_lines" -gt "$maximum_padding" ]; then
    padding="$maximum_padding"
  else
    padding="$number_of_lines"
  fi

  # cannot create padding, exit function
  if [ "$padding" -eq "0" ]; then
    return
  fi

  tmux send-keys -X -N "$padding" cursor-down
  tmux send-keys -X -N "$padding" cursor-up
}

fuzzback::get_line_number() {
  local position line_number
  position=$(echo "$1" | cut -d':' -f1 | tr -d '[:space:]')
  line_number=$((position - 1))
  echo "$line_number"
}

main() {

  local content match line_number window_height query max_lines max_jump
  local correction correct_line_number trimmed_line column

  content="$(tmux capture-pane -e -p -S -)"
  match=$(echo "$content" | tac | nl -b 'a' -s ':' | fuzzback::fzf_cmd)

  if [ -n "$match" ]; then

    query=$(echo "$match" | cut -d$'\n' -f1)
    rest=$(echo "$match" | cut -d$'\n' -f2)
    trimmed_line=$(echo "$rest" | sed 's/[[:space:]]\+[[:digit:]]\+://')
    line_number=$(fuzzback::get_line_number "$rest")
    window_height="$(tmux display-message -p '#{pane_height}')"
    max_lines=$(echo "$content" | wc -l)
    max_jump=$(fuzzback::get_max_jump "$max_lines" "$window_height")
    correction="0"
    column=$(fuzzback::query_column "$query" "$trimmed_line")

    # To go line
    # -----------------
    if [ "$line_number" -gt "$max_jump" ]; then
      # We need to reach a line number that is not accessible via goto-line.
      # So we need to correct position to reach the desired line number
      correct_line_number="$max_jump"
      correction=$((line_number - correct_line_number))
    else
      # we can reach the desired line number via goto-line. Correction not
      # needed.
      correct_line_number="$line_number"
    fi

    tmux copy-mode
    fuzzback::goto_line "$correct_line_number"

    # Correct if needed
    if [ "$correction" -gt "0" ]; then
      fuzzback::cursor_up "$correction"
    fi

    # Centering
    # -------------
    # If no corrections (meaning result is not at the top of scrollback)
    # we can then 'center' the result within a pane.
    if [ "$correction" -eq "0" ]; then
      local half_window_height="$((window_height / 2))"
      # creating as much padding as possible, up to half pane height
      fuzzback::center "$line_number" "$half_window_height"
    fi

    # Move to column
    # ------------------
    if [ "$column" -gt "0" ]; then
      tmux send-keys -X start-of-line
      tmux send-keys -X -N "$column" cursor-right
    fi

  fi
}

main
