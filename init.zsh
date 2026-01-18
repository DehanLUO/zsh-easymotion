#!/usr/bin/env zsh

################################################################################
# @brief  Applies syntax highlighting to EasyMotion jump markers in the buffer.
#
# This function configures visual highlighting for EasyMotion jump markers,
# dimming the background text and applying colour-coded highlights to jump keys
# based on their type (single-key vs. multi-key).
#
# Highlighting strategy:
#   - Entire buffer dimmed to de-emphasise non-target text
#   - Single-character jump keys: primary colour (default: bold red)
#   - Multi-character jump keys:
#       - First character: secondary colour (default: bold orange)
#       - Subsequent characters: tertiary colour (default: bold dark brown)
#
# Colours and styles are configurable via zstyle for custom theming.
#
# @param[in] _buffer Original buffer content for calculating positions.
# @param[in] _key_sequences Already typed key sequence for multi-key jumps.
# @param[in] _arr_keymaps Array of keymap entries in "key\0index" format.
# @return Modifies region_highlight array directly; no explicit return value.
################################################################################
function _zsh_easymotion_apply_highlights() {
  local _buffer="$1"; shift
  local _key_sequences="$1"; shift
  local -a _arr_keymaps=($@)

  # Fetch colour/style settings via zstyle, with sensible defaults.
  local _fg_primary _fg_secondary _fg_tertiary _fg_dim
  # Default: red for primary keys
  zstyle -s ':zsh-easymotion:*' fg-primary _fg_primary \
    || _fg_primary='fg=196,bold' 
  # Default: orange for secondary keys
  zstyle -s ':zsh-easymotion:*' fg-secondary _fg_secondary \
    || _fg_secondary='fg=208,bold' 
  # Default: dark brown for tertiary character in multi-char keys
  zstyle -s ':zsh-easymotion:*' fg-tertiary _fg_tertiary \
    || _fg_tertiary='fg=94,bold'
  # Default: dim background
  zstyle -s ':zsh-easymotion:*' fg-dim _fg_dim \
    || _fg_dim='fg=black,bold'

  # Dim entire buffer as background
  region_highlight=("0 $#_buffer $_fg_dim")

  local -a _primary_highlights _secondary_highlights

  local _item
  for _item in $@; do
    # Extract index from "key\0index" format
    local _idx=${_item#*$'\0'} # Remove everything before first null byte

    # Extract jump key from "key\0index" format and remove already-typed prefix
    # 1. ${_item%$'\0'*}: Remove everything after null byte, leaving "key"
    # 2. ${...#$_key_sequences}: Remove already-typed key sequence prefix
    local _key=${${_item%$'\0'*}#$_key_sequences}

    # Calculate end position for replacement
    local _end_idx=$(( _idx + $#_key - 1 ))

    if (( 1 == $#_key )); then
      # Single-character keys: highlight with primary colour
      _primary_highlights+=("$(( _idx - 1 )) $_idx $_fg_primary")
    else
      # Multi-character keys: first character secondary, rest tertiary
      _secondary_highlights+=("$(( _idx - 1 )) $_idx $_fg_secondary")
      _secondary_highlights+=("$_idx $(( _idx + 1 )) $_fg_tertiary")
    fi
  done

  # Apply all highlights to region_highlight array
  region_highlight+=(${_primary_highlights[@]} ${_secondary_highlights[@]})
}

################################################################################
# @brief  Applies EasyMotion visual replacements to the editing buffer.
#
# This function modifies the ZLE buffer to display EasyMotion visual markers
# (jump keys) over the corresponding target positions. It restores the original
# buffer content first, then iteratively replaces character sequences at target
# positions with their assigned jump keys.
#
# The keymap array contains entries in the format "key\0index", where:
#   - key: The jump key or key sequence to display
#   - index: 1-based position in the buffer to replace
#
# @param[in] _buffer Original buffer content to restore and modify.
# @param[in] _key_sequences Already typed key sequence for multi-key jumps.
# @param[in] _arr_keymaps Array of keymap entries in "key\0index" format.
# @return Modifies BUFFER directly; no explicit return value.
################################################################################
function _zsh_easymotion_apply_replacements() {
  local _buffer="$1"; shift
  local _key_sequences="$1"; shift
  local -a _arr_keymaps=($@)

  # Restore original buffer state first
  BUFFER=$_buffer

  local _item
  for _item in $@; do
    # Extract index from "key\0index" format
    local _idx=${_item#*$'\0'} # Remove everything before first null byte

    # Extract jump key from "key\0index" format and remove already-typed prefix
    # 1. ${_item%$'\0'*}: Remove everything after null byte, leaving "key"
    # 2. ${...#$_key_sequences}: Remove already-typed key sequence prefix
    local _key=${${_item%$'\0'*}#$_key_sequences}

    # Calculate end position for replacement
    local _end_idx=$(( _idx + $#_key - 1 ))

    # Replace characters in buffer with jump key
    BUFFER[$_idx,$_end_idx]="${(s..)_key}"
  done
}

################################################################################
# @brief  Generates EasyMotion jump keys based on target count and available
#         keys.
#
# This function dynamically generates a sequence of jump keys for EasyMotion
# operations. Given a number of target positions and a set of available keys, it
# determines an optimal distribution between single keys and two-key
# combinations (prefix + suffix) to uniquely identify all targets.
#
# The algorithm follows these principles:
# 1. Calculate minimum prefix count (P) needed to cover target count
# 2. Reserve the last P keys from the source set as prefixes
# 3. Use remaining (K-P) keys as single keys (most efficient)
# 4. For each reserved prefix, generate K two-key combinations
# 5. Output keys in order: single keys, then prefix-generated keys
#
# Capacity calculation:
#   - Single keys: K - P
#   - Two-key combinations: P × K
#   - Total capacity: (K - P) + P × K = K + P × (K - 1)
#
# Example:
#   _keys = "abc" (K=3), target_count=6
#   Calculate P=2 (reserve "b" and "c" as prefixes)
#   Single keys: ["a"]
#   Two-key combos: ["ba","bb","bc","ca","cb","cc"]
#   Output (first 6): ["a","ba","bb","bc","ca","cb"]
#
# @param[in] _indices Space-separated position string (determines target count).
# @param[out] _var_output Variable to receive space-separated generated keys.
# @return Returns 0 on success, non-zero on failure (if target count exceeds K²).
################################################################################
function _zsh_easymotion_assign_keys() {
  local _indices="$1"; shift
  local _var_output="$1"

  # Edge case: no targets, return empty
  if [[ -z "$_indices" ]]; then
    $_fn_success
    return $?
  fi

  setopt localoptions extendedglob braceccl
  local _keys
  zstyle -s ':zsh-easymotion:*' keys _keys ||
    _keys=${(j..)$(print {a-z} \;)}

  # Step 1: Parse input 
  # Convert position string to array to determine target count
  local -a _arr_indices
  : ${(A)_arr_indices::=${(s. .)_indices}}
  local -i _count=$#_arr_indices

  # Edge case: no targets, return empty
  if (( 0 == _count )); then
    $_fn_success
    return $?
  fi

  # Split available keys into character array
  local -a _arr_keys
  : ${(A)_arr_keys::=${(s..)_keys}}
  local -i _sources=$#_arr_keys

  # Step 2: Calculate minimum prefix count (P)
  # Let K = total keys, P = reserved prefixes (from end of array)
  # Capacity = (K - P) + P × K = K + P × (K - 1)
  # Find minimum P (0 ≤ P ≤ K) such that capacity ≥ target_count

  # Maximum capacity = K × K (all keys as prefixes, no single keys)
  if (( _count > _sources * _sources )); then
    $_fn_failure
    return $?
  fi

  local -i _reserved=0
  while (( _reserved <= _sources )); do
    local -i _capacity=$(( (_sources - _reserved) \
      + _reserved * _sources ))
    if (( _capacity >= _count )); then
      break
    fi

    # Use prefix increment (++_reserved) instead of postfix (_reserved++).
    # Postfix increment returns the original value before incrementing. When
    # _reserved = 0, (( _reserved++ )) evaluates to 0, which in Zsh arithmetic
    # context is considered "false", causing the command to fail with exit
    # status 1.
    #
    # Test frameworks like ZUnit interpret non-zero exit status as test failure,
    # potentially skipping subsequent assertions and reporting generic errors.
    # Prefix increment returns the incremented value, avoiding this issue.
    (( ++_reserved ))
  done

  # Step 3: Build result array
  local -a _arr_result

  # 3.1 Add single keys: first (K - P) keys (not reserved as prefixes)
  local -i _singles=$(( _sources - _reserved ))
  if (( _singles > 0 )); then
    _arr_result+=("${_arr_keys[@]:0:$_singles}")
  fi

  # 3.2 Add two-key combinations: for each reserved prefix (from end of array)
  local -i _primer_idx=$(( _sources - _reserved + 1 ))
  local -i _prefix_idx _suffix_idx

  for (( _prefix_idx = _primer_idx; _prefix_idx <= _sources; _prefix_idx++ )); do
    local _current_prefix="${_arr_keys[_prefix_idx]}"
    for (( _suffix_idx = 1; _suffix_idx <= _sources; _suffix_idx++ )); do
      _arr_result+=("${_current_prefix}${_arr_keys[_suffix_idx]}")
    done
  done

  # Step 4: Truncate to actual target count
  _arr_result=("${_arr_result[@]:0:$_count}")

  # Step 5: Output as space-separated string
  : ${(P)_var_output::=${(j. .)_arr_result}}
}

################################################################################
# @brief  Finds word boundaries in a buffer and returns 1-based positions.
#
# This function identifies all word occurrences in a buffer (using vim-like word
# definition: sequences of alphanumeric characters and underscores) and returns
# either word-start or word-end positions as a space-separated string.
# The function supports two modes:
#   - "word": Returns 1-based starting positions of each word
#   - "end": Returns 1-based ending positions of each word
#
# The algorithm iteratively matches word patterns using POSIX extended regex,
# tracking cumulative offsets to maintain correct 1-based indexing throughout
# the buffer.
#
# Example: For buffer "abc abc abc"
#   - Mode "word": returns "1 5 9"
#   - Mode "end": returns "3 7 11"
#
# @param[in] _mode Output mode: "word" for start positions
#                               "end" for end positions.
# @param[in] _buffer Text buffer to analyze for word boundaries.
# @param[out] _ref_output Variable to receive space-separated positions.
# @return Returns 0 on successful completion.
################################################################################
function _zsh_easymotion_boundaries() {
  # Extract parameters.
  local _mode="$1"; shift
  local _buffer="$1"; shift
  local _ref_output="$1"

  local -a _word_indices _end_indices

  local _total_offset=0
  
  # Regex pattern matching vim-style words: sequences of alnum or underscore
  local pattern='[[:alnum:]_]+'

  # Iteratively find all word matches in the buffer
  while [[ "$_buffer" =~ $pattern ]]; do
    local _match="$MATCH"
    # Calculate 1-based position within current substring
    local _index=$(( ${#${_buffer%%$_match*}} + 1 ))
  
    # Convert to absolute 1-based position in original buffer
    local _word_index=$((_total_offset + _index))
    local _end_index=$((_word_index + ${#_match} - 1))

    _word_indices+=($_word_index)
    _end_indices+=($_end_index)

    # Update remaining buffer and cumulative offset
    local _cut_index=$((_index + ${#_match} - 1))
    _buffer="${_buffer:$_cut_index}"
    _total_offset=$((_total_offset + _cut_index))
  done

  # Output positions based on requested mode
  if [[ "word" == "$_mode" ]]; then
    : ${(P)_ref_output::=${(j. .)_word_indices}}
  else
    : ${(P)_ref_output::=${(j. .)_end_indices}}
  fi
}

################################################################################
# @brief  Builds a keymap array mapping jump keys to position indices.
#
# This function creates a keymap that associates each jump key with its
# corresponding position index. It generates jump keys from position indices,
# then creates an array where each element contains a key-index pair in the
# format "key\0index", suitable for efficient lookup during jump operations.
#
# The keymap is constructed by:
#   1. Generating jump keys from position indices using the key assignment
#      function
#   2. Replacing spaces between keys with null bytes followed by position
#      indices to create individual key-index pairs
#   3. Splitting the resulting string into an array of "key\0index" elements
#
# Array element format: "key\0index"
#
# Example:
#   Input suffixes: "1 2 3"
#   Generated prefixes: "a ba bb"
#   Intermediate: "a\01 ba\02 bb\03"
#   Output array: ("a\01" "ba\02" "bb\03")
#
# @param[in] _suffixes Space-separated position indices (1-based).
# @param[out] _var_output Variable to receive the keymap array.
# @return Returns 0 on success, non-zero if key generation fails.
################################################################################
function _zsh_easymotion_build_keymap() {
  # extended globbing within this scope
  setopt localoptions extendedglob

  local _suffixes="$1"; shift
  local _var_output="$1"; shift

  if [[ -z $_suffixes ]]; then
    $_fn_success
    return $?
  fi

  local _prefixes
  $_fn_assign_keys \
    "$_suffixes"    \
    "_prefixes" || {
      $_fn_failure
      return $?
    }

  local -a _arr_suffixes
  : ${(A)_arr_suffixes::=${(s. .)_suffixes}}

  local _idx=1
  local _null=$'\0'
  local _map
  # Replace spaces between keys with null byte + index + space
  # The pattern (#m)$'\ ' matches literal spaces in the prefixes string
  # Each matched space is replaced with \0 + corresponding index + space
  _map="${_prefixes//(#m)$' '/${_null}$_arr_suffixes[((_idx++))] }"
  # Append final null byte + index for the last key (which has no trailing space)
  _map+="${_null}$_arr_suffixes[_idx]"

  : ${(PA)_var_output::=${(s. .)_map}}
}

################################################################################
# @brief  Constructs a regular expression pattern based on case-matching mode.
#
# This function converts a single input character into a regex pattern
# according to the configured case-matching mode. It supports three modes:
#   - default: Literal matching with regex escaping
#   - ignorecase: Case-insensitive matching for alphabetic characters
#   - smartcase: Case-insensitive only for lowercase letters
#
# The resulting regex pattern is assigned to the specified output variable,
# suitable for use in buffer search operations.
#
# @param[in] _char Input character to convert to regex pattern.
# @param[out] _ref_output Name of variable to receive the regex pattern.
# @return Returns 0 on successful pattern construction.
################################################################################
function _zsh_easymotion_char2regex() {
  local _char="$1"; shift
  local _ref_output="$1"

  # Fetch case-matching mode via zstyle.
  local _case_mode
  zstyle -s ':zsh-easymotion:*' search-case _case_mode || _case_mode=default

  local _pattern
  # Case-insensitive: match both lower and upper forms.
  # Condition: mode is ignorecase AND input is an alphabetic character.
  if [[ "$_case_mode" == ignorecase && "$_char" == [[:lower:][:upper:]] ]]; then
    # Build regex character class with both cases.
    # (L) converts to lowercase, (U) converts to uppercase.
    _pattern="[${(L)_char}${(U)_char}]"
  # Smartcase: if input is lowercase, match both cases; else literal.
  # Condition: mode is smartcase AND input is a lowercase letter.
  elif [[ "$_case_mode" == smartcase && "$_char" == [[:lower:]] ]]; then
    # Build character class: original lowercase + escaped uppercase.
    # Lowercase letters match both lower and upper case versions.
    _pattern="[${_char}${(U)_char}]"
  # Default case: literal matching (no case folding).
  # This handles uppercase in smartcase mode, digits, symbols, etc.
  else
    # Escape any regex metacharacters in the input character.
    # (b) flag ensures characters like '[', ']', '.' are escaped as '\[', etc.
    _pattern="${(b)_char}"
  fi

  : ${(P)_ref_output::=$_pattern}
}

################################################################################
# @brief  Signals failure in a motion operation.
#
# This function indicates that a motion operation (e.g., a search or jump has
# failed, either because no match was found or the user cancelled the action. It
# returns a non-zero exit code, which in shell convention represents a boolean
# false.
#
# @return Returns 1 to signal failure.
################################################################################
function _zsh_easymotion_failure() {
  # Return 1 to indicate failure (non-zero for boolean false in shell).
  return 1
}

################################################################################
# @brief  Handles the interactive EasyMotion jump selection and execution.
#
# This function orchestrates the complete EasyMotion jump workflow:
# 1. Direct jump if only one target exists
# 2. Visual replacement of targets with jump keys
# 3. Syntax highlighting of jump markers
# 4. ZLE redraw to display changes
# 5. User input collection for jump selection
# 6. Recursive filtering or final cursor movement
#
# The function implements a stateful interaction where each keystroke
# filters available jump targets, allowing for multi-key jump sequences.
#
# @param[in] _buffer Original buffer content for visual restoration.
# @param[in] _key_sequences Keys already typed in this jump session.
# @param[in] _arr_keymaps Array of keymap entries in "key\0index" format.
# @return Returns 0 on successful jump, non-zero on failure/cancellation.
################################################################################
function _zsh_easymotion_handle_jump() {
  local _buffer="$1"; shift # Current screen buffer content
  local _key_sequences="$1"; shift # User-typed key sequence so far
  local -a _arr_keymaps=($@) # Array elements: "key\0index"

  if (( 0 == $#_arr_keymaps )); then
    $_fn_failure
    return $?
  # Direct jump if only one target remains
  elif (( 1 == $#_arr_keymaps )); then
    $_fn_move_cursor ${_arr_keymaps[1]#*$'\0'}
    return $?
  fi

  # Apply visual replacements (show jump keys in buffer)
  $_fn_apply_replacement \
    "$_buffer"           \
    "$_key_sequences"    \
    ${_arr_keymaps}

  # Localising region_highlight ensures cleanup when function exits
  local region_highlight
  # Apply syntax highlighting to jump markers
  $_fn_apply_highlights \
    "$_buffer"          \
    "$_key_sequences"   \
    ${_arr_keymaps}

# TODO: Optimisation opportunity - combine _fn_apply_replacement and
#       _fn_apply_highlights logic for efficiency improvement

  # Redraw ZLE with updated buffer and highlights
  zle -R

  local _input # Prompt user for next key in jump sequence
  if $_fn_prompt_jump _input; then
    # Recursively filter targets starting with the extended key sequence
    $_fn_handle_jump \
      "$_buffer" \
      "$_key_sequences$_input" \
      ${(M)_arr_keymaps:#$_key_sequences$_input*} # Keep only matching prefixes
    return $?
  else
    $_fn_failure
    return $?
  fi
}

################################################################################
# @brief  Main entry point for EasyMotion motion operations.
#
# This function serves as the primary orchestrator for EasyMotion operations,
# executing the complete workflow from target identification to cursor jump.
# It coordinates the three-phase process:
#   1. Generate position indices based on the selected motion mode
#   2. Build keymap associating jump keys with position indices
#   3. Initiate interactive jump selection process
#
# The function handles different motion modes (search, word, end) through
# delegation to specialised functions, providing a unified interface for all
# EasyMotion operations.
#
# @param[in] _mode Motion mode: "search", "word", or "end".
# @param[in] _buffer Text buffer to operate on (typically $BUFFER).
# @return Returns 0 on successful jump, non-zero on failure or cancellation.
################################################################################
function _zsh_easymotion_invoke() {
  local _mode="$1"; shift
  local _buffer="$1"; shift

  # Phase 1: Generate position indices for motion targets
  local _indices
  $_fn_jump_indices \
    "$_mode"        \
    "$_buffer"      \
    "_indices" || {
      $_fn_failure
      return $?
    }
  
  # Phase 2: Build keymap linking jump keys to position indices
  local -a _arr_keymaps
  $_fn_build_keymap \
    "$_indices"     \
    "_arr_keymaps" || {
      $_fn_failure
      return $?
    }

  # Phase 3: Initiate interactive jump selection and execution
  $_fn_handle_jump \
    "$_buffer"     \
    ""             \
    ${_arr_keymaps} || {
      $_fn_failure
      return $?
    }
}

################################################################################
# @brief  Validates whether a string consists of a single printable character.
#
# This function checks if the given string contains exactly one printable
# character as defined by POSIX character classes. It returns success (0) for
# valid printable characters and failure (1) for all other inputs.
#
# The validation is used to ensure search inputs are suitable for buffer
# scanning and highlighting operations within motion functions.
#
# @param[in] _str The string to validate as a printable character.
# @return Returns 0 if the string is a single printable character, 1 otherwise.
################################################################################
function _zsh_easymotion_isprintable() {
  local _str="$1"

  [[ 1 -eq ${#_str} && "$_str" == [[:print:]] ]]
}

################################################################################
# @brief  Generates indices for EasyMotion jumps based on operation mode.
#
# This function acts as the main dispatcher for generating position indices
# used by EasyMotion jump operations. It supports multiple modes:
#   - "word": Returns start positions of words (alnum + underscore sequences)
#   - "end": Returns end positions of words
#   - "search": Prompts for a search character and returns its occurrence
#               positions
#
# For search mode, the function performs the complete workflow:
#   1. Prompts user for a search character
#   2. Validates it's a printable character
#   3. Converts character to regex pattern based on case-sensitivity settings
#   4. Finds all occurrences in the buffer
#
# The output is a space-separated string of 1-based position indices suitable
# for ZLE cursor positioning.
#
# @param[in] _mode Operation mode: "word", "end", or "search".
# @param[in] _buffer Text buffer to analyze.
# @param[out] _ref_output Variable to receive space-separated position indices.
# @return Returns 0 on success, non-zero on failure (e.g., invalid input).
################################################################################
function _zsh_easymotion_jump_indices() {
  local _mode="$1"; shift
  local _buffer="$1"; shift
  local _ref_output="$1"

  if [[ "search" != $_mode ]]; then
    # Word/end mode: directly call boundaries function
    $_fn_boundaries \
      "$_mode"      \
      "$_buffer"    \
      "$_ref_output"

    return $?
  fi

  # Search mode: full interactive workflow
  local _char
  $_fn_prompt_search "_char" || {
    $_fn_failure
    return $?
  }
  
  $_fn_isprintable "$_char" || {
    $_fn_failure
    return $?
  }

  local _regex
  $_fn_char2regex \
    "$_char"      \
    "_regex"

  $_fn_match_indices \
    "$_regex"        \
    "$_buffer"       \
    "$_ref_output"

  $_fn_success
  return $?
}

################################################################################
# @brief  Finds all pattern matches in a buffer and returns 1-based positions.
#
# This function identifies all occurrences of a regex pattern within a buffer
# and outputs their 1-based character indices as a space-separated string. It
# uses zsh extended globbing with pattern substitution and null-byte delimiters
# to efficiently extract match positions.
#
# The algorithm works by:
# 1. Replacing each pattern match with a unique marker containing its position
# 2. Splitting the modified buffer on null bytes to isolate markers
# 3. Filtering and extracting position numbers from markers
# 4. Joining positions with spaces for output
#
# Example: For buffer "a/b/c" and pattern "/", returns "2 4"
#
# @param[in] _pattern Regex pattern to search for in the buffer.
# @param[in] _buffer Text buffer to search within.
# @param[out] _ref_output Variable to receive space-separated positions.
# @return Returns 0 on successful extraction.
################################################################################
function _zsh_easymotion_match_indices() {
  # Enable safe array indexing (1-based) and extended globbing within this scope.
  setopt localoptions no_ksharrays no_kshzerosubscript extendedglob

  # Extract parameters.
  local _pattern="$1"; shift
  local _buffer="$1"; shift
  local _ref_output="$1"

  # Define a null byte for internal delimiting.
  local _null_char=$'\0'
  # Define a unique escape sequence unlikely to appear in normal text.
  local _escape_ok=$'\e\e '
  # Define a glob pattern matching the escape sequence followed by digits.
  local _escape_pattern=$'\e\e [[:digit:]]##(#e)'

  local -a _result

  # Core algorithm explanation:
  # ---------------------------
  # Example: _buffer="a/b/c", _pattern="/"
  # Step 1: Replace matches with position markers
  #   - First '/' at position 2 → replaced with "\e\e 2\0"
  #   - Second '/' at position 4 → replaced with "\e\e 4\0"
  #   Result: "a\e\e 2\0b\e\e 4\0c"
  #
  # Step 2: Split on null bytes
  #   - ${(0)...} splits at \0, giving: ["a\e\e 2", "b\e\e 4", "c"]
  #
  # Step 3: Filter and extract positions
  #   - (M) flag keeps only elements matching _escape_pattern
  #   - ${#${_escape_ok}} removes the "\e\e " prefix
  #   Result: ["2", "4"]
  
  # Perform pattern substitution with position capture.
  # ${(S)_buffer//*(#b)($~_pattern)/${_escape_ok}$mbegin[1]$_null_char}:
  #   - (S): Shortest match (non-greedy) to find each pattern instance
  #   - //: Global substitution operator
  #   - *: Match any preceding characters (ensures we find all instances)
  #   - (#b): Enable backreferences for capturing match information
  #   - ($~_pattern): Expand _pattern as a regex and capture it
  #   - $mbegin[1]: 1-based position of the first character in capture group 1
  #   - ${_escape_ok}$mbegin[1]$_null_char: Replacement with marker
  # ${(0)...}: Split the result into array elements on null bytes
  _result=(
    ${(0)${(S)_buffer//*(#b)($~_pattern)/${_escape_ok}$mbegin[1]$_null_char}}
  )

  # Filter array to keep only elements containing position markers and extract
  # the position numbers.
  # ${(M)_result:#${~_escape_pattern}}:
  #   - (M): Keep (Match) elements that match the pattern (reverse of #)
  #   - :#: Operator for removing matching elements (but (M) reverses it)
  #   - ${~_escape_pattern}: Expand _escape_pattern as a glob pattern
  #   - Pattern matches "\e\e " followed by digits at end of string ((#e))
  # ${...#${_escape_ok}}: Remove the "\e\e " prefix from each element
  _result=( 
    ${${(M)_result:#${~_escape_pattern}}#${_escape_ok}}
  )

  # Join positions with spaces and assign to output variable.
  # ${(j. .)_result}: Join array elements with space delimiter
  # ${(P)_ref_output::=...}: Indirect assignment to named variable
  : ${(P)_ref_output::=${(j. .)_result}}
}

################################################################################
# @brief  Sets the CURSOR variable with 1-based to 0-based index conversion.
#
# This function is designed to be called within zle widgets. It converts the
# given 1-based position (zsh convention) to 0-based (zle convention) and
# assigns the result to the calling context's CURSOR variable.
#
# CURSOR is a special zsh ZLE (Zsh Line Editor) variable that determines the
# cursor position within the current editing buffer. When modified, the cursor
# movement takes effect immediately in the ZLE context.
#
# @param[in] $1 The desired cursor position using 1-based indexing.
#
# @return  Returns 0 to indicate the assignment was performed.
################################################################################
function _zsh_easymotion_move_cursor() {
  (( CURSOR = $1 - 1 )) || $_fn_success
}

################################################################################
# @brief  Prompts the user to input a jump key for target selection.
#
# This function displays a prompt asking the user to press a key (or key
# combination) corresponding to the desired jump target. The prompt text is
# configurable via zstyle, with a default green-coloured prompt.
#
# The function delegates the actual character reading to the low-level query
# function, optionally applying the newline workaround for display refresh when
# needed.
#
# @param[out] _ref_output Variable to store the user's key input.
# @param[in] _add_newline Optional flag to force newline workaround.
# @return Returns exit status from the underlying query function.
################################################################################
function _zsh_easymotion_prompt_jump() {
  local _ref_output="$1"; shift
  local _add_newline="${1-}"

  # Fetch customisable prompt string via zstyle; default if not set.
  local _prompt 
  zstyle -s ':zsh-easymotion:*' prompt-key _prompt ||
    _prompt='%{\e[1;32m%}Target key:%{\e[0m%} '

  # Delegate to low-level reader.
  $_fn_query_char \
    $_ref_output  \
    $_prompt      \
    $_add_newline
}

################################################################################
# @brief  Prompts the user to input a character for search operations.
#
# This function displays a prompt asking the user to input a single character
# that will be used as the search pattern. The prompt text is configurable via
# zstyle, with a default green-coloured prompt.
#
# The function delegates the actual character reading to the low-level query
# function, optionally applying the newline workaround for display refresh when
# needed.
#
# @param[out] _ref_output Variable to store the user's character input.
# @param[in] _add_newline Optional flag to force newline workaround.
# @return Returns exit status from the underlying query function.
################################################################################
function _zsh_easymotion_prompt_search() {
  local _ref_output="$1"; shift
  local _add_newline="${1-}"

  local _prompt
  zstyle -s ':zsh-easymotion:*' prompt-char _prompt ||
    _prompt='%{\e[1;32m%}Search for character:%{\e[0m%} '

  $_fn_query_char \
    $_ref_output  \
    $_prompt      \
    $_add_newline
}

################################################################################
# @brief  Displays a prompt and reads a single character with UI handling.
#
# This function provides a user interface for reading a single character while
# displaying a prompt. It handles terminal redraw edge cases when POSTDISPLAY
# lacks a newline, ensuring the prompt is properly refreshed.
#
# The function saves and restores cursor position, displays the prompt on a new
# line, reads a single character without echoing, then cleans up the display and
# returns the read status.
#
# @param[out] _ref_output Name of the variable to store the read character.
# @param[in] _prompt Prompt string to display to the user.
# @param[in] _add_newline Optional flag 'true' to force redraw workaround.
# @return Returns the exit status of the character reading function.
################################################################################
function _zsh_easymotion_query_char() {
  zmodload zsh/terminfo 2>/dev/null

  local _ref_output="$1"; shift
  local _prompt="$1"; shift 
  local _add_newline="${1-}"
  # TODO: add_newline parameter should ideally be sourced from a global state
  # or configuration to ensure the first invocation always triggers the newline
  # workaround logic, which is crucial for proper ZLE display refresh.

  # Handle ZLE redraw edge case when POSTDISPLAY lacks newline. Without a
  # newline, ZLE may not fully redraw the prompt. The workaround forces terminal
  # desynchronisation to trigger redraw.
  if [[ "$_add_newline" == "true" ]] &&
     { [[ -z "${POSTDISPLAY-}" ]] || [[ "${POSTDISPLAY-}" != *$'\n'* ]]; }; then
    echoti cud1
    echoti cuu1
    zle reset-prompt
  fi

  echoti sc                 # Save cursor position
  echoti cud 1              # Move to next line for prompt display
  echoti hpa 0 2>/dev/null || echo -n $'\x1b[1G'  # Move to column 0
  echoti el                 # Clear to end of line
  print -Pn "$_prompt"      # Display prompt without newline
  
  $_fn_readkey $_ref_output # Read single character without echo
  local _ret=$?             # Capture read exit status
  
  echoti hpa 0 2>/dev/null || echo -n $'\x1b[1G'  # Move to column 0
  echoti el                 # Clear the prompt line
  echoti rc                 # Restore original cursor position
  return $_ret              # Return read status
}

################################################################################
# @brief  Reads a single character from user input without echoing.
#
# This function reads exactly one character from standard input without
# displaying it on the screen. It uses a non-blocking read with no line
# buffering, making it suitable for interactive key handling in zle widgets.
#
# The character read is stored in the variable named by the caller. This allows
# the result to be captured and used in the calling context.
#
# @param[out] $_var_output Name of the variable to store the read character.
# @return  Returns the exit status of the internal `read` command.
################################################################################
function _zsh_easymotion_readkey() {
  local _var_output="$1"
  read -s -k 1 $_var_output
  return $?
}

################################################################################
# @brief  Signals successful completion of a motion operation.
#
# This function indicates that a motion operation (e.g., a search or jump)
# has completed successfully. It returns a zero exit code, which in shell
# convention represents a boolean true, confirming the operation's success.
#
# @return Returns 0 to signal success.
################################################################################
function _zsh_easymotion_success() {
  # Return 0 to indicate success (zero for boolean true in shell).
  return 0
}

################################################################################
# @brief  Main ZLE widget entry point for EasyMotion operations.
#
# This function serves as the primary ZLE (Zsh Line Editor) widget for all
# EasyMotion operations. It initialises the function dispatch environment, backs
# up editor state, executes the motion operation, and ensures proper cleanup
# regardless of success or failure.
#
# Key responsibilities:
# 1. Initialise function dispatch variables for modular testing
# 2. Backup original buffer content and cursor position
# 3. Move cursor to end of buffer for full visibility of motion targets
# 4. Invoke the main EasyMotion workflow
# 5. Restore original buffer and refresh display in all cases
#
# The 'always' block ensures proper cleanup even if the motion operation fails
# or is cancelled by the user.
#
# @param[in] _mode Motion mode: "search", "word", or "end".
# @return Modifies BUFFER and CURSOR; returns exit status from motion operation.
################################################################################
function _zsh_easymotion_widget() {
  local _mode="$1"; shift

  # Initialise function dispatch variables for modular testing. Using _fn_xxx
  # variables enables test suites to replace individual function references with
  # mock implementations, allowing isolated unit testing of each component
  # without ZLE dependencies.
  local _fn_apply_highlights=_zsh_easymotion_apply_highlights
  local _fn_apply_replacement=_zsh_easymotion_apply_replacements
  local _fn_assign_keys=_zsh_easymotion_assign_keys
  local _fn_boundaries=_zsh_easymotion_boundaries
  local _fn_build_keymap=_zsh_easymotion_build_keymap
  local _fn_char2regex=_zsh_easymotion_char2regex
  local _fn_failure=_zsh_easymotion_failure
  local _fn_handle_jump=_zsh_easymotion_handle_jump
  local _fn_invoke=_zsh_easymotion_invoke
  local _fn_isprintable=_zsh_easymotion_isprintable
  local _fn_jump_indices=_zsh_easymotion_jump_indices
  local _fn_match_indices=_zsh_easymotion_match_indices
  local _fn_move_cursor=_zsh_easymotion_move_cursor
  local _fn_prompt_jump=_zsh_easymotion_prompt_jump
  local _fn_prompt_search=_zsh_easymotion_prompt_search
  local _fn_query_char=_zsh_easymotion_query_char
  local _fn_readkey=_zsh_easymotion_readkey
  local _fn_success=_zsh_easymotion_success

  # Backup original editor state
  local _orig_buffer="$BUFFER"
  local _orig_cursor="$CURSOR"

  # Move cursor to end of buffer for full visibility of motion targets
  (( CURSOR = $#BUFFER ))
  zle -R

  {
    # Execute the main EasyMotion workflow
    $_fn_invoke       \
      "$_mode"        \
      "$_orig_buffer" \
      || (( CURSOR = _orig_cursor )) # Restore cursor on failure
  } always {
    # Always restore original buffer content
    BUFFER="$_orig_buffer"
    # Refresh and reprocess the entire command line
    zle redisplay
  }
}

################################################################################
# Public ZLE widget: activate easymotion.
################################################################################
zsh-easymotion-word() {
  _zsh_easymotion_widget "word"
}

zsh-easymotion-end() {
  _zsh_easymotion_widget "end"
}

zsh-easymotion-search() {
  _zsh_easymotion_widget "search"
}

# Register ZLE widget so it can be bound to keys.
zle -N zsh-easymotion-word
zle -N zsh-easymotion-end
zle -N zsh-easymotion-search

# Bind to Ctrl-X / in all major keymaps (emacs, vicmd, viins).
bindkey -M emacs '^Xw' zsh-easymotion-word
bindkey -M vicmd '^Xw' zsh-easymotion-word
bindkey -M viins '^Xw' zsh-easymotion-word
bindkey -M emacs '^Xe' zsh-easymotion-end
bindkey -M vicmd '^Xe' zsh-easymotion-end
bindkey -M viins '^Xe' zsh-easymotion-end
bindkey -M emacs '^Xf' zsh-easymotion-search
bindkey -M vicmd '^Xf' zsh-easymotion-search
bindkey -M viins '^Xf' zsh-easymotion-search
