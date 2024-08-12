local TextBuffer = require("TextBuffer"):getInstance()

ScreenManager = {}
ScreenManager.__index = ScreenManager

local instance

function ScreenManager:new()
	if not instance then
		instance = {
			windows = {},
			savedScreenBuffer = {},
		}
		setmetatable(instance, ScreenManager)
	end
	return instance
end

function ScreenManager:getInstance()
	if not instance then
		instance = ScreenManager:new()
	end
	return instance
end

function ScreenManager:createWindow(x, y, width, height, backgroundColor, textColor)
	width = width or (SCREENWIDTH - x + 1)
	height = height or (SCREENHEIGHT - y)

	if x + width - 1 > SCREENWIDTH then
		width = SCREENWIDTH - x + 1
	end
	if y + height > SCREENHEIGHT then
		height = SCREENHEIGHT - y
	end

	local window = {
		x = x,
		y = y,
		width = width,
		height = height,
		backgroundColor = backgroundColor or colors.black,
		textColor = textColor or colors.white,
		buffer = {},
		currentLine = 1,
		currentColumn = 1,
		minimized = false, -- new property to track minimization
	}

	for i = 1, height do
		window.buffer[i] = string.rep(" ", width)
	end

	function window:show()
		if self.minimized then
			return
		end -- don't show if minimized
		term.setBackgroundColor(self.backgroundColor)
		term.setTextColor(self.textColor)
		for i = 1, self.height do
			term.setCursorPos(self.x, self.y + i - 1)
			term.write(self.buffer[i])
		end
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
	end

	function window:minimize()
		self.minimized = true
		ScreenManager:getInstance():drawScreen() -- Update screen to reflect minimization
	end

	function window:restore()
		self.minimized = false
		ScreenManager:getInstance():drawScreen() -- Update screen to reflect restoration
	end

	function window:scrollUp()
		if self.currentLine > 1 then
			self.currentLine = self.currentLine - 1
			-- Shift buffer lines up
			for i = 1, self.height - 1 do
				self.buffer[i] = self.buffer[i + 1]
			end
			self.buffer[self.height] = string.rep(" ", self.width) -- Clear the last line
			self:show() -- Redraw the window content
		end
	end
	function window:scrollDown()
		if self.currentLine < #self.buffer then
			self.currentLine = self.currentLine + 1
			-- Shift buffer lines down
			for i = self.height, 2, -1 do
				self.buffer[i] = self.buffer[i - 1]
			end
			self.buffer[1] = string.rep(" ", self.width) -- Clear the first line
			self:show()
		end
	end

	function window:transform(newX, newY, newWidth, newHeight)
		-- Clear the old window area
		term.setCursorPos(self.x, self.y)
		for i = 1, self.height do
			term.clearLine()
			term.setCursorPos(self.x, self.y + i)
		end

		-- Update position if newX or newY is provided
		if newX then
			self.x = newX
		end
		if newY then
			self.y = newY
		end

		-- Update dimensions if newWidth or newHeight is provided
		if newWidth then
			self.width = newWidth
			-- Ensure the width doesn't go out of bounds
			if self.x + self.width - 1 > SCREENWIDTH then
				self.width = SCREENWIDTH - self.x + 1
			end
		end
		if newHeight then
			self.height = newHeight
			-- Ensure the height doesn't go out of bounds
			if self.y + self.height > SCREENHEIGHT then
				self.height = SCREENHEIGHT - self.y
			end
		end

		-- Reinitialize buffer if size changes
		if newWidth or newHeight then
			self.buffer = {}
			for i = 1, self.height do
				self.buffer[i] = string.rep(" ", self.width)
			end
		end

		-- Mark the new area as dirty to trigger redraw
		self:markDirty()

		-- Redraw the window in the new position/size
		self:show()
	end

	function window:markDirty()
		for i = 1, self.height do
			TextBuffer.dirtyLines[self.y + i - 1] = true
		end
	end
	function window:close()
		self:markDirty()
		local windows = ScreenManager:getInstance().windows
		for i, w in ipairs(windows) do
			if w == self then
				table.remove(windows, i)
				break
			end
		end
		-- Clear the area where the window was located
		term.setCursorPos(self.x, self.y)
		for i = 1, self.height do
			term.clearLine()
			term.setCursorPos(self.x, self.y + i)
		end
		ScreenManager:getInstance():drawScreen()
	end

	function window:writeText(x, y, text)
		local bufferLine = self.buffer[y] or string.rep(" ", self.width)
		self.buffer[y] = bufferLine:sub(1, x - 1) .. text .. bufferLine:sub(x + #text)
		self:markDirty()
	end

	function window:write(text)
		local remainingSpace = self.width - self.currentColumn + 1
		local textToWrite = text:sub(1, remainingSpace)

		self:writeText(self.currentColumn, self.currentLine, textToWrite)
		self.currentColumn = self.currentColumn + #textToWrite

		if self.currentColumn > self.width then
			self.currentLine = self.currentLine + 1
			self.currentColumn = 1
		end
		self:markDirty()
	end

	function window:writeline(text)
		self:write(text)
		self.currentLine = self.currentLine + 1
		self.currentColumn = 1
	end

	function window:clear()
		for i = 1, self.height do
			-- Clear each line in the buffer
			self.buffer[i] = string.rep(" ", self.width)
		end
		self.currentLine = 1
		self.currentColumn = 1
	end

	function window:print(text)
		local lines = {}

		for line in text:gmatch("[^\r\n]+") do
			table.insert(lines, line)
		end

		for _, line in ipairs(lines) do
			if self.currentLine > self.height then
				return
			end
			self:writeline(line)
		end
	end

	table.insert(ScreenManager:getInstance().windows, window)

	return window
end

function ScreenManager:closeAllWindows()
	for _, window in ipairs(self.windows) do
		window:close()
	end
	self.windows = {}
end

function ScreenManager:showPopup(message)
	local padding = 2
	local maxPopupWidth = SCREENWIDTH - 4 -- Max possible width with some margin
	local effectiveMaxWidth = maxPopupWidth - padding * 2

	local lines = {}
	local currentLine = ""

	-- Process the message to wrap words into lines
	for word in message:gmatch("%S+") do
		if #currentLine + #word + 1 <= effectiveMaxWidth then
			-- Add the word to the current line
			if currentLine ~= "" then
				currentLine = currentLine .. " "
			end
			currentLine = currentLine .. word
		else
			-- Move to the next line
			table.insert(lines, currentLine)
			currentLine = word
		end
	end

	-- Add the last line if it contains any text
	if currentLine ~= "" then
		table.insert(lines, currentLine)
	end

	-- Handle cases where a line might exceed the effective max width
	local splitLines = {}
	for _, line in ipairs(lines) do
		while #line > effectiveMaxWidth do
			table.insert(splitLines, line:sub(1, effectiveMaxWidth))
			line = line:sub(effectiveMaxWidth + 1)
		end
		table.insert(splitLines, line)
	end
	lines = splitLines

	-- Calculate the final width and height of the popup
	local popupWidth = 0
	for _, line in ipairs(lines) do
		popupWidth = math.max(popupWidth, #line + padding * 2)
	end
	popupWidth = math.min(maxPopupWidth, popupWidth)

	local popupHeight = SCREENHEIGHT - 4 -- Full screen height with some margin
	local popupX = math.floor((SCREENWIDTH - popupWidth) / 2)
	local popupY = 1

	-- Create and display the popup window
	local window = self:createWindow(popupX, popupY, popupWidth, popupHeight)

	local startIndex = 1
	local itemsPerPage = popupHeight - 4 -- Adjust based on available window height

	-- Function to display the popup content in the window
	local function displayPopupContent(startIndex)
		window:clear()
		window:writeline(string.rep("-", popupWidth))

		for i = startIndex, math.min(#lines, startIndex + itemsPerPage - 1) do
			local line = lines[i]
			local paddingSpaces = math.floor((popupWidth - #line) / 2)
			window:writeline(
				"|"
					.. string.rep(" ", paddingSpaces)
					.. line
					.. string.rep(" ", popupWidth - #line - paddingSpaces - 2)
					.. "|"
			)
		end

		window:writeline(string.rep("-", popupWidth))
		window:show()
	end

	displayPopupContent(startIndex)

	-- Listen for input to scroll and close the window
	while true do
		local event, key = os.pullEvent("key")
		if key == keys.down or key == keys.j then
			if startIndex + itemsPerPage - 1 < #lines then
				startIndex = startIndex + 1
				displayPopupContent(startIndex)
			end
		elseif key == keys.up or key == keys.k then
			if startIndex > 1 then
				startIndex = startIndex - 1
				displayPopupContent(startIndex)
			end
		else
			window:close()
			break
		end
	end
end

function ScreenManager:drawScreen()
	term.setCursorBlink(false)
	local adjustedHeight = SCREENHEIGHT - TextBuffer.statusBarHeight

	-- Redraw the text buffer (or any background layer) first
	for lineNumber in pairs(TextBuffer.dirtyLines) do
		self:drawLine(lineNumber)
	end
	TextBuffer:clearDirtyLines()

	-- Draw the first non-minimized window
	if self.windows and #self.windows > 0 then
		for _, window in ipairs(self.windows) do
			if not window.minimized then
				window:show()
				break
			end
		end
	end

	term.setCursorBlink(true)
end

function ScreenManager:getLineNumberWidth()
	return #tostring(#TextBuffer.buffer)
end

function ScreenManager:drawLine(y)
	if type(y) ~= "number" then
		error("Invalid argument: 'y' should be a number, but received a " .. type(y))
	end

	local lineIndex = TextBuffer.scrollOffset + y
	term.setCursorPos(1, y)
	term.clearLine()

	if TextBuffer.buffer[lineIndex] then
		local lineNumberWidth = self:getLineNumberWidth()
		local lineNumber = tostring(lineIndex)

		lineNumber = string.rep(" ", lineNumberWidth - #lineNumber) .. lineNumber

		term.setTextColor(colors.lightGray)
		term.write(lineNumber .. " ")

		term.setTextColor(colors.white)

		local lineToDisplay = TextBuffer.buffer[lineIndex]

		if TextBuffer.allow_horizontal_scroll then
			lineToDisplay = lineToDisplay:sub(
				TextBuffer.horizontalScrollOffset + 1,
				TextBuffer.horizontalScrollOffset + TextBuffer.maxVisibleColumns
			)
		end

		-- Adjusted logic to account for scrolling
		local visualStartY = math.min(TextBuffer.visualStartY or TextBuffer.cursorY, TextBuffer.cursorY)
		local visualEndY = math.max(TextBuffer.visualStartY or TextBuffer.cursorY, TextBuffer.cursorY)

		if TextBuffer.isVisualMode and lineIndex >= visualStartY and lineIndex <= visualEndY then
			local startX = 1
			local endX = #lineToDisplay

			if lineIndex == TextBuffer.visualStartY then
				startX = TextBuffer.visualStartX
			end
			if lineIndex == TextBuffer.cursorY then
				endX = TextBuffer.cursorX
			end

			if startX > endX then
				startX, endX = endX, startX
			end

			local beforeHighlight = lineToDisplay:sub(1, startX - 1)
			local highlightText = lineToDisplay:sub(startX, endX)
			local afterHighlight = lineToDisplay:sub(endX + 1)

			term.write(beforeHighlight)
			term.setBackgroundColor(colors.gray)
			term.write(highlightText)
			term.setBackgroundColor(colors.black)
			term.write(afterHighlight)
		else
			term.write(lineToDisplay)
		end
	end
end

function ScreenManager:drawStatusBar()
	local statusBarLines = TextBuffer.statusBarHeight

	if statusBarLines > 1 then
		term.setCursorPos(1, SCREENHEIGHT - statusBarLines + 1)
		term.setBackgroundColor(TextBuffer.statusColor)
		term.clearLine()
		term.setTextColor(colors.white)
		if TextBuffer.statusMessage ~= "" then
			term.write(TextBuffer.statusMessage)
		end
	end

	term.setCursorPos(1, SCREENHEIGHT)
	term.setBackgroundColor(TextBuffer.statusColor)
	term.clearLine()
	term.setTextColor(colors.white)
	term.write(
		"File: "
			.. TextBuffer.filename
			.. " | Pos: "
			.. TextBuffer.cursorY
			.. ","
			.. TextBuffer.cursorX
			.. " | Mode: "
			.. TextBuffer.mode
			.. " | Word: "
			.. TextBuffer:getWordAtCursor()
	)

	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
end

function ScreenManager:updateCursor()
	local lineNumberWidth = self:getLineNumberWidth() + 1
	local screenCursorX = TextBuffer.cursorX - TextBuffer.horizontalScrollOffset
	term.setCursorPos(screenCursorX + lineNumberWidth, TextBuffer.cursorY - TextBuffer.scrollOffset)
end

function ScreenManager:getAvailableWidth()
	local lineNumberWidth = self:getLineNumberWidth()
	return SCREENWIDTH - lineNumberWidth - 1
end

return ScreenManager
