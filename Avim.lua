-- Model.lua

Avim = {}
Avim.__index = Avim

local instance
local cachedView -- This will hold the cached View instance

-- Singleton pattern for Model
function Avim:new()
    if not instance then
        instance = {
            buffer = {},
            cursorX = 1,
            cursorY = 1,
            scrollOffset = 0,
            filename = "",
            yankRegister = "",
            visualStartX = nil,
            visualStartY = nil,
            isVisualMode = false,
            InputMode = "keys", -- Used to decide whether to handle key events or char events: keys or chars
            history = {},
            redoStack = {},
            statusMessage = "",
            shouldExit = false,
            mode = "normal",
            statusColor = colors.green, -- Default status bar color
            statusBarHeight = 2, -- Height of the status bar (dynamically tracked)
            dirtyLines = {}, -- Added initialization for dirtyLines
            allow_horizontal_scroll = true,  -- New flag for enabling/disabling horizontal scroll
            horizontalScrollOffset = 0,  -- Scroll offset for horizontal scrolling
            maxVisibleColumns = SCREENWIDTH, -- Width of the text area in characters
        }
        setmetatable(instance, Avim)
    end
    return instance
end
function Avim:getInstance()
    if not instance then
        instance = Avim:new()
    end
    return instance
end

-- Lazy loading and caching of the View instance
local function getView()
    if not cachedView then
        cachedView = require("View"):getInstance()
    end
    return cachedView
end

function Avim:updateStatusBar(message)
    local view = getView()
    self.statusMessage = message
    self.statusColor = colors.green -- Reset to default color
    view:drawStatusBar(SCREENWIDTH, SCREENHEIGHT)
end

function Avim:updateStatusError(message)
    local view = getView()
    self.statusMessage = message
    self.statusColor = colors.red -- Set color to red for errors
    view:drawStatusBar(SCREENWIDTH, SCREENHEIGHT)
end

function Avim:clearStatusBar()
    local view = getView()
    self.statusMessage = ""
    self.statusColor = colors.green -- Reset to default color
    view:drawStatusBar(SCREENWIDTH, SCREENHEIGHT)
end

-- Undo functionality with history and redo stack management
function Avim:undo()
    if #self.history > 0 then
        local lastState = table.remove(self.history)
        table.insert(self.redoStack, {
            buffer = table.deepCopy(self.buffer),
            cursorX = self.cursorX,
            cursorY = self.cursorY
        })
        self.buffer = lastState.buffer
        self.cursorX = lastState.cursorX
        self.cursorY = lastState.cursorY
        self:markDirty(self.cursorY) -- Mark current line as dirty after undo
        self:updateStatusBar("Undid last action")
    else
        self:updateStatusError("Nothing to undo")
    end
end

function Avim:redo()
    if #self.redoStack > 0 then
        local redoState = table.remove(self.redoStack)
        table.insert(self.history, {
            buffer = table.deepCopy(self.buffer),
            cursorX = self.cursorX,
            cursorY = self.cursorY
        })
        self.buffer = redoState.buffer
        self.cursorX = redoState.cursorX
        self.cursorY = redoState.cursorY
        self:markDirty(self.cursorY) -- Mark current line as dirty after redo
        self:updateStatusBar("Redid last action")
    else
        self:updateStatusError("Nothing to redo")
    end
end

-- Visual mode handling
function Avim:startVisualMode()
    self.visualStartX = self.cursorX
    self.visualStartY = self.cursorY
    self.isVisualMode = true
    self:updateStatusBar("Entered visual mode")
    self:switchMode("visual") -- Switch to visual mode
end

function Avim:endVisualMode()
    self.visualStartX = nil
    self.visualStartY = nil
    self.isVisualMode = false
    self:updateStatusBar("Exited visual mode")
    self:switchMode("normal") -- Switch back to normal mode
    
    -- Redraw the screen to remove highlights
    local view = getView()
    view:drawScreen()
end

-- Loading and saving files
function Avim:loadFile(name)
    self.filename = name
    self.buffer = {}
    if fs.exists(self.filename) then
        local file = fs.open(self.filename, "r")
        for line in file.readLine do
            table.insert(self.buffer, line)
        end
        file.close()
        self:updateStatusBar("Loaded file: " .. self.filename)
    else
        table.insert(self.buffer, "")
        self:updateStatusError("File not found, created new file: " .. self.filename)
    end
    -- Mark all lines as dirty after loading a file
    for i = 1, #self.buffer do
        self:markDirty(i)
    end
end
function Avim:close()
    self.shouldExit = true
    self:updateStatusBar("Closed editor")
end

function Avim:yankLine()
    if #self.buffer == 0 then
        self:updateStatusError("Nothing to yank")
        return
    end

    self.yankRegister = self.buffer[self.cursorY] -- Copy current line to yank register
    self:updateStatusBar("Yanked line")
end



function Avim:saveFile()
    local file = fs.open(self.filename, "w")
    for _, line in ipairs(self.buffer) do
        file.writeLine(line)
    end
    file.close()
    self:updateStatusBar("File saved: " .. self.filename)
end

function Avim:updateScroll()
    local adjustedHeight = SCREENHEIGHT - self.statusBarHeight
    local oldScrollOffset = self.scrollOffset
    local oldHorizontalScrollOffset = self.horizontalScrollOffset

    -- Vertical scrolling
    if self.cursorY < self.scrollOffset + 1 then
        self.scrollOffset = math.max(0, self.cursorY - 1)
    elseif self.cursorY > self.scrollOffset + adjustedHeight then
        self.scrollOffset = math.min(self.cursorY - adjustedHeight, #self.buffer - adjustedHeight)
    end
    self.scrollOffset = math.min(self.scrollOffset, math.max(0, #self.buffer - adjustedHeight))

    -- Horizontal scrolling
    if self.allow_horizontal_scroll then
        local cursorLine = self.buffer[self.cursorY] or ""
        local visibleWidth = self.maxVisibleColumns

        -- Scroll left if the cursor is before the visible area
        if self.cursorX < self.horizontalScrollOffset + 1 then
            self.horizontalScrollOffset = math.max(0, self.cursorX - 1)

        -- Scroll right if the cursor is past the visible area
        elseif self.cursorX > self.horizontalScrollOffset + visibleWidth then
            self.horizontalScrollOffset = math.min(self.cursorX - visibleWidth, #cursorLine - visibleWidth)
        end
    end

    -- Mark all visible lines as dirty if the scroll offset changes
    if self.scrollOffset ~= oldScrollOffset or self.horizontalScrollOffset ~= oldHorizontalScrollOffset then
        local view = getView()
        for i = 1, adjustedHeight do
            self:markDirty(self.scrollOffset + i)
        end
        view:drawScreen()  -- Ensure the screen is fully redrawn
        return true -- Indicate that the scroll offset was updated
    end

    return false -- Indicate that the scroll offset did not change
end




-- Function to mark all visible lines as dirty
function Avim:markAllVisibleLinesDirty(adjustedHeight)
    for i = 1, adjustedHeight do
        self:markDirty(self.scrollOffset + i)
    end
end



function Avim:setStatusBarHeight(height)
    self.statusBarHeight = height
end

-- Mark a line as dirty (needing to be redrawn)
function Avim:markDirty(lineNumber)
    if type(lineNumber) == "number" and lineNumber > 0 and lineNumber <= #self.buffer then
        self.dirtyLines[lineNumber] = true
    end
end

-- Clear all dirty lines after they've been redrawn
function Avim:clearDirtyLines()
    self.dirtyLines = {}
end

-- Editing operations
function Avim:insertChar(char)
    if #self.buffer == 0 then
        table.insert(self.buffer, "")
    end
    self:saveToHistory()
    local line = self.buffer[self.cursorY]
    self.buffer[self.cursorY] = line:sub(1, self.cursorX - 1) .. char .. line:sub(self.cursorX)
    self.cursorX = self.cursorX + 1
    self:markDirty(self.cursorY) -- Mark line as dirty
    self:updateStatusBar("Inserted character")
end

function Avim:backspace()
    if self.cursorX > 1 then
        self:saveToHistory()
        local line = self.buffer[self.cursorY]
        self.buffer[self.cursorY] = line:sub(1, self.cursorX - 2) .. line:sub(self.cursorX)
        self.cursorX = self.cursorX - 1
        self:markDirty(self.cursorY) -- Mark line as dirty
        self:updateStatusBar("Deleted character")
    elseif self.cursorY > 1 then
        self:saveToHistory()
        local line = table.remove(self.buffer, self.cursorY)
        self.cursorY = self.cursorY - 1
        self.cursorX = #self.buffer[self.cursorY] + 1
        self.buffer[self.cursorY] = self.buffer[self.cursorY] .. line
        self:markDirty(self.cursorY) -- Mark line as dirty
        self:updateStatusBar("Deleted line")
    else
        self:updateStatusError("Nothing to delete")
    end
end

function Avim:enter()
    if #self.buffer == 0 then
        table.insert(self.buffer, "")
    end
    self:saveToHistory()
    local line = self.buffer[self.cursorY]
    local newLine = line:sub(self.cursorX)
    self.buffer[self.cursorY] = line:sub(1, self.cursorX - 1)
    table.insert(self.buffer, self.cursorY + 1, newLine)
    self.cursorY = self.cursorY + 1
    self.cursorX = 1
    self:markDirty(self.cursorY) -- Mark current and previous lines as dirty
    self:markDirty(self.cursorY - 1)
    self:updateStatusBar("Inserted new line")
end

function Avim:paste()
    self:saveToHistory()

    local lines = {}
    for line in self.yankRegister:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    if #lines == 1 then
        -- Single-line yank, paste normally
        local currentLine = self.buffer[self.cursorY]
        self.buffer[self.cursorY] = currentLine:sub(1, self.cursorX - 1) .. lines[1] .. currentLine:sub(self.cursorX)
        self.cursorX = self.cursorX + #lines[1]
    else
        -- Multi-line yank
        local currentLine = self.buffer[self.cursorY]
        local beforeCursor = currentLine:sub(1, self.cursorX - 1)
        local afterCursor = currentLine:sub(self.cursorX)

        -- Paste the first line into the current line
        self.buffer[self.cursorY] = beforeCursor .. lines[1]

        -- Insert the middle lines
        for i = 2, #lines - 1 do
            table.insert(self.buffer, self.cursorY + i - 1, lines[i])
        end

        -- Append the last line to the line after the cursor
        self.cursorY = self.cursorY + #lines - 1
        self.buffer[self.cursorY] = lines[#lines] .. afterCursor

        -- Set the cursor position to the end of the pasted text
        self.cursorX = #lines[#lines] + 1
    end

    -- Mark all affected lines as dirty
    for i = 0, #lines - 1 do
        self:markDirty(self.cursorY - i)
    end

    self:updateStatusBar("Pasted text")
end

-- Visual mode operations (yank and cut)
function Avim:yankSelection()
    if not self.visualStartX or not self.visualStartY then
        self:updateStatusError("No selection to yank")
        return
    end

    local startX, startY = math.min(self.cursorX, self.visualStartX), math.min(self.cursorY, self.visualStartY)
    local endX, endY = math.max(self.cursorX, self.visualStartX), math.max(self.cursorY, self.visualStartY)

    self.yankRegister = "" -- Clear yank register

    for y = startY, endY do
        local line = self.buffer[y]
        local yankText
        if y == startY and y == endY then
            yankText = line:sub(startX, endX - 1)
        elseif y == startY then
            yankText = line:sub(startX)
        elseif y == endY then
            yankText = line:sub(1, endX - 1)
        else
            yankText = line
        end
        self.yankRegister = self.yankRegister .. yankText .. "\n"
    end
    self:updateStatusBar("Yanked selection")
end

function Avim:cutSelection()
    if not self.visualStartX or not self.visualStartY then
        self:updateStatusError("No selection to cut")
        return
    end

    self:saveToHistory()
    local startX, startY = math.min(self.cursorX, self.visualStartX), math.min(self.cursorY, self.visualStartY)
    local endX, endY = math.max(self.cursorX, self.visualStartX), math.max(self.cursorY, self.visualStartY)

    self.yankRegister = "" -- Clear yank register

    for y = startY, endY do
        local line = self.buffer[y]
        local cutText
        if y == startY and y == endY then
            cutText = line:sub(startX, endX - 1)
            self.buffer[y] = line:sub(1, startX - 1) .. line:sub(endX)
        elseif y == startY then
            cutText = line:sub(startX)
            self.buffer[y] = line:sub(1, startX - 1)
        elseif y == endY then
            cutText = line:sub(1, endX - 1)
            self.buffer[y] = line:sub(endX)
        else
            cutText = line
            self.buffer[y] = ""
        end
        self.yankRegister = self.yankRegister .. cutText .. "\n"
        self:markDirty(y) -- Mark affected lines as dirty
    end

    self.cursorX = startX
    self.cursorY = startY

    if startY ~= endY then
        self.buffer[startY] = self.buffer[startY] .. self.buffer[startY + 1]
        table.remove(self.buffer, startY + 1)
    end

    self:updateStatusBar("Cut selection")
end

function Avim:cutLine()
    if #self.buffer == 0 then
        self:updateStatusError("Nothing to cut")
        return
    end

    self:saveToHistory()
    self.yankRegister = self.buffer[self.cursorY]
    table.remove(self.buffer, self.cursorY)
    if self.cursorY > #self.buffer then
        self.cursorY = #self.buffer
    end
    self.cursorX = 1
    self:markDirty(self.cursorY) -- Mark current line as dirty
    self:updateStatusBar("Cut line")
end

-- Mode switching and history management
function Avim:switchMode(mode, initialCommand, autoExecute)
    self:saveToHistory()
    self.mode = mode

    -- Close the autocomplete window if switching out of 'insert' mode
    if mode ~= "insert" and self.autocompleteWindow then
        self.autocompleteWindow:close()
        self.autocompleteWindow = nil
    end

    -- Reset the InputMode based on the new mode
    if mode == "insert" then
        self.InputMode = "chars"
    else
        self.InputMode = "keys"
    end

    -- Reset key sequence and other state variables to default
    local keyHandler = require("KeyHandler"):getInstance()
    keyHandler:resetKeySequence()

    -- Additional resets can be added here if needed
    -- For example, reset search highlight, visual selection, etc.

    local view = getView()
    if mode == "command" then
        local commandHandler = require("CommandHandler"):getInstance()
        -- Pass initialCommand and autoExecute, even if initialCommand is nil
        commandHandler:handleCommandInput(self, view, initialCommand, autoExecute)
    end

    view:refreshScreen()
end

-- Save the current state to history
function Avim:saveToHistory()
    table.insert(self.history, {
        buffer = table.deepCopy(self.buffer),
        cursorX = self.cursorX,
        cursorY = self.cursorY
    })
    self.redoStack = {} -- Clear the redo stack since new history invalidates future redo actions
end

-- Deep copy utility function for saving history states
function table.deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[table.deepCopy(orig_key)] = table.deepCopy(orig_value)
        end
        setmetatable(copy, table.deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- Word detection for autocomplete functionality
function Avim:getWordAtCursor()
    local line = self.buffer[self.cursorY] or ""
    local startPos = self.cursorX

    while startPos > 1 and line:sub(startPos - 1, startPos - 1):match("[%w_%.:]") do
        startPos = startPos - 1
    end

    return line:sub(startPos, self.cursorX - 1)
end

-- Hardcoded autocomplete keywords
local autocompleteKeywords = {
    "and", "break", "do", "else", "elseif", "end", "for", "function", "if", "in", 
    "local", "nil", "not", "or", "repeat", "require", "return", "then", "until", 
    "while", "View", "Model", "highlightLine", "createWindow"
}

-- Helper function to get the value of a nested key
local function getNestedValue(root, pathParts)
    local current = root
    for _, part in ipairs(pathParts) do
        if type(current) == "table" and current[part] then
            current = current[part]
        else
            return nil
        end
    end
    return current
end

-- Function to get autocomplete suggestions
function Avim:getAutocompleteSuggestions(prefix)
    local suggestions = {}

    self:updateStatusBar("Suggestions for: " .. prefix)

    local pathParts = {}
    for part in prefix:gmatch("[^%.:]+") do
        table.insert(pathParts, part)
    end

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
        for _, keyword in ipairs(autocompleteKeywords) do
            if keyword:sub(1, #prefix) == prefix then
                table.insert(suggestions, keyword)
            end
        end

        for name, value in pairs(_G) do
            if type(name) == "string" and name:sub(1, #prefix) == prefix then
                table.insert(suggestions, name)
            end

            if type(value) == "table" then
                for key in pairs(value) do
                    if type(key) == "string" and key:sub(1, #prefix) == prefix then
                        table.insert(suggestions, name .. "." .. key)
                    end
                end
            end
        end
    end

    self:updateStatusBar("Suggestions for: " .. prefix .. " (" .. #suggestions .. " found)")

    return suggestions
end

function Avim:insertTextAtCursor(text)

    local lines = {}
    for line in text:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    -- Insert each line into the buffer
    for i, line in ipairs(lines) do
        -- If it's the first line, insert it at the cursor position
        if i == 1 then
            local currentLine = self.buffer[self.cursorY] or ""
            local beforeCursor = currentLine:sub(1, self.cursorX - 1)
            local afterCursor = currentLine:sub(self.cursorX)

            -- Handle wrapping the first line
            if #beforeCursor + #line > SCREENWIDTH then
                local remainingText = beforeCursor .. line .. afterCursor
                self.buffer[self.cursorY] = remainingText:sub(1, SCREENWIDTH)
                table.insert(self.buffer, self.cursorY + 1, remainingText:sub(SCREENWIDTH + 1))
                self.cursorX = #line - (SCREENWIDTH - #beforeCursor) + 1
            else
                self.buffer[self.cursorY] = beforeCursor .. line .. afterCursor
                self.cursorX = #beforeCursor + #line + 1
            end
        else
            -- For subsequent lines, insert them as new lines
            self.cursorY = self.cursorY + 1
            table.insert(self.buffer, self.cursorY, line)
            self.cursorX = #line + 1
        end
    end

    -- Ensure the view is updated to reflect changes
    self:updateScroll()
    self:saveToHistory()
end

return Avim
