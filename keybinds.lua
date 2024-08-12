local InputController = require("InputController"):getInstance()
local TextBuffer = require("TextBuffer"):getInstance()
local ScreenManager = require("ScreenManager"):getInstance()

--NOTE: ==================== Helper Functions ====================
local function scrollPage(linesToScroll)
	-- Calculate the new scroll offset
	TextBuffer.scrollOffset =
		math.max(0, math.min(TextBuffer.scrollOffset + linesToScroll, #TextBuffer.buffer - SCREENHEIGHT))

	-- Adjust the cursor position based on the scroll direction
	if linesToScroll > 0 then
		-- Scrolling down
		TextBuffer.cursorY = math.min(#TextBuffer.buffer, TextBuffer.cursorY + linesToScroll)
	else
		-- Scrolling up
		TextBuffer.cursorY = math.max(1, TextBuffer.cursorY + linesToScroll)
	end

	-- Ensure the cursor stays within the visible area
	TextBuffer.cursorY =
		math.max(TextBuffer.scrollOffset + 1, math.min(TextBuffer.cursorY, TextBuffer.scrollOffset + SCREENHEIGHT))

	TextBuffer:updateScroll(SCREENHEIGHT)
end

local function replaceAndMove(oldPattern, newPattern)
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	local startX, endX = line:find(oldPattern, TextBuffer.cursorX)
	if startX then
		local newLine = line:sub(1, startX - 1) .. newPattern .. line:sub(endX + 1)
		TextBuffer.buffer[TextBuffer.cursorY] = newLine
		TextBuffer.cursorX = startX + #newPattern
		TextBuffer:updateScroll(SCREENHEIGHT)
		TextBuffer:updateStatusBar("Replaced '" .. oldPattern .. "' with '" .. newPattern .. "'")
		return true
	end
	return false
end

local function wrapSearch(pattern, direction, searchFunc)
	local lineCount = #TextBuffer.buffer
	local startY = TextBuffer.lastSearchPosition.y
	local startX = TextBuffer.lastSearchPosition.x

	local y = startY
	while true do
		local line = TextBuffer.buffer[y]
		local startX, endX = searchFunc(line, (y == startY) and startX or 1)

		if startX then
			TextBuffer.cursorY = y
			TextBuffer.cursorX = startX
			TextBuffer:updateScroll(SCREENHEIGHT)
			TextBuffer:updateStatusBar("Found '" .. pattern .. "' at line " .. y)

			TextBuffer.lastSearchPosition = { y = y, x = endX + 1 }

			if y == startY and startX <= TextBuffer.cursorX then
				TextBuffer.lastSearchPosition = { y = startY, x = 1 }
			end

			return true -- Indicate that a match was found
		end

		-- Wraparound search
		if direction == "forward" then
			y = y + 1
			if y > lineCount then
				y = 1
			end
		else
			y = y - 1
			if y < 1 then
				y = lineCount
			end
		end

		TextBuffer.lastSearchPosition.x = 1

		if y == startY then
			break
		end
	end

	TextBuffer:updateStatusError("Pattern '" .. pattern .. "' not found")
	TextBuffer.lastSearchPosition = { y = 1, x = 1 }
	return false -- Indicate that no match was found
end

-- Helper function to get the selection range
local function getSelectionRange()
	local startX = math.min(TextBuffer.cursorX, TextBuffer.visualStartX)
	local startY = math.min(TextBuffer.cursorY, TextBuffer.visualStartY)
	local endX = math.max(TextBuffer.cursorX, TextBuffer.visualStartX)
	local endY = math.max(TextBuffer.cursorY, TextBuffer.visualStartY)
	return startX, startY, endX, endY
end

-- Helper function to merge lines after deletion or cutting
local function mergeLines(startY, endY)
	if startY ~= endY then
		TextBuffer.buffer[startY] = TextBuffer.buffer[startY] .. (TextBuffer.buffer[startY + 1] or "")
		table.remove(TextBuffer.buffer, startY + 1)
	end
end

-- Helper function to update the buffer after visual operations
local function updateBufferAfterVisualOperation(startX, startY)
	TextBuffer.cursorX = startX
	TextBuffer.cursorY = startY
	InputController:map("normal", { "end_visual_mode" }, "end_visual_mode", function()
		TextBuffer:endVisualMode()
	end)
end

-- Helper function to apply a transformation to a visual selection
local function transformVisualSelection(transformFunc)
	local startX, startY, endX, endY = getSelectionRange()
	TextBuffer:saveToHistory()

	for y = startY, endY do
		local line = TextBuffer.buffer[y]
		if y == startY and y == endY then
			TextBuffer.buffer[y] = line:sub(1, startX - 1)
				.. transformFunc(line:sub(startX, endX - 1))
				.. line:sub(endX)
		elseif y == startY then
			TextBuffer.buffer[y] = line:sub(1, startX - 1) .. transformFunc(line:sub(startX))
		elseif y == endY then
			TextBuffer.buffer[y] = transformFunc(line:sub(1, endX - 1)) .. line:sub(endX)
		else
			TextBuffer.buffer[y] = transformFunc(line)
		end
	end

	updateBufferAfterVisualOperation(TextBuffer, startX)
end

-- Helper function to move the cursor to the first non-blank character on a line
local function moveToFirstNonBlank(lineNumber)
	local line = TextBuffer.buffer[lineNumber] or ""
	local firstNonBlankPos = line:find("%S") or 1 -- Find the first non-blank character or default to 1
	TextBuffer.cursorX = firstNonBlankPos
end

--NOTE: ==================== Navigation Keybindings ====================
InputController:map({ "normal", "visual" }, { "h" }, "move_left", function()
	TextBuffer:markDirty(TextBuffer.cursorY)
	TextBuffer.cursorX = math.max(1, TextBuffer.cursorX - 1)
end, "Move Left")

InputController:map({ "normal", "visual" }, { "l" }, "move_right", function()
	TextBuffer:markDirty(TextBuffer.cursorY)
	TextBuffer.cursorX = math.min(#TextBuffer.buffer[TextBuffer.cursorY] + 1, TextBuffer.cursorX + 1)
end, "Move Right")

InputController:map({ "normal", "visual" }, { "k" }, "move_up", function()
	TextBuffer:markDirty(TextBuffer.cursorY)
	if TextBuffer.cursorY > 1 then
		TextBuffer.cursorY = TextBuffer.cursorY - 1
	end
	TextBuffer.cursorX = math.min(TextBuffer.cursorX, #TextBuffer.buffer[TextBuffer.cursorY] + 1)
end, "Move Up")

InputController:map({ "normal", "visual" }, { "j" }, "move_down", function()
	TextBuffer:markDirty(TextBuffer.cursorY)
	if TextBuffer.cursorY < #TextBuffer.buffer then
		TextBuffer.cursorY = TextBuffer.cursorY + 1
	end
	TextBuffer.cursorX = math.min(TextBuffer.cursorX, #TextBuffer.buffer[TextBuffer.cursorY] + 1)
end, "Move Down")

InputController:map({ "normal", "visual" }, { "ctrl + f" }, "page_down", function()
	local linesToScroll = SCREENHEIGHT - 2
	scrollPage(linesToScroll)
end, "Page Down")

InputController:map({ "normal", "visual" }, { "ctrl + b" }, "page_up", function()
	local linesToScroll = -(SCREENHEIGHT - 2)
	scrollPage(linesToScroll)
end, "Page Up")

InputController:map({ "normal", "visual" }, { "ctrl + d" }, "half_page_down", function()
	local linesToScroll = math.floor(SCREENHEIGHT / 2)
	scrollPage(linesToScroll)
end, "Half Page Down")

InputController:map({ "normal", "visual" }, { "ctrl + u" }, "half_page_up", function()
	local linesToScroll = -math.floor(SCREENHEIGHT / 2)
	scrollPage(linesToScroll)
end, "Half Page Up")

InputController:map({ "normal", "visual" }, { "g + g" }, "move_to_top", function()
	TextBuffer.cursorY = 1
	TextBuffer.cursorX = 1
	TextBuffer:updateScroll()
end, "Move to Top")

InputController:map({ "normal", "visual" }, { "G" }, "move_to_bottom", function()
	TextBuffer.cursorY = #TextBuffer.buffer
	TextBuffer.cursorX = 1
	TextBuffer:updateScroll()
end, "Move to Bottom")

InputController:map({ "normal", "visual" }, { "H" }, "move_to_top_of_screen", function()
	local screenStart = TextBuffer.scrollOffset + 1
	if screenStart > #TextBuffer.buffer then
		screenStart = #TextBuffer.buffer
	else
		TextBuffer.cursorY = screenStart
	end
	TextBuffer:updateStatusBar("Moved to top of screen")
end, "Move to Top of Screen")

InputController:map({ "normal", "visual" }, { "M" }, "move_to_middle_of_screen", function()
	local screenHeight = SCREENHEIGHT
	local screenMiddle = math.floor(screenHeight / 2)
	if screenMiddle > #TextBuffer.buffer then
		screenMiddle = #TextBuffer.buffer
	end
	TextBuffer.cursorY = screenMiddle
	TextBuffer:updateStatusBar("Moved to middle of screen")
end, "Move to Middle of Screen")

InputController:map({ "normal", "visual" }, { "L" }, "move_to_bottom_of_screen", function()
	local screenHeight = SCREENHEIGHT
	local screenEnd = TextBuffer.scrollOffset + screenHeight - 1
	if screenEnd > #TextBuffer.buffer then
		screenEnd = #TextBuffer.buffer
	end
	TextBuffer.cursorY = screenEnd
	TextBuffer:updateStatusBar("Moved to bottom of screen")
end, "Move to Bottom of Screen")

-- === Word and Line Motions ===
InputController:map({ "normal", "visual" }, { "w" }, "move_word_forward", function()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	local nextSpace = line:find("%s", TextBuffer.cursorX)
	if nextSpace then
		TextBuffer.cursorX = nextSpace + 1
	else
		TextBuffer.cursorX = #line + 1
	end
end, "Move to Next Word")

InputController:map({ "normal", "visual" }, { "b" }, "move_word_back", function()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	local prevSpace = line:sub(1, TextBuffer.cursorX - 1):find("%s[^%s]*$")
	if prevSpace then
		TextBuffer.cursorX = prevSpace
	else
		TextBuffer.cursorX = 1
	end
end, "Move to Previous Word")

InputController:map({ "normal", "visual" }, { "e" }, "move_word_end", function()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	-- Find the start of the next word from the current cursor position
	local nextWordStart = line:find("[^%s]", TextBuffer.cursorX)
	if nextWordStart then
		-- Find the end of the word that starts at 'nextWordStart'
		local nextWordEnd = line:find("%s", nextWordStart)
		if nextWordEnd then
			-- Move to the end of the current word
			TextBuffer.cursorX = nextWordEnd
		else
			-- If there is no space after the word, move to the end of the line
			TextBuffer.cursorX = #line + 1
		end
	else
		-- If no more words are found, move to the end of the line
		TextBuffer.cursorX = #line + 1
	end
end, "Move to End of Word")

InputController:map({ "normal", "visual" }, { "0" }, "move_to_line_start", function()
	TextBuffer.cursorX = 1
end, "Move to Start of Line")

InputController:map({ "normal", "visual" }, { "//" }, "move_to_first_non_blank", function()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	local firstNonBlank = line:find("%S")
	if firstNonBlank then
		TextBuffer.cursorX = firstNonBlank
	else
		TextBuffer.cursorX = 1
	end
end, "Move to First Non-Blank Character")

InputController:map({ "normal", "visual" }, { "$" }, "move_to_line_end", function()
	TextBuffer.cursorX = #TextBuffer.buffer[TextBuffer.cursorY] + 1
end, "Move to End of Line")

--NOTE: ==================== Editing Keybindings ====================
InputController:map({ "normal" }, { "d + d" }, "cut_line", function(isRepeated, iteration, count)
	TextBuffer:saveToHistory()
	if iteration == 1 then
		TextBuffer.yankRegister = ""
	end
	local lineToCut = TextBuffer.buffer[TextBuffer.cursorY]
	if isRepeated then
		TextBuffer.yankRegister = TextBuffer.yankRegister .. "\n" .. lineToCut
	else
		TextBuffer.yankRegister = lineToCut
	end

	-- Remove the line from the buffer
	table.remove(TextBuffer.buffer, TextBuffer.cursorY)

	-- Adjust cursor position after cutting the line
	if TextBuffer.cursorY > #TextBuffer.buffer then
		TextBuffer:moveCursorUp(1) -- Move cursor up if cutting the last line
	else
		TextBuffer:moveCursorDown(0) -- Keep cursor on the current line or move down if there are more lines
	end

	-- Ensure there's always at least one line in the buffer
	if #TextBuffer.buffer == 0 then
		table.insert(TextBuffer.buffer, "")
		TextBuffer.cursorY = 1
	end

	term.clear()
	TextBuffer:updateStatusBar("Cut line")
end, "Cut Line")

InputController:map({ "normal" }, { "d + w" }, "delete_word", function()
	TextBuffer:saveToHistory()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	local nextSpace = line:find("%s", TextBuffer.cursorX)
	if nextSpace then
		line = line:sub(1, TextBuffer.cursorX - 1) .. line:sub(nextSpace + 1)
	else
		line = line:sub(1, TextBuffer.cursorX - 1)
	end
	TextBuffer.buffer[TextBuffer.cursorY] = line
	TextBuffer:markDirty(TextBuffer.cursorY)
	TextBuffer:updateStatusBar("Deleted word")
end, "Delete Word")

InputController:map({ "normal" }, { "c + w^" }, "change_word", function()
	TextBuffer:saveToHistory()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	local nextSpace = line:find("%s", TextBuffer.cursorX)
	if nextSpace then
		line = line:sub(1, TextBuffer.cursorX - 1) .. line:sub(nextSpace + 1)
	else
		line = line:sub(1, TextBuffer.cursorX - 1)
	end
	TextBuffer.buffer[TextBuffer.cursorY] = line
	TextBuffer:markDirty(TextBuffer.cursorY)
	TextBuffer:switchMode("insert")
end, "Change Word")

InputController:map({ "normal" }, { "y + y" }, "yank_line", function(isRepeated, iteration)
	if iteration == 1 then
		TextBuffer.yankRegister = ""
	end
	-- Save the original cursor position
	local originalCursorY = TextBuffer.cursorY

	if isRepeated then
		TextBuffer.yankRegister = TextBuffer.yankRegister .. "\n" .. TextBuffer.buffer[TextBuffer.cursorY]
	else
		TextBuffer.yankRegister = TextBuffer.buffer[TextBuffer.cursorY]
	end

	TextBuffer:updateStatusBar("Yanked line")

	-- Move the cursor down after yanking the line
	if TextBuffer.cursorY < #TextBuffer.buffer then
		TextBuffer.cursorY = TextBuffer.cursorY + 1
	end

	-- If this is the final repetition, move the cursor back to the original position
	if not isRepeated then
		TextBuffer.cursorY = originalCursorY
	end
end, "Yank Line")

InputController:map({ "normal", "visual" }, { "x" }, "delete_char", function()
	TextBuffer:saveToHistory()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	if TextBuffer.cursorX <= #line then
		TextBuffer.buffer[TextBuffer.cursorY] = line:sub(1, TextBuffer.cursorX - 1) .. line:sub(TextBuffer.cursorX + 1)
		TextBuffer:markDirty(TextBuffer.cursorY)
		TextBuffer:updateStatusBar("Deleted character")
	else
		TextBuffer:updateStatusError("Nothing to delete")
	end
end, "Delete Char")

InputController:map({ "normal", "visual" }, { "X" }, "delete_char_before", function()
	TextBuffer:saveToHistory()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	if TextBuffer.cursorX > 1 then
		TextBuffer.buffer[TextBuffer.cursorY] = line:sub(1, TextBuffer.cursorX - 2) .. line:sub(TextBuffer.cursorX)
		TextBuffer.cursorX = TextBuffer.cursorX - 1
		TextBuffer:markDirty(TextBuffer.cursorY)
		TextBuffer:updateStatusBar("Deleted character")
	else
		TextBuffer:updateStatusError("Nothing to delete")
	end
end, "Delete Char Before")

InputController:map({ "normal" }, { "p" }, "paste", function()
	TextBuffer:paste()
	TextBuffer:updateStatusBar("Pasted text")
end, "Paste")

InputController:map({ "normal" }, { "u" }, "undo", function()
	TextBuffer:undo()
end, "Undo")

InputController:map({ "normal" }, { "ctrl + r" }, "redo", function()
	TextBuffer:redo()
end, "Redo")

InputController:map({ "normal", "insert" }, { "ctrl + v" }, "paste_clipboard", function()
	local event, clipboardText = os.pullEvent("paste")
	if clipboardText then
		TextBuffer:saveToHistory()

		-- Save the current cursor position
		local originalCursorX = TextBuffer.cursorX
		local originalCursorY = TextBuffer.cursorY

		-- Split the clipboard text into lines
		local lines = {}
		for line in clipboardText:gmatch("([^\r\n]*)\r?\n?") do
			-- Remove leading indentation (whitespace) from each line
			line = line:gsub("^%s+", "")
			table.insert(lines, line)
		end

		-- Insert each line into the buffer
		for i, line in ipairs(lines) do
			TextBuffer:insertTextAtCursor(line)
			if i < #lines then
				TextBuffer.cursorY = TextBuffer.cursorY + 1 -- Move the cursor down to the new line
				TextBuffer.cursorX = 1 -- Move cursor to the start of the line
			end
		end

		-- Restore the cursor to its original position
		TextBuffer.cursorX = originalCursorX
		TextBuffer.cursorY = originalCursorY

		TextBuffer:updateScroll(SCREENHEIGHT)
		TextBuffer:updateStatusBar("Pasted text from clipboard")
	else
		TextBuffer:updateStatusError("No text in clipboard or paste operation failed")
	end
end, "Paste Clipboard")

--NOTE: ==================== Mode Keybindings ====================
InputController:map({ "normal" }, { "i^" }, "enter_insert_mode", function()
	TextBuffer:switchMode("insert")
end, "Enter Insert Mode")

InputController:map({ "normal" }, { "a^" }, "append_to_line", function()
	TextBuffer.cursorX = math.min(TextBuffer.cursorX + 1, #TextBuffer.buffer[TextBuffer.cursorY] + 1)
	TextBuffer:switchMode("insert")
end, "Append to Line")

InputController:map({ "normal" }, { "shift + a^" }, "append_to_line_end", function()
	TextBuffer.cursorX = #TextBuffer.buffer[TextBuffer.cursorY] + 1
	TextBuffer:switchMode("insert")
end, "Append to Line End")

InputController:map({ "normal" }, { "shift + i^" }, "insert_at_line_start", function()
	local line = TextBuffer.buffer[TextBuffer.cursorY]
	local firstNonBlank = line:find("%S")
	if firstNonBlank then
		TextBuffer.cursorX = firstNonBlank
	else
		TextBuffer.cursorX = 1
	end
	TextBuffer:switchMode("insert")
end, "Insert at Line Start")

InputController:map({ "normal" }, { "o^" }, "open_line_below", function()
	local line = TextBuffer.cursorY
	table.insert(TextBuffer.buffer, line + 1, "")
	TextBuffer.cursorY = line + 1
	TextBuffer.cursorX = 1
	TextBuffer:switchMode("insert")
end, "Open Line Below")

InputController:map({ "normal" }, { "shift + o^" }, "open_line_above", function()
	local line = TextBuffer.cursorY
	table.insert(TextBuffer.buffer, line, "")
	TextBuffer.cursorY = line
	TextBuffer.cursorX = 1
	TextBuffer:switchMode("insert")
end, "Open Line Above")

InputController:map({ "normal" }, { "s^" }, "delete_char_and_insert", function()
	local line = TextBuffer.buffer[TextBuffer.cursorY]

	-- If cursor is beyond the line length, there's nothing to delete
	if TextBuffer.cursorX > #line then
		TextBuffer:updateStatusError("Nothing to delete at the current cursor position")
		return
	end

	-- Save current state for undo
	TextBuffer:saveToHistory()

	-- Delete the character at the cursor position
	TextBuffer.buffer[TextBuffer.cursorY] = line:sub(1, TextBuffer.cursorX - 1) .. line:sub(TextBuffer.cursorX + 1)

	-- Refresh the screen and move to insert mode
	TextBuffer:switchMode("insert")
end, "Substitute Char")

InputController:map({ "normal" }, { "shift + s^" }, "delete_line_and_insert", function()
	-- Save current state for undo
	TextBuffer:saveToHistory()

	-- Delete the entire line where the cursor is
	table.remove(TextBuffer.buffer, TextBuffer.cursorY)

	-- If we removed the last line, add an empty line
	if #TextBuffer.buffer == 0 then
		table.insert(TextBuffer.buffer, "")
	end

	-- Move the cursor to the start of the new line
	TextBuffer.cursorX = 1

	-- Ensure cursorY is within the bounds of the buffer
	if TextBuffer.cursorY > #TextBuffer.buffer then
		TextBuffer.cursorY = #TextBuffer.buffer
	end

	-- Refresh the screen and move to insert mode
	TextBuffer:switchMode("insert")
end, "Substitute Line")

InputController:map({ "normal" }, { "shift + c^" }, "delete_until_end_of_line_and_insert", function()
	local line = TextBuffer.buffer[TextBuffer.cursorY]

	-- If the cursor is already at the end of the line, there's nothing to delete
	if TextBuffer.cursorX > #line then
		TextBuffer:updateStatusError("Cursor is already at the end of the line")
		TextBuffer:switchMode("insert")
		return
	end

	-- Save current state for undo
	TextBuffer:saveToHistory()

	-- Delete from the cursor position to the end of the line
	TextBuffer.buffer[TextBuffer.cursorY] = line:sub(1, TextBuffer.cursorX - 1)

	-- Refresh the screen and move to insert mode
	TextBuffer:switchMode("insert")
end, "Change to Line End")

InputController:map({ "normal" }, { ":", "shift + semiColon" }, "__enter_command_mode", function()
	TextBuffer:switchMode("command")
end, "Enter Command Mode")

InputController:map({ "normal" }, { "v" }, "enter_visual_mode", function()
	TextBuffer:startVisualMode()
end, "Enter Visual Mode")

InputController:map({ "normal" }, { "f9" }, "exit_editor", function()
	TextBuffer.shouldExit = true
end, "Exit Editor")

InputController:map({ "normal" }, { "ctrl + g" }, "goto_line", function(_, _, lineNumber)
	lineNumber = tonumber(lineNumber)
	if not lineNumber or lineNumber < 1 or lineNumber > #TextBuffer.buffer then
		TextBuffer:updateStatusError("Invalid line number: " .. (lineNumber or ""))
		return
	end
	TextBuffer.cursorY = lineNumber
	TextBuffer.cursorX = 1
	TextBuffer:updateScroll(SCREENHEIGHT)
	TextBuffer:updateStatusBar("Moved to line " .. lineNumber)
end, "Go to Line")

--NOTE: ==================== Search and Replace Keybindings =================
InputController:mapCommand("search", function(pattern, direction)
	if not pattern then
		pattern = TextBuffer.lastSearchPattern
		if not pattern then
			TextBuffer:updateStatusError("No previous search pattern to repeat")
			return
		end
	else
		TextBuffer.lastSearchPattern = pattern
		TextBuffer.lastSearchPosition = { y = TextBuffer.cursorY, x = TextBuffer.cursorX + 1 }
	end

	direction = direction or "forward"

	local searchFunc = function(line, startPos)
		return line:find(pattern, startPos)
	end

	wrapSearch(pattern, direction, searchFunc)
end)
InputController:map({ "normal" }, { "/" }, "__search", function()
	TextBuffer:switchMode("command", "search ")
end, "Search")
InputController:mapCommand("replace", function(oldPattern, newPattern, direction)
	if not oldPattern or not newPattern then
		TextBuffer:updateStatusError("Usage: :replace <old> <new>")
		return
	end

	TextBuffer.lastReplacePattern = oldPattern
	TextBuffer.replaceWithPattern = newPattern
	TextBuffer.lastReplacePosition = { y = TextBuffer.cursorY, x = TextBuffer.cursorX + 1 }

	direction = direction or "forward"

	local searchFunc = function(line, startPos)
		return line:find(oldPattern, startPos)
	end

	local found = wrapSearch(oldPattern, direction, searchFunc)
	if found then
		replaceAndMove(oldPattern, newPattern)
	end
end)

InputController:map({ "normal" }, { "?" }, "__replace", function()
	TextBuffer:switchMode("command", "replace ")
end, "Replace")

InputController:map({ "normal" }, { "n" }, "__repeat_last_search_or_replace", function()
	if TextBuffer.lastSearchPattern then
		-- Reuse the existing search logic
		InputController:executeCommand("search " .. TextBuffer.lastSearchPattern)
	elseif TextBuffer.lastReplacePattern and TextBuffer.replaceWithPattern then
		-- Reuse the existing replace logic
		InputController:executeCommand(
			"replace " .. TextBuffer.lastReplacePattern .. " " .. TextBuffer.replaceWithPattern
		)
	else
		TextBuffer:updateStatusError("No previous search or replace operation to repeat")
	end
end, "Repeat Last Search or Replace")

InputController:map({ "normal" }, { "ctrl + /" }, "replace_all", function(oldPattern, newPattern)
	if not oldPattern or not newPattern then
		TextBuffer:updateStatusError("Usage: :replace_all <old> <new>")
		return
	end

	local replacements = 0

	for y, line in ipairs(TextBuffer.buffer) do
		local newLine, count = line:gsub(oldPattern, newPattern)
		if count > 0 then
			TextBuffer.buffer[y] = newLine
			replacements = replacements + count
		end
	end

	if replacements > 0 then
		TextBuffer:updateScroll(SCREENHEIGHT)
		TextBuffer:updateStatusBar(
			"Replaced " .. replacements .. " occurrence(s) of '" .. oldPattern .. "' with '" .. newPattern .. "'"
		)
	else
		TextBuffer:updateStatusError("No occurrences of '" .. oldPattern .. "' found")
	end
end, "Replace All")

--NOTE: ==================== Insert Mode Keybindings ====================
InputController:map({ "insert" }, { "f1" }, "insert_exit_to_normal", function()
	TextBuffer:switchMode("normal")
end, "Exit to Normal Mode")

InputController:map({ "insert" }, { "left" }, "move_left", function()
	TextBuffer:markDirty(TextBuffer.cursorY)
	TextBuffer.cursorX = math.max(1, TextBuffer.cursorX - 1)
end, "Move Left")

InputController:map({ "insert" }, { "right" }, "move_right", function()
	TextBuffer:markDirty(TextBuffer.cursorY)
	TextBuffer.cursorX = math.min(#TextBuffer.buffer[TextBuffer.cursorY] + 1, TextBuffer.cursorX + 1)
end, "Move Right")

InputController:map({ "insert" }, { "up" }, "move_up", function()
	TextBuffer:markDirty(TextBuffer.cursorY)
	if TextBuffer.cursorY > 1 then
		TextBuffer.cursorY = TextBuffer.cursorY - 1
	end
	TextBuffer.cursorX = math.min(TextBuffer.cursorX, #TextBuffer.buffer[TextBuffer.cursorY] + 1)
end, "Move Up")

InputController:map({ "insert" }, { "down" }, "move_down", function()
	TextBuffer:markDirty(TextBuffer.cursorY)
	if TextBuffer.cursorY < #TextBuffer.buffer then
		TextBuffer.cursorY = TextBuffer.cursorY + 1
	end
	TextBuffer.cursorX = math.min(TextBuffer.cursorX, #TextBuffer.buffer[TextBuffer.cursorY] + 1)
end, "Move Down")

InputController:map({ "insert" }, { "tab" }, "insert_tab", function()
	TextBuffer:tab()
end, "Insert Tab")

InputController:map({ "insert" }, { "enter" }, "insert_enter", function()
	TextBuffer:enter()
end, "Insert New Line")

InputController:map({ "insert" }, { "backspace" }, "insert_backspace", function()
	TextBuffer:backspace()
end, "Backspace")

--NOTE: ==================== Visual Mode Keybindings ====================
InputController:map({ "visual" }, { "y" }, "yank_visual_selection", function()
	TextBuffer:yankSelection()
	InputController:executeCommand("end_visual_mode")
end, "Yank Visual Selection and Exit Visual Mode")

InputController:map({ "visual" }, { "x" }, "delete_visual_selection", function()
	if not TextBuffer.visualStartX or not TextBuffer.visualStartY then
		TextBuffer:updateStatusError("No selection to delete")
		return
	end

	local startX, startY, endX, endY = getSelectionRange()

	TextBuffer:saveToHistory()

	for y = startY, endY do
		local line = TextBuffer.buffer[y]
		if y == startY and y == endY then
			TextBuffer.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
		elseif y == startY then
			TextBuffer.buffer[y] = line:sub(1, startX - 1)
		elseif y == endY then
			TextBuffer.buffer[y] = line:sub(endX)
		else
			TextBuffer.buffer[y] = ""
		end
	end

	mergeLines(startY, endY)
	updateBufferAfterVisualOperation(startX, startY)

	TextBuffer:updateStatusBar("Deleted visual selection")
	InputController:executeCommand("end_visual_mode")
end, "Delete Visual Selection and Exit Visual Mode")

InputController:map({ "visual" }, { "c^" }, "change_visual_selection", function()
	InputController:executeCommand("delete_visual_selection")
	TextBuffer:switchMode("insert")
end, "Change Visual Selection")

InputController:map({ "visual" }, { "d" }, "cut_visual_selection", function()
	if not TextBuffer.visualStartX or not TextBuffer.visualStartY then
		TextBuffer:updateStatusError("No selection to cut")
		return
	end

	local startX, startY, endX, endY = getSelectionRange()

	TextBuffer:saveToHistory()
	TextBuffer.yankRegister = ""

	for y = startY, endY do
		local line = TextBuffer.buffer[y]
		if y == startY and y == endY then
			TextBuffer.yankRegister = line:sub(startX, endX - 1)
			TextBuffer.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
		elseif y == startY then
			TextBuffer.yankRegister = line:sub(startX) .. "\n"
			TextBuffer.buffer[y] = line:sub(1, startX - 1)
		elseif y == endY then
			TextBuffer.yankRegister = TextBuffer.yankRegister .. line:sub(1, endX - 1)
			TextBuffer.buffer[y] = line:sub(endX)
		else
			TextBuffer.yankRegister = TextBuffer.yankRegister .. line .. "\n"
			TextBuffer.buffer[y] = ""
		end
	end

	mergeLines(startY, endY)
	updateBufferAfterVisualOperation(startX, startY)

	TextBuffer:updateStatusBar("Cut visual selection")
	InputController:executeCommand("end_visual_mode")
end, "Cut Visual Selection and Exit Visual Mode")

InputController:map({ "visual", "normal" }, { "<" }, "unindent", function()
	local function unindentLine(line)
		local tabWidth = TextBuffer.tabWidth or 4
		if line:sub(1, tabWidth):match("^%s+$") then
			return line:sub(tabWidth + 1)
		else
			return line:gsub("^%s+", "", 1)
		end
	end

	TextBuffer:saveToHistory()

	if TextBuffer.isVisualMode then
		local startX, startY, endX, endY = getSelectionRange()
		for i = startY, endY do
			TextBuffer.buffer[i] = unindentLine(TextBuffer.buffer[i])
			ScreenManager:drawLine(i - TextBuffer.scrollOffset)
		end
		TextBuffer:updateStatusBar("Unindented selection")
	else
		TextBuffer.cursorX = 1
		local line = TextBuffer.buffer[TextBuffer.cursorY]
		TextBuffer.buffer[TextBuffer.cursorY] = unindentLine(line)
		moveToFirstNonBlank(TextBuffer.cursorY)
		ScreenManager:drawLine(TextBuffer.cursorY - TextBuffer.scrollOffset)
		TextBuffer:updateStatusBar("Unindented line")
	end
end, "Unindent visual selection or line")

InputController:map({ "visual", "normal" }, { ">" }, "indent", function()
	local function indentLine(line)
		local tabWidth = TextBuffer.tabWidth or 4
		return string.rep(" ", tabWidth) .. line
	end

	TextBuffer:saveToHistory()

	if TextBuffer.isVisualMode then
		local startX, startY, endX, endY = getSelectionRange()
		for i = startY, endY do
			TextBuffer.buffer[i] = indentLine(TextBuffer.buffer[i])
			ScreenManager:drawLine(i - TextBuffer.scrollOffset)
		end
		TextBuffer:updateStatusBar("Indented selection")
	else
		TextBuffer.cursorX = 1
		TextBuffer.buffer[TextBuffer.cursorY] = indentLine(TextBuffer.buffer[TextBuffer.cursorY])
		moveToFirstNonBlank(TextBuffer.cursorY)
		ScreenManager:drawLine(TextBuffer.cursorY - TextBuffer.scrollOffset)
		TextBuffer:updateStatusBar("Indented line")
	end
end, "Indent visual selection or line")

InputController:map({ "visual" }, { "U" }, "uppercase_visual_selection", function()
	transformVisualSelection(string.upper)
	TextBuffer:updateStatusBar("Uppercased visual selection")
end, "Uppercase Visual Selection")

InputController:map({ "visual" }, { "u" }, "lowercase_visual_selection", function()
	transformVisualSelection(string.lower)
	TextBuffer:updateStatusBar("Lowercased visual selection")
end, "Lowercase Visual Selection")

InputController:map({ "visual" }, { "J" }, "join_visual_selection", function()
	if not TextBuffer.visualStartX or not TextBuffer.visualStartY then
		TextBuffer:updateStatusError("No selection to join")
		return
	end

	local startX, startY, endX, endY = getSelectionRange()

	TextBuffer:saveToHistory()

	local joinedLine = ""
	for y = startY, endY do
		joinedLine = joinedLine .. TextBuffer.buffer[y]:gsub("%s+$", "")
		TextBuffer.buffer[y] = ""
	end

	TextBuffer.buffer[startY] = joinedLine
	TextBuffer.cursorY = startY
	TextBuffer.cursorX = #joinedLine + 1

	for y = startY + 1, endY do
		table.remove(TextBuffer.buffer, startY + 1)
	end

	updateBufferAfterVisualOperation(startX, startY)
	TextBuffer:updateStatusBar("Joined lines")
end, "Join Visual Selection")

InputController:map({ "visual" }, { "~" }, "swap_case_visual_selection", function()
	TextBuffer:saveToHistory()
	local function swapCase(text)
		return text:gsub(".", function(c)
			return c:match("%l") and c:upper() or c:lower()
		end)
	end

	transformVisualSelection(swapCase)
	TextBuffer:updateStatusBar("Swapped case of visual selection")
end, "Swap Case of Visual Selection")

InputController:map({ "visual" }, { "v" }, "end_visual_mode", function()
	TextBuffer:endVisualMode()
end, "End Visual Mode")
--NOTE: ==================== Command Mode Keybindings ====================
InputController:mapCommand("w", function(name)
	if name then
		TextBuffer:saveFileAs(name)
	else
		TextBuffer:saveFile()
	end
end)

InputController:mapCommand("qa!", function()
	TextBuffer.shouldExit = true
end)

InputController:mapCommand("qa", function()
	local filename = TextBuffer.filename
	if not fs.exists(filename) then
		TextBuffer:updateStatusError("File does not exist, use :qa! to exit without saving")
		return
	end
	--check if filename..".temp" exists, delete it
	if fs.exists(filename .. ".temp") then
		fs.delete(filename .. ".temp")
	end
	TextBuffer:saveFileAs(filename .. ".temp")
	--compare the .temp file with the current file and if they are the same, delete the .temp file and exit other wise throw updateStatusError
	local file1 = fs.open(filename, "r")
	local file2 = fs.open(filename .. ".temp", "r")
	if file1 == nil then
		TextBuffer.updateStatusError("Error reading file")
		return
	end
	if file2 == nil then
		TextBuffer.updateStatusError("Error reading file")
		return
	end
	local file1Content = file1.readAll()
	local file2Content = file2.readAll()
	file1.close()
	file2.close()
	if file1Content == file2Content then
		TextBuffer.shouldExit = true
	else
		TextBuffer:updateStatusError("File has been modified, use :qa! to exit without saving")
	end
	if fs.exists(filename .. ".temp") then
		fs.delete(filename .. ".temp")
	end
end)

InputController:mapCommand("q", function()
	if ScreenManager.activeWindow then
		ScreenManager.activeWindow:close()
	else
		InputController:executeCommand("qa")
	end
end)

InputController:mapCommand("q!", function()
	if ScreenManager.activeWindow then
		ScreenManager:closeAllWindows()
	else
		TextBuffer.shouldExit = true
	end
end)

InputController:mapCommand("wq", function(name)
	if name then
		TextBuffer:saveFileAs(name)
	else
		TextBuffer:saveFile()
	end
	if not TextBuffer.shouldExit then
		TextBuffer.shouldExit = true
	end
end)
InputController:mapCommand("run", function()
	local filename = TextBuffer.filename
	if not fs.exists(filename) then
		TextBuffer:updateStatusError("File does not exist")
		return
	end
	local id = shell.openTab(filename)
	term.clear()
	shell.switchTab(id)
end)
InputController:mapCommand("run!", function()
	local filename = TextBuffer.filename
	if not fs.exists(filename) then
		TextBuffer:updateStatusError("File does not exist")
		return
	end
	term.clear()
	shell.run(filename)
end)

InputController:mapCommand("cd", function(dir)
	if not dir then
		TextBuffer:updateStatusError("No directory specified")
		return
	end
	if not fs.exists(dir) then
		TextBuffer:updateStatusError("Directory does not exist")
		return
	end
	shell.setDir(dir)
end)

InputController:mapCommand("ls", function()
	local currentDir = shell.dir()
	if currentDir == "" then
		currentDir = "ROOT"
	else
		currentDir = "~/" .. currentDir
	end
	TextBuffer:updateStatusBar(currentDir)
end)

InputController:map({ "normal" }, { "f3" }, "show_keybindings", function()
	local descriptions = InputController:getKeyDescriptions(TextBuffer.mode)
	local keybindsWindow =
		ScreenManager:createWindow(1, 1, SCREENWIDTH, SCREENHEIGHT - 1, colors.lightGray, colors.black)

	local startIndex = 1
	local itemsPerPage = keybindsWindow.height - 2

	local function displayKeybindings(startIndex)
		keybindsWindow:clear()
		keybindsWindow:print("Keybindings for " .. TextBuffer.mode:upper() .. " Mode:")
		for i = startIndex, math.min(#descriptions, startIndex + itemsPerPage - 1) do
			local desc = descriptions[i]
			keybindsWindow:writeline("  " .. desc.combo .. (desc.description ~= "" and ": " .. desc.description or ""))
		end
		keybindsWindow:show()
	end

	displayKeybindings(startIndex)

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
end, "Show Keybindings")

InputController:map({ "normal", "visual", "insert" }, { "f4" }, "close_windows", function()
	ScreenManager:closeAllWindows()
end, "Close Windows")

InputController:map({ "n", "v" }, ".", "__repeat_last_command", function()
	TextBuffer:switchMode("command", nil, true)
end, "Repeat Last Command")
