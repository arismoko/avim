-- commands.lua
local CommandHandler = require("CommandHandler"):getInstance()
local bufferHandler = require("BufferHandler"):getInstance()
local View = require("View"):getInstance()

-- === Basic Navigation ===
CommandHandler:map("move_left", function()
    bufferHandler.cursorX = math.max(1, bufferHandler.cursorX - 1)
end)

CommandHandler:map("move_down", function()
    if bufferHandler.cursorY < #bufferHandler.buffer then
        bufferHandler.cursorY = bufferHandler.cursorY + 1
    end
    bufferHandler.cursorX = math.min(bufferHandler.cursorX, #bufferHandler.buffer[bufferHandler.cursorY] + 1)
end)

CommandHandler:map("move_up", function()
    if bufferHandler.cursorY > 1 then
        bufferHandler.cursorY = bufferHandler.cursorY - 1
    end
    bufferHandler.cursorX = math.min(bufferHandler.cursorX, #bufferHandler.buffer[bufferHandler.cursorY] + 1)
end)

CommandHandler:map("move_right", function()
    bufferHandler.cursorX = math.min(#bufferHandler.buffer[bufferHandler.cursorY] + 1, bufferHandler.cursorX + 1)
end)

-- === File and Screen Navigation ===
CommandHandler:map("move_to_top", function()
    bufferHandler.cursorY = 1
    bufferHandler.cursorX = 1
    bufferHandler:updateScroll()
end)

CommandHandler:map("move_to_bottom", function()
    bufferHandler.cursorY = #bufferHandler.buffer
    bufferHandler.cursorX = 1
    bufferHandler:updateScroll()
end)

CommandHandler:map("move_to_top_of_screen", function()
    local screenStart = bufferHandler.scrollOffset + 1
    bufferHandler.cursorY = screenStart
    bufferHandler.cursorX = 1
    bufferHandler:updateStatusBar("Moved to top of screen")
end)

CommandHandler:map("move_to_middle_of_screen", function()
    local screenHeight = SCREENHEIGHT
    local screenMiddle = math.floor(screenHeight / 2)
    bufferHandler.cursorY = bufferHandler.scrollOffset + screenMiddle
    bufferHandler.cursorX = 1
    bufferHandler:updateStatusBar("Moved to middle of screen")
end)

CommandHandler:map("move_to_bottom_of_screen", function()
    local screenHeight = SCREENHEIGHT
    local screenEnd = bufferHandler.scrollOffset + screenHeight - 1
    bufferHandler.cursorY = screenEnd
    bufferHandler.cursorX = 1
    bufferHandler:updateStatusBar("Moved to bottom of screen")
end)

-- === Word and Line Motions ===
CommandHandler:map("move_word_forward", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local nextSpace = line:find("%s", bufferHandler.cursorX)
    if nextSpace then
        bufferHandler.cursorX = nextSpace + 1
    else
        bufferHandler.cursorX = #line + 1
    end
end)

CommandHandler:map("move_word_start", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local nextSpace = line:find("%s", bufferHandler.cursorX)
    if nextSpace then
        local nextWordStart = line:find("%S", nextSpace + 1)
        if nextWordStart then
            bufferHandler.cursorX = nextWordStart
        else
            bufferHandler.cursorX = #line + 1
        end
    else
        bufferHandler.cursorX = #line + 1
    end
end)

CommandHandler:map("move_word_back", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local prevSpace = line:sub(1, bufferHandler.cursorX - 1):find("%s[^%s]*$")
    if prevSpace then
        bufferHandler.cursorX = prevSpace
    else
        bufferHandler.cursorX = 1
    end
end)

CommandHandler:map("move_word_end", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local nextWordEnd = line:find("[^%s]+", bufferHandler.cursorX)
    if nextWordEnd then
        bufferHandler.cursorX = nextWordEnd + line:sub(nextWordEnd):find("%s") - 1
    else
        bufferHandler.cursorX = #line + 1
    end
end)

CommandHandler:map("move_to_line_start", function()
    bufferHandler.cursorX = 1
end)

CommandHandler:map("move_to_line_end", function()
    bufferHandler.cursorX = #bufferHandler.buffer[bufferHandler.cursorY] + 1
end)

CommandHandler:map("move_to_first_non_blank", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local firstNonBlank = line:find("%S")
    if firstNonBlank then
        bufferHandler.cursorX = firstNonBlank
    else
        bufferHandler.cursorX = 1
    end
end)

-- === Paragraph Motions ===
CommandHandler:map("move_paragraph_back", function()
    local cursorY = bufferHandler.cursorY
    while cursorY > 1 do
        cursorY = cursorY - 1
        if bufferHandler.buffer[cursorY]:match("^%s*$") then
            bufferHandler.cursorY = cursorY
            bufferHandler:updateScroll()
            bufferHandler:updateStatusBar("Moved to Previous Paragraph")
            return
        end
    end
    bufferHandler:updateStatusError("No previous paragraph found")
end)

CommandHandler:map("move_paragraph_forward", function()
    local cursorY = bufferHandler.cursorY
    while cursorY < #bufferHandler.buffer do
        cursorY = cursorY + 1
        if bufferHandler.buffer[cursorY]:match("^%s*$") then
            bufferHandler.cursorY = cursorY + 1
            bufferHandler:updateScroll()
            bufferHandler:updateStatusBar("Moved to Next Paragraph")
            return
        end
    end
    bufferHandler:updateStatusError("No next paragraph found")
end)

-- === Editing ===
CommandHandler:map("delete_char", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    if bufferHandler.cursorX <= #line then
        bufferHandler.buffer[bufferHandler.cursorY] = line:sub(1, bufferHandler.cursorX - 1) .. line:sub(bufferHandler.cursorX + 1)
        bufferHandler:updateStatusBar("Deleted character")
    else
        bufferHandler:updateStatusError("Nothing to delete")
    end
end)

CommandHandler:map("delete_char_before", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    if bufferHandler.cursorX > 1 then
        bufferHandler.buffer[bufferHandler.cursorY] = line:sub(1, bufferHandler.cursorX - 2) .. line:sub(bufferHandler.cursorX)
        bufferHandler.cursorX = bufferHandler.cursorX - 1
        bufferHandler:updateStatusBar("Deleted character")
    else
        bufferHandler:updateStatusError("Nothing to delete")
    end
end)

CommandHandler:map("cut_line", function()
    bufferHandler:cutLine()
end)

CommandHandler:map("delete_word", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local nextSpace = line:find("%s", bufferHandler.cursorX)
    if nextSpace then
        line = line:sub(1, bufferHandler.cursorX - 1) .. line:sub(nextSpace + 1)
    else
        line = line:sub(1, bufferHandler.cursorX - 1)
    end
    bufferHandler.buffer[bufferHandler.cursorY] = line
    bufferHandler:updateStatusBar("Deleted word")
end)

CommandHandler:map("change_word", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local nextSpace = line:find("%s", bufferHandler.cursorX)
    if nextSpace then
        line = line:sub(1, bufferHandler.cursorX - 1) .. line:sub(nextSpace + 1)
    else
        line = line:sub(1, bufferHandler.cursorX - 1)
    end
    bufferHandler.buffer[bufferHandler.cursorY] = line
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("yank_line", function()
    bufferHandler:yankLine()
end)


CommandHandler:map("yank_visual_selection", function()
    bufferHandler:yankSelection()
end)

CommandHandler:map("paste_clipboard", function()
    local event, clipboardText = os.pullEvent("paste")
    if clipboardText then
        bufferHandler:insertTextAtCursor(clipboardText)
        bufferHandler:updateScroll(SCREENHEIGHT)
        bufferHandler:updateStatusBar("Pasted text from clipboard")
    else
        bufferHandler:updateStatusError("No text in clipboard or paste operation failed")
    end
end)

CommandHandler:map("paste", function()
    bufferHandler:paste()
    bufferHandler:updateStatusBar("Pasted text")
end)

CommandHandler:map("undo", function()
    bufferHandler:undo()
end)

CommandHandler:map("redo", function()
    bufferHandler:redo()
end)

-- === Mode Switching ===
CommandHandler:map("enter_insert_mode", function()
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("append_to_line", function()
    bufferHandler.cursorX = math.min(bufferHandler.cursorX + 1, #bufferHandler.buffer[bufferHandler.cursorY] + 1)
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("append_to_line_end", function()
    bufferHandler.cursorX = #bufferHandler.buffer[bufferHandler.cursorY] + 1
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("insert_at_line_start", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local firstNonBlank = line:find("%S")
    if firstNonBlank then
        bufferHandler.cursorX = firstNonBlank
    else
        bufferHandler.cursorX = 1
    end
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("open_line_below", function()
    local line = bufferHandler.cursorY
    table.insert(bufferHandler.buffer, line + 1, "")
    bufferHandler.cursorY = line + 1
    bufferHandler.cursorX = 1
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("open_line_above", function()
    local line = bufferHandler.cursorY
    table.insert(bufferHandler.buffer, line, "")
    bufferHandler.cursorY = line
    bufferHandler.cursorX = 1
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("enter_command_mode", function()
    bufferHandler:switchMode("command")
end)

CommandHandler:map("enter_visual_mode", function()
    bufferHandler:startVisualMode()
end)

CommandHandler:map("end_visual_mode", function()
    bufferHandler:endVisualMode()
end)

-- === Search and Replace Commands ===
CommandHandler:map("search", function(pattern)
    if not pattern then
        pattern = bufferHandler.lastSearchPattern
        if not pattern then
            bufferHandler:updateStatusError("No previous search pattern to repeat")
            return
        end
    else
        bufferHandler.lastSearchPattern = pattern
        bufferHandler.lastSearchPosition = { y = bufferHandler.cursorY, x = bufferHandler.cursorX + 1 }
    end

    local startSearchY = bufferHandler.lastSearchPosition.y
    local startSearchX = bufferHandler.lastSearchPosition.x

    for y = startSearchY, #bufferHandler.buffer do
        local line = bufferHandler.buffer[y]
        local startX, endX = line:find(pattern, (y == startSearchY) and startSearchX or 1)

        if startX then
            bufferHandler.cursorY = y
            bufferHandler.cursorX = startX
            bufferHandler:updateScroll(SCREENHEIGHT)
            bufferHandler:updateStatusBar("Found '" .. pattern .. "' at line " .. y)

            bufferHandler.lastSearchPosition = { y = y, x = endX + 1 }

            if y == startSearchY and startX <= bufferHandler.cursorX then
                bufferHandler.lastSearchPosition = { y = startSearchY, x = 1 }
            end

            return
        end

        bufferHandler.lastSearchPosition.x = 1
    end

    bufferHandler:updateStatusError("Pattern '" .. pattern .. "' not found")
    bufferHandler.lastSearchPosition = { y = 1, x = 1 }
end)

CommandHandler:map("replace", function(oldPattern, newPattern)
    if not oldPattern or not newPattern then
        bufferHandler:updateStatusError("Usage: :replace <old> <new>")
        return
    end

    bufferHandler.lastReplacePattern = oldPattern
    bufferHandler.replaceWithPattern = newPattern
    bufferHandler.lastReplacePosition = { y = bufferHandler.cursorY, x = bufferHandler.cursorX + 1 }

    local replacements = 0

    local startReplaceY = bufferHandler.lastReplacePosition.y
    local startReplaceX = bufferHandler.lastReplacePosition.x

    for y = startReplaceY, #bufferHandler.buffer do
        local line = bufferHandler.buffer[y]
        local startX, endX = line:find(oldPattern, (y == startReplaceY) and startReplaceX or 1)

        if startX then
            local newLine = line:sub(1, startX - 1) .. newPattern .. line:sub(endX + 1)
            bufferHandler.buffer[y] = newLine
            replacements = replacements + 1

            bufferHandler.cursorY = y
            bufferHandler.cursorX = startX
            bufferHandler:updateScroll(SCREENHEIGHT)
            bufferHandler:updateStatusBar("Replaced '" .. oldPattern .. "' with '" .. newPattern .. "' at line " .. y)

            bufferHandler.lastReplacePosition = { y = y, x = startX + #newPattern }

            if y == startReplaceY and startX <= bufferHandler.cursorX then
                bufferHandler.lastReplacePosition = { y = startSearchY, x = 1 }
            end

            return
        end

        bufferHandler.lastReplacePosition.x = 1
    end

    bufferHandler:updateStatusError("No more occurrences of '" .. oldPattern .. "' found")
    bufferHandler.lastReplacePosition = { y = 1, x = 1 }
end)

CommandHandler:map("replace_all", function(oldPattern, newPattern)
    if not oldPattern or not newPattern then
        bufferHandler:updateStatusError("Usage: :replace_all <old> <new>")
        return
    end

    local replacements = 0

    for y, line in ipairs(bufferHandler.buffer) do
        local newLine, count = line:gsub(oldPattern, newPattern)
        if count > 0 then
            bufferHandler.buffer[y] = newLine
            replacements = replacements + count
        end
    end

    if replacements > 0 then
        bufferHandler:updateScroll(SCREENHEIGHT)
        bufferHandler:updateStatusBar("Replaced " .. replacements .. " occurrence(s) of '" .. oldPattern .. "' with '" .. newPattern .. "'")
    else
        bufferHandler:updateStatusError("No occurrences of '" .. oldPattern .. "' found")
    end
end)

CommandHandler:map("goto_line", function(lineNumber)
    lineNumber = tonumber(lineNumber)
    if not lineNumber or lineNumber < 1 or lineNumber > #bufferHandler.buffer then
        bufferHandler:updateStatusError("Invalid line number: " .. (lineNumber or ""))
        return
    end
    bufferHandler.cursorY = lineNumber
    bufferHandler.cursorX = 1
    bufferHandler:updateScroll(SCREENHEIGHT)
    bufferHandler:updateStatusBar("Moved to line " .. lineNumber)
end)

-- === Miscellaneous ===
CommandHandler:map("exit_editor", function()
    bufferHandler.shouldExit = true
end)

CommandHandler:map("qa", function()
    bufferHandler.shouldExit = true
end)
CommandHandler:map("save_file", function()
    bufferHandler:saveFile()
end)
CommandHandler:map("w", function()
    bufferHandler:saveFile()
end)

CommandHandler:map("show_keybindings", function()
    local keyHandler = KeyHandler:getInstance() -- Ensure instance is initialized
    local view = View:getInstance()
    local keybindsWindow = view:createWindow(1, 1, SCREENWIDTH, SCREENHEIGHT - 1, colors.lightGray, colors.black)
    local currentMode = bufferHandler.mode -- Get the current mode from the model
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
    -- Perform the backspace action
    bufferHandler:backspace()
    View:drawScreen()
end)

CommandHandler:map("insert_exit_to_normal", function()
    bufferHandler:switchMode("normal")
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_up", function()
    -- Normal cursor up movement
    bufferHandler:moveCursorUp()
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_down", function()
    -- Normal cursor down movement
    bufferHandler:moveCursorDown()
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_left", function()
    -- Normal cursor left movement
    bufferHandler:moveCursorLeft()
    View:drawScreen()
end)

CommandHandler:map("insert_arrow_right", function()
    -- Normal cursor right movement
    bufferHandler:moveCursorRight()
    View:drawScreen()
end)

CommandHandler:map("insert_tab", function()
    -- Insert a tab character
    bufferHandler:insertChar("    ")
    View:drawLine(bufferHandler.cursorY - bufferHandler.scrollOffset)
    View:drawScreen()
end)

CommandHandler:map("insert_enter", function()
    -- Insert a new line
    bufferHandler:enter()
    View:drawScreen()
end)

-- === Change Line ===
CommandHandler:map("change_line", function()
    bufferHandler:cutLine()  -- Cuts the current line
    bufferHandler:switchMode("insert")
end)

-- === Search Next ===
CommandHandler:map("search_next", function()
    if bufferHandler.lastSearchPattern then
        CommandHandler:execute("search", bufferHandler.lastSearchPattern)
    else
        bufferHandler:updateStatusError("No previous search pattern to repeat")
    end
end)
-- === Searching within the Line ===
CommandHandler:map("find_character", function()
    bufferHandler:switchMode("command", "find ")
end)

CommandHandler:map("find_before_character", function()
    bufferHandler:switchMode("command", "find_before ")
end)

-- === Repeating Last Character Search ===
CommandHandler:map("repeat_last_find", function()
    if bufferHandler.lastFindCharacter then
        CommandHandler:execute("find_character")
    else
        bufferHandler:updateStatusError("No previous find to repeat")
    end
end)

CommandHandler:map("repeat_last_find_reverse", function()
    if bufferHandler.lastFindCharacter then
        -- Implement reverse find logic here
    else
        bufferHandler:updateStatusError("No previous find to repeat")
    end
end)

CommandHandler:map("delete_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to delete")
        return
    end

    -- Save current state for undo
    bufferHandler:saveToHistory()

    -- Determine the range of the selection
    local startX, startY = math.min(bufferHandler.cursorX, bufferHandler.visualStartX), math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endX, endY = math.max(bufferHandler.cursorX, bufferHandler.visualStartX), math.max(bufferHandler.cursorY, bufferHandler.visualStartY)

    -- Delete the selected text
    for y = startY, endY do
        local line = bufferHandler.buffer[y]
        if y == startY and y == endY then
            -- Single-line selection
            bufferHandler.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            -- Start of multi-line selection
            bufferHandler.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            -- End of multi-line selection
            bufferHandler.buffer[y] = line:sub(endX)
        else
            -- Middle lines of multi-line selection
            bufferHandler.buffer[y] = ""
        end
    end

    -- Adjust cursor position after deletion
    bufferHandler.cursorX = startX
    bufferHandler.cursorY = startY

    -- Handle merging of lines if multi-line selection was deleted
    if startY ~= endY then
        bufferHandler.buffer[startY] = bufferHandler.buffer[startY] .. (bufferHandler.buffer[startY + 1] or "")
        table.remove(bufferHandler.buffer, startY + 1)
    end

    -- End visual mode
    CommandHandler:execute("end_visual_mode")

    bufferHandler:updateStatusBar("Deleted visual selection")
end)
CommandHandler:map("cut_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to cut")
        return
    end

    -- Save current state for undo
    bufferHandler:saveToHistory()

    -- Determine the range of the selection
    local startX, startY = math.min(bufferHandler.cursorX, bufferHandler.visualStartX), math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endX, endY = math.max(bufferHandler.cursorX, bufferHandler.visualStartX), math.max(bufferHandler.cursorY, bufferHandler.visualStartY)

    -- Clear the yank register
    bufferHandler.yankRegister = ""

    -- Cut the selected text and save it to yank register
    for y = startY, endY do
        local line = bufferHandler.buffer[y]
        if y == startY and y == endY then
            -- Single-line selection
            bufferHandler.yankRegister = line:sub(startX, endX - 1)
            bufferHandler.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            -- Start of multi-line selection
            bufferHandler.yankRegister = line:sub(startX) .. "\n"
            bufferHandler.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            -- End of multi-line selection
            bufferHandler.yankRegister = bufferHandler.yankRegister .. line:sub(1, endX - 1)
            bufferHandler.buffer[y] = line:sub(endX)
        else
            -- Middle lines of multi-line selection
            bufferHandler.yankRegister = bufferHandler.yankRegister .. line .. "\n"
            bufferHandler.buffer[y] = ""
        end
    end

    -- Adjust cursor position after cutting
    bufferHandler.cursorX = startX
    bufferHandler.cursorY = startY

    -- Handle merging of lines if multi-line selection was cut
    if startY ~= endY then
        bufferHandler.buffer[startY] = bufferHandler.buffer[startY] .. (bufferHandler.buffer[startY + 1] or "")
        table.remove(bufferHandler.buffer, startY + 1)
    end

    -- End visual mode
    CommandHandler:execute("end_visual_mode")

    bufferHandler:updateStatusBar("Cut visual selection")
end)

CommandHandler:map("unindent_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to unindent")
        return
    end

    local startY = math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endY = math.max(bufferHandler.cursorY, bufferHandler.visualStartY)

    bufferHandler:saveToHistory()

    for y = startY, endY do
        if bufferHandler.buffer[y]:sub(1, 4) == "    " then
            bufferHandler.buffer[y] = bufferHandler.buffer[y]:sub(5)
        end
    end

    CommandHandler:execute("end_visual_mode")
    bufferHandler:updateStatusBar("Unindented visual selection")
end)
CommandHandler:map("indent_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to indent")
        return
    end

    local startY = math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endY = math.max(bufferHandler.cursorY, bufferHandler.visualStartY)
    

    bufferHandler:saveToHistory()

    for y = startY, endY do
        bufferHandler.buffer[y] = "    " .. bufferHandler.buffer[y]
    end

    CommandHandler:execute("end_visual_mode")
    bufferHandler:updateStatusBar("Indented visual selection")
end)
CommandHandler:map("uppercase_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to convert")
        return
    end

    local startY = math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endY = math.max(bufferHandler.cursorY, bufferHandler.visualStartY)

    bufferHandler:saveToHistory()

    for y = startY, endY do
        local line = bufferHandler.buffer[y]
        if y == startY and y == endY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.visualStartX - 1) ..
                            line:sub(bufferHandler.visualStartX, bufferHandler.cursorX - 1):upper() ..
                            line:sub(bufferHandler.cursorX)
        elseif y == startY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.visualStartX - 1) .. line:sub(bufferHandler.visualStartX):upper()
        elseif y == endY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.cursorX - 1):upper() .. line:sub(bufferHandler.cursorX)
        else
            bufferHandler.buffer[y] = line:upper()
        end
    end

    CommandHandler:execute("end_visual_mode")
    bufferHandler:updateStatusBar("Uppercased visual selection")
end)
CommandHandler:map("lowercase_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to convert")
        return
    end

    local startY = math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endY = math.max(bufferHandler.cursorY, bufferHandler.visualStartY)

    bufferHandler:saveToHistory()

    for y = startY, endY do
        local line = bufferHandler.buffer[y]
        if y == startY and y == endY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.visualStartX - 1) ..
                            line:sub(bufferHandler.visualStartX, bufferHandler.cursorX - 1):lower() ..
                            line:sub(bufferHandler.cursorX)
        elseif y == startY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.visualStartX - 1) .. line:sub(bufferHandler.visualStartX):lower()
        elseif y == endY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.cursorX - 1):lower() .. line:sub(bufferHandler.cursorX)
        else
            bufferHandler.buffer[y] = line:lower()
        end
    end

    CommandHandler:execute("end_visual_mode")
    bufferHandler:updateStatusBar("Lowercased visual selection")
end)
CommandHandler:map("join_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to join")
        return
    end

    local startY = math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endY = math.max(bufferHandler.cursorY, bufferHandler.visualStartY)

    bufferHandler:saveToHistory()

    local joinedLine = ""
    for y = startY, endY do
        joinedLine = joinedLine .. bufferHandler.buffer[y]:gsub("%s+$", "")
        bufferHandler.buffer[y] = ""
    end

    bufferHandler.buffer[startY] = joinedLine
    bufferHandler.cursorY = startY
    bufferHandler.cursorX = #joinedLine + 1

    -- Remove empty lines in the range after joining
    for y = startY + 1, endY do
        table.remove(bufferHandler.buffer, startY + 1)
    end

    CommandHandler:execute("end_visual_mode")
    bufferHandler:updateStatusBar("Joined lines")
end)
CommandHandler:map("swap_case_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to swap case")
        return
    end

    local startY = math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endY = math.max(bufferHandler.cursorY, bufferHandler.visualStartY)

    bufferHandler:saveToHistory()

    for y = startY, endY do
        local line = bufferHandler.buffer[y]
        if y == startY and y == endY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.visualStartX - 1) ..
                            line:sub(bufferHandler.visualStartX, bufferHandler.cursorX - 1):gsub(".", function(c)
                                return c:match("%l") and c:upper() or c:lower()
                            end) ..
                            line:sub(bufferHandler.cursorX)
        elseif y == startY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.visualStartX - 1) .. line:sub(bufferHandler.visualStartX):gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end)
        elseif y == endY then
            bufferHandler.buffer[y] = line:sub(1, bufferHandler.cursorX - 1):gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end) .. line:sub(bufferHandler.cursorX)
        else
            bufferHandler.buffer[y] = line:gsub(".", function(c)
                return c:match("%l") and c:upper() or c:lower()
            end)
        end
    end

    CommandHandler:execute("end_visual_mode")
    bufferHandler:updateStatusBar("Swapped case of visual selection")
end)
