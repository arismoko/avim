-- commands.lua
local CommandHandler = require("CommandHandler"):getInstance()
local bufferHandler = require("BufferHandler"):getInstance()
local View = require("View"):getInstance()
--=== HELPER FUNCTIONS ===
local function scrollPage(bufferHandler, linesToScroll)
    -- Calculate the new scroll offset
    bufferHandler.scrollOffset = math.max(0, math.min(bufferHandler.scrollOffset + linesToScroll, #bufferHandler.buffer - SCREENHEIGHT))

    -- Adjust the cursor position based on the scroll direction
    if linesToScroll > 0 then
        -- Scrolling down
        bufferHandler.cursorY = math.min(#bufferHandler.buffer, bufferHandler.cursorY + linesToScroll)
    else
        -- Scrolling up
        bufferHandler.cursorY = math.max(1, bufferHandler.cursorY + linesToScroll)
    end

    -- Ensure the cursor stays within the visible area
    bufferHandler.cursorY = math.max(bufferHandler.scrollOffset + 1, math.min(bufferHandler.cursorY, bufferHandler.scrollOffset + SCREENHEIGHT))

    bufferHandler:updateScroll(SCREENHEIGHT)
end

local function replaceAndMove(bufferHandler, oldPattern, newPattern)
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local startX, endX = line:find(oldPattern, bufferHandler.cursorX)
    if startX then
        local newLine = line:sub(1, startX - 1) .. newPattern .. line:sub(endX + 1)
        bufferHandler.buffer[bufferHandler.cursorY] = newLine
        bufferHandler.cursorX = startX + #newPattern
        bufferHandler:updateScroll(SCREENHEIGHT)
        bufferHandler:updateStatusBar("Replaced '" .. oldPattern .. "' with '" .. newPattern .. "'")
        return true
    end
    return false
end
local function wrapSearch(bufferHandler, pattern, direction, searchFunc)
    local lineCount = #bufferHandler.buffer
    local startY = bufferHandler.lastSearchPosition.y
    local startX = bufferHandler.lastSearchPosition.x

    local y = startY
    while true do
        local line = bufferHandler.buffer[y]
        local startX, endX = searchFunc(line, (y == startY) and startX or 1)

        if startX then
            bufferHandler.cursorY = y
            bufferHandler.cursorX = startX
            bufferHandler:updateScroll(SCREENHEIGHT)
            bufferHandler:updateStatusBar("Found '" .. pattern .. "' at line " .. y)

            bufferHandler.lastSearchPosition = { y = y, x = endX + 1 }

            if y == startY and startX <= bufferHandler.cursorX then
                bufferHandler.lastSearchPosition = { y = startY, x = 1 }
            end

            return true -- Indicate that a match was found
        end

        -- Wraparound search
        if direction == "forward" then
            y = y + 1
            if y > lineCount then y = 1 end
        else
            y = y - 1
            if y < 1 then y = lineCount end
        end

        bufferHandler.lastSearchPosition.x = 1

        if y == startY then
            break
        end
    end

    bufferHandler:updateStatusError("Pattern '" .. pattern .. "' not found")
    bufferHandler.lastSearchPosition = { y = 1, x = 1 }
    return false -- Indicate that no match was found
end
-- Helper function to get the selection range
    local function getSelectionRange(bufferHandler)
        local startX = math.min(bufferHandler.cursorX, bufferHandler.visualStartX)
        local startY = math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
        local endX = math.max(bufferHandler.cursorX, bufferHandler.visualStartX)
        local endY = math.max(bufferHandler.cursorY, bufferHandler.visualStartY)
        return startX, startY, endX, endY
    end
    
    -- Helper function to merge lines after deletion or cutting
    local function mergeLines(bufferHandler, startY, endY)
        if startY ~= endY then
            bufferHandler.buffer[startY] = bufferHandler.buffer[startY] .. (bufferHandler.buffer[startY + 1] or "")
            table.remove(bufferHandler.buffer, startY + 1)
        end
    end
    
    -- Helper function to update the buffer after visual operations
    local function updateBufferAfterVisualOperation(bufferHandler, startX, startY)
        bufferHandler.cursorX = startX
        bufferHandler.cursorY = startY
        CommandHandler:execute("end_visual_mode")
    end
    
    -- Helper function to apply a transformation to a visual selection
    local function transformVisualSelection(bufferHandler, transformFunc)
        local startX, startY, endX, endY = getSelectionRange(bufferHandler)
        bufferHandler:saveToHistory()
    
        for y = startY, endY do
            local line = bufferHandler.buffer[y]
            if y == startY and y == endY then
                bufferHandler.buffer[y] = line:sub(1, startX - 1) .. transformFunc(line:sub(startX, endX - 1)) .. line:sub(endX)
            elseif y == startY then
                bufferHandler.buffer[y] = line:sub(1, startX - 1) .. transformFunc(line:sub(startX))
            elseif y == endY then
                bufferHandler.buffer[y] = transformFunc(line:sub(1, endX - 1)) .. line:sub(endX)
            else
                bufferHandler.buffer[y] = transformFunc(line)
            end
        end
    
        updateBufferAfterVisualOperation(bufferHandler, startX, startY)
    end

    -- Helper function to get the selection range
local function getSelectionRange(bufferHandler)
    local startX = math.min(bufferHandler.cursorX, bufferHandler.visualStartX)
    local startY = math.min(bufferHandler.cursorY, bufferHandler.visualStartY)
    local endX = math.max(bufferHandler.cursorX, bufferHandler.visualStartX)
    local endY = math.max(bufferHandler.cursorY, bufferHandler.visualStartY)
    return startX, startY, endX, endY
end

-- Helper function to move the cursor to the first non-blank character on a line
local function moveToFirstNonBlank(bufferHandler, lineNumber)
    local line = bufferHandler.buffer[lineNumber] or ""
    local firstNonBlankPos = line:find("%S") or 1 -- Find the first non-blank character or default to 1
    bufferHandler.cursorX = firstNonBlankPos
end
-- === END OF HELPER FUNCTIONS ===

-- === Basic Navigation ===
CommandHandler:map("move_left", function()
    bufferHandler:markDirty(bufferHandler.cursorY)  -- Mark the current line as dirty
    bufferHandler.cursorX = math.max(1, bufferHandler.cursorX - 1)
    bufferHandler:refreshScreen()  -- Refresh the screen to reflect the change
end)

CommandHandler:map("move_right", function()
    bufferHandler:markDirty(bufferHandler.cursorY)  -- Mark the current line as dirty
    bufferHandler.cursorX = math.min(#bufferHandler.buffer[bufferHandler.cursorY] + 1, bufferHandler.cursorX + 1)
    bufferHandler:refreshScreen()  -- Refresh the screen to reflect the change
end)

CommandHandler:map("move_up", function()
    bufferHandler:markDirty(bufferHandler.cursorY)  -- Mark the current line as dirty
    if bufferHandler.cursorY > 1 then
        bufferHandler.cursorY = bufferHandler.cursorY - 1
    end
    bufferHandler.cursorX = math.min(bufferHandler.cursorX, #bufferHandler.buffer[bufferHandler.cursorY] + 1)
    bufferHandler:refreshScreen()  -- Refresh the screen to reflect the change
end)

CommandHandler:map("move_down", function()
    bufferHandler:markDirty(bufferHandler.cursorY)  -- Mark the current line as dirty
    if bufferHandler.cursorY < #bufferHandler.buffer then
        bufferHandler.cursorY = bufferHandler.cursorY + 1
    end
    bufferHandler.cursorX = math.min(bufferHandler.cursorX, #bufferHandler.buffer[bufferHandler.cursorY] + 1)
    bufferHandler:refreshScreen()  -- Refresh the screen to reflect the change
end)

CommandHandler:map("page_down", function()
    local linesToScroll = SCREENHEIGHT - 2  -- Number of lines to scroll down (subtract 2 for better visibility)
    scrollPage(bufferHandler, linesToScroll)
end)

CommandHandler:map("page_up", function()
    local linesToScroll = -(SCREENHEIGHT - 2)  -- Number of lines to scroll up (subtract 2 for better visibility)
    scrollPage(bufferHandler, linesToScroll)
end)
CommandHandler:map("half_page_down", function()
    local linesToScroll = math.floor(SCREENHEIGHT / 2)  -- Number of lines to scroll down (half page)
    scrollPage(bufferHandler, linesToScroll)
end)
CommandHandler:map("half_page_up", function()
    local linesToScroll = -math.floor(SCREENHEIGHT / 2)  -- Number of lines to scroll up (half page)
    scrollPage(bufferHandler, linesToScroll)
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
    
    -- Find the start of the next word from the current cursor position
    local nextWordStart = line:find("[^%s]", bufferHandler.cursorX)
    
    if nextWordStart then
        -- Find the end of the word that starts at 'nextWordStart'
        local nextWordEnd = line:find("%s", nextWordStart)
        
        if nextWordEnd then
            -- Move to the end of the current word
            bufferHandler.cursorX = nextWordEnd
        else
            -- If there is no space after the word, move to the end of the line
            bufferHandler.cursorX = #line + 1
        end
    else
        -- If no more words are found, move to the end of the line
        bufferHandler.cursorX = #line + 1
    end
end)

CommandHandler:map("test_status_error", function()
    bufferHandler:updateStatusError("This is an error message")
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
    bufferHandler:saveToHistory()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    if bufferHandler.cursorX <= #line then
        bufferHandler.buffer[bufferHandler.cursorY] = line:sub(1, bufferHandler.cursorX - 1) .. line:sub(bufferHandler.cursorX + 1)
        -- Mark the line as dirty
        bufferHandler:markDirty(bufferHandler.cursorY)
        bufferHandler:updateStatusBar("Deleted character")
    else
        bufferHandler:updateStatusError("Nothing to delete")
    end
end)

CommandHandler:map("delete_char_before", function()
    bufferHandler:saveToHistory()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    if bufferHandler.cursorX > 1 then
        bufferHandler.buffer[bufferHandler.cursorY] = line:sub(1, bufferHandler.cursorX - 2) .. line:sub(bufferHandler.cursorX)
        bufferHandler.cursorX = bufferHandler.cursorX - 1
        bufferHandler:markDirty(bufferHandler.cursorY)
        bufferHandler:updateStatusBar("Deleted character")
    else
        bufferHandler:updateStatusError("Nothing to delete")
    end
end)

CommandHandler:map("cut_line", function(isRepeated)
    local bufferHandler = require("BufferHandler"):getInstance()

    local lineToCut = bufferHandler.buffer[bufferHandler.cursorY]
    if isRepeated then
        bufferHandler.yankRegister = bufferHandler.yankRegister .. "\n" .. lineToCut
    else
        bufferHandler.yankRegister = lineToCut
    end

    -- Remove the line from the buffer
    table.remove(bufferHandler.buffer, bufferHandler.cursorY)

    -- Adjust cursor position
    if bufferHandler.cursorY > #bufferHandler.buffer then
        bufferHandler.cursorY = #bufferHandler.buffer
    end

    if bufferHandler.cursorY == 0 then
        table.insert(bufferHandler.buffer, "")
        bufferHandler.cursorY = 1
    end

    -- Reset cursor position to the beginning of the line

    -- Mark the entire buffer as dirty
    for i = 1, #bufferHandler.buffer do
        bufferHandler:markDirty(i)
    end

    bufferHandler:updateStatusBar("Cut line")
    bufferHandler:refreshScreen()
end)





CommandHandler:map("delete_word", function()
    bufferHandler:saveToHistory()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local nextSpace = line:find("%s", bufferHandler.cursorX)
    if nextSpace then
        line = line:sub(1, bufferHandler.cursorX - 1) .. line:sub(nextSpace + 1)
    else
        line = line:sub(1, bufferHandler.cursorX - 1)
    end
    bufferHandler.buffer[bufferHandler.cursorY] = line
    bufferHandler:markDirty(bufferHandler.cursorY)
    bufferHandler:updateStatusBar("Deleted word")
end)

CommandHandler:map("change_word", function()
    bufferHandler:saveToHistory()
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    local nextSpace = line:find("%s", bufferHandler.cursorX)
    if nextSpace then
        line = line:sub(1, bufferHandler.cursorX - 1) .. line:sub(nextSpace + 1)
    else
        line = line:sub(1, bufferHandler.cursorX - 1)
    end
    bufferHandler.buffer[bufferHandler.cursorY] = line
    bufferHandler:markDirty(bufferHandler.cursorY)
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("yank_line", function(isRepeated)
    local bufferHandler = require("BufferHandler"):getInstance()

    -- Save the original cursor position
    local originalCursorY = bufferHandler.cursorY

    if isRepeated then
        bufferHandler.yankRegister = bufferHandler.yankRegister .. "\n" .. bufferHandler.buffer[bufferHandler.cursorY]
    else
        bufferHandler.yankRegister = bufferHandler.buffer[bufferHandler.cursorY]
    end

    bufferHandler:updateStatusBar("Yanked line")

    -- Move the cursor down after yanking the line
    if bufferHandler.cursorY < #bufferHandler.buffer then
        bufferHandler.cursorY = bufferHandler.cursorY + 1
    end

    -- If this is the final repetition, move the cursor back to the original position
    if not isRepeated then
        bufferHandler.cursorY = originalCursorY
    end

    -- Refresh the screen to reflect the cursor movement
    bufferHandler:refreshScreen()
end)



CommandHandler:map("yank_visual_selection", function()
    bufferHandler:yankSelection()
end)

CommandHandler:map("paste_clipboard", function()
    local event, clipboardText = os.pullEvent("paste")
    if clipboardText then
        
        bufferHandler:saveToHistory()
        bufferHandler:insertTextAtCursor(clipboardText)
        bufferHandler:updateScroll(SCREENHEIGHT)
        bufferHandler:refreshScreen()
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

CommandHandler:map("insert_at_line_end", function()
    bufferHandler.cursorX = #bufferHandler.buffer[bufferHandler.cursorY] + 1
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("delete_char_and_insert", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]

    -- If cursor is beyond the line length, there's nothing to delete
    if bufferHandler.cursorX > #line then
        bufferHandler:updateStatusError("Nothing to delete at the current cursor position")
        return
    end

    -- Save current state for undo
    bufferHandler:saveToHistory()

    -- Delete the character at the cursor position
    bufferHandler.buffer[bufferHandler.cursorY] = line:sub(1, bufferHandler.cursorX - 1) .. line:sub(bufferHandler.cursorX + 1)

    -- Refresh the screen and move to insert mode
    bufferHandler:refreshScreen()
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("delete_line_and_insert", function()
    -- Save current state for undo
    bufferHandler:saveToHistory()

    -- Delete the entire line where the cursor is
    table.remove(bufferHandler.buffer, bufferHandler.cursorY)

    -- If we removed the last line, add an empty line
    if #bufferHandler.buffer == 0 then
        table.insert(bufferHandler.buffer, "")
    end

    -- Move the cursor to the start of the new line
    bufferHandler.cursorX = 1

    -- Ensure cursorY is within the bounds of the buffer
    if bufferHandler.cursorY > #bufferHandler.buffer then
        bufferHandler.cursorY = #bufferHandler.buffer
    end

    -- Refresh the screen and move to insert mode
    bufferHandler:refreshScreen()
    bufferHandler:switchMode("insert")
end)

CommandHandler:map("delete_until_end_of_line_and_insert", function()
    local line = bufferHandler.buffer[bufferHandler.cursorY]

    -- If the cursor is already at the end of the line, there's nothing to delete
    if bufferHandler.cursorX > #line then
        bufferHandler:updateStatusError("Cursor is already at the end of the line")
        bufferHandler:switchMode("insert")
        return
    end

    -- Save current state for undo
    bufferHandler:saveToHistory()

    -- Delete from the cursor position to the end of the line
    bufferHandler.buffer[bufferHandler.cursorY] = line:sub(1, bufferHandler.cursorX - 1)

    -- Refresh the screen and move to insert mode
    bufferHandler:refreshScreen()
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
CommandHandler:map("search", function(pattern, direction)
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

    direction = direction or "forward"

    local searchFunc = function(line, startPos)
        return line:find(pattern, startPos)
    end

    wrapSearch(bufferHandler, pattern, direction, searchFunc)
end)


CommandHandler:map("replace", function(oldPattern, newPattern, direction)
    if not oldPattern or not newPattern then
        bufferHandler:updateStatusError("Usage: :replace <old> <new>")
        return
    end

    bufferHandler.lastReplacePattern = oldPattern
    bufferHandler.replaceWithPattern = newPattern
    bufferHandler.lastReplacePosition = { y = bufferHandler.cursorY, x = bufferHandler.cursorX + 1 }

    direction = direction or "forward"

    local searchFunc = function(line, startPos)
        return line:find(oldPattern, startPos)
    end

    local found = wrapSearch(bufferHandler, oldPattern, direction, searchFunc)
    if found then
        replaceAndMove(bufferHandler, oldPattern, newPattern)
    end
end)

CommandHandler:map("repeat_last_search_or_replace", function()
    if bufferHandler.lastSearchPattern then
        -- Reuse the existing search logic
        CommandHandler:execute("search", bufferHandler.lastSearchPattern)
    elseif bufferHandler.lastReplacePattern and bufferHandler.replaceWithPattern then
        -- Reuse the existing replace logic
        CommandHandler:execute("replace", bufferHandler.lastReplacePattern, bufferHandler.replaceWithPattern)
    else
        bufferHandler:updateStatusError("No previous search or replace operation to repeat")
    end
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
end)

CommandHandler:map("insert_exit_to_normal", function()
    bufferHandler:switchMode("normal")
end)

CommandHandler:map("insert_arrow_up", function()
    -- Normal cursor up movement
    bufferHandler:moveCursorUp()
end)

CommandHandler:map("insert_arrow_down", function()
    -- Normal cursor down movement
    bufferHandler:moveCursorDown()
end)

CommandHandler:map("insert_arrow_left", function()
    -- Normal cursor left movement
    bufferHandler:moveCursorLeft()
end)

CommandHandler:map("insert_arrow_right", function()
    -- Normal cursor right movement
    bufferHandler:moveCursorRight()
end)

CommandHandler:map("insert_tab", function()
    -- Insert a tab character
    bufferHandler:insertChar("    ")
    View:drawLine(bufferHandler.cursorY - bufferHandler.scrollOffset)
end)

CommandHandler:map("insert_enter", function()
    -- Insert a new line
    bufferHandler:enter()
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

-- === Visual Mode Stuff == 


CommandHandler:map("delete_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to delete")
        return
    end

    local startX, startY, endX, endY = getSelectionRange(bufferHandler)

    bufferHandler:saveToHistory()

    -- Delete the selected text
    for y = startY, endY do
        local line = bufferHandler.buffer[y]
        if y == startY and y == endY then
            bufferHandler.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            bufferHandler.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            bufferHandler.buffer[y] = line:sub(endX)
        else
            bufferHandler.buffer[y] = ""
        end
    end

    mergeLines(bufferHandler, startY, endY)
    updateBufferAfterVisualOperation(bufferHandler, startX, startY)

    bufferHandler:updateStatusBar("Deleted visual selection")
end)

CommandHandler:map("cut_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to cut")
        return
    end

    local startX, startY, endX, endY = getSelectionRange(bufferHandler)

    bufferHandler:saveToHistory()
    bufferHandler.yankRegister = ""

    -- Cut the selected text and save it to yank register
    for y = startY, endY do
        local line = bufferHandler.buffer[y]
        if y == startY and y == endY then
            bufferHandler.yankRegister = line:sub(startX, endX - 1)
            bufferHandler.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            bufferHandler.yankRegister = line:sub(startX) .. "\n"
            bufferHandler.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            bufferHandler.yankRegister = bufferHandler.yankRegister .. line:sub(1, endX - 1)
            bufferHandler.buffer[y] = line:sub(endX)
        else
            bufferHandler.yankRegister = bufferHandler.yankRegister .. line .. "\n"
            bufferHandler.buffer[y] = ""
        end
    end

    mergeLines(bufferHandler, startY, endY)
    updateBufferAfterVisualOperation(bufferHandler, startX, startY)

    bufferHandler:updateStatusBar("Cut visual selection")
end)

CommandHandler:map("indent", function(isRepeated)
    local function indentLine(line)
        return " " .. line  -- Indent with four spaces
    end

    bufferHandler:saveToHistory()

    bufferHandler.cursorX = 1
    bufferHandler.buffer[bufferHandler.cursorY] = indentLine(bufferHandler.buffer[bufferHandler.cursorY])
    moveToFirstNonBlank(bufferHandler, bufferHandler.cursorY)
    View:drawLine(bufferHandler.cursorY - bufferHandler.scrollOffset)

    if bufferHandler.cursorY < #bufferHandler.buffer then
        bufferHandler.cursorY = bufferHandler.cursorY + 1
    end

    bufferHandler:updateStatusBar("Indented line(s)")
    bufferHandler:refreshScreen()
end)

CommandHandler:map("unindent", function(isRepeated)
    local function unindentLine(line)
        -- Check if the line starts with 1 space and remove it if so
        return line:sub(1, 1) == " " and line:sub(2) or line
    end

    bufferHandler:saveToHistory()

    bufferHandler.cursorX = 1
    local line = bufferHandler.buffer[bufferHandler.cursorY]
    if line:match("^%s") then
        bufferHandler.buffer[bufferHandler.cursorY] = unindentLine(line)
        moveToFirstNonBlank(bufferHandler, bufferHandler.cursorY)
        View:drawLine(bufferHandler.cursorY - bufferHandler.scrollOffset)
    end

    if bufferHandler.cursorY < #bufferHandler.buffer then
        bufferHandler.cursorY = bufferHandler.cursorY + 1
    end

    bufferHandler:updateStatusBar("Unindented line(s)")
    bufferHandler:refreshScreen()
end)







CommandHandler:map("uppercase_visual_selection", function()
    transformVisualSelection(bufferHandler, string.upper)
    bufferHandler:updateStatusBar("Uppercased visual selection")
end)

CommandHandler:map("lowercase_visual_selection", function()
    transformVisualSelection(bufferHandler, string.lower)
    bufferHandler:updateStatusBar("Lowercased visual selection")
end)

CommandHandler:map("join_visual_selection", function()
    if not bufferHandler.visualStartX or not bufferHandler.visualStartY then
        bufferHandler:updateStatusError("No selection to join")
        return
    end

    local startX, startY, endX, endY = getSelectionRange(bufferHandler)

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

    updateBufferAfterVisualOperation(bufferHandler, startX, startY)
    bufferHandler:updateStatusBar("Joined lines")
end)

CommandHandler:map("swap_case_visual_selection", function()
    bufferHandler:saveToHistory()
    local function swapCase(text)
        return text:gsub(".", function(c)
            return c:match("%l") and c:upper() or c:lower()
        end)
    end

    transformVisualSelection(bufferHandler, swapCase)
    bufferHandler:updateStatusBar("Swapped case of visual selection")
end)
