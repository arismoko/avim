-- Model.lua

BufferHandler = {}
BufferHandler.__index = BufferHandler

local instance
local cachedView -- This will hold the cached View instance

-- Singleton pattern for Model
function BufferHandler:new()
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
        setmetatable(instance, BufferHandler)
    end
    return instance
end
function BufferHandler:getInstance()
    if not instance then
        instance = BufferHandler:new()
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

function BufferHandler:updateStatusBar(message)
    local view = getView()
    self.statusMessage = message
    self.statusColor = colors.green -- Reset to default color
    view:drawStatusBar(SCREENWIDTH, SCREENHEIGHT)
end

function BufferHandler:updateStatusError(message)
    local view = getView()
    self.statusMessage = message
    self.statusColor = colors.red -- Set color to red for errors
    view:drawStatusBar(SCREENWIDTH, SCREENHEIGHT)
end

function BufferHandler:clearStatusBar()
    local view = getView()
    self.statusMessage = ""
    self.statusColor = colors.green -- Reset to default color
    view:drawStatusBar(SCREENWIDTH, SCREENHEIGHT)
end

-- Undo functionality with history and redo stack management
function BufferHandler:undo()
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
        self:refreshScreen()
        self:updateStatusBar("Undid last action")
    else
        self:updateStatusError("Nothing to undo")
    end
end

function BufferHandler:refreshScreen()
    -- Mark all lines as dirty except the status bar
    local adjustedHeight = SCREENHEIGHT - self.statusBarHeight
    for i = 1, adjustedHeight do
        self:markDirty(i)
    end
    term.setCursorBlink(true)
end

function BufferHandler:redo()
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
        self:refreshScreen()
        self:updateStatusBar("Redid last action")
    else
        self:updateStatusError("Nothing to redo")
    end
end

-- Visual mode handling
function BufferHandler:startVisualMode()
    self.visualStartX = self.cursorX
    self.visualStartY = self.cursorY
    self.isVisualMode = true
    self:updateStatusBar("Entered visual mode")
    self:switchMode("visual") -- Switch to visual mode
end

function BufferHandler:endVisualMode()
    self.visualStartX = nil
    self.visualStartY = nil
    self.isVisualMode = false
    self:updateStatusBar("Exited visual mode")
    self:switchMode("normal") -- Switch back to normal mode
    
    -- Redraw the screen to remove highlights
    local view = getView()
    self:refreshScreen()
end

-- Loading and saving files
function BufferHandler:loadFile(name)
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
    self:refreshScreen()
end
function BufferHandler:close()
    self.shouldExit = true
    self:updateStatusBar("Closed editor")
end

function BufferHandler:yankLine()
    if #self.buffer == 0 then
        self:updateStatusError("Nothing to yank")
        return
    end
    self.yankRegister = self.buffer[self.cursorY] -- Copy current line to yank register
    self:updateStatusBar("Yanked line")
end



function BufferHandler:saveFile()
    local file = fs.open(self.filename, "w")
    for _, line in ipairs(self.buffer) do
        file.writeLine(line)
    end
    file.close()
    self:updateStatusBar("File saved: " .. self.filename)
end

function BufferHandler:saveFileAs(name)
    self.filename = name
    self:saveFile()
end

function BufferHandler:updateScroll()
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
        local lineNumberWidth = getView():getLineNumberWidth() + 1 -- Add 1 for space between number and text
        local visibleWidth = self.maxVisibleColumns - lineNumberWidth

        -- Scroll left if the cursor is before the visible area
        if self.cursorX < self.horizontalScrollOffset + 1 then
            self.horizontalScrollOffset = math.max(0, self.cursorX - 1)
        -- Scroll right if the cursor is past the visible area
        elseif self.cursorX > self.horizontalScrollOffset + visibleWidth then
            self.horizontalScrollOffset = math.max(0, self.cursorX - visibleWidth)
        end
    end
    if self.scrollOffset ~= oldScrollOffset or self.horizontalScrollOffset ~= oldHorizontalScrollOffset then
        self:refreshScreen()
        View:drawScreen()
        return true -- Indicate that the scroll offset was updated
    end

    return false -- Indicate that the scroll offset did not change
end





-- Function to mark all visible lines as dirty
function BufferHandler:markAllVisibleLinesDirty()
    local adjustedHeight = SCREENHEIGHT - self.statusBarHeight
    for i = 1, adjustedHeight do
        self:markDirty(self.scrollOffset + i)
    end
end



function BufferHandler:setStatusBarHeight(height)
    self.statusBarHeight = height
end

-- Mark a line as dirty (needing to be redrawn)
function BufferHandler:markDirty(lineNumber)
    if type(lineNumber) == "number" and lineNumber > 0 and lineNumber <= #self.buffer then
        self.dirtyLines[lineNumber] = true
    end
end

-- Clear all dirty lines after they've been redrawn
function BufferHandler:clearDirtyLines()
    self.dirtyLines = {}
end

-- Editing operations
function BufferHandler:insertChar(char)
    if #self.buffer == 0 then
        table.insert(self.buffer, "")
    end
    self:saveToHistory()
    local line = self.buffer[self.cursorY]
    self.buffer[self.cursorY] = line:sub(1, self.cursorX - 1) .. char .. line:sub(self.cursorX)
    self.cursorX = self.cursorX + 1
    self:markDirty(self.cursorY)
    self:markDirty(self.cursorY + 1)
    --if cursorX is greater than the maxVisibleColumns, update cursor and scroll
    if self.cursorX > self.maxVisibleColumns then
        self:updateScroll()
    end
    self:refreshScreen()
    getView():drawScreen()
    self:updateStatusBar("Inserted character")
end

function BufferHandler:backspace()
    if self.cursorX > 1 then
        self:saveToHistory()
        local line = self.buffer[self.cursorY]
        self.buffer[self.cursorY] = line:sub(1, self.cursorX - 2) .. line:sub(self.cursorX)
        self.cursorX = self.cursorX - 1
        self:refreshScreen()
        self:updateStatusBar("Deleted character")
    elseif self.cursorY > 1 then
        self:saveToHistory()
        local line = table.remove(self.buffer, self.cursorY)
        self.cursorY = self.cursorY - 1
        self.cursorX = #self.buffer[self.cursorY] + 1
        self.buffer[self.cursorY] = self.buffer[self.cursorY] .. line
        self:refreshScreen()
        self:updateStatusBar("Deleted line")
    else
        self:updateStatusError("Nothing to delete")
    end
        local view = getView()
end

function BufferHandler:enter()
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
    self:refreshScreen()
    self:updateStatusBar("Inserted new line")
end

function BufferHandler:paste()
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
function BufferHandler:yankSelection()
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

function BufferHandler:cutSelection()
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
        self:refreshScreen()
    end

    self.cursorX = startX
    self.cursorY = startY

    if startY ~= endY then
        self.buffer[startY] = self.buffer[startY] .. self.buffer[startY + 1]
        table.remove(self.buffer, startY + 1)
    end

    self:updateStatusBar("Cut selection")
end

function BufferHandler:cutLine()
    if #self.buffer == 1 then
        self:saveToHistory()
        self.yankRegister = self.buffer[1]
        self.buffer = {""}
        self.cursorX = 1
        self.cursorY = 1
        self:refreshScreen()
        self:updateStatusBar("Cut line")
        return
    end

    self:saveToHistory()
    self.yankRegister = self.buffer[self.cursorY]
    table.remove(self.buffer, self.cursorY)
    if self.cursorY > #self.buffer then
        self.cursorY = #self.buffer
    end
    self.cursorX = 1
    self:refreshScreen()
    self:updateStatusBar("Cut line")
end

-- Mode switching and history management
function BufferHandler:switchMode(mode, initialCommand, autoExecute)
    self:saveToHistory()
    self.mode = mode

    -- Reset the InputMode based on the new mode
    if mode == "insert" then
        self.InputMode = "chars"
    else
        self.InputMode = "keys"
    end

    -- Reset key sequence and other state variables to default
    local keyHandler = require("InputHandler"):getInstance()
    keyHandler:resetKeySequence()

    -- Additional resets can be added here if needed
    -- For example, reset search highlight, visual selection, etc.

    local view = getView()
    if mode == "command" then
        local inputHandler = require("InputHandler"):getInstance()
        -- Pass initialCommand and autoExecute, even if initialCommand is nil
        inputHandler:handleCommandInput(initialCommand, autoExecute)
    end
    self:refreshScreen()
end

-- Save the current state to history
function BufferHandler:saveToHistory()
    if self.history == nil then
        self.history = {}
    end
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

function BufferHandler:getWordAtCursor()
    local line = self.buffer[self.cursorY] or ""
    local cursorPos = self.cursorX

    -- Find the start of the word
    local startPos = cursorPos
    while startPos > 1 and line:sub(startPos - 1, startPos - 1):match("[%w_%.:]") do
        startPos = startPos - 1
    end

    -- Find the end of the word
    local endPos = cursorPos
    while endPos <= #line and line:sub(endPos, endPos):match("[%w_%.:]") do
        endPos = endPos + 1
    end

    -- Return the word under the cursor
    return line:sub(startPos, endPos - 1)
end

function BufferHandler:getNextIdentifierOnLine()
    if self.dynamicIdentifiers == nil or #self.dynamicIdentifiers == 0 then
        return nil
    end

    local line = self.buffer[self.cursorY] or ""
    local startPos = self.cursorX
    local lineEnd = #line

    while startPos <= lineEnd do
        -- Get the word starting at the current cursor position
        self.cursorX = startPos
        local word = self:getWordAtCursor()

        if word then
            for _, identifierEntry in ipairs(self.dynamicIdentifiers) do
                if word == identifierEntry.identifier then
                    -- Move cursor to the found word
                    self.cursorX = startPos
                    return word
                end
            end
        end

        -- Move cursor to the next non-alphanumeric character
        while startPos <= lineEnd and line:sub(startPos, startPos):match("[%w_%.:]") do
            startPos = startPos + 1
        end

        -- Move cursor past non-alphanumeric characters
        while startPos <= lineEnd and not line:sub(startPos, startPos):match("[%w_]") do
            startPos = startPos + 1
        end
    end

    return nil
end




function BufferHandler:insertTextAtCursor(text)

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
function BufferHandler:getLine(lineIndex)
    if lineIndex < 1 or lineIndex > #self.buffer then
        return nil -- Return nil if the requested line is out of bounds
    end
    return self.buffer[lineIndex]
end

function BufferHandler:getBufferAsString()
    return table.concat(self.buffer, "\n")
end
function BufferHandler:getBufferState()
    -- Capture the current buffer state, including buffer content, cursor position, and scroll offsets
    return {
        buffer = table.deepCopy(self.buffer),
        cursorX = self.cursorX,
        cursorY = self.cursorY,
        scrollOffset = self.scrollOffset,
        horizontalScrollOffset = self.horizontalScrollOffset,
        visualStartX = self.visualStartX,
        visualStartY = self.visualStartY,
        isVisualMode = self.isVisualMode
    }
end

function BufferHandler:restoreBufferState(state)
    -- Restore the buffer state from the given state table
    if not state then return end

    self.buffer = table.deepCopy(state.buffer)
    self.cursorX = state.cursorX
    self.cursorY = state.cursorY
    self.scrollOffset = state.scrollOffset
    self.horizontalScrollOffset = state.horizontalScrollOffset
    self.visualStartX = state.visualStartX
    self.visualStartY = state.visualStartY
    self.isVisualMode = state.isVisualMode

    -- Refresh the screen to reflect the restored state
    self:refreshScreen()
    getView():drawScreen()
end


return BufferHandler
