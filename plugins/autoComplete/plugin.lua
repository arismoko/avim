local function init(components)
    local View = components.view
    local InputHandler = components.inputHandler
    local bufferHandler = components.bufferHandler

    -- Hardcoded autocomplete keywords
    local autocompleteKeywords = {
        "and", "break", "do", "else", "elseif", "end", "for", "function", "if", "in", 
        "local", "nil", "not", "or", "repeat", "require", "return", "then", "until", 
        "while"
    }

    -- Create a set for quick lookup of hardcoded keywords
    local keywordSet = {}
    for _, keyword in ipairs(autocompleteKeywords) do
        keywordSet[keyword] = true
    end

    -- Function to update the identifiers based on the current buffer content
    local function updateIdentifiers()
        local content = bufferHandler:getBufferAsString()  -- Fetch the entire buffer content
        local identifiers = {}  -- Reset the identifiers
        local lineNumber = 1

        -- Iterate through each line in the content
        for line in content:gmatch("[^\n]*\n?") do
            -- Remove Lua comments and strings from the line
            line = line:gsub("%-%-.*", "")  -- Remove single-line comments
            line = line:gsub("%[%[.-%]%]", "")  -- Remove multiline strings
            line = line:gsub("\"[^\"]*\"", "")  -- Remove double-quoted strings
            line = line:gsub("\'[^\']*\'", "")  -- Remove single-quoted strings

            -- Extract and update identifiers with line numbers
            for word in line:gmatch("[_%a][_%w]*") do
                if not keywordSet[word] and not textutils.complete(word, _G)[1] then
                    table.insert(identifiers, {identifier = word, line = lineNumber})
                end
            end

            lineNumber = lineNumber + 1
        end

        bufferHandler.dynamicIdentifiers = identifiers  -- Store the identifiers in the bufferHandler
    end

    -- Function to get a nested value from a table
    local function getNestedValue(tbl, keys)
        local value = tbl
        for _, key in ipairs(keys) do
            if type(value) == "table" and value[key] ~= nil then
                value = value[key]
            else
                return nil
            end
        end
        return value
    end

    -- Store the original handleCharInput function
    local originalHandleCharInput = InputHandler.handleCharInput

    -- Override the handleCharInput function to include autocomplete
    function InputHandler:handleCharInput(char)
        -- Call the original function to insert the character
        originalHandleCharInput(self, char)

        -- Trigger autocomplete after inserting a character
        local currentWord = bufferHandler:getWordAtCursor()
        if #currentWord > 0 then
            local suggestions = bufferHandler:getAutocompleteSuggestions(currentWord)
            if #suggestions > 0 then
                View:showAutocompleteWindow(suggestions)
                bufferHandler:updateStatusBar("Autocomplete suggestions for: " .. currentWord)
            end
        else
            bufferHandler:resetAutocomplete()
            bufferHandler:updateStatusBar("No words to autocomplete")
        end
    end

    -- Function to show the autocomplete window
    function View:showAutocompleteWindow(suggestions)
        -- Save current terminal state
        local savedCursorX, savedCursorY = term.getCursorPos()
        local savedTextColor = term.getTextColor()
        local savedBGColor = term.getBackgroundColor()

        local x = bufferHandler.cursorX
        local y = bufferHandler.cursorY - bufferHandler.scrollOffset + 1

        -- Limit the number of suggestions to 5
        local limitedSuggestions = {}
        for i = 1, math.min(#suggestions, 5) do
            table.insert(limitedSuggestions, suggestions[i])
        end

        -- Calculate the height of the autocomplete window
        local height = #limitedSuggestions
        
        -- Determine the dynamic width based on the longest suggestion, capped at 15 characters
        local maxSuggestionLength = 0
        for _, suggestion in ipairs(limitedSuggestions) do
            maxSuggestionLength = math.max(maxSuggestionLength, #suggestion)
        end
    
        -- Set the width to be the length of the longest suggestion, plus padding, up to a maximum of 15 characters
        local width = math.min(maxSuggestionLength + 5, 15)
    
        -- Adjust 'y' to place the window above the cursor line if possible
        if y > SCREENHEIGHT / 2 then
            y = y - height - 1 -- Move the window above the cursor line
        end
    
        -- Ensure the window doesn't go off-screen
        if y < 1 then
            y = 1
        elseif y + height - 1 > SCREENHEIGHT then
            y = SCREENHEIGHT - height + 2
        end
    
        -- Draw autocomplete suggestions
        for i, suggestion in ipairs(limitedSuggestions) do
            term.setCursorPos(x, y + i - 1)
            term.clearLine()
            term.write(suggestion)
        end
    
        -- Restore terminal state after drawing
        term.setCursorPos(savedCursorX, savedCursorY)
        term.setTextColor(savedTextColor)
        term.setBackgroundColor(savedBGColor)
    
        bufferHandler.suggestions = limitedSuggestions
        bufferHandler.autocompleteWindow = {x = x, y = y, width = width, height = height}

        return bufferHandler.autocompleteWindow
    end
    
    -- Function to get autocomplete suggestions
    function bufferHandler:getAutocompleteSuggestions(prefix)
        local suggestions = {}
        local pathParts = {}
    
        for part in prefix:gmatch("[^%.:]+") do
            table.insert(pathParts, part)
        end
    
        -- If the prefix ends with a dot, suggest members of the preceding object
        if prefix:sub(-1) == "." then
            local baseParts = {table.unpack(pathParts)}
            local baseValue = getNestedValue(_G, baseParts)
    
            if type(baseValue) == "table" then
                for name, _ in pairs(baseValue) do
                    table.insert(suggestions, prefix .. name)
                end
            end
    
        -- Otherwise, suggest matches based on the full prefix
        else
            if #pathParts > 1 then
                local baseParts = {table.unpack(pathParts, 1, #pathParts - 1)}
                local lastPart = pathParts[#pathParts]
                local baseValue = getNestedValue(_G, baseParts)
    
                if type(baseValue) == "table" then
                    for name, _ in pairs(baseValue) do
                        if name:sub(1, #lastPart) == lastPart then
                            table.insert(suggestions, table.concat(baseParts, ".") .. "." .. name)
                        end
                    end
                end
            else
                -- Use textutils.complete for suggestions
                local dynamicSuggestions = textutils.complete(prefix, _G)
                for _, suggestion in ipairs(dynamicSuggestions) do
                    table.insert(suggestions, suggestion)
                end
    
                -- Add dynamic identifiers
                for _, identifierEntry in ipairs(self.dynamicIdentifiers or {}) do
                    local identifier = identifierEntry.identifier
                    if identifier:sub(1, #prefix) == prefix then
                        table.insert(suggestions, identifier)
                    end
                end
    
                -- Add hardcoded keywords
                for _, keyword in ipairs(autocompleteKeywords) do
                    if keyword:sub(1, #prefix) == prefix then
                        table.insert(suggestions, keyword)
                    end
                end
            end
        end
        
        -- Remove any duplicates in the suggestions
        local uniqueSuggestions = {}
        local suggestionSet = {}
        
        for _, suggestion in ipairs(suggestions) do
            if not suggestionSet[suggestion] then
                table.insert(uniqueSuggestions, suggestion)
                suggestionSet[suggestion] = true
            end
        end
        
        self:updateStatusBar("Suggestions for: " .. prefix .. " (" .. #uniqueSuggestions .. " found)")
        return uniqueSuggestions
    end

    -- Function to reset autocomplete state
    function bufferHandler:resetAutocomplete()
        if self.autocompleteWindow then
            -- Clear the area where the autocomplete window was displayed
            for i = 0, self.autocompleteWindow.height - 1 do
                term.setCursorPos(self.autocompleteWindow.x, self.autocompleteWindow.y + i)
                term.clearLine()
            end
            self.autocompleteWindow = nil
        end
        self.suggestions = nil
        term.clear()
        bufferHandler:refreshScreen()
        View:drawScreen()
    end

    -- Function to handle inserting the selected suggestion
    function bufferHandler:acceptAutocompleteSuggestion()
        local selectedSuggestion = self.suggestions and self.suggestions[1]
        if selectedSuggestion then
            local currentWord = self:getWordAtCursor()
            
            -- Clean up the suggestion if necessary
            local cleanedSuggestion = selectedSuggestion:gsub("^"..currentWord, "")
            
            -- Insert the cleaned suggestion suffix
            self:insertChar(cleanedSuggestion)
            
            -- Move the cursor to the end of the inserted word
            self.cursorX = self.cursorX + #cleanedSuggestion
            
            -- Reset the autocomplete
            self:resetAutocomplete()
        end
    end

    -- Map keybindings related to autocomplete
    InputHandler:map({"insert"}, {"backspace"}, "autocomplete_backspace", function()
        updateIdentifiers()
        if bufferHandler.suggestions then
            bufferHandler:resetAutocomplete()
        else
            bufferHandler:backspace()
        end
    end, "Handle backspace with autocomplete")

    InputHandler:map({"insert"}, {"tab"}, "autocomplete_tab", function()
        if bufferHandler.suggestions then
            bufferHandler:acceptAutocompleteSuggestion()
        else
            bufferHandler:insertChar("  ")
        end
    end, "Autocomplete or insert tab")

    InputHandler:map({"insert"}, {"enter"}, "autocomplete_enter", function()
        if bufferHandler.suggestions then
            bufferHandler:acceptAutocompleteSuggestion()
        else
            bufferHandler:enter()
        end
    end, "Autocomplete or insert new line")

    InputHandler:map({"insert"}, {"up"}, "autocomplete_up", function()
        if bufferHandler.suggestions then
            table.insert(bufferHandler.suggestions, 1, table.remove(bufferHandler.suggestions))
            View:showAutocompleteWindow(bufferHandler.suggestions)
        else
            InputHandler:execute("move_up")
        end
    end, "Move up in autocomplete or move cursor up")

    InputHandler:map({"insert"}, {"down"}, "autocomplete_down", function()
        if bufferHandler.suggestions then
            table.insert(bufferHandler.suggestions, table.remove(bufferHandler.suggestions, 1))
            View:showAutocompleteWindow(bufferHandler.suggestions)
        else
            bufferHandler:markDirty(bufferHandler.cursorY)
            InputHandler:execute("move_down")
        end
        View:drawScreen()
    end, "Move down in autocomplete or move cursor down")

    InputHandler:map({"insert"}, {"left"}, "autocomplete_left", function()
        if bufferHandler.suggestions then
            bufferHandler:resetAutocomplete()
        else
            InputHandler:execute("move_left")
        end
        
    end, "Cancel autocomplete and move cursor left")

    InputHandler:map({"insert"}, {"right"}, "autocomplete_right", function()
        if bufferHandler.suggestions then
            bufferHandler:acceptAutocompleteSuggestion()
        else
            InputHandler:execute("move_right")
        end

    end, "Accept autocomplete or move cursor right")

    -- Save the original loadFile function
    local originalLoadFile = bufferHandler.loadFile

    -- Extend the loadFile function
    function bufferHandler:loadFile(name)
        -- Call the original loadFile method
        originalLoadFile(self, name)
        -- After loading the file, call updateIdentifiers to refresh the identifier list
        updateIdentifiers()
    end

    -- Save the original saveFile function
    local originalSaveFile = bufferHandler.saveFile

    -- Extend the saveFile function
    function bufferHandler:saveFile()
        -- Call the original saveFile method
        originalSaveFile(self)
        -- After saving the file, call updateIdentifiers to refresh the identifier list
        updateIdentifiers()
    end
end

return {
    init = init
}
