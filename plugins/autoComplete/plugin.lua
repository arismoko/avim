local function init(components)
    local View = components.view
    local bufferHandler = components.bufferHandler
    local InputHandler = components.inputHandler
    
    -- Store the original handleCharInput function
    local originalHandleCharInput = InputHandler.handleCharInput

    -- Override the handleCharInput function to include autocomplete
    function InputHandler:handleCharInput(char, model, view)
        -- Call the original function to insert the character
        originalHandleCharInput(self, char, model, view)

        -- Trigger autocomplete after inserting a character
        local currentWord = model:getWordAtCursor()
        if #currentWord > 0 then
            local suggestions = model:getAutocompleteSuggestions(currentWord)
            if #suggestions > 0 then
                view:showAutocompleteWindow(suggestions)
            else
                model:resetAutocomplete()
            end
        else
            model:resetAutocomplete()
        end
    end

    -- Helper function to get a nested value from a table
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

    -- Hardcoded autocomplete keywords
    local autocompleteKeywords = {
        "and", "break", "do", "else", "elseif", "end", "for", "function", "if", "in", 
        "local", "nil", "not", "or", "repeat", "require", "return", "then", "until", 
        "while"
    }

    -- Function to show the autocomplete window
    function View:showAutocompleteWindow(suggestions)
        local x = bufferHandler.cursorX
        local y = bufferHandler.cursorY - bufferHandler.scrollOffset + 1
    
        -- Calculate the height of the autocomplete window
        local height = math.min(#suggestions, 5)
        
        -- Determine the dynamic width based on the longest suggestion, capped at 15 characters
        local maxSuggestionLength = 0
        for _, suggestion in ipairs(suggestions) do
            maxSuggestionLength = math.max(maxSuggestionLength, #suggestion)
        end
    
        -- Set the width to be the length of the longest suggestion, plus padding, up to a maximum of 15 characters
        local width = math.min(maxSuggestionLength + 5, 15)
    
        -- Adjust 'y' to place the window above the cursor line if possible
        if y > SCREENHEIGHT/2 then
            y = y - height - 1 -- Move the window above the cursor line
        end
    
        -- Ensure the window doesn't go off-screen
        if y < 1 then
            y = 1
        elseif y + height - 1 > SCREENHEIGHT then
            y = SCREENHEIGHT - height + 1
        end
    
        if bufferHandler.autocompleteWindow then
            bufferHandler.autocompleteWindow:clear()
        else
            bufferHandler.autocompleteWindow = self:createWindow(x, y, width, height, colors.lightGray, colors.black)
            bufferHandler:updateStatusBar("Autocomplete suggestions window opened")
        end
    
        for i, suggestion in ipairs(suggestions) do
            bufferHandler.autocompleteWindow:writeline(suggestion)
        end
    
        bufferHandler.suggestions = suggestions
        bufferHandler.autocompleteWindow:show()
    
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
    
                -- Add hardcoded keywords
                for _, keyword in ipairs(autocompleteKeywords) do
                    if keyword:sub(1, #prefix) == prefix then
                        table.insert(suggestions, keyword)
                    end
                end
            end
        end
    
        self:updateStatusBar("Suggestions for: " .. prefix .. " (" .. #suggestions .. " found)")
        return suggestions
    end
    
    -- Function to reset autocomplete state
    function bufferHandler:resetAutocomplete()
        if self.autocompleteWindow then
            self.autocompleteWindow:close()
            self.autocompleteWindow = nil
            self.suggestions = nil
            require("View"):drawScreen()
        end
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
            View:drawScreen()
        end
    end

    -- Map keybindings related to autocomplete
    InputHandler:map({"insert"}, {"backspace"}, "autocomplete_backspace", function()
        bufferHandler:resetAutocomplete()
        bufferHandler:backspace()
        View:drawScreen()
    end, "Handle backspace with autocomplete")

    InputHandler:map({"insert"}, {"tab"}, "autocomplete_tab", function()
        if bufferHandler.suggestions then
            bufferHandler:acceptAutocompleteSuggestion()
        else
            bufferHandler:insertChar("    ")
            bufferHandler:markDirty(bufferHandler.cursorY)
            View:drawLine(bufferHandler.cursorY - bufferHandler.scrollOffset)
        end
        View:drawScreen()
    end, "Autocomplete or insert tab")

    InputHandler:map({"insert"}, {"enter"}, "autocomplete_enter", function()
        if bufferHandler.suggestions then
            bufferHandler:acceptAutocompleteSuggestion()
        else
            bufferHandler:enter()
            bufferHandler:markDirty(bufferHandler.cursorY)
            View:drawScreen()
        end
    end, "Autocomplete or insert new line")

    InputHandler:map({"insert"}, {"up"}, "autocomplete_up", function()
        if bufferHandler.suggestions then
            table.insert(bufferHandler.suggestions, 1, table.remove(bufferHandler.suggestions))
            View:showAutocompleteWindow(bufferHandler.suggestions)
        else
            bufferHandler:markDirty(bufferHandler.cursorY)
            InputHandler:execute("move_up")
        end
        View:drawScreen()
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
        bufferHandler:resetAutocomplete()
        InputHandler:execute("move_left")
        bufferHandler:markDirty(bufferHandler.cursorY)
        View:drawScreen()
    end, "Cancel autocomplete and move cursor left")

    InputHandler:map({"insert"}, {"right"}, "autocomplete_right", function()
        if bufferHandler.suggestions then
            bufferHandler:acceptAutocompleteSuggestion()
        else
            InputHandler:execute("move_right")
            bufferHandler:markDirty(bufferHandler.cursorY)
            View:drawScreen()
        end
    end, "Accept autocomplete or move cursor right")
end

return {
    init = init
}
