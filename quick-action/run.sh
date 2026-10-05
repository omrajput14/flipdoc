#!/bin/zsh
# Called by the Finder Quick Action with the selected PDFs as arguments.
# Automator runs with a minimal PATH, so add the usual uv install locations.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
project="${0:A:h:h}"
for f in "$@"; do
  if msg=$(uv run --project "$project" flipdoc tables "$f" 2>&1); then
    osascript -e "display notification \"${msg//\"/}\" with title \"Flipdoc\""
  else
    osascript -e "display notification \"Failed: ${f:t}\" with title \"Flipdoc\""
  fi
done
