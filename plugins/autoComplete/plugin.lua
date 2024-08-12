local function init(components)
	local ScreenManager = components.ScreenManager
	local InputController = components.InputController
	local TextBuffer = components.TextBuffer
	-- Hardcoded autocomplete keywords
	local autocompleteKeywords = {
		"and",
		"break",
		"do",
		"else",
		"elseif",
		"end",
		"for",
		"function",
		"if",
		"in",
		"local",
		"nil",
		"not",
		"or",
		"repeat",
		"require",
		"return",
		"then",
		"until",
		"while",
	}

	-- Store the original handleCharInput function
	local originalHandleCharInput = InputController.handleCharInput

	-- Override the handleCharInput function to include autocomplete
	function InputController:handleCharInput(char)
		-- Call the original function to insert the character
		originalHandleCharInput(self, char)

		if TextBuffer.mode ~= "insert" then
			return
		end

		-- Trigger autocomplete after inserting a character
		local currentWord = TextBuffer:getWordAtCursor()
		if #currentWord > 0 then
			local suggestions = TextBuffer:getAutocompleteSuggestions(currentWord)
			if #suggestions > 0 then
				ScreenManager:showAutocompleteWindow(suggestions, false)
			else
				TextBuffer:resetAutocomplete()
			end
		else
			TextBuffer:resetAutocomplete()
		end
	end

	-- Function to show the autocomplete window
	function ScreenManager:showAutocompleteWindow(suggestions, showList)
		-- Ensure that any existing autocomplete window is closed before creating a new one
		if TextBuffer.autocompleteWindow then
			TextBuffer.autocompleteWindow:close()
		end

		if #suggestions == 0 then
			TextBuffer:resetAutocomplete()
			return
		end

		local height = showList and math.min(#suggestions, 5) or 1
		local maxWidth = math.min(12, math.max(#suggestions[1], 12))

		-- Calculate the x position for the autocomplete window
		local x = TextBuffer:getColumn() + maxWidth / 2 - #tostring(#TextBuffer.buffer) - 2
		local y = TextBuffer.cursorY + 1

		-- Adjust if the window goes beyond screen bounds
		if x + maxWidth > SCREENWIDTH then
			x = SCREENWIDTH - maxWidth + #tostring(#TextBuffer.buffer) + 1
			y = TextBuffer.cursorY + 1
		end

		-- Ensure the window is created
		local autocompleteWindow = self:createWindow(x, y, maxWidth, height, colors.gray, colors.white)
		autocompleteWindow:clear()

		-- Fill the window with suggestions
		for i = 1, height do
			local suggestion = suggestions[i]
			if suggestion then
				autocompleteWindow:writeline(suggestion)
			end
		end

		autocompleteWindow:show()

		TextBuffer.suggestions = suggestions
		TextBuffer.autocompleteWindow = autocompleteWindow
	end

	function TextBuffer:getAutocompleteSuggestions(prefix)
		local suggestions = {}

		-- Add dynamic suggestions from collected identifiers
		for _, identifier in ipairs(self.dynamicIdentifiers or {}) do
			if identifier:sub(1, #prefix) == prefix then
				identifier = identifier:sub(#prefix + 1)
				if #identifier > 0 then
					table.insert(suggestions, identifier)
				end
			end
		end

		-- Add dynamic suggestions from textutils.complete
		local dynamicSuggestions = textutils.complete(prefix, _G)
		for _, suggestion in ipairs(dynamicSuggestions) do
			table.insert(suggestions, suggestion)
		end

		-- Add hardcoded keywords
		for _, keyword in ipairs(autocompleteKeywords) do
			if keyword:sub(1, #prefix) == prefix then
				keyword = keyword:sub(#prefix + 1)
				table.insert(suggestions, keyword)
			end
		end

		-- Remove duplicates
		local uniqueSuggestions = {}
		local suggestionSet = {}
		for _, suggestion in ipairs(suggestions) do
			if not suggestionSet[suggestion] and suggestion ~= prefix then
				table.insert(uniqueSuggestions, suggestion)
				suggestionSet[suggestion] = true
			end
		end

		return uniqueSuggestions
	end

	-- Function to reset autocomplete state
	function TextBuffer:resetAutocomplete()
		if self.autocompleteWindow then
			self.autocompleteWindow:close()
			self.autocompleteWindow = nil
		end
		self.suggestions = nil
	end

	function TextBuffer:acceptAutocompleteSuggestion()
		if self.suggestions and #self.suggestions > 0 then
			local suggestion = self.suggestions[1]
			-- Replace the current word with the full suggestion
			local insertText = suggestion
			-- Insert the full suggestion
			self:insertChar(insertText)
			self.cursorX = self.cursorX + #insertText
			self:resetAutocomplete()
		end
	end

	-- InputController mappings for autocomplete
	InputController:map({ "insert" }, { "backspace" }, "autocomplete_backspace", function()
		if TextBuffer.suggestions then
			TextBuffer:resetAutocomplete()
		else
			TextBuffer:backspace()
		end
	end)

	InputController:map({ "insert" }, { "enter" }, "autocomplete_enter", function()
		if TextBuffer.suggestions then
			TextBuffer:acceptAutocompleteSuggestion()
		else
			TextBuffer:enter()
		end
	end)

	InputController:map({ "insert" }, { "up", "ctrl + p" }, "autocomplete_up", function()
		if TextBuffer.suggestions then
			table.insert(TextBuffer.suggestions, 1, table.remove(TextBuffer.suggestions))
			ScreenManager:showAutocompleteWindow(TextBuffer.suggestions, true)
		else
			InputController:executeCommand("move_up")
		end
	end)

	InputController:map({ "insert" }, { "down", "ctrl + n" }, "autocomplete_down", function()
		if TextBuffer.suggestions then
			table.insert(TextBuffer.suggestions, table.remove(TextBuffer.suggestions, 1))
			ScreenManager:showAutocompleteWindow(TextBuffer.suggestions, true)
		else
			TextBuffer:markDirty(TextBuffer.cursorY)
			InputController:executeCommand("move_down")
		end
		ScreenManager:drawScreen()
	end)

	InputController:map({ "insert" }, { "left" }, "autocomplete_left", function()
		if TextBuffer.suggestions then
			TextBuffer:resetAutocomplete()
		else
			InputController:executeCommand("move_left")
		end
	end)

	InputController:map({ "insert" }, { "right", "ctrl + y" }, "autocomplete_right", function()
		if TextBuffer.suggestions then
			TextBuffer:acceptAutocompleteSuggestion()
		else
			InputController:executeCommand("move_right")
		end
	end)
end

return {
	init = init,
}
