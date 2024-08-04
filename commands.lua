-- commands.lua
local CommandHandler = require("CommandHandler"):getInstance()
local Model = require("Model"):getInstance()
local View = require("View"):getInstance()

-- === Basic Navigation ===
CommandHandler:map("move_left", function()
    Model.cursorX = math.max(1, Model.cursorX - 1)
end)

CommandHandler:map("move_down", function()
    if Model.cursorY < #Model.buffer then
        Model.cursorY = Model.cursorY + 1
    end
    Model.cursorX = math.min(Model.cursorX, #Model.buffer[Model.cursorY] + 1)
end)

CommandHandler:map("move_up", function()
    if Model.cursorY > 1 then
        Model.cursorY = Model.cursorY - 1
    end
    Model.cursorX = math.min(Model.cursorX, #Model.buffer[Model.cursorY] + 1)
end)

CommandHandler:map("move_right", function()
    Model.cursorX = math.min(#Model.buffer[Model.cursorY] + 1, Model.cursorX + 1)
end)

-- === File and Screen Navigation ===
CommandHandler:map("move_to_top", function()
    Model.cursorY = 1
    Model.cursorX = 1
    Model:updateScroll()
end)

CommandHandler:map("move_to_bottom", function()
    Model.cursorY = #Model.buffer
    Model.cursorX = 1
    Model:updateScroll()
end)

CommandHandler:map("move_to_top_of_screen", function()
    local screenStart = Model.scrollOffset + 1
    Model.cursorY = screenStart
    Model.cursorX = 1
    Model:updateStatusBar("Moved to top of screen")
end)

CommandHandler:map("move_to_middle_of_screen", function()
    local screenHeight = SCREENHEIGHT
    local screenMiddle = math.floor(screenHeight / 2)
    Model.cursorY = Model.scrollOffset + screenMiddle
    Model.cursorX = 1
    Model:updateStatusBar("Moved to middle of screen")
end)

CommandHandler:map("move_to_bottom_of_screen", function()
    local screenHeight = SCREENHEIGHT
    local screenEnd = Model.scrollOffset + screenHeight - 1
    Model.cursorY = screenEnd
    Model.cursorX = 1
    Model:updateStatusBar("Moved to bottom of screen")
end)

-- === Word and Line Motions ===
CommandHandler:map("move_word_forward", function()
    local line = Model.buffer[Model.cursorY]
    local nextSpace = line:find("%s", Model.cursorX)
    if nextSpace then
        Model.cursorX = nextSpace + 1
    else
        Model.cursorX = #line + 1
    end
end)

CommandHandler:map("move_word_start", function()
    local line = Model.buffer[Model.cursorY]
    local nextSpace = line:find("%s", Model.cursorX)
    if nextSpace then
        local nextWordStart = line:find("%S", nextSpace + 1)
        if nextWordStart then
            Model.cursorX = nextWordStart
        else
            Model.cursorX = #line + 1
        end
    else
        Model.cursorX = #line + 1
    end
end)

CommandHandler:map("move_word_back", function()
    local line = Model.buffer[Model.cursorY]
    local prevSpace = line:sub(1, Model.cursorX - 1):find("%s[^%s]*$")
    if prevSpace then
        Model.cursorX = prevSpace
    else
        Model.cursorX = 1
    end
end)

CommandHandler:map("move_word_end", function()
    local line = Model.buffer[Model.cursorY]
    local nextWordEnd = line:find("[^%s]+", Model.cursorX)
    if nextWordEnd then
        Model.cursorX = nextWordEnd + line:sub(nextWordEnd):find("%s") - 1
    else
        Model.cursorX = #line + 1
    end
end)

CommandHandler:map("move_to_line_start", function()
    Model.cursorX = 1
end)

CommandHandler:map("move_to_line_end", function()
    Model.cursorX = #Model.buffer[Model.cursorY] + 1
end)

CommandHandler:map("move_to_first_non_blank", function()
    local line = Model.buffer[Model.cursorY]
    local firstNonBlank = line:find("%S")
    if firstNonBlank then
        Model.cursorX = firstNonBlank
    else
        Model.cursorX = 1
    end
end)

-- === Paragraph Motions ===
CommandHandler:map("move_paragraph_back", function()
    local cursorY = Model.cursorY
    while cursorY > 1 do
        cursorY = cursorY - 1
        if Model.buffer[cursorY]:match("^%s*$") then
            Model.cursorY = cursorY
            Model:updateScroll()
            Model:updateStatusBar("Moved to Previous Paragraph")
            return
        end
    end
    Model:updateStatusError("No previous paragraph found")
end)

CommandHandler:map("move_paragraph_forward", function()
    local cursorY = Model.cursorY
    while cursorY < #Model.buffer do
        cursorY = cursorY + 1
        if Model.buffer[cursorY]:match("^%s*$") then
            Model.cursorY = cursorY + 1
            Model:updateScroll()
            Model:updateStatusBar("Moved to Next Paragraph")
            return
        end
    end
    Model:updateStatusError("No next paragraph found")
end)

-- === Editing ===
CommandHandler:map("delete_char", function()
    local line = Model.buffer[Model.cursorY]
    if Model.cursorX <= #line then
        Model.buffer[Model.cursorY] = line:sub(1, Model.cursorX - 1) .. line:sub(Model.cursorX + 1)
        Model:updateStatusBar("Deleted character")
    else
        Model:updateStatusError("Nothing to delete")
    end
end)

CommandHandler:map("delete_char_before", function()
    local line = Model.buffer[Model.cursorY]
    if Model.cursorX > 1 then
        Model.buffer[Model.cursorY] = line:sub(1, Model.cursorX - 2) .. line:sub(Model.cursorX)
        Model.cursorX = Model.cursorX - 1
        Model:updateStatusBar("Deleted character")
    else
        Model:updateStatusError("Nothing to delete")
    end
end)

CommandHandler:map("cut_line", function()
    Model:cutLine()
end)

CommandHandler:map("delete_word", function()
    local line = Model.buffer[Model.cursorY]
    local nextSpace = line:find("%s", Model.cursorX)
    if nextSpace then
        line = line:sub(1, Model.cursorX - 1) .. line:sub(nextSpace + 1)
    else
        line = line:sub(1, Model.cursorX - 1)
    end
    Model.buffer[Model.cursorY] = line
    Model:updateStatusBar("Deleted word")
end)

CommandHandler:map("change_word", function()
    local line = Model.buffer[Model.cursorY]
    local nextSpace = line:find("%s", Model.cursorX)
    if nextSpace then
        line = line:sub(1, Model.cursorX - 1) .. line:sub(nextSpace + 1)
    else
        line = line:sub(1, Model.cursorX - 1)
    end
    Model.buffer[Model.cursorY] = line
    Model:switchMode("insert")
end)

CommandHandler:map("yank_line", function()
    Model:yankLine()
end)


CommandHandler:map("yank_visual_selection", function()
    Model:yankSelection()
end)

CommandHandler:map("paste_clipboard", function()
    local event, clipboardText = os.pullEvent("paste")
    if clipboardText then
        Model:insertTextAtCursor(clipboardText)
        Model:updateScroll(SCREENHEIGHT)
        Model:updateStatusBar("Pasted text from clipboard")
    else
        Model:updateStatusError("No text in clipboard or paste operation failed")
    end
end)

CommandHandler:map("paste", function()
    Model:paste()
    Model:updateStatusBar("Pasted text")
end)

CommandHandler:map("undo", function()
    Model:undo()
end)

CommandHandler:map("redo", function()
    Model:redo()
end)

-- === Mode Switching ===
CommandHandler:map("enter_insert_mode", function()
    Model:switchMode("insert")
end)

CommandHandler:map("append_to_line", function()
    Model.cursorX = math.min(Model.cursorX + 1, #Model.buffer[Model.cursorY] + 1)
    Model:switchMode("insert")
end)

CommandHandler:map("append_to_line_end", function()
    Model.cursorX = #Model.buffer[Model.cursorY] + 1
    Model:switchMode("insert")
end)

CommandHandler:map("insert_at_line_start", function()
    local line = Model.buffer[Model.cursorY]
    local firstNonBlank = line:find("%S")
    if firstNonBlank then
        Model.cursorX = firstNonBlank
    else
        Model.cursorX = 1
    end
    Model:switchMode("insert")
end)

CommandHandler:map("open_line_below", function()
    local line = Model.cursorY
    table.insert(Model.buffer, line + 1, "")
    Model.cursorY = line + 1
    Model.cursorX = 1
    Model:switchMode("insert")
end)

CommandHandler:map("open_line_above", function()
    local line = Model.cursorY
    table.insert(Model.buffer, line, "")
    Model.cursorY = line
    Model.cursorX = 1
    Model:switchMode("insert")
end)

CommandHandler:map("enter_command_mode", function()
    Model:switchMode("command")
end)

CommandHandler:map("enter_visual_mode", function()
    Model:startVisualMode()
end)

CommandHandler:map("end_visual_mode", function()
    Model:endVisualMode()
end)

-- === Search and Replace Commands ===
CommandHandler:map("search", function(pattern)
    if not pattern then
        pattern = Model.lastSearchPattern
        if not pattern then
            Model:updateStatusError("No previous search pattern to repeat")
            return
        end
    else
        Model.lastSearchPattern = pattern
        Model.lastSearchPosition = { y = Model.cursorY, x = Model.cursorX + 1 }
    end

    local startSearchY = Model.lastSearchPosition.y
    local startSearchX = Model.lastSearchPosition.x

    for y = startSearchY, #Model.buffer do
        local line = Model.buffer[y]
        local startX, endX = line:find(pattern, (y == startSearchY) and startSearchX or 1)

        if startX then
            Model.cursorY = y
            Model.cursorX = startX
            Model:updateScroll(SCREENHEIGHT)
            Model:updateStatusBar("Found '" .. pattern .. "' at line " .. y)

            Model.lastSearchPosition = { y = y, x = endX + 1 }

            if y == startSearchY and startX <= Model.cursorX then
                Model.lastSearchPosition = { y = startSearchY, x = 1 }
            end

            return
        end

        Model.lastSearchPosition.x = 1
    end

    Model:updateStatusError("Pattern '" .. pattern .. "' not found")
    Model.lastSearchPosition = { y = 1, x = 1 }
end)

CommandHandler:map("replace", function(oldPattern, newPattern)
    if not oldPattern or not newPattern then
        Model:updateStatusError("Usage: :replace <old> <new>")
        return
    end

    Model.lastReplacePattern = oldPattern
    Model.replaceWithPattern = newPattern
    Model.lastReplacePosition = { y = Model.cursorY, x = Model.cursorX + 1 }

    local replacements = 0

    local startReplaceY = Model.lastReplacePosition.y
    local startReplaceX = Model.lastReplacePosition.x

    for y = startReplaceY, #Model.buffer do
        local line = Model.buffer[y]
        local startX, endX = line:find(oldPattern, (y == startReplaceY) and startReplaceX or 1)

        if startX then
            local newLine = line:sub(1, startX - 1) .. newPattern .. line:sub(endX + 1)
            Model.buffer[y] = newLine
            replacements = replacements + 1

            Model.cursorY = y
            Model.cursorX = startX
            Model:updateScroll(SCREENHEIGHT)
            Model:updateStatusBar("Replaced '" .. oldPattern .. "' with '" .. newPattern .. "' at line " .. y)

            Model.lastReplacePosition = { y = y, x = startX + #newPattern }

            if y == startReplaceY and startX <= Model.cursorX then
                Model.lastReplacePosition = { y = startSearchY, x = 1 }
            end

            return
        end

        Model.lastReplacePosition.x = 1
    end

    Model:updateStatusError("No more occurrences of '" .. oldPattern .. "' found")
    Model.lastReplacePosition = { y = 1, x = 1 }
end)

CommandHandler:map("replace_all", function(oldPattern, newPattern)
    if not oldPattern or not newPattern then
        Model:updateStatusError("Usage: :replace_all <old> <new>")
        return
    end

    local replacements = 0

    for y, line in ipairs(Model.buffer) do
        local newLine, count = line:gsub(oldPattern, newPattern)
        if count > 0 then
            Model.buffer[y] = newLine
            replacements = replacements + count
        end
    end

    if replacements > 0 then
        Model:updateScroll(SCREENHEIGHT)
        Model:updateStatusBar("Replaced " .. replacements .. " occurrence(s) of '" .. oldPattern .. "' with '" .. newPattern .. "'")
    else
        Model:updateStatusError("No occurrences of '" .. oldPattern .. "' found")
    end
end)

CommandHandler:map("goto_line", function(lineNumber)
    lineNumber = tonumber(lineNumber)
    if not lineNumber or lineNumber < 1 or lineNumber > #Model.buffer then
        Model:updateStatusError("Invalid line number: " .. (lineNumber or ""))
        return
    end
    Model.cursorY = lineNumber
    Model.cursorX = 1
    Model:updateScroll(SCREENHEIGHT)
    Model:updateStatusBar("Moved to line " .. lineNumber)
end)

-- === Miscellaneous ===
CommandHandler:map("exit_editor", function()
    Model.shouldExit = true
end)

CommandHandler:map("qa", function()
    Model.shouldExit = true
end)

CommandHandler:map("show_keybindings", function()
    local keyHandler = KeyHandler:getInstance() -- Ensure instance is initialized
    local view = View:getInstance()
    local keybindsWindow = view:createWindow(1, 1, SCREENWIDTH, SCREENHEIGHT - 1, colors.lightGray, colors.black)
    local currentMode = Model.mode -- Get the current mode from the model
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
    if Model.autocompleteWindow then
        -- If autocomplete is open, close it on backspace
        Model.autocompleteWindow:close()
        Model.autocompleteWindow = nil
        Model.suggestions = nil
    else
        -- Otherwise, perform the backspace action
        Model:backspace()
        Model:markDirty(Model.cursorY)
        View:updateCursor()
    end
    View:drawScreen()
end)

CommandHandler:map("insert_exit_to_normal", function()
    Model:switchMode("normal")
    if Model.autocompleteWindow then
        Model.autocompleteWindow:close()
    end
    Model.autocompleteWindow = nil
    Model.suggestions = nil
    Model:markDirty(Model.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_up", function()
    if Model.autocompleteWindow and Model.suggestions then
        -- Move selection up in the autocomplete window
        table.insert(Model.suggestions, 1, table.remove(Model.suggestions))
        View:showAutocompleteWindow(Model.suggestions)
        Model:updateStatusBar("new sugg. selected: " .. Model.suggestions[1])
    else
        -- Normal cursor up movement
        Model:moveCursorUp()
        View:updateCursor()
    end
    Model:markDirty(Model.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_down", function()
    if Model.autocompleteWindow and Model.suggestions then
        -- Move selection down in the autocomplete window
        table.insert(Model.suggestions, table.remove(Model.suggestions, 1))
        View:showAutocompleteWindow(Model.suggestions)
        Model:updateStatusBar("new sugg. selected: " .. Model.suggestions[1])
    else
        -- Normal cursor down movement
        Model:moveCursorDown()
        View:updateCursor()
    end
    Model:markDirty(Model.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_left", function()
    if Model.autocompleteWindow then
        -- Close the autocomplete window on left arrow
        Model.autocompleteWindow:close()
        Model.autocompleteWindow = nil
        Model.suggestions = nil
    end
    -- Normal cursor left movement
    Model:moveCursorLeft()
    View:updateCursor()
    Model:markDirty(Model.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_right", function()
    if Model.autocompleteWindow and Model.suggestions then
        -- Accept current autocomplete suggestion and close the window
        local selectedSuggestion = Model.suggestions[1]
        if selectedSuggestion then
            local currentWord = Model:getWordAtCursor()
            local suffix = selectedSuggestion:sub(#currentWord + 1)
            Model:insertChar(suffix)
            Model.cursorX = #Model.buffer[Model.cursorY] + 1
        end
        Model.autocompleteWindow:close()
        Model.autocompleteWindow = nil
        Model.suggestions = nil
    else
        -- Normal cursor right movement
        Model:moveCursorRight()
        View:updateCursor()
    end
    Model:markDirty(Model.cursorY)
    View:drawScreen()
end)

CommandHandler:map("insert_tab", function()
    if Model.autocompleteWindow and Model.suggestions then
        -- If autocomplete is open, treat Tab as selecting the current suggestion
        local selectedSuggestion = Model.suggestions[1]
        if selectedSuggestion then
            local currentWord = Model:getWordAtCursor()
            local suffix = selectedSuggestion:sub(#currentWord + 1)
            Model:insertChar(suffix)
            Model.cursorX = #Model.buffer[Model.cursorY] + 1
        end
        Model.autocompleteWindow:close()
        Model.autocompleteWindow = nil
        Model.suggestions = nil
    else
        -- Otherwise, insert a tab character
        Model:insertChar("    ")
        Model:markDirty(Model.cursorY)
        View:drawLine(Model.cursorY - Model.scrollOffset)
        View:updateCursor()
    end
    View:drawScreen()
end)

CommandHandler:map("insert_enter", function()
    if Model.autocompleteWindow and Model.suggestions then
        -- If autocomplete is open, treat Enter as selecting the current suggestion
        local selectedSuggestion = Model.suggestions[1]
        if selectedSuggestion then
            local currentWord = Model:getWordAtCursor()
            local suffix = selectedSuggestion:sub(#currentWord + 1)
            Model:insertChar(suffix)
            Model.cursorX = #Model.buffer[Model.cursorY] + 1
        end
        Model.autocompleteWindow:close()
        Model.autocompleteWindow = nil
        Model.suggestions = nil
    else
        -- Otherwise, insert a new line
        Model:enter()
        Model:markDirty(Model.cursorY)
        View:updateCursor()
    end
    View:drawScreen()
end)
-- === Change Line ===
CommandHandler:map("change_line", function()
    Model:cutLine()  -- Cuts the current line
    Model:switchMode("insert")
end)

-- === Search Next ===
CommandHandler:map("search_next", function()
    if Model.lastSearchPattern then
        CommandHandler:execute("search", Model.lastSearchPattern)
    else
        Model:updateStatusError("No previous search pattern to repeat")
    end
end)
-- === Searching within the Line ===
CommandHandler:map("find_character", function()
    Model:switchMode("command", "find ")
end)

CommandHandler:map("find_before_character", function()
    Model:switchMode("command", "find_before ")
end)

-- === Repeating Last Character Search ===
CommandHandler:map("repeat_last_find", function()
    if Model.lastFindCharacter then
        CommandHandler:execute("find_character")
    else
        Model:updateStatusError("No previous find to repeat")
    end
end)

CommandHandler:map("repeat_last_find_reverse", function()
    if Model.lastFindCharacter then
        -- Implement reverse find logic here
    else
        Model:updateStatusError("No previous find to repeat")
    end
end)

CommandHandler:map("delete_visual_selection", function()
    if not Model.visualStartX or not Model.visualStartY then
        Model:updateStatusError("No selection to delete")
        return
    end

    -- Save current state for undo
    Model:saveToHistory()

    -- Determine the range of the selection
    local startX, startY = math.min(Model.cursorX, Model.visualStartX), math.min(Model.cursorY, Model.visualStartY)
    local endX, endY = math.max(Model.cursorX, Model.visualStartX), math.max(Model.cursorY, Model.visualStartY)

    -- Delete the selected text
    for y = startY, endY do
        local line = Model.buffer[y]
        if y == startY and y == endY then
            -- Single-line selection
            Model.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            -- Start of multi-line selection
            Model.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            -- End of multi-line selection
            Model.buffer[y] = line:sub(endX)
        else
            -- Middle lines of multi-line selection
            Model.buffer[y] = ""
        end
        Model:markDirty(y) -- Mark affected lines as dirty
    end

    -- Adjust cursor position after deletion
    Model.cursorX = startX
    Model.cursorY = startY

    -- Handle merging of lines if multi-line selection was deleted
    if startY ~= endY then
        Model.buffer[startY] = Model.buffer[startY] .. (Model.buffer[startY + 1] or "")
        table.remove(Model.buffer, startY + 1)
    end

    -- End visual mode
    CommandHandler:execute("end_visual_mode")

    Model:updateStatusBar("Deleted visual selection")
end)
CommandHandler:map("cut_visual_selection", function()
    if not Model.visualStartX or not Model.visualStartY then
        Model:updateStatusError("No selection to cut")
        return
    end

    -- Save current state for undo
    Model:saveToHistory()

    -- Determine the range of the selection
    local startX, startY = math.min(Model.cursorX, Model.visualStartX), math.min(Model.cursorY, Model.visualStartY)
    local endX, endY = math.max(Model.cursorX, Model.visualStartX), math.max(Model.cursorY, Model.visualStartY)

    -- Clear the yank register
    Model.yankRegister = ""

    -- Cut the selected text and save it to yank register
    for y = startY, endY do
        local line = Model.buffer[y]
        if y == startY and y == endY then
            -- Single-line selection
            Model.yankRegister = line:sub(startX, endX - 1)
            Model.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            -- Start of multi-line selection
            Model.yankRegister = line:sub(startX) .. "\n"
            Model.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            -- End of multi-line selection
            Model.yankRegister = Model.yankRegister .. line:sub(1, endX - 1)
            Model.buffer[y] = line:sub(endX)
        else
            -- Middle lines of multi-line selection
            Model.yankRegister = Model.yankRegister .. line .. "\n"
            Model.buffer[y] = ""
        end
        Model:markDirty(y) -- Mark affected lines as dirty
    end

    -- Adjust cursor position after cutting
    Model.cursorX = startX
    Model.cursorY = startY

    -- Handle merging of lines if multi-line selection was cut
    if startY ~= endY then
        Model.buffer[startY] = Model.buffer[startY] .. (Model.buffer[startY + 1] or "")
        table.remove(Model.buffer, startY + 1)
    end

    -- End visual mode
    CommandHandler:execute("end_visual_mode")

    Model:updateStatusBar("Cut visual selection")
end)

CommandHandler:map("unindent_visual_selection", function()
    if not Model.visualStartX or not Model.visualStartY then
        Model:updateStatusError("No selection to unindent")
        return
    end

    local startY = math.min(Model.cursorY, Model.visualStartY)
    local endY = math.max(Model.cursorY, Model.visualStartY)

    Model:saveToHistory()

    for y = startY, endY do
        if Model.buffer[y]:sub(1, 4) == "    " then
            Model.buffer[y] = Model.buffer[y]:sub(5)
        end
        Model:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    Model:updateStatusBar("Unindented visual selection")
end)
CommandHandler:map("indent_visual_selection", function()
    if not Model.visualStartX or not Model.visualStartY then
        Model:updateStatusError("No selection to indent")
        return
    end

    local startY = math.min(Model.cursorY, Model.visualStartY)
    local endY = math.max(Model.cursorY, Model.visualStartY)
    

    Model:saveToHistory()

    for y = startY, endY do
        Model.buffer[y] = "    " .. Model.buffer[y]
        Model:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    Model:updateStatusBar("Indented visual selection")
end)
CommandHandler:map("uppercase_visual_selection", function()
    if not Model.visualStartX or not Model.visualStartY then
        Model:updateStatusError("No selection to convert")
        return
    end

    local startY = math.min(Model.cursorY, Model.visualStartY)
    local endY = math.max(Model.cursorY, Model.visualStartY)

    Model:saveToHistory()

    for y = startY, endY do
        local line = Model.buffer[y]
        if y == startY and y == endY then
            Model.buffer[y] = line:sub(1, Model.visualStartX - 1) ..
                            line:sub(Model.visualStartX, Model.cursorX - 1):upper() ..
                            line:sub(Model.cursorX)
        elseif y == startY then
            Model.buffer[y] = line:sub(1, Model.visualStartX - 1) .. line:sub(Model.visualStartX):upper()
        elseif y == endY then
            Model.buffer[y] = line:sub(1, Model.cursorX - 1):upper() .. line:sub(Model.cursorX)
        else
            Model.buffer[y] = line:upper()
        end
        Model:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    Model:updateStatusBar("Uppercased visual selection")
end)
CommandHandler:map("lowercase_visual_selection", function()
    if not Model.visualStartX or not Model.visualStartY then
        Model:updateStatusError("No selection to convert")
        return
    end

    local startY = math.min(Model.cursorY, Model.visualStartY)
    local endY = math.max(Model.cursorY, Model.visualStartY)

    Model:saveToHistory()

    for y = startY, endY do
        local line = Model.buffer[y]
        if y == startY and y == endY then
            Model.buffer[y] = line:sub(1, Model.visualStartX - 1) ..
                            line:sub(Model.visualStartX, Model.cursorX - 1):lower() ..
                            line:sub(Model.cursorX)
        elseif y == startY then
            Model.buffer[y] = line:sub(1, Model.visualStartX - 1) .. line:sub(Model.visualStartX):lower()
        elseif y == endY then
            Model.buffer[y] = line:sub(1, Model.cursorX - 1):lower() .. line:sub(Model.cursorX)
        else
            Model.buffer[y] = line:lower()
        end
        Model:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    Model:updateStatusBar("Lowercased visual selection")
end)
CommandHandler:map("join_visual_selection", function()
    if not Model.visualStartX or not Model.visualStartY then
        Model:updateStatusError("No selection to join")
        return
    end

    local startY = math.min(Model.cursorY, Model.visualStartY)
    local endY = math.max(Model.cursorY, Model.visualStartY)

    Model:saveToHistory()

    local joinedLine = ""
    for y = startY, endY do
        joinedLine = joinedLine .. Model.buffer[y]:gsub("%s+$", "")
        Model.buffer[y] = ""
        Model:markDirty(y)
    end

    Model.buffer[startY] = joinedLine
    Model.cursorY = startY
    Model.cursorX = #joinedLine + 1

    -- Remove empty lines in the range after joining
    for y = startY + 1, endY do
        table.remove(Model.buffer, startY + 1)
    end

    CommandHandler:execute("end_visual_mode")
    Model:updateStatusBar("Joined lines")
end)
CommandHandler:map("swap_case_visual_selection", function()
    if not Model.visualStartX or not Model.visualStartY then
        Model:updateStatusError("No selection to swap case")
        return
    end

    local startY = math.min(Model.cursorY, Model.visualStartY)
    local endY = math.max(Model.cursorY, Model.visualStartY)

    Model:saveToHistory()

    for y = startY, endY do
        local line = Model.buffer[y]
        if y == startY and y == endY then
            Model.buffer[y] = line:sub(1, Model.visualStartX - 1) ..
                            line:sub(Model.visualStartX, Model.cursorX - 1):gsub(".", function(c)
                                return c:match("%l") and c:upper() or c:lower()
                            end) ..
                            line:sub(Model.cursorX)
        elseif y == startY then
            Model.buffer[y] = line:sub(1, Model.visualStartX - 1) .. line:sub(Model.visualStartX):gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end)
        elseif y == endY then
            Model.buffer[y] = line:sub(1, Model.cursorX - 1):gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end) .. line:sub(Model.cursorX)
        else
            Model.buffer[y] = line:gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end)
        end
        Model:markDirty(y)
    end

    CommandHandler:execute("end_visual_mode")
    Model:updateStatusBar("Swapped case of visual selection")
end)
