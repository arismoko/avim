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
  

    -- Overwrite the createWindow function to apply custom colors
    function viewInstance:createWindow(x, y, width, height, backgroundColor, textColor)
        backgroundColor = backgroundColor or colorMatch.popupBG
        textColor = textColor or colorMatch.popupFont
        
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
            backgroundColor = backgroundColor,
            textColor = textColor,
            buffer = {},
            currentLine = 1,
            currentColumn = 1
        }

        for i = 1, height do
            window.buffer[i] = string.rep(" ", width)
        end

        function window:show()
            View:getInstance().activeWindow = self
            term.setBackgroundColor(self.backgroundColor)
            term.setTextColor(self.textColor)
            for i = 1, self.height do
                term.setCursorPos(self.x, self.y + i - 1)
                term.write(self.buffer[i])
            end
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            View:drawScreen()
        end

        function window:scrollUp()
            if self.currentLine > 1 then
                self.currentLine = self.currentLine - 1
                for i = 1, self.height - 1 do
                    self.buffer[i] = self.buffer[i + 1]
                end
                self.buffer[self.height] = string.rep(" ", self.width)
                self:show()
                View:drawScreen()
            end
        end

        function window:scrollDown()
            if self.currentLine < #self.buffer then
                self.currentLine = self.currentLine + 1
                for i = self.height, 2, -1 do
                    self.buffer[i] = self.buffer[i - 1]
                end
                self.buffer[1] = string.rep(" ", self.width)
                self:show()
                View:drawScreen()
            end
        end

        function window:close()
            local view = View:getInstance()

            view.activeWindow = nil
            view:drawScreen()
        end

        function window:writeText(x, y, text)
            local bufferLine = self.buffer[y] or string.rep(" ", self.width)
            self.buffer[y] = bufferLine:sub(1, x - 1) .. text .. bufferLine:sub(x + #text)
            View:drawScreen()
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
            View:drawScreen()
        end

        function window:writeline(text)
            self:write(text)
            self.currentLine = self.currentLine + 1
            self.currentColumn = 1
            bufferHandler:refreshScreen()
            View:drawScreen()
        end

        function window:clear()
            for i = 1, self.height do
                self.buffer[i] = string.rep(" ", self.width)
            end
            self.currentLine = 1
            self.currentColumn = 1
            self:show()  -- Only redraw the window area
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

        table.insert(View:getInstance().windows, window)

        View:drawScreen()
        return window
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