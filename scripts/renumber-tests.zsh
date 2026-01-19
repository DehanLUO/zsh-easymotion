#!/usr/bin/env zsh

# This script automatically updates test numbering in Zunit test files
# It adds/maintains # N comments above each @test block, starting from 1

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <zunit-test-file> [<zunit-test-file> ...]"
    exit 1
fi

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "Error: File '$file' not found" >&2
    continue
  fi

  echo "Processing: $file"

  # Create a temporary file
  local tempfile="${file}.tmp.$$"

  # Read file line by line
  local line='' test_count=0 in_test_block=0
  local -a buffer=()

  while IFS= read -r line; do
    if [[ "$line" =~ ^@test ]]; then
      # Found a test block
      ((++test_count))

      # Check if previous line is already a test number comment
      if [[ ${#buffer[@]} -gt 0 && "${buffer[-1]}" =~ ^#[[:space:]]*[0-9]+ ]]; then
        # Replace existing number
        buffer[-1]="# $test_count"
      else
        # Add new number comment
        buffer+=("# $test_count")
      fi

      # Add the test line
      buffer+=("$line")
      in_test_block=1
    elif [[ "$line" =~ ^# && $in_test_block -eq 0 ]]; then
      # Preserve other comments outside test blocks
      buffer+=("$line")
    elif [[ -z "$line" && $in_test_block -eq 0 ]]; then
      # Preserve empty lines outside test blocks
      buffer+=("$line")
    elif [[ "$line" =~ ^[[:space:]]*\} && $in_test_block -eq 1 ]]; then
      # End of test block
      buffer+=("$line")
      in_test_block=0
    elif [[ $in_test_block -eq 1 ]]; then
      # Inside test block, preserve all lines
      buffer+=("$line")
    else
      # Outside test blocks, preserve other content
      buffer+=("$line")
    fi
  done < "$file"

  # Write to temporary file
  printf "%s\n" "${buffer[@]}" > "$tempfile"

  # Replace original file
  mv "$tempfile" "$file"

  echo "  Updated $test_count test(s)"
done

echo "Done."
