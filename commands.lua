-- commands.lua
local CommandHandler = require("CommandHandler"):getInstance()
local avim = require("Avim"):getInstance()
local View = require("View"):getInstance()

-- === Basic Navigation ===
CommandHandler:map("move_left", function()
    avim.cursorX = math.max(1, avim.cursorX - 1)
end)

CommandHandler:map("move_down", function()
    if avim.cursorY < #avim.buffer then
        avim.cursorY = avim.cursorY + 1
    end
    avim.cursorX = math.min(avim.cursorX, #avim.buffer[avim.cursorY] + 1)
end)

CommandHandler:map("move_up", function()
    if avim.cursorY > 1 then
        avim.cursorY = avim.cursorY - 1
    end
    avim.cursorX = math.min(avim.cursorX, #avim.buffer[avim.cursorY] + 1)
end)

CommandHandler:map("move_right", function()
    avim.cursorX = math.min(#avim.buffer[avim.cursorY] + 1, avim.cursorX + 1)
end)

-- === File and Screen Navigation ===
CommandHandler:map("move_to_top", function()
    avim.cursorY = 1
    avim.cursorX = 1
    avim:updateScroll()
end)

CommandHandler:map("move_to_bottom", function()
    avim.cursorY = #avim.buffer
    avim.cursorX = 1
    avim:updateScroll()
end)

CommandHandler:map("move_to_top_of_screen", function()
    local screenStart = avim.scrollOffset + 1
    avim.cursorY = screenStart
    avim.cursorX = 1
    avim:updateStatusBar("Moved to top of screen")
end)

CommandHandler:map("move_to_middle_of_screen", function()
    local screenHeight = SCREENHEIGHT
    local screenMiddle = math.floor(screenHeight / 2)
    avim.cursorY = avim.scrollOffset + screenMiddle
    avim.cursorX = 1
    avim:updateStatusBar("Moved to middle of screen")
end)

CommandHandler:map("move_to_bottom_of_screen", function()
    local screenHeight = SCREENHEIGHT
    local screenEnd = avim.scrollOffset + screenHeight - 1
    avim.cursorY = screenEnd
    avim.cursorX = 1
    avim:updateStatusBar("Moved to bottom of screen")
end)

-- === Word and Line Motions ===
CommandHandler:map("move_word_forward", function()
    local line = avim.buffer[avim.cursorY]
    local nextSpace = line:find("%s", avim.cursorX)
    if nextSpace then
        avim.cursorX = nextSpace + 1
    else
        avim.cursorX = #line + 1
    end
end)

CommandHandler:map("move_word_start", function()
    local line = avim.buffer[avim.cursorY]
    local nextSpace = line:find("%s", avim.cursorX)
    if nextSpace then
        local nextWordStart = line:find("%S", nextSpace + 1)
        if nextWordStart then
            avim.cursorX = nextWordStart
        else
            avim.cursorX = #line + 1
        end
    else
        avim.cursorX = #line + 1
    end
end)

CommandHandler:map("move_word_back", function()
    local line = avim.buffer[avim.cursorY]
    local prevSpace = line:sub(1, avim.cursorX - 1):find("%s[^%s]*$")
    if prevSpace then
        avim.cursorX = prevSpace
    else
        avim.cursorX = 1
    end
end)

CommandHandler:map("move_word_end", function()
    local line = avim.buffer[avim.cursorY]
    local nextWordEnd = line:find("[^%s]+", avim.cursorX)
    if nextWordEnd then
        avim.cursorX = nextWordEnd + line:sub(nextWordEnd):find("%s") - 1
    else
        avim.cursorX = #line + 1
    end
end)

CommandHandler:map("move_to_line_start", function()
    avim.cursorX = 1
end)

CommandHandler:map("move_to_line_end", function()
    avim.cursorX = #avim.buffer[avim.cursorY] + 1
end)

CommandHandler:map("move_to_first_non_blank", function()
    local line = avim.buffer[avim.cursorY]
    local firstNonBlank = line:find("%S")
    if firstNonBlank then
        avim.cursorX = firstNonBlank
    else
        avim.cursorX = 1
    end
end)

-- === Paragraph Motions ===
CommandHandler:map("move_paragraph_back", function()
    local cursorY = avim.cursorY
    while cursorY > 1 do
        cursorY = cursorY - 1
        if avim.buffer[cursorY]:match("^%s*$") then
            avim.cursorY = cursorY
            avim:updateScroll()
            avim:updateStatusBar("Moved to Previous Paragraph")
            return
        end
    end
    avim:updateStatusError("No previous paragraph found")
end)

CommandHandler:map("move_paragraph_forward", function()
    local cursorY = avim.cursorY
    while cursorY < #avim.buffer do
        cursorY = cursorY + 1
        if avim.buffer[cursorY]:match("^%s*$") then
            avim.cursorY = cursorY + 1
            avim:updateScroll()
            avim:updateStatusBar("Moved to Next Paragraph")
            return
        end
    end
    avim:updateStatusError("No next paragraph found")
end)

-- === Editing ===
CommandHandler:map("delete_char", function()
    local line = avim.buffer[avim.cursorY]
    if avim.cursorX <= #line then
        avim.buffer[avim.cursorY] = line:sub(1, avim.cursorX - 1) .. line:sub(avim.cursorX + 1)
        avim:updateStatusBar("Deleted character")
    else
        avim:updateStatusError("Nothing to delete")
    end
end)

CommandHandler:map("delete_char_before", function()
    local line = avim.buffer[avim.cursorY]
    if avim.cursorX > 1 then
        avim.buffer[avim.cursorY] = line:sub(1, avim.cursorX - 2) .. line:sub(avim.cursorX)
        avim.cursorX = avim.cursorX - 1
        avim:updateStatusBar("Deleted character")
    else
        avim:updateStatusError("Nothing to delete")
    end
end)

CommandHandler:map("cut_line", function()
    avim:cutLine()
end)

CommandHandler:map("delete_word", function()
    local line = avim.buffer[avim.cursorY]
    local nextSpace = line:find("%s", avim.cursorX)
    if nextSpace then
        line = line:sub(1, avim.cursorX - 1) .. line:sub(nextSpace + 1)
    else
        line = line:sub(1, avim.cursorX - 1)
    end
    avim.buffer[avim.cursorY] = line
    avim:updateStatusBar("Deleted word")
end)

CommandHandler:map("change_word", function()
    local line = avim.buffer[avim.cursorY]
    local nextSpace = line:find("%s", avim.cursorX)
    if nextSpace then
        line = line:sub(1, avim.cursorX - 1) .. line:sub(nextSpace + 1)
    else
        line = line:sub(1, avim.cursorX - 1)
    end
    avim.buffer[avim.cursorY] = line
    avim:switchMode("insert")
end)

CommandHandler:map("yank_line", function()
    avim:yankLine()
end)


CommandHandler:map("yank_visual_selection", function()
    avim:yankSelection()
end)

CommandHandler:map("paste_clipboard", function()
    local event, clipboardText = os.pullEvent("paste")
    if clipboardText then
        avim:insertTextAtCursor(clipboardText)
        avim:updateScroll(SCREENHEIGHT)
        avim:updateStatusBar("Pasted text from clipboard")
    else
        avim:updateStatusError("No text in clipboard or paste operation failed")
    end
end)

CommandHandler:map("paste", function()
    avim:paste()
    avim:updateStatusBar("Pasted text")
end)

CommandHandler:map("undo", function()
    avim:undo()
end)

CommandHandler:map("redo", function()
    avim:redo()
end)

-- === Mode Switching ===
CommandHandler:map("enter_insert_mode", function()
    avim:switchMode("insert")
end)

CommandHandler:map("append_to_line", function()
    avim.cursorX = math.min(avim.cursorX + 1, #avim.buffer[avim.cursorY] + 1)
    avim:switchMode("insert")
end)

CommandHandler:map("append_to_line_end", function()
    avim.cursorX = #avim.buffer[avim.cursorY] + 1
    avim:switchMode("insert")
end)

CommandHandler:map("insert_at_line_start", function()
    local line = avim.buffer[avim.cursorY]
    local firstNonBlank = line:find("%S")
    if firstNonBlank then
        avim.cursorX = firstNonBlank
    else
        avim.cursorX = 1
    end
    avim:switchMode("insert")
end)

CommandHandler:map("open_line_below", function()
    local line = avim.cursorY
    table.insert(avim.buffer, line + 1, "")
    avim.cursorY = line + 1
    avim.cursorX = 1
    avim:switchMode("insert")
end)

CommandHandler:map("open_line_above", function()
    local line = avim.cursorY
    table.insert(avim.buffer, line, "")
    avim.cursorY = line
    avim.cursorX = 1
    avim:switchMode("insert")
end)

CommandHandler:map("enter_command_mode", function()
    avim:switchMode("command")
end)

CommandHandler:map("enter_visual_mode", function()
    avim:startVisualMode()
end)

CommandHandler:map("end_visual_mode", function()
    avim:endVisualMode()
end)

-- === Search and Replace Commands ===
CommandHandler:map("search", function(pattern)
    if not pattern then
        pattern = avim.lastSearchPattern
        if not pattern then
            avim:updateStatusError("No previous search pattern to repeat")
            return
        end
    else
        avim.lastSearchPattern = pattern
        avim.lastSearchPosition = { y = avim.cursorY, x = avim.cursorX + 1 }
    end

    local startSearchY = avim.lastSearchPosition.y
    local startSearchX = avim.lastSearchPosition.x

    for y = startSearchY, #avim.buffer do
        local line = avim.buffer[y]
        local startX, endX = line:find(pattern, (y == startSearchY) and startSearchX or 1)

        if startX then
            avim.cursorY = y
            avim.cursorX = startX
            avim:updateScroll(SCREENHEIGHT)
            avim:updateStatusBar("Found '" .. pattern .. "' at line " .. y)

            avim.lastSearchPosition = { y = y, x = endX + 1 }

            if y == startSearchY and startX <= avim.cursorX then
                avim.lastSearchPosition = { y = startSearchY, x = 1 }
            end

            return
        end

        avim.lastSearchPosition.x = 1
    end

    avim:updateStatusError("Pattern '" .. pattern .. "' not found")
    avim.lastSearchPosition = { y = 1, x = 1 }
end)

CommandHandler:map("replace", function(oldPattern, newPattern)
    if not oldPattern or not newPattern then
        avim:updateStatusError("Usage: :replace <old> <new>")
        return
    end

    avim.lastReplacePattern = oldPattern
    avim.replaceWithPattern = newPattern
    avim.lastReplacePosition = { y = avim.cursorY, x = avim.cursorX + 1 }

    local replacements = 0

    local startReplaceY = avim.lastReplacePosition.y
    local startReplaceX = avim.lastReplacePosition.x

    for y = startReplaceY, #avim.buffer do
        local line = avim.buffer[y]
        local startX, endX = line:find(oldPattern, (y == startReplaceY) and startReplaceX or 1)

        if startX then
            local newLine = line:sub(1, startX - 1) .. newPattern .. line:sub(endX + 1)
            avim.buffer[y] = newLine
            replacements = replacements + 1

            avim.cursorY = y
            avim.cursorX = startX
            avim:updateScroll(SCREENHEIGHT)
            avim:updateStatusBar("Replaced '" .. oldPattern .. "' with '" .. newPattern .. "' at line " .. y)

            avim.lastReplacePosition = { y = y, x = startX + #newPattern }

            if y == startReplaceY and startX <= avim.cursorX then
                avim.lastReplacePosition = { y = startSearchY, x = 1 }
            end

            return
        end

        avim.lastReplacePosition.x = 1
    end

    avim:updateStatusError("No more occurrences of '" .. oldPattern .. "' found")
    avim.lastReplacePosition = { y = 1, x = 1 }
end)

CommandHandler:map("replace_all", function(oldPattern, newPattern)
    if not oldPattern or not newPattern then
        avim:updateStatusError("Usage: :replace_all <old> <new>")
        return
    end

    local replacements = 0

    for y, line in ipairs(avim.buffer) do
        local newLine, count = line:gsub(oldPattern, newPattern)
        if count > 0 then
            avim.buffer[y] = newLine
            replacements = replacements + count
        end
    end

    if replacements > 0 then
        avim:updateScroll(SCREENHEIGHT)
        avim:updateStatusBar("Replaced " .. replacements .. " occurrence(s) of '" .. oldPattern .. "' with '" .. newPattern .. "'")
    else
        avim:updateStatusError("No occurrences of '" .. oldPattern .. "' found")
    end
end)

CommandHandler:map("goto_line", function(lineNumber)
    lineNumber = tonumber(lineNumber)
    if not lineNumber or lineNumber < 1 or lineNumber > #avim.buffer then
        avim:updateStatusError("Invalid line number: " .. (lineNumber or ""))
        return
    end
    avim.cursorY = lineNumber
    avim.cursorX = 1
    avim:updateScroll(SCREENHEIGHT)
    avim:updateStatusBar("Moved to line " .. lineNumber)
end)

-- === Miscellaneous ===
CommandHandler:map("exit_editor", function()
    avim.shouldExit = true
end)

CommandHandler:map("qa", function()
    avim.shouldExit = true
end)
CommandHandler:map("save_file", function()
    avim:saveFile()
end)
CommandHandler:map("w", function()
    avim:saveFile()
end)

CommandHandler:map("show_keybindings", function()
    local keyHandler = KeyHandler:getInstance() -- Ensure instance is initialized
    local view = View:getInstance()
    local keybindsWindow = view:createWindow(1, 1, SCREENWIDTH, SCREENHEIGHT - 1, colors.lightGray, colors.black)
    local currentMode = avim.mode -- Get the current mode from the model
    local descriptions = keyHandler:getKeyDescriptions(currentMode)

    local startIndex = 1
    local itemsPerPage = keybindsWindow.height - 2  -- Adjust based on available window height

    -- Function to display keybindings in the window
    local function displayKeybindings(startIndex)
        keybindsWindow:clear()
        keybindsWindow:print("Keybindings for " .. currentMode:upper() .. " Mode:")
        for i = startIndex, math.min(#descriptions, startIndex + itemsPerPage - 1) do
            local desc = descriptions[i]
            keybindsWindow:writeline("  " .. desc.combo .. (desc.description ~= "" and ": " .. desc.description or "")) 
        end
        keybindsWindow:show()
    end

    displayKeybindings(startIndex)

    -- Listen for input to scroll and close the window
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.down or key == keys.j then
            if startIndex + itemsPerPage - 1 < #descriptions then
                startIndex = startIndex + 1
                displayKeybindings(startIndex)
            end
        elseif key == keys.up or key == keys.k then
            if startIndex > 1 then
                startIndex = startIndex - 1
                displayKeybindings(startIndex)
            end
        elseif key == keys.q then
            keybindsWindow:close()
            break
        end
    end
end)

CommandHandler:map("close_windows", function()
    View:closeAllWindows()
end)

-- === Insert Mode Keybindings ===
CommandHandler:map("insert_backspace", function()
    if avim.autocompleteWindow then
        -- If autocomplete is open, close it on backspace
        avim.autocompleteWindow:close()
        avim.autocompleteWindow = nil
        avim.suggestions = nil
    else
        -- Otherwise, perform the backspace action
        avim:backspace()
        avim:markDirty(avim.cursorY)
        View:updateCursor()
    end
    View:drawScreen()
end)

CommandHandler:map("insert_exit_to_normal", function()
    avim:switchMode("normal")
    if avim.autocompleteWindow then
        avim.autocompleteWindow:close()
    end
    avim.autocompleteWindow = nil
    avim.suggestions = nil
    avim:markDirty(avim.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_up", function()
    if avim.autocompleteWindow and avim.suggestions then
        -- Move selection up in the autocomplete window
        table.insert(avim.suggestions, 1, table.remove(avim.suggestions))
        View:showAutocompleteWindow(avim.suggestions)
        avim:updateStatusBar("new sugg. selected: " .. avim.suggestions[1])
    else
        -- Normal cursor up movement
        avim:moveCursorUp()
        View:updateCursor()
    end
    avim:markDirty(avim.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_down", function()
    if avim.autocompleteWindow and avim.suggestions then
        -- Move selection down in the autocomplete window
        table.insert(avim.suggestions, table.remove(avim.suggestions, 1))
        View:showAutocompleteWindow(avim.suggestions)
        avim:updateStatusBar("new sugg. selected: " .. avim.suggestions[1])
    else
        -- Normal cursor down movement
        avim:moveCursorDown()
        View:updateCursor()
    end
    avim:markDirty(avim.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_left", function()
    if avim.autocompleteWindow then
        -- Close the autocomplete window on left arrow
        avim.autocompleteWindow:close()
        avim.autocompleteWindow = nil
        avim.suggestions = nil
    end
    -- Normal cursor left movement
    avim:moveCursorLeft()
    View:updateCursor()
    avim:markDirty(avim.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_right", function()
    if avim.autocompleteWindow and avim.suggestions then
        -- Accept current autocomplete suggestion and close the window
        local selectedSuggestion = avim.suggestions[1]
        if selectedSuggestion then
            local currentWord = avim:getWordAtCursor()
            local suffix = selectedSuggestion:sub(#currentWord + 1)
            avim:insertChar(suffix)
            avim.cursorX = #avim.buffer[avim.cursorY] + 1
        end
        avim.autocompleteWindow:close()
        avim.autocompleteWindow = nil
        avim.suggestions = nil
    else
        -- Normal cursor right movement
        avim:moveCursorRight()
        View:updateCursor()
    end
    avim:markDirty(avim.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_tab", function()
    if avim.autocompleteWindow and avim.suggestions then
        -- If autocomplete is open, treat Tab as selecting the current suggestion
        local selectedSuggestion = avim.suggestions[1]
        if selectedSuggestion then
            local currentWord = avim:getWordAtCursor()
            local suffix = selectedSuggestion:sub(#currentWord + 1)
            avim:insertChar(suffix)
            avim.cursorX = #avim.buffer[avim.cursorY] + 1
        end
        avim.autocompleteWindow:close()
        avim.autocompleteWindow = nil
        avim.suggestions = nil
    else
        -- Otherwise, insert a tab character
        avim:insertChar("    ")
        avim:markDirty(avim.cursorY)
        View:drawLine(avim.cursorY - avim.scrollOffset)
        View:updateCursor()
    end
    View:drawScreen()
end)

CommandHandler:map("insert_enter", function()
    if avim.autocompleteWindow and avim.suggestions then
        -- If autocomplete is open, treat Enter as selecting the current suggestion
        local selectedSuggestion = avim.suggestions[1]
        if selectedSuggestion then
            local currentWord = avim:getWordAtCursor()
            local suffix = selectedSuggestion:sub(#currentWord + 1)
            avim:insertChar(suffix)
            avim.cursorX = #avim.buffer[avim.cursorY] + 1
        end
        avim.autocompleteWindow:close()
        avim.autocompleteWindow = nil
        avim.suggestions = nil
    else
        -- Otherwise, insert a new line
        avim:enter()
        avim:markDirty(avim.cursorY)
        View:updateCursor()
    end
    View:drawScreen()
end)
-- === Change Line ===
CommandHandler:map("change_line", function()
    avim:cutLine()  -- Cuts the current line
    avim:switchMode("insert")
end)

-- === Search Next ===
CommandHandler:map("search_next", function()
    if avim.lastSearchPattern then
        CommandHandler:execute("search", avim.lastSearchPattern)
    else
        avim:updateStatusError("No previous search pattern to repeat")
    end
end)
-- === Searching within the Line ===
CommandHandler:map("find_character", function()
    avim:switchMode("command", "find ")
end)

CommandHandler:map("find_before_character", function()
    avim:switchMode("command", "find_before ")
end)

-- === Repeating Last Character Search ===
CommandHandler:map("repeat_last_find", function()
    if avim.lastFindCharacter then
        CommandHandler:execute("find_character")
    else
        avim:updateStatusError("No previous find to repeat")
    end
end)

CommandHandler:map("repeat_last_find_reverse", function()
    if avim.lastFindCharacter then
        -- Implement reverse find logic here
    else
        avim:updateStatusError("No previous find to repeat")
    end
end)

CommandHandler:map("delete_visual_selection", function()
    if not avim.visualStartX or not avim.visualStartY then
        avim:updateStatusError("No selection to delete")
        return
    end

    -- Save current state for undo
    avim:saveToHistory()

    -- Determine the range of the selection
    local startX, startY = math.min(avim.cursorX, avim.visualStartX), math.min(avim.cursorY, avim.visualStartY)
    local endX, endY = math.max(avim.cursorX, avim.visualStartX), math.max(avim.cursorY, avim.visualStartY)

    -- Delete the selected text
    for y = startY, endY do
        local line = avim.buffer[y]
        if y == startY and y == endY then
            -- Single-line selection
            avim.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            -- Start of multi-line selection
            avim.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            -- End of multi-line selection
            avim.buffer[y] = line:sub(endX)
        else
            -- Middle lines of multi-line selection
            avim.buffer[y] = ""
        end
        avim:markDirty(y) -- Mark affected lines as dirty
    end

    -- Adjust cursor position after deletion
    avim.cursorX = startX
    avim.cursorY = startY

    -- Handle merging of lines if multi-line selection was deleted
    if startY ~= endY then
        avim.buffer[startY] = avim.buffer[startY] .. (avim.buffer[startY + 1] or "")
        table.remove(avim.buffer, startY + 1)
    end

    -- End visual mode
    CommandHandler:execute("end_visual_mode")

    avim:updateStatusBar("Deleted visual selection")
end)
CommandHandler:map("cut_visual_selection", function()
    if not avim.visualStartX or not avim.visualStartY then
        avim:updateStatusError("No selection to cut")
        return
    end

    -- Save current state for undo
    avim:saveToHistory()

    -- Determine the range of the selection
    local startX, startY = math.min(avim.cursorX, avim.visualStartX), math.min(avim.cursorY, avim.visualStartY)
    local endX, endY = math.max(avim.cursorX, avim.visualStartX), math.max(avim.cursorY, avim.visualStartY)

    -- Clear the yank register
    avim.yankRegister = ""

    -- Cut the selected text and save it to yank register
    for y = startY, endY do
        local line = avim.buffer[y]
        if y == startY and y == endY then
            -- Single-line selection
            avim.yankRegister = line:sub(startX, endX - 1)
            avim.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            -- Start of multi-line selection
            avim.yankRegister = line:sub(startX) .. "\n"
            avim.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            -- End of multi-line selection
            avim.yankRegister = avim.yankRegister .. line:sub(1, endX - 1)
            avim.buffer[y] = line:sub(endX)
        else
            -- Middle lines of multi-line selection
            avim.yankRegister = avim.yankRegister .. line .. "\n"
            avim.buffer[y] = ""
        end
        avim:markDirty(y) -- Mark affected lines as dirty
    end

    -- Adjust cursor position after cutting
    avim.cursorX = startX
    avim.cursorY = startY

    -- Handle merging of lines if multi-line selection was cut
    if startY ~= endY then
        avim.buffer[startY] = avim.buffer[startY] .. (avim.buffer[startY + 1] or "")
        table.remove(avim.buffer, startY + 1)
    end

    -- End visual mode
    CommandHandler:execute("end_visual_mode")

    avim:updateStatusBar("Cut visual selection")
end)

CommandHandler:map("unindent_visual_selection", function()
    if not avim.visualStartX or not avim.visualStartY then
        avim:updateStatusError("No selection to unindent")
        return
    end

    local startY = math.min(avim.cursorY, avim.visualStartY)
    local endY = math.max(avim.cursorY, avim.visualStartY)

    avim:saveToHistory()

    for y = startY, endY do
        if avim.buffer[y]:sub(1, 4) == "    " then
            avim.buffer[y] = avim.buffer[y]:sub(5)
        end
        avim:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    avim:updateStatusBar("Unindented visual selection")
end)
CommandHandler:map("indent_visual_selection", function()
    if not avim.visualStartX or not avim.visualStartY then
        avim:updateStatusError("No selection to indent")
        return
    end

    local startY = math.min(avim.cursorY, avim.visualStartY)
    local endY = math.max(avim.cursorY, avim.visualStartY)
    

    avim:saveToHistory()

    for y = startY, endY do
        avim.buffer[y] = "    " .. avim.buffer[y]
        avim:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    avim:updateStatusBar("Indented visual selection")
end)
CommandHandler:map("uppercase_visual_selection", function()
    if not avim.visualStartX or not avim.visualStartY then
        avim:updateStatusError("No selection to convert")
        return
    end

    local startY = math.min(avim.cursorY, avim.visualStartY)
    local endY = math.max(avim.cursorY, avim.visualStartY)

    avim:saveToHistory()

    for y = startY, endY do
        local line = avim.buffer[y]
        if y == startY and y == endY then
            avim.buffer[y] = line:sub(1, avim.visualStartX - 1) ..
                            line:sub(avim.visualStartX, avim.cursorX - 1):upper() ..
                            line:sub(avim.cursorX)
        elseif y == startY then
            avim.buffer[y] = line:sub(1, avim.visualStartX - 1) .. line:sub(avim.visualStartX):upper()
        elseif y == endY then
            avim.buffer[y] = line:sub(1, avim.cursorX - 1):upper() .. line:sub(avim.cursorX)
        else
            avim.buffer[y] = line:upper()
        end
        avim:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    avim:updateStatusBar("Uppercased visual selection")
end)
CommandHandler:map("lowercase_visual_selection", function()
    if not avim.visualStartX or not avim.visualStartY then
        avim:updateStatusError("No selection to convert")
        return
    end

    local startY = math.min(avim.cursorY, avim.visualStartY)
    local endY = math.max(avim.cursorY, avim.visualStartY)

    avim:saveToHistory()

    for y = startY, endY do
        local line = avim.buffer[y]
        if y == startY and y == endY then
            avim.buffer[y] = line:sub(1, avim.visualStartX - 1) ..
                            line:sub(avim.visualStartX, avim.cursorX - 1):lower() ..
                            line:sub(avim.cursorX)
        elseif y == startY then
            avim.buffer[y] = line:sub(1, avim.visualStartX - 1) .. line:sub(avim.visualStartX):lower()
        elseif y == endY then
            avim.buffer[y] = line:sub(1, avim.cursorX - 1):lower() .. line:sub(avim.cursorX)
        else
            avim.buffer[y] = line:lower()
        end
        avim:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    avim:updateStatusBar("Lowercased visual selection")
end)
CommandHandler:map("join_visual_selection", function()
    if not avim.visualStartX or not avim.visualStartY then
        avim:updateStatusError("No selection to join")
        return
    end

    local startY = math.min(avim.cursorY, avim.visualStartY)
    local endY = math.max(avim.cursorY, avim.visualStartY)

    avim:saveToHistory()

    local joinedLine = ""
    for y = startY, endY do
        joinedLine = joinedLine .. avim.buffer[y]:gsub("%s+$", "")
        avim.buffer[y] = ""
        avim:markDirty(y)
    end

    avim.buffer[startY] = joinedLine
    avim.cursorY = startY
    avim.cursorX = #joinedLine + 1

    -- Remove empty lines in the range after joining
    for y = startY + 1, endY do
        table.remove(avim.buffer, startY + 1)
    end

    CommandHandler:execute("end_visual_mode")
    avim:updateStatusBar("Joined lines")
end)
CommandHandler:map("swap_case_visual_selection", function()
    if not avim.visualStartX or not avim.visualStartY then
        avim:updateStatusError("No selection to swap case")
        return
    end

    local startY = math.min(avim.cursorY, avim.visualStartY)
    local endY = math.max(avim.cursorY, avim.visualStartY)

    avim:saveToHistory()

    for y = startY, endY do
        local line = avim.buffer[y]
        if y == startY and y == endY then
            avim.buffer[y] = line:sub(1, avim.visualStartX - 1) ..
                            line:sub(avim.visualStartX, avim.cursorX - 1):gsub(".", function(c)
                                return c:match("%l") and c:upper() or c:lower()
                            end) ..
                            line:sub(avim.cursorX)
        elseif y == startY then
            avim.buffer[y] = line:sub(1, avim.visualStartX - 1) .. line:sub(avim.visualStartX):gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end)
        elseif y == endY then
            avim.buffer[y] = line:sub(1, avim.cursorX - 1):gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end) .. line:sub(avim.cursorX)
        else
            avim.buffer[y] = line:gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end)
        end
        avim:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    avim:updateStatusBar("Swapped case of visual selection")
end)
