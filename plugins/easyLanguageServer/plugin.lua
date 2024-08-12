local function init(components)
	local TextBuffer = components.TextBuffer
	local ScreenManagerInstance = components.ScreenManager
	local InputController = components.InputController
	local LuaParser = require("plugins.easyLanguageServer.lua.parser")
	local Tokenizer = require("plugins.easyLanguageServer.lua.tokenizer")
	local colorMatch = {
		popupBG = colors.lightGray,
		popupFrame = colors.gray,
		popupFont = colors.black,
		cAccentText = colors.lightGray,
		bg = colors.black,
		bracket = colors.lightGray,
		comment = colors.gray,
		func = colors.orange,
		keyword = colors.blue, -- Changed from red to blue
		number = colors.magenta,
		operator = colors.cyan,
		string = colors.green,
		special = colors.yellow,
		text = colors.white,
		positive = colors.lime,
		negative = colors.purple,
		error = colors.red, -- Added explicitly for errors
	}
	local tKeywords = {
		["and"] = true,
		["break"] = true,
		["do"] = true,
		["else"] = true,
		["elseif"] = true,
		["end"] = true,
		["for"] = true,
		["function"] = true,
		["if"] = true,
		["in"] = true,
		["local"] = true,
		["nil"] = true,
		["not"] = true,
		["or"] = true,
		["repeat"] = true,
		["require"] = true,
		["return"] = true,
		["then"] = true,
		["until"] = true,
		["while"] = true,
	}
	local tPatterns = {
		{ "^%-%-.*", colorMatch["comment"] },
		{ '^""', colorMatch["string"] },
		{ '^".-[^\\]"', colorMatch["string"] },
		{ "^''", colorMatch["string"] },
		{ "^'.-[^\\]'", colorMatch["string"] },
		{ "^%[%[%]%]", colorMatch["string"] },
		{ "^%[%[.-[^\\]%]%]", colorMatch["string"] },
		{ "^[\127\162\163\165\169\174\182\181\177\183\186\188\189\190\215\247@]+", colorMatch["special"] },
		{ "^[%d][xA-Fa-f.%d#]+", colorMatch["number"] },
		{ "^[%d]+", colorMatch["number"] },
		{ "^[,{}%[%]%(%)]", colorMatch["bracket"] },
		{ "^[!%/\\:~<>=%*%+%-%%]+", colorMatch["operator"] },
		{ "^true", colorMatch["number"] },
		{ "^false", colorMatch["number"] },
		{
			"^[%w_%.]+",
			function(match, after)
				if tKeywords[match] then
					return colorMatch["keyword"]
				elseif after:sub(1, 1) == "(" then
					return colorMatch["func"]
				end
				return colorMatch["text"]
			end,
		},
		{ "^[^%w_]", colorMatch["text"] },
	}
	local errors = {}
	local function convertToLineNumber(wordNumber, fileName)
		local file = fs.open(fileName, "r")
		if not file then
			error("Failed to open file for error checking")
		end
		local file_content = file.readAll()
		if file_content == "" then
			error("File is empty")
		end
		local tokens = Tokenizer.tokenize(file_content)
		if file_content then
			local lineBreakCount = 0
			local lineCount = 1
			-- Get the amount of line breaks in the tokens:
			for i = 1, #tokens do
				if tokens[i].type == Tokenizer.TOKEN_TYPES.LINE_BREAK then
					lineBreakCount = lineBreakCount + 1
				end
			end

			-- Adjust wordNumber based on the number of line breaks
			wordNumber = wordNumber + lineBreakCount

			-- Iterate over the tokens to find the line number
			for i = 1, wordNumber - 1 do
				if tokens[i].type == Tokenizer.TOKEN_TYPES.LINE_BREAK then
					lineCount = lineCount + 1
				end
			end

			return math.min(#TextBuffer.buffer, lineCount) -- If not found, return the last line number
		end
	end
	local function extractFromErrorString(message, fileName)
		local cleanedMessage = message:gsub("^[^:]+:%d+:%s*", "")
		local wordPosition = cleanedMessage:match("position (%d+)")
		if wordPosition then
			wordPosition = tonumber(wordPosition)
			local lineNumber = convertToLineNumber(wordPosition, fileName)
			table.insert(errors, { line = lineNumber, message = cleanedMessage })
		end

		return errors
	end
	local function extractFromErrorMessage(message)
		local lineNumber = message:match(":(%d+):")
		local cleanedMessage = message:gsub("^[^:]+:%d+:%s*", "")
		lineNumber = tonumber(lineNumber)
		lineNumber = math.min(#TextBuffer.buffer, lineNumber) -- If not found, return the last line number
		table.insert(errors, { line = lineNumber, message = cleanedMessage })
		return errors
	end
	local function getIdentifierLine(name, filename)
		local position = nil

		-- Traverse the AST to find the identifier and its position
		local function traverse(node)
			if node.type == "identifier" and node.value == name then
				position = node.position
				return position
			end
			for _, v in pairs(node) do
				if type(v) == "table" then
					traverse(v)
				end
			end
		end

		-- Read the file and tokenize the content
		local file = fs.open(filename, "r")
		if not file then
			error("Failed to open file")
		end
		local code = file.readAll()
		file.close()

		if code == "" then
			error("File is empty")
		end

		local tokens = Tokenizer.tokenize(code)
		local parser = LuaParser:new(tokens)
		local ast = parser:parse()

		-- Traverse the AST to find the position
		traverse(ast)

		-- If position is found, use the working function to calculate the line number
		if position then
			local lineNumber = convertToLineNumber(position, filename)
			return math.min(#TextBuffer.buffer, lineNumber - 1)
		else
			error("Identifier not found")
		end
	end

	local function checkCurrentFileForErrors()
		errors = {} -- Clear previous errors
		local fileName = TextBuffer.filename
		if not fileName then
			ScreenManagerInstance:showPopup(
				"Error",
				"No file to check for errors",
				{ "OK" },
				colorMatch.popupBG,
				colorMatch.popupFont
			)
			return
		end
		local file = fs.open(fileName, "r")
		if not file then
			ScreenManagerInstance:showPopup(
				"Error",
				"Failed to open file for error checking",
				{ "OK" },
				colorMatch.popupBG,
				colorMatch.popupFont
			)
			return
		end
		local fileContent = file.readAll() -- Read the entire file content
		file.close()
		if fileContent == "" then
			ScreenManagerInstance:showPopup(
				"Error",
				"File is empty",
				{ "OK" },
				colorMatch.popupBG,
				colorMatch.popupFont
			)
			return
		end
		if fileContent == nil then
			ScreenManagerInstance:showPopup(
				"Error",
				"Failed to read file content",
				{ "OK" },
				colorMatch.popupBG,
				colorMatch.popupFont
			)
			return
		end

		-- Run the LuaParser to check for errors
		local _, msg = LuaParser:loadFile(fileName)
		if msg then
			if type(msg) == "table" then
				-- Add identifiers to the dynamicIdentifiers list
				TextBuffer.dynamicIdentifiers = LuaParser:getIdentifiersAsList(fileName)
			-- Show popup of each identifier
			else
				extractFromErrorString(msg, fileName)
			end
		end

		-- If there are no parser errors, check for Lua syntax errors using `load`
		if #errors == 0 then
			local func, syntaxError = load(fileContent)
			if not func and syntaxError then
				extractFromErrorMessage(syntaxError)
			end
		end

		-- Update errors in the TextBuffer if necessary
		if TextBuffer.checkLineForErrors then
			TextBuffer.checkLineForErrors()
		end
	end

	-- Function to apply syntax highlighting to a line of text
	local function highlightLine(line)
		while #line > 0 do
			for _, pattern in ipairs(tPatterns) do
				local match = line:match(pattern[1])
				if match then
					local color = pattern[2]
					if type(color) == "function" then
						color = color(match, line:sub(#match + 1))
					end
					term.setTextColor(color)
					term.write(match)
					line = line:sub(#match + 1)
					break
				end
			end
		end
	end

	-- Helper function to determine if a line has an error
	local function lineHasError(lineIndex)
		for _, error in ipairs(errors) do
			if error.line == lineIndex then
				return true, error.message
			end
		end
		return false
	end
	-- Function to check for errors on the current line and update the status bar if an error is found
	local function checkLineForErrors()
		local lineIndex = TextBuffer.cursorY
		local hasError, errorMessage = lineHasError(lineIndex)

		if hasError then
			TextBuffer:updateStatusError("Error at line " .. lineIndex)

			-- Show the error window when hovering over the line with the error
			ScreenManagerInstance:showErrorWindow(errorMessage, lineIndex)

			-- Optional: remove the error from the errors list once it's shown
			for i, error in ipairs(errors) do
				if error.line == lineIndex then
					table.remove(errors, i)
					break
				end
			end
		else
			-- If there is no error, ensure the error window is closed
			if TextBuffer.errorWindow then
				TextBuffer.errorWindow:close()
				TextBuffer.errorWindow = nil
				ScreenManager:drawScreen()
			end
		end
	end
	function ScreenManagerInstance:drawLine(y)
		-- Validate the input argument
		if type(y) ~= "number" then
			error("Invalid argument: 'y' should be a number, but received a " .. type(y))
		end

		-- Calculate the line index and retrieve its content
		local lineIndex = TextBuffer.scrollOffset + y
		local lineContent = TextBuffer:getLine(lineIndex)

		-- Set cursor position and clear the line
		term.setCursorPos(1, y)
		term.clearLine()

		-- Proceed if the line content exists
		if lineContent then
			-- Prepare the line number display
			local lineNumberWidth = self:getLineNumberWidth()
			local lineNumber = tostring(lineIndex)
			lineNumber = string.rep(" ", lineNumberWidth - #lineNumber) .. lineNumber

			-- Display the line number
			term.setTextColor(colors.lightGray)
			term.write(lineNumber .. " ")

			-- Adjust the line content for horizontal scrolling
			if TextBuffer.allow_horizontal_scroll then
				lineContent = lineContent:sub(
					TextBuffer.horizontalScrollOffset + 1,
					TextBuffer.horizontalScrollOffset + TextBuffer.maxVisibleColumns
				)
			end

			-- Check if the line has an error
			if lineHasError(lineIndex) then
				-- Highlight the entire line in red if there's an error
				term.setTextColor(colorMatch.error)
				term.write(lineContent)
			else
				-- Handle visual mode highlighting
				local visualStartY = math.min(TextBuffer.visualStartY or TextBuffer.cursorY, TextBuffer.cursorY)
				local visualEndY = math.max(TextBuffer.visualStartY or TextBuffer.cursorY, TextBuffer.cursorY)

				if TextBuffer.isVisualMode and lineIndex >= visualStartY and lineIndex <= visualEndY then
					local startX = 1
					local endX = #lineContent

					if lineIndex == TextBuffer.visualStartY then
						startX = TextBuffer.visualStartX - TextBuffer.horizontalScrollOffset
					end
					if lineIndex == TextBuffer.cursorY then
						endX = TextBuffer.cursorX - TextBuffer.horizontalScrollOffset
					end

					if startX > endX then
						startX, endX = endX, startX
					end

					-- Split the line content based on the visual selection
					local beforeHighlight = lineContent:sub(1, startX - 1)
					local highlightText = lineContent:sub(startX, endX)
					local afterHighlight = lineContent:sub(endX + 1)

					-- Apply normal syntax highlighting to the part before the visual selection
					highlightLine(beforeHighlight)

					-- Highlight the selected portion with a different background color
					term.setBackgroundColor(colors.gray)
					highlightLine(highlightText)
					term.setBackgroundColor(colors.black)

					-- Apply normal syntax highlighting to the part after the visual selection
					highlightLine(afterHighlight)
				else
					-- If not in visual mode or the line is not part of the visual selection, apply normal syntax highlighting
					highlightLine(lineContent)
				end
			end
		end
	end

	--extend TextBuffer:loadFile to check for errors
	local oldLoadFile = TextBuffer.loadFile
	function TextBuffer:loadFile(fileName)
		oldLoadFile(self, fileName)
		checkCurrentFileForErrors()
	end

	function ScreenManager:showErrorWindow(errorMessage, lineNumber)
		local x = 1 -- Align the window to start from the left of the screen
		local y = lineNumber + 1 -- Place the window right below the error line

		-- Determine the window dimensions
		local width = math.min(50, #errorMessage + 4) -- Dynamic width based on the error message length
		local height = 3 -- Enough height to fit the message and some padding

		-- Ensure the window stays within the screen bounds
		if y + height > SCREENHEIGHT then
			y = SCREENHEIGHT - height
		end

		-- Create the window or reuse the existing one
		if TextBuffer.errorWindow then
			TextBuffer.errorWindow:clear()
		else
			TextBuffer.errorWindow = self:createWindow(x, y, width, height, colors.lightGray, colors.black)
			TextBuffer:updateStatusBar("Error window opened")
		end

		-- Write the error message to the window
		TextBuffer.errorWindow:writeline("Error at line " .. lineNumber)
		TextBuffer.errorWindow:writeline(errorMessage)

		TextBuffer.errorWindow:show()
	end

	-- Expose the error checking function to be called manually (e.g., on save)
	TextBuffer.checkCurrentFileForErrors = checkCurrentFileForErrors
	TextBuffer.checkLineForErrors = checkLineForErrors
	InputController:mapCommand("w", function(name)
		if name then
			TextBuffer:saveFileAs(name)
		else
			TextBuffer:saveFile()
			TextBuffer.checkCurrentFileForErrors()
			TextBuffer:updateStatusBar("Checked for errors!")
			ScreenManagerInstance:drawScreen()
		end
	end)
	InputController:map({ "normal", "visual" }, { "h" }, "move_left", function()
		TextBuffer:markDirty(TextBuffer.cursorY)
		TextBuffer.cursorX = math.max(1, TextBuffer.cursorX - 1)
		TextBuffer.checkLineForErrors()
	end, "Move Left")

	InputController:map({ "normal", "visual" }, { "l" }, "move_right", function()
		TextBuffer:markDirty(TextBuffer.cursorY)
		TextBuffer.cursorX = math.min(#TextBuffer.buffer[TextBuffer.cursorY] + 1, TextBuffer.cursorX + 1)
		TextBuffer.checkLineForErrors()
	end, "Move Right")

	InputController:map({ "normal", "visual" }, { "k" }, "move_up", function()
		TextBuffer:markDirty(TextBuffer.cursorY)
		if TextBuffer.cursorY > 1 then
			TextBuffer.cursorY = TextBuffer.cursorY - 1
		end
		TextBuffer.cursorX = math.min(TextBuffer.cursorX, #TextBuffer.buffer[TextBuffer.cursorY] + 1)
		TextBuffer.checkLineForErrors()
	end, "Move Up")

	InputController:map({ "normal", "visual" }, { "j" }, "move_down", function()
		TextBuffer:markDirty(TextBuffer.cursorY)
		if TextBuffer.cursorY < #TextBuffer.buffer then
			TextBuffer.cursorY = TextBuffer.cursorY + 1
		end
		TextBuffer.cursorX = math.min(TextBuffer.cursorX, #TextBuffer.buffer[TextBuffer.cursorY] + 1)
		TextBuffer.checkLineForErrors()
	end, "Move Down")

	InputController:map({ "normal" }, { "g + d" }, "goto_definition", function()
		-- Get the word under the cursor

		local word = TextBuffer:getWordAtCursor()
		if not word or word == "" then
			TextBuffer:updateStatusError("No word under cursor")
			return
		end

		-- Check if the dynamicIdentifiers list is empty or nil
		if not TextBuffer.dynamicIdentifiers or #TextBuffer.dynamicIdentifiers == 0 then
			TextBuffer:updateStatusError("No identifiers available for: " .. word)
			return
		end

		--convert pos to line number and move cursor to that line
		local line = getIdentifierLine(word, TextBuffer.filename)
		if line then
			-- Move the cursor to the line where the identifier was defined
			TextBuffer.cursorY = line
			TextBuffer.cursorX = 1
			TextBuffer:updateScroll(SCREENHEIGHT)
			TextBuffer:updateStatusBar("Jumped to definition of '" .. word .. "' at line " .. line)
		else
			TextBuffer:updateStatusError("Definition for '" .. word .. "' not found")
		end
	end, "Go to Definition")
end

return {
	init = init,
}
