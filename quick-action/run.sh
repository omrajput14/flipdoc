#!/bin/zsh
# Paste into Automator > Quick Action (Files: PDF files, Finder) > Run Shell Script, "Pass input: as arguments".
for f in "$@"; do
  /Users/0mrajput/.local/bin/uv run --project /Users/0mrajput/Desktop/flipdoc flipdoc tables "$f"
done
osascript -e 'display notification "Done" with title "Flipdoc"'
