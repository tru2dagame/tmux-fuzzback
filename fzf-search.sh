#!/usr/bin/env bash

set -uo pipefail
IFS=$'\n\t'

fzf_search::fzf_cmd() {
  fzf-tmux --delimiter=":" \
           --ansi \
           --with-nth="2.." \
           --no-sort \
           --no-preview \
           --print-query
}

# "manually" go up in the scrollback for a number of lines
# https://github.com/tmux-plugins/tmux-copycat/blob/e95528ebaeb6300d8620c8748a686b786056f374/scripts/copycat_jump.sh#L121
fzf_search::manually_go_up() {
  local line_number
  line_number="$1"
  tmux send-keys -X -N "$line_number" cursor-up
  tmux send-keys -X start-of-line
}

fzf_search::get_query_line_position() {
  local query="$1"
  local result_line="$2"
  local column zero_index

  column=$(echo "$result_line" | ag --column "$query" | cut -d':' -f1)
  zero_index=$((column - 1))
  echo "$zero_index"
}

# maximum line number that can be reached via tmux 'jump'
# https://github.com/tmux-plugins/tmux-copycat/blob/e95528ebaeb6300d8620c8748a686b786056f374/scripts/copycat_jump.sh#L159
fzf_search::get_max_jump() {
  local max_jump scrollback_line_number window_height
  local scrollback_line_number="$1"
  local window_height="$2"
  max_jump=$((scrollback_line_number - $window_height))
  # max jump can't be lower than zero
  if [ "$max_jump" -lt "0" ]; then
    max_jump="0"
  fi
  echo "$max_jump"
}

# performs a jump to go to line
# https://github.com/tmux-plugins/tmux-copycat/blob/e95528ebaeb6300d8620c8748a686b786056f374/scripts/copycat_jump.sh#L150
fzf_search::go_to_line_with_jump() {
  local line_number="$1"
  # tmux send-keys -X history-bottom
  tmux send-keys -X start-of-line
  tmux send-keys -X goto-line "$line_number"
}

# https://github.com/tmux-plugins/tmux-copycat/blob/e95528ebaeb6300d8620c8748a686b786056f374/scripts/copycat_jump.sh#L127
fzf_search::create_padding_below_result() {
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

fzf_search::get_line_number() {
  local position line_number
  position=$(echo "$1" | cut -d':' -f1 | tr -d '[:space:]')
  line_number=$((position - 1))
  echo "$line_number"
}

main() {

  local content match line_number window_height query max_lines
  max_jump correction correct_line_number trimmed_line query_line_position

  content="$(tmux capture-pane -e -p -S -)"
  match=$(echo "$content" | tac | nl -b 'a' -s ':' | fzf_search::fzf_cmd)

  if [ -n "$match" ]; then

    query=$(echo "$match" | cut -d$'\n' -f1)
    rest=$(echo "$match" | cut -d$'\n' -f2)
    trimmed_line=$(echo "$rest" | sed 's/[[:space:]]\+[[:digit:]]\+://')
    line_number=$(fzf_search::get_line_number "$rest")
    window_height="$(tmux display-message -p '#{pane_height}')"
    max_lines=$(echo "$content" | wc -l)
    max_jump=$(fzf_search::get_max_jump "$max_lines" "$window_height")
    correction="0"
    query_line_position=$(fzf_search::get_query_line_position "$query" "$trimmed_line")

    # Jump vertically
    # -----------------
    if [ "$line_number" -gt "$max_jump" ]; then
      # We need to 'reach' a line number that is not accessible via 'jump'.
      # Introducing 'correction'
      correct_line_number="$max_jump"
      correction=$((line_number - "$correct_line_number"))
    else
      # we can reach the desired line number via 'jump'. Correction not needed.
      correct_line_number="$line_number"
    fi

    tmux copy-mode
    fzf_search::go_to_line_with_jump "$correct_line_number"

    if [ "$correction" -gt "0" ]; then
      fzf_search::manually_go_up "$correction"
    fi

    # Padding
    # -------------
    # If no corrections (meaning result is not at the top of scrollback)
    # we can then 'center' the result within a pane.
    if [ "$correction" -eq "0" ]; then
      local half_window_height="$((window_height / 2))"
      # creating as much padding as possible, up to half pane height
      fzf_search::create_padding_below_result "$line_number" "$half_window_height"
    fi

    # Jump horizontally
    # ------------------
    if [ "$query_line_position" -gt "0" ]; then
      tmux send-keys -X -N "$query_line_position" cursor-right
    fi

  fi
}

main
