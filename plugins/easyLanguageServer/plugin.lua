local function init(components)
    local bufferHandler = components.bufferHandler
    local viewInstance = components.view
    local inputHandler = components.inputHandler

    local colorMatch = {
        popupBG = colors.lightGray,
        popupFrame = colors.gray,
        popupFont = colors.black,
        cAccentText = colors.lightGray,
        bg = colors.black,
        bracket = colors.lightGray,
        comment = colors.gray,
        func = colors.orange,
        keyword = colors.blue,  -- Changed from red to blue
        number = colors.magenta,
        operator = colors.cyan,
        string = colors.green,
        special = colors.yellow,
        text = colors.white,
        positive = colors.lime,
        negative = colors.purple,
        error = colors.red  -- Added explicitly for errors
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
        { "^\"\"", colorMatch["string"] },
        { "^\".-[^\\]\"", colorMatch["string"] },
        { "^\'\'", colorMatch["string"] },
        { "^\'.-[^\\]\'", colorMatch["string"] },
        { "^%[%[%]%]", colorMatch["string"] },
        { "^%[%[.-[^\\]%]%]", colorMatch["string"] },
        { "^[\127\162\163\165\169\174\182\181\177\183\186\188\189\190\215\247@]+", colorMatch["special"] },
        { "^[%d][xA-Fa-f.%d#]+", colorMatch["number"] },
        { "^[%d]+", colorMatch["number"] },
        { "^[,{}%[%]%(%)]", colorMatch["bracket"] },
        { "^[!%/\\:~<>=%*%+%-%%]+", colorMatch["operator"] },
        { "^true", colorMatch["number"] },
        { "^false", colorMatch["number"] },
        { "^[%w_%.]+", function(match, after)
            if tKeywords[match] then
                return colorMatch["keyword"]
            elseif after:sub(1,1) == "(" then
                return colorMatch["func"]
            end
            return colorMatch["text"]
        end },
        { "^[^%w_]", colorMatch["text"] }
    }
    local errors = {}
    local function checkCurrentFileForErrors()
        errors = {}  -- Clear previous errors
    
        local fileName = bufferHandler.filename
        if not fileName then
            viewInstance:showPopup("Error", "No file to check for errors", {"OK"}, colorMatch.popupBG, colorMatch.popupFont)
            return
        end
    
        local file = fs.open(fileName, "r")
        if not file then
            viewInstance:showPopup("Error", "Failed to open file for error checking", {"OK"}, colorMatch.popupBG, colorMatch.popupFont)
            return
        end
    
        local fileContent = file.readAll()  -- Read the entire file content
        file.close()
    
        -- Pass _G as the environment to load the file content
        local func, syntaxErr = load(fileContent, fileName, "t", _G)
    
        if not func then
            -- Syntax error found
            viewInstance:showPopup("Syntax Error!", syntaxErr, {"OK"}, colorMatch.popupBG, colorMatch.popupFont)
            for lineNum, msg in syntaxErr:gmatch(":(%d+): (.+)") do
                local maxLineNum = #bufferHandler.buffer
                local lineNumCapped = math.min(tonumber(lineNum), maxLineNum)
                table.insert(errors, {line = lineNumCapped, message = msg})
            end
        else
            -- Step 2: Execute the code with pcall to catch runtime errors
            local success, runtimeErr = pcall(func)
    
            if not success and runtimeErr then
                -- Runtime error found
                viewInstance:showPopup("Runtime Error!", runtimeErr, {"OK"}, colorMatch.popupBG, colorMatch.popupFont)
                for lineNum, msg in runtimeErr:gmatch(":(%d+): (.+)") do
                    local maxLineNum = #bufferHandler.buffer
                    local lineNumCapped = math.min(tonumber(lineNum), maxLineNum)
                    table.insert(errors, {line = lineNumCapped, message = msg})
                end
            end
        end
    
        -- Update errors in the bufferHandler if necessary
        if bufferHandler.checkLineForErrors then
            bufferHandler.checkLineForErrors()
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
    local lineIndex = bufferHandler.cursorY
    local hasError, errorMessage = lineHasError(lineIndex)

    if hasError then
        bufferHandler:updateStatusError("Error at line " .. lineIndex )
        
        -- Show the error window when hovering over the line with the error
        viewInstance:showErrorWindow(errorMessage, lineIndex)
        
        -- Optional: remove the error from the errors list once it's shown
        for i, error in ipairs(errors) do
            if error.line == lineIndex then
                table.remove(errors, i)
                break
            end
        end
    else
        -- If there is no error, ensure the error window is closed
        if bufferHandler.errorWindow then
            bufferHandler.errorWindow:close()
            bufferHandler.errorWindow = nil
            View:drawScreen()
        end
    end
end
function viewInstance:drawLine(y)
    local lineIndex = bufferHandler.scrollOffset + y
    local lineContent = bufferHandler:getLine(lineIndex)
    
    term.setCursorPos(1, y)
    term.clearLine()
    
    if lineContent then
        local lineNumberWidth = self:getLineNumberWidth()
        local lineNumber = tostring(lineIndex)
        lineNumber = string.rep(" ", lineNumberWidth - #lineNumber) .. lineNumber

        term.setTextColor(colors.lightGray)
        term.write(lineNumber .. " ")

        -- Check if the line has an error
        if lineHasError(lineIndex) then
            -- Highlight the entire line in red if there's an error
            term.setTextColor(colorMatch.error)
            term.write(lineContent)
        else
            -- Handle visual mode highlighting
            local visualStartY = math.min(bufferHandler.visualStartY or bufferHandler.cursorY, bufferHandler.cursorY)
            local visualEndY = math.max(bufferHandler.visualStartY or bufferHandler.cursorY, bufferHandler.cursorY)

            if bufferHandler.isVisualMode and lineIndex >= visualStartY and lineIndex <= visualEndY then
                local startX = 1
                local endX = #lineContent

                if lineIndex == bufferHandler.visualStartY then startX = bufferHandler.visualStartX end
                if lineIndex == bufferHandler.cursorY then endX = bufferHandler.cursorX end

                if startX > endX then
                    startX, endX = endX, startX
                end

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
    function View:showErrorWindow(errorMessage, lineNumber)
        local x = 1  -- Align the window to start from the left of the screen
        local y = lineNumber + 1  -- Place the window right below the error line
        
        -- Determine the window dimensions
        local width = math.min(50, #errorMessage + 4)  -- Dynamic width based on the error message length
        local height = 3  -- Enough height to fit the message and some padding
        
        -- Ensure the window stays within the screen bounds
        if y + height > SCREENHEIGHT then
            y = SCREENHEIGHT - height
        end
        
        -- Create the window or reuse the existing one
        if bufferHandler.errorWindow then
            bufferHandler.errorWindow:clear()
        else
            bufferHandler.errorWindow = self:createWindow(x, y, width, height, colors.lightGray, colors.black)
            bufferHandler:updateStatusBar("Error window opened")
        end
        
        -- Write the error message to the window
        bufferHandler.errorWindow:writeline("Error at line " .. lineNumber)
        bufferHandler.errorWindow:writeline(errorMessage)
        
        bufferHandler.errorWindow:show()
    end
    
    -- Expose the error checking function to be called manually (e.g., on save)
    bufferHandler.checkCurrentFileForErrors = checkCurrentFileForErrors
    bufferHandler.checkLineForErrors = checkLineForErrors
    inputHandler:mapCommand(
    "w",
    function(name)
        if name then bufferHandler:saveFileAs(name)
        else 
            bufferHandler:saveFile()
            bufferHandler.checkCurrentFileForErrors()
            bufferHandler:updateStatusBar("Checked for errors!")
            viewInstance:drawScreen()
        end
    end)
    inputHandler:map({"normal", "visual"}, {"h"}, "move_left", function()
        bufferHandler:markDirty(bufferHandler.cursorY)  
        bufferHandler.cursorX = math.max(1, bufferHandler.cursorX - 1)
        bufferHandler.checkLineForErrors()
    end, "Move Left")
    
    inputHandler:map({"normal", "visual"}, {"l"}, "move_right", function()
        bufferHandler:markDirty(bufferHandler.cursorY)  
        bufferHandler.cursorX = math.min(#bufferHandler.buffer[bufferHandler.cursorY] + 1, bufferHandler.cursorX + 1)
        bufferHandler.checkLineForErrors()
    end, "Move Right")
    
    inputHandler:map({"normal", "visual"}, {"k"}, "move_up", function()
        bufferHandler:markDirty(bufferHandler.cursorY)  
        if bufferHandler.cursorY > 1 then
            bufferHandler.cursorY = bufferHandler.cursorY - 1
        end
        bufferHandler.cursorX = math.min(bufferHandler.cursorX, #bufferHandler.buffer[bufferHandler.cursorY] + 1)
        bufferHandler.checkLineForErrors()
    end, "Move Up")
    
    inputHandler:map({"normal", "visual"}, {"j"}, "move_down", function()
        bufferHandler:markDirty(bufferHandler.cursorY)  
        if bufferHandler.cursorY < #bufferHandler.buffer then
            bufferHandler.cursorY = bufferHandler.cursorY + 1
        end
        bufferHandler.cursorX = math.min(bufferHandler.cursorX, #bufferHandler.buffer[bufferHandler.cursorY] + 1)
        bufferHandler.checkLineForErrors()
    end, "Move Down")

    inputHandler:map({"normal"}, {"g + d"}, "goto_definition", function()
        -- Get the word under the cursor
        local word = bufferHandler:getNextIdentifierOnLine()
    
        if not word or word == "" then
            bufferHandler:updateStatusError("No word under cursor")
            return
        end
    
        -- Check if the dynamicIdentifiers list is empty or nil
        if not bufferHandler.dynamicIdentifiers or #bufferHandler.dynamicIdentifiers == 0 then
            bufferHandler:updateStatusError("No identifiers available for: ".. word)
            return
        end
    
        -- Search for the word in the dynamicIdentifiers list
        local identifierEntry = nil
        for _, entry in ipairs(bufferHandler.dynamicIdentifiers) do
            if entry.identifier == word then
                identifierEntry = entry
                break
            end
        end
    
        if identifierEntry then
            -- Move the cursor to the line where the identifier was defined
            bufferHandler.cursorY = identifierEntry.line
            bufferHandler.cursorX = 1
            bufferHandler:updateScroll(SCREENHEIGHT)
            bufferHandler:updateStatusBar("Jumped to definition of '" .. word .. "' at line " .. identifierEntry.line)
        else
            bufferHandler:updateStatusError("Definition for '" .. word .. "' not found")
        end
    end, "Go to Definition")

end

return {
    init = init
}