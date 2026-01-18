#!/usr/bin/env zsh

################################################################################
# FUNCTION: _zsh_easymotion_failure
#
# PURPOSE: Standardised failure signalling for motion operations.
#
# INPUTS: None
#
# OUTPUTS: Returns 1 (non-zero exit status)
#
# LOGIC:
#   - Return 1 to indicate operation failure
#   - Used consistently across all functions for error handling
################################################################################
function _zsh_easymotion_failure() {
  # PSEUDOCODE
  return 1
}

################################################################################
# FUNCTION: _zsh_easymotion_success
#
# PURPOSE: Standardised success signalling for motion operations.
#
# INPUTS: None
#
# OUTPUTS: Returns 0 (zero exit status)
#
# LOGIC:
#   - Return 0 to indicate operation success
#   - Used for consistent boolean returns
################################################################################
function _zsh_easymotion_success() {
  # PSEUDOCODE
  return 0
}

################################################################################
# FUNCTION: _zsh_easymotion_move_cursor
#
# PURPOSE: Sets cursor position with 1-based to 0-based conversion.
#
# INPUTS:
#   position: Desired cursor position (1-based indexing)
#
# OUTPUTS:
#   Modifies CURSOR variable directly
#
# LOGIC:
#   1. Convert 1-based position to 0-based: CURSOR = position - 1
#   2. Update CURSOR variable (global ZLE variable)
################################################################################
function _zsh_easymotion_move_cursor(position) {
  # PSEUDOCODE
  CURSOR = position - 1
  return success
}

################################################################################
# FUNCTION: _zsh_easymotion_prompt_search
#
# PURPOSE: Prompts user for a search character.
#
# INPUTS:
#   output_var: Name of variable to store user input
#   add_newline: Optional flag for display workaround
#
# OUTPUTS:
#   Sets output_var to user's character input
#   Returns success/failure status
#
# LOGIC:
#   1. Get prompt text from configuration
#   2. Delegate to generic query_char() function
#   3. Store result in output variable
################################################################################
function _zsh_easymotion_prompt_search(output_var, add_newline="") {
  # PSEUDOCODE
  prompt = get_config("prompt-char", "Search for character: ")
  character = query_char(prompt, add_newline)
  
  if operation_failed:
    return failure
  
  set_variable(output_var, character)
  return success
}

################################################################################
# FUNCTION: _zsh_easymotion_prompt_jump
#
# PURPOSE: Prompts user for a jump key selection.
#
# INPUTS:
#   output_var: Name of variable to store user input
#   add_newline: Optional flag for display workaround
#
# OUTPUTS:
#   Sets output_var to user's key input
#   Returns success/failure status
#
# LOGIC:
#   1. Get prompt text from configuration
#   2. Delegate to generic query_char() function
#   3. Store result in output variable
################################################################################
function _zsh_easymotion_prompt_jump(output_var, add_newline="") {
  # PSEUDOCODE
  prompt = get_config("prompt-key", "Target key: ")
  key = query_char(prompt, add_newline)
  
  if operation_failed:
    return failure
  
  set_variable(output_var, key)
  return success
}

################################################################################
# FUNCTION: _zsh_easymotion_query_char
#
# PURPOSE: Generic character input with prompt display and cursor management.
#
# INPUTS:
#   output_var: Name of variable to store input
#   prompt: Text to display to user
#   add_newline: Flag to force display workaround
#
# OUTPUTS:
#   Sets output_var to user's character input
#   Returns success/failure status
#
# LOGIC:
#   1. Handle display refresh edge cases
#   2. Save cursor position
#   3. Move to new line, display prompt
#   4. Read single character without echo
#   5. Clear prompt line, restore cursor
#   6. Store result in output variable
################################################################################
function _zsh_easymotion_query_char(output_var, prompt, add_newline) {
  # PSEUDOCODE
  # Handle ZLE display edge case
  if add_newline == "true" and needs_workaround():
    reset_prompt()
  
  # Save current cursor position
  save_cursor_position()
  
  # Display prompt on new line
  move_to_next_line()
  move_to_column_zero()
  clear_to_end_of_line()
  print_prompt(prompt)
  
  # Read character
  character = readkey()
  read_status = $?
  
  # Clean up display
  move_to_column_zero()
  clear_to_end_of_line()
  restore_cursor_position()
  
  if read_status != success:
    return failure
  
  set_variable(output_var, character)
  return success
}

################################################################################
# FUNCTION: _zsh_easymotion_readkey
#
# PURPOSE: Low-level single character reading without echo.
#
# INPUTS:
#   output_var: Name of variable to store character
#
# OUTPUTS:
#   Sets output_var to read character
#   Returns read command exit status
#
# LOGIC:
#   1. Use built-in read command with -s -k options
#   2. Read exactly one character
#   3. Store result in output variable
################################################################################
function _zsh_easymotion_readkey(output_var) {
  # PSEUDOCODE
  # Zsh specific: read -s -k 1 variable
  # -s: silent (no echo)
  # -k: read single key
  
  read -s -k 1 character
  read_status = $?
  
  set_variable(output_var, character)
  return read_status
}

################################################################################
# FUNCTION: _zsh_easymotion_isprintable
#
# PURPOSE: Validates if input is a single printable character.
#
# INPUTS:
#   str: String to validate
#
# OUTPUTS:
#   Returns 0 if single printable character, 1 otherwise
#
# LOGIC:
#   1. Check string length is exactly 1
#   2. Verify character matches POSIX [[:print:]] class
#   3. Return appropriate status
################################################################################
function _zsh_easymotion_isprintable(str) {
  # PSEUDOCODE
  if length(str) == 1 and str matches "[[:print:]]":
    return success
  else:
    return failure
}


################################################################################
# FUNCTION: _zsh_easymotion_apply_highlights
#
# PURPOSE: Configures syntax highlighting for EasyMotion jump markers.
# 
# INPUTS:
#   buffer: Original buffer content for position calculations
#   key_sequences: Already typed key sequence for multi-key jumps
#   keymaps: Array of "key\0index" entries mapping keys to positions
#
# OUTPUTS:
#   Modifies region_highlight array directly (no explicit return)
#
# LOGIC:
#   1. Fetch colour styles via zstyle with defaults
#   2. Dim entire buffer background
#   3. For each keymap entry:
#      - Extract position and jump key
#      - If single-character key: apply primary colour
#      - If multi-character key: first char secondary, rest tertiary
#   4. Add all highlights to region_highlight
################################################################################
function _zsh_easymotion_apply_highlights(buffer, key_sequences, keymaps) {
  # PSEUDOCODE
  colours = fetch_zstyle_colours()
  region_highlight = dim_entire_buffer(buffer, colours.bg)
  
  for each keymap in keymaps {
    (key, position) = parse_keymap_entry(keymap)
    display_key = remove_typed_prefix(key, key_sequences)
    
    if length(display_key) == 1 {
      highlight = create_highlight(position, colours.primary)
      region_highlight += highlight
    } else {
      highlight1 = create_highlight(position, colours.secondary)
      highlight2 = create_highlight(position+1, colours.tertiary)
      region_highlight += (highlight1, highlight2)
    }
  }
}

################################################################################
# FUNCTION: _zsh_easymotion_apply_replacements
#
# PURPOSE: Temporarily replaces buffer content with jump markers.
#
# INPUTS:
#   buffer: Original buffer content to restore
#   key_sequences: Already typed key sequence for filtering
#   keymaps: Array of "key\0index" entries
#
# OUTPUTS:
#   Modifies BUFFER directly (no explicit return)
#
# LOGIC:
#   1. Restore original buffer
#   2. For each keymap entry:
#      - Extract position and jump key
#      - Remove already-typed prefix
#      - Replace characters at position with display key
################################################################################
function _zsh_easymotion_apply_replacements(buffer, key_sequences, keymaps) {
  # PSEUDOCODE
  BUFFER = buffer
  
  for each keymap in keymaps {
    (key, position) = parse_keymap_entry(keymap)
    display_key = remove_typed_prefix(key, key_sequences)
    end_position = position + length(display_key) - 1
    
    BUFFER[position..end_position] = display_key
  }
}

# ============================================================================
# SECTION 2: KEY MANAGEMENT LAYER (LOGIC)
# ============================================================================

################################################################################
# FUNCTION: _zsh_easymotion_assign_keys
#
# PURPOSE: Generates optimal jump key sequences for given number of targets.
#
# INPUTS:
#   target_count: Number of positions requiring jump keys
#
# OUTPUTS:
#   Returns array of jump keys (strings)
#
# LOGIC:
#   1. Get available keys from configuration (default: a-z)
#   2. Calculate minimum prefix count needed
#   3. Generate keys in order:
#      - Single keys: first (total - reserved) keys
#      - Two-key combos: each reserved prefix + all keys
#   4. Truncate to target_count
#
# EXAMPLE:
#   keys = "abc", target_count = 6
#   Calculate: need 2 prefixes (b, c)
#   Single keys: ["a"]
#   Two-key: ["ba","bb","bc","ca","cb","cc"]
#   Result: ["a","ba","bb","bc","ca","cb"]
################################################################################
function _zsh_easymotion_assign_keys(target_count) {
  # PSEUDOCODE
  available_keys = get_config("keys")  # Default: a-z
  
  if target_count == 0:
    return empty_array
  
  if target_count > length(available_keys)^2:
    return error("Too many targets")
  
  # Calculate optimal prefix count
  prefix_count = calculate_minimum_prefixes(target_count, available_keys)
  
  # Generate key sequences
  single_keys = first_n_keys(available_keys, length(available_keys) - prefix_count)
  
  two_key_combinations = []
  prefixes = last_n_keys(available_keys, prefix_count)
  for each prefix in prefixes {
    for each key in available_keys {
      two_key_combinations += prefix + key
    }
  }
  
  all_keys = single_keys + two_key_combinations
  return first_n_elements(all_keys, target_count)
}

################################################################################
# FUNCTION: _zsh_easymotion_build_keymap
#
# PURPOSE: Creates mapping between jump keys and buffer positions.
#
# INPUTS:
#   positions: Array of 1-based position indices
#   keys: Array of jump keys from _zsh_easymotion_assign_keys()
#
# OUTPUTS:
#   Returns array of "key\0index" strings
#
# LOGIC:
#   1. Pair each key with corresponding position
#   2. Format as "key\0position"
#   3. Return array of formatted strings
################################################################################
function _zsh_easymotion_build_keymap(positions, keys) {
  # PSEUDOCODE
  if length(positions) != length(keys):
    return error("Mismatched array lengths")
  
  keymap = []
  for i from 1 to length(positions) {
    entry = keys[i] + "\0" + string(positions[i])
    keymap += entry
  }
  
  return keymap
}

# ============================================================================
# SECTION 3: MOTION ENGINE (CORE FUNCTIONALITY)
# ============================================================================

################################################################################
# FUNCTION: _zsh_easymotion_invoke
#
# PURPOSE: Main entry point for EasyMotion operations.
#
# INPUTS:
#   mode: "search", "word", or "end"
#   buffer: Current command line buffer
#
# OUTPUTS:
#   Returns success/failure status
#
# LOGIC:
#   1. Generate position indices based on mode
#   2. Build keymap linking keys to positions
#   3. Initiate interactive jump selection
################################################################################
function _zsh_easymotion_invoke(mode, buffer) {
  # PSEUDOCODE
  positions = get_positions(mode, buffer)
  if empty(positions):
    return failure("No targets found")
  
  keys = _zsh_easymotion_assign_keys(length(positions))
  keymap = _zsh_easymotion_build_keymap(positions, keys)
  
  return _zsh_easymotion_handle_jump(buffer, "", keymap)
}

################################################################################
# FUNCTION: _zsh_easymotion_handle_jump
#
# PURPOSE: Interactive jump selection state machine.
#
# INPUTS:
#   buffer: Original buffer content
#   typed_sequence: Keys already typed by user
#   keymap: Current filtered keymap entries
#
# OUTPUTS:
#   Returns success/failure status
#
# LOGIC:
#   1. If only one target: jump directly
#   2. Apply visual replacements and highlighting
#   3. Redraw display
#   4. Read user input
#   5. Filter keymap based on input
#   6. Recursively call with filtered keymap
################################################################################
function _zsh_easymotion_handle_jump(buffer, typed_sequence, keymap) {
  # PSEUDOCODE
  if length(keymap) == 0:
    return failure("No matching targets")
  
  if length(keymap) == 1:
    position = extract_position(keymap[0])
    move_cursor(position)
    return success
  
  # Show jump markers
  _zsh_easymotion_apply_replacements(buffer, typed_sequence, keymap)
  _zsh_easymotion_apply_highlights(buffer, typed_sequence, keymap)
  redraw_display()
  
  # Get user input
  user_input = prompt_user("Target key: ")
  
  # Filter keymap to entries starting with extended sequence
  new_sequence = typed_sequence + user_input
  filtered_keymap = filter(keymap, starts_with(new_sequence))
  
  # Recursive call with filtered keymap
  return _zsh_easymotion_handle_jump(buffer, new_sequence, filtered_keymap)
}

# ============================================================================
# SECTION 4: UTILITY LAYER (SUPPORTING FUNCTIONS)
# ============================================================================

################################################################################
# FUNCTION: _zsh_easymotion_boundaries
#
# PURPOSE: Finds word _zsh_easymotion_boundaries in buffer.
#
# INPUTS:
#   mode: "word" (start positions) or "end" (end positions)
#   buffer: Text to analyse
#
# OUTPUTS:
#   Returns array of 1-based positions
#
# LOGIC:
#   1. Define word pattern: [[:alnum:]_]+
#   2. Find all matches using regex
#   3. Calculate positions based on mode
#   4. Return as array
################################################################################
function _zsh_easymotion_boundaries(mode, buffer) {
  # PSEUDOCODE
  pattern = "[[:alnum:]_]+"
  positions = []
  
  while match = find_next_match(buffer, pattern) {
    if mode == "word":
      positions += match.start_position
    else:  # mode == "end"
      positions += match.end_position
    
    buffer = remove_matched_prefix(buffer, match)
  }
  
  return positions
}

################################################################################
# FUNCTION: _zsh_easymotion_char2regex
#
# PURPOSE: Converts character to regex pattern based on case mode.
#
# INPUTS:
#   character: Single character to convert
#   case_mode: "default", "ignorecase", or "smartcase"
#
# OUTPUTS:
#   Returns regex pattern string
#
# LOGIC:
#   1. default: Escape character for literal match
#   2. ignorecase: Create character class [lower|upper]
#   3. smartcase: If lowercase, [lower|upper]; else literal
################################################################################
function _zsh_easymotion_char2regex(character, case_mode) {
  # PSEUDOCODE
  if case_mode == "ignorecase" and is_alpha(character):
    return "[" + lowercase(character) + uppercase(character) + "]"
  
  if case_mode == "smartcase" and is_lowercase(character):
    return "[" + character + uppercase(character) + "]"
  
  return escape_regex(character)
}

################################################################################
# FUNCTION: _zsh_easymotion_match_indices
#
# PURPOSE: Finds all occurrences of pattern in buffer.
#
# INPUTS:
#   pattern: Regex pattern to search for
#   buffer: Text to search within
#
# OUTPUTS:
#   Returns array of 1-based match positions
#
# LOGIC:
#   1. Use global substitution with position capture
#   2. Replace matches with position markers
#   3. Extract positions from markers
#   4. Return as sorted array
################################################################################
function _zsh_easymotion_match_indices(pattern, buffer) {
  # PSEUDOCODE
  # This uses Zsh's pattern substitution with backreferences
  # ${(S)buffer//*(#b)($~pattern)/${marker}$mbegin[1]$null}
  
  marker = "\x1b\x1b "  # Unlikely escape sequence
  null = "\0"
  
  # Perform substitution capturing match positions
  modified = substitute_all_matches(buffer, pattern, marker + position + null)
  
  # Split on null, filter marker lines, extract positions
  parts = split(modified, null)
  positions = []
  
  for each part in parts {
    if starts_with(part, marker):
      position = extract_number(remove_prefix(part, marker))
      positions += position
  }
  
  return sort(positions)
}

################################################################################
# FUNCTION: _zsh_easymotion_jump_indices
#
# PURPOSE: Main dispatcher for generating position indices by mode.
#
# INPUTS:
#   mode: "search", "word", or "end"
#   buffer: Text buffer to analyse
#   output_var: Name of variable to receive positions
#
# OUTPUTS:
#   Sets output_var to space-separated position string
#   Returns success/failure status
#
# LOGIC:
#   1. If mode is "word" or "end": call boundaries()
#   2. If mode is "search":
#      - Prompt user for search character
#      - Validate character is printable
#      - Convert to regex based on case mode
#      - Find all occurrences with match_indices()
#   3. Store result in output variable
################################################################################
function _zsh_easymotion_jump_indices(mode, buffer, output_var) {
  # PSEUDOCODE
  if mode == "word" or mode == "end":
    positions = boundaries(mode, buffer)
    set_variable(output_var, positions)
    return success
  
  if mode == "search":
    # Get search character from user
    character = prompt_search()
    
    if not isprintable(character):
      return failure
    
    # Convert to regex pattern
    case_mode = get_config("search-case", "default")
    regex = char2regex(character, case_mode)
    
    # Find all occurrences
    positions = match_indices(regex, buffer)
    set_variable(output_var, positions)
    return success
  
  return failure  # Invalid mode
}

################################################################################
# FUNCTION: widget
#
# PURPOSE: ZLE widget entry point.
#
# LOGIC:
#   1. Backup original buffer and cursor
#   2. Move cursor to end for full visibility
#   3. Call _zsh_easymotion_invoke() with selected mode
#   4. Always restore buffer (even on failure)
#   5. Redraw display
################################################################################
function widget(mode) {
  # PSEUDOCODE
  original_buffer = BUFFER
  original_cursor = CURSOR
  
  try {
    CURSOR = length(BUFFER)  # Move to end
    redraw()
    
    _zsh_easymotion_invoke(mode, original_buffer)
  } always {
    BUFFER = original_buffer
    redraw()
  }
}

# All configuration uses zstyle patterns:
#   zstyle ':zsh-easymotion:*' key value
#
# Required settings with defaults:
#   keys: "abcdefghijklmnopqrstuvwxyz"
#   fg-primary: "fg=196,bold"     # Red
#   fg-secondary: "fg=208,bold"   # Orange
#   fg-tertiary: "fg=94,bold"     # Dark brown
#   bg: "fg=black,bold"          # Dim background
#   search-case: "default"        # "default|ignorecase|smartcase"
#   prompt-char: "Search for character: "
#   prompt-key: "Target key: "
