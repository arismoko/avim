local Model = require("Avim"):getInstance()

View = {}
View.__index = View

local instance

local colorMatch = {
    popupBG = colors.lightGray,
    popupFrame = colors.gray,
    popupFont = colors.black,
    cAccentText = colors.lightGray,
    bg = colors.black,
    bracket = colors.lightGray,
    comment = colors.gray,
    func = colors.orange,
    keyword = colors.red,
    number = colors.magenta,
    operator = colors.cyan,
    string = colors.green,
    special = colors.yellow,
    text = colors.white,
    positive = colors.lime,
    negative = colors.red
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

function View:new()
    if not instance then
        instance = {
            windows = {}, 
            activeWindow = nil, 
            savedScreenBuffer = {}
        }
        setmetatable(instance, View)
    end
    return instance
end

function View:getInstance()
    if not instance then
        instance = View:new()
    end
    return instance
end

function View:createWindow(x, y, width, height, backgroundColor, textColor)
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
    end
    function window:scrollUp()
        if self.currentLine > 1 then
            self.currentLine = self.currentLine - 1
            -- Shift buffer lines up
            for i = 1, self.height - 1 do
                self.buffer[i] = self.buffer[i + 1]
            end
            self.buffer[self.height] = string.rep(" ", self.width)  -- Clear the last line
            self:show()  -- Redraw the window content
        end
    end
    function window:scrollDown()
        if self.currentLine < #self.buffer then
            self.currentLine = self.currentLine + 1
            -- Shift buffer lines down
            for i = self.height, 2, -1 do
                self.buffer[i] = self.buffer[i - 1]
            end
            self.buffer[1] = string.rep(" ", self.width)  -- Clear the first line
            self:show()  -- Redraw the window content
        end
    end
        
    function window:close()
        local view = View:getInstance()

        view.activeWindow = nil
                term.clear()
        view:refreshScreen()
    end

    function window:writeText(x, y, text)
        local bufferLine = self.buffer[y] or string.rep(" ", self.width)
        self.buffer[y] = bufferLine:sub(1, x - 1) .. text .. bufferLine:sub(x + #text)
        self:show()
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
    end

    function window:writeline(text)
        self:write(text)
        self.currentLine = self.currentLine + 1
        self.currentColumn = 1
    end

    function window:clear()
        for i = 1, self.height do
            self.buffer[i] = string.rep(" ", self.width)
        end
        self.currentLine = 1
        self.currentColumn = 1
        self:show()
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

    return window
end

function View:closeAllWindows()
    for _, window in ipairs(self.windows) do
        window:close()
    end
    self.windows = {}
    self.activeWindow = nil
    self:refreshScreen()
end

function View:showPopup(message)
    local padding = 2
    local maxPopupWidth = SCREENWIDTH - 4  -- Max possible width with some margin
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

    local popupHeight = #lines + 2  -- 2 extra for the top and bottom borders
    local popupX = math.floor((SCREENWIDTH - popupWidth) / 2)
    local popupY = math.floor((SCREENHEIGHT - popupHeight) / 2)

    -- Create and display the popup window
    local window = self:createWindow(popupX, popupY, popupWidth, popupHeight, colorMatch.popupBG, colorMatch.popupFont)
    window:clear()
    window:writeline(string.rep("-", popupWidth))

    for _, line in ipairs(lines) do
        local paddingSpaces = math.floor((popupWidth - #line) / 2)
        window:writeline("|" .. string.rep(" ", paddingSpaces) .. line .. string.rep(" ", popupWidth - #line - paddingSpaces - 2) .. "|")
    end

    window:writeline(string.rep("-", popupWidth))

    os.pullEvent("key")
    window:close()
end






function View:drawScreen()
    if self.activeWindow then
        self.activeWindow:show()
        return
    else
        local adjustedHeight = SCREENHEIGHT - Model.statusBarHeight


        for lineNumber in pairs(Model.dirtyLines) do
            self:drawLine(lineNumber)
        end

        Model:clearDirtyLines()
        self:drawStatusBar()
        term.setCursorBlink(true)
    end
end

function View:getLineNumberWidth()
    return #tostring(#Model.buffer)
end

function View:drawLine(y)
    if type(y) ~= "number" then
        error("Invalid argument: 'y' should be a number, but received a " .. type(y))
    end
    if self.activeWindow then
        return
    end

    local lineIndex = Model.scrollOffset + y
    term.setCursorPos(1, y)
    term.clearLine()

    if Model.buffer[lineIndex] then
        local lineNumberWidth = self:getLineNumberWidth()
        local lineNumber = tostring(lineIndex)

        lineNumber = string.rep(" ", lineNumberWidth - #lineNumber) .. lineNumber

        term.setTextColor(colors.lightGray)
        term.write(lineNumber .. " ")

        term.setTextColor(colors.white)

        local lineToDisplay = Model.buffer[lineIndex]

        if Model.allow_horizontal_scroll then
            lineToDisplay = lineToDisplay:sub(Model.horizontalScrollOffset + 1, Model.horizontalScrollOffset + Model.maxVisibleColumns)
        end

        if Model.isVisualMode and Model.visualStartY and lineIndex >= math.min(Model.visualStartY, Model.cursorY) and lineIndex <= math.max(Model.visualStartY, Model.cursorY) then
            local startX = 1
            local endX = #lineToDisplay
            if lineIndex == Model.visualStartY then startX = Model.visualStartX end
            if lineIndex == Model.cursorY then endX = Model.cursorX end

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
            highlightLine(lineToDisplay)
        end
    end
end


function View:drawStatusBar()
    local statusBarLines = Model.statusBarHeight

    if statusBarLines > 1 then
        term.setCursorPos(1, SCREENHEIGHT - statusBarLines + 1)
        term.setBackgroundColor(Model.statusColor)
        term.clearLine()
        term.setTextColor(colors.white)
        if Model.statusMessage ~= "" then
            term.write(Model.statusMessage)
        end
    end

    term.setCursorPos(1, SCREENHEIGHT)
    term.setBackgroundColor(Model.statusColor)
    term.clearLine()
    term.setTextColor(colors.white)
    term.write("File: " .. Model.filename .. " | Pos: " .. Model.cursorY .. "," .. Model.cursorX .. " | Mode: " .. Model.mode)

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function View:updateCursor()
    local lineNumberWidth = self:getLineNumberWidth() + 1
    term.setCursorPos(Model.cursorX + lineNumberWidth, Model.cursorY - Model.scrollOffset)
end

function View:showAutocompleteWindow(suggestions)
    local x = Model.cursorX
    local y = Model.cursorY - Model.scrollOffset + 1

    local width = math.max(10, #suggestions[1] + 2)
    local height = math.min(#suggestions, 5)

    if #suggestions > 5 then
        suggestions = {table.unpack(suggestions, 1, 5)}
    end

    if Model.autocompleteWindow then
        Model.autocompleteWindow:clear()
    else
        Model.autocompleteWindow = self:createWindow(x, y, width, height, colorMatch.popupBG, colorMatch.popupFont)
        Model:updateStatusBar("Autocomplete suggestions window opened")
    end

    for i, suggestion in ipairs(suggestions) do
        Model.autocompleteWindow:writeline(suggestion)
    end

    Model.suggestions = suggestions
    Model.autocompleteWindow:show()

    View:refreshScreen()
    return Model.autocompleteWindow
end
function View:refreshScreen()
    -- Mark all lines as dirty except the status bar
    local adjustedHeight = SCREENHEIGHT - Model.statusBarHeight
    for i = 1, adjustedHeight do
        Model:markDirty(i)
    end
    View:drawScreen()
    term.setCursorBlink(true)
end

function View:getAvailableWidth()
    local lineNumberWidth = self:getLineNumberWidth()
    return SCREENWIDTH - lineNumberWidth - 1
end
return View
