InputHandler = {}
InputHandler.__index = InputHandler

local instance

local model = BufferHandler:getInstance()
local view = View:getInstance()
function InputHandler:new()
    if not instance then
        instance = {
            -- KeyHandler properties
            keyStates = {
                shift = false,
                ctrl = false,
                alt = false
            },
            currentModifierHeld = "",
            currentKeySequence = {},
            isKeySequence = false,
            leaderKey = "space",
            leaderTimeout = 1,
            modifierKeys = {
                [keys.leftShift] = "shift",
                [keys.rightShift] = "shift",
                [keys.leftCtrl] = "ctrl",
                [keys.rightCtrl] = "ctrl",
                [keys.leftAlt] = "alt",
                [keys.rightAlt] = "alt"
            },
            keyMap = {
                normal = {},
                insert = {},
                visual = {},
                command = {}
            },
            -- CommandHandler properties
            commands = {},
            commandHistory = {},
            historyIndex = nil,
            numericPrefix = nil
        }
        setmetatable(instance, InputHandler)
    end
    return instance
end

function InputHandler:getInstance()
    if not instance then
        instance = InputHandler:new()
    end
    return instance
end

-- Unified map method
function InputHandler:map(modes, keyCombos, commandName, callback, description)
    -- Handle the command mapping first
    if commandName and callback then
        self:mapCommand(commandName, callback)
    end

    -- Now handle the key mapping
    if modes and keyCombos then
        -- Convert modes to a table if it's a single string
        if type(modes) == "string" then
            modes = { modes }
        end

        -- Convert single keyCombo to a list if it's not already a list
        if type(keyCombos) == "string" then
            keyCombos = { keyCombos }
        end

        -- Map shorthand modes to their full names
        local modeMap = {
            n = "normal",
            v = "visual",
            i = "insert",
            c = "command"
        }

        -- Function to add the keybinding to a specific mode
        local function addKeybindingToMode(targetMap, keyCombo)
            local modifiers, keys, _, keyUpEvent = self:parseKeyCombo(keyCombo)
            local currentMap = targetMap

            -- First apply all modifiers
            for _, mod in ipairs(modifiers) do
                if not currentMap[mod] then
                    currentMap[mod] = {}
                end
                currentMap = currentMap[mod]
            end

            -- Then apply all keys in the sequence
            for i, key in ipairs(keys) do
                if not currentMap[key] then
                    currentMap[key] = {}
                end

                if i == #keys then
                    currentMap[key] = { 
                        command = commandName, 
                        description = description,
                        keyUpEvent = keyUpEvent -- Store key up event flag
                    }
                else
                    currentMap = currentMap[key]
                end
            end
        end

        -- Handle "all" mode
        if table.contains(modes, "all") then
            modes = { "normal", "visual", "insert" }
        end

        -- Iterate over each mode in the modes list
        for _, mode in ipairs(modes) do
            local targetMap = self.keyMap[modeMap[mode] or mode]
            if targetMap then
                for _, keyCombo in ipairs(keyCombos) do
                    addKeybindingToMode(targetMap, keyCombo)
                end
            else
                error("Unknown mode: " .. tostring(mode))
            end
        end
    end
end

-- KeyHandler methods

-- Special character mappings
local specialCharacterMap = {
    ["!"] = "shift + one",
    ["@"] = "shift + two",
    ["#"] = "shift + three",
    ["$"] = "shift + four",
    ["%"] = "shift + five",
    ["//"] = "shift + six",
    ["&"] = "shift + seven",
    ["*"] = "shift + eight",
    ["("] = "shift + nine",
    [")"] = "shift + zero",
    ["_"] = "shift + minus",
    ["+"] = "shift + equals",
    ["Q"] = "shift + q",
    ["W"] = "shift + w",
    ["E"] = "shift + e",
    ["R"] = "shift + r",
    ["T"] = "shift + t",
    ["Y"] = "shift + y",
    ["U"] = "shift + u",
    ["I"] = "shift + i",
    ["O"] = "shift + o",
    ["P"] = "shift + p",
    ["{"] = "shift + leftBracket",
    ["}"] = "shift + rightBracket",
    ["|"] = "shift + backslash",
    ["A"] = "shift + a",
    ["S"] = "shift + s",
    ["D"] = "shift + d",
    ["F"] = "shift + f",
    ["G"] = "shift + g",
    ["H"] = "shift + h",
    ["J"] = "shift + j",
    ["K"] = "shift + k",
    ["L"] = "shift + l",
    [":"] = "shift + semicolon",
    ['"'] = "shift + apostrophe",
    ["Z"] = "shift + z",
    ["X"] = "shift + x",
    ["C"] = "shift + c",
    ["V"] = "shift + v",
    ["B"] = "shift + b",
    ["N"] = "shift + n",
    ["M"] = "shift + m",
    ["<"] = "shift + comma",
    [">"] = "shift + period",
    ["?"] = "shift + slash",
    ["/"] = "slash",
    ["."] = "period",
    [","] = "comma",
    [";"] = "semicolon",
    ["'"] = "apostrophe",
    ["["] = "leftBracket",
    ["]"] = "rightBracket",
    ["\\"] = "backslash",
    ["`"] = "backtick",
    ["~"] = "shift + backtick",
    ["1"] = "one",
    ["2"] = "two",
    ["3"] = "three",
    ["4"] = "four",
    ["5"] = "five",
    ["6"] = "six",
    ["7"] = "seven",
    ["8"] = "eight",
    ["9"] = "nine",
    ["0"] = "zero",
    ["-"] = "minus",
    ["="] = "equals",
}

function InputHandler:parseKeyCombo(combo)
    local modifiers = {}
    local keys = {}
    local isLeaderKey = false
    local keyUpEvent = false

    for part in combo:gmatch("[^%s+]+") do
        if part == "ctrl" or part == "shift" or part == "alt" then
            table.insert(modifiers, part)
        elseif part == "leader" then
            table.insert(keys, self.leaderKey)
            isLeaderKey = true
        elseif part:sub(-1) == "^" then
            table.insert(keys, part:sub(1, -2)) -- Remove the "^"
            keyUpEvent = true
        else
            -- Check if the part is in the specialCharacterMap
            local mappedPart = specialCharacterMap[part]
            if mappedPart then
                -- Split the mappedPart into modifiers and keys
                for mod in mappedPart:gmatch("[^%s+]+") do
                    if mod == "shift" or mod == "ctrl" or mod == "alt" then
                        table.insert(modifiers, mod)
                    else
                        table.insert(keys, mod)
                    end
                end
            else
                table.insert(keys, part)
            end
        end
    end

    return modifiers, keys, isLeaderKey, keyUpEvent
end

function table.contains(tbl, element)
    for _, value in pairs(tbl) do
        if value == element then
            return true
        end
    end
    return false
end

function InputHandler:handleKeyPress(key, isDown)
    local keyName = keys.getName(key)

    if model.InputMode == "keys" then
        if model.mode == "insert" then
            return self:handleInsertMode(keyName, isDown)
        end

        if self.modifierKeys[key] then
            return self:handleModifierKeys(key, isDown)
        end

        if isDown then
            return self:handleKeyDown(keyName)
        else
            return self:handleKeyUp()
        end
    end
end

function InputHandler:handleInsertMode(keyName, isDown)
    if isDown then
        self:handleCharInput(keyName) -- Treat as character input
    end
end

function InputHandler:handleModifierKeys(key, isDown)
    local modifier = self.modifierKeys[key]

    if model.mode == "insert" and modifier == "shift" then
        return
    end

    self.keyStates[modifier] = isDown

    if isDown then
        self.currentModifierHeld = modifier
        model:updateStatusBar(modifier:sub(1, 1):upper() .. modifier:sub(2) .. " held, waiting for inputs")
    else
        if self.currentModifierHeld == modifier then
            self.currentModifierHeld = ""
            model:updateStatusBar(modifier:sub(1, 1):upper() .. modifier:sub(2) .. " released with no subkey found")
        end
    end
end

function InputHandler:handleKeyDown(keyName)
    if self.currentModifierHeld == "" then

        local numericKeyMap = self:getNumericKeyMap()

        if numericKeyMap[keyName] then
            return self:handleNumericPrefix(keyName)
        end
    end
    table.insert(self.currentKeySequence, keyName)

    if self:isLeaderKeySequence(keyName) then
        model:updateStatusBar("Leader key pressed, waiting for sequence...")
        return
    end

    return self:handleKeySequence()
end

function InputHandler:handleKeyUp()
    local currentMap = self:getCurrentKeyMap(model.mode)

    for _, key in ipairs(self.currentKeySequence) do
        currentMap = currentMap[key] or {}
    end

    if currentMap.command and currentMap.keyUpEvent then
        self:executeCommand(currentMap.command)
    end
end

function InputHandler:getNumericKeyMap()
    return {
        one = "1", two = "2", three = "3", four = "4", five = "5",
        six = "6", seven = "7", eight = "8", nine = "9", zero = "0"
    }
end

function InputHandler:handleNumericPrefix(keyName)
    local numericKeyMap = self:getNumericKeyMap()

    if self.numericPrefix then
        self.numericPrefix = self.numericPrefix .. numericKeyMap[keyName]
    else
        self.numericPrefix = numericKeyMap[keyName]
    end
    model:updateStatusBar("Prefix: " .. self.numericPrefix)
end

function InputHandler:isLeaderKeySequence(keyName)
    return #self.currentKeySequence == 1 and keyName == self.leaderKey
end

function InputHandler:handleKeySequence()
    local currentMap = self:getCurrentKeyMap(model.mode)
    local isValidSequence = true

    for _, key in ipairs(self.currentKeySequence) do
        if not currentMap[key] then
            isValidSequence = false
            break
        end
        currentMap = currentMap[key]
    end

    if not isValidSequence then
        model:updateStatusBar("Invalid key sequence: " .. table.concat(self.currentKeySequence, " + ") .. ", resetting...")
        self:resetKeySequence()
        return
    end

    if currentMap.command and not currentMap.keyUpEvent then
        self:executeCommand(currentMap.command, tonumber(self.numericPrefix))
    else
        self:updateStatusBarForSequence()
    end
end

function InputHandler:getCurrentKeyMap(mode)
    local currentMap = self.keyMap[mode]
    if self.currentModifierHeld ~= "" then
        currentMap = currentMap[self.currentModifierHeld] or {}
    end
    return currentMap
end

function InputHandler:updateStatusBarForSequence()
    if #self.currentKeySequence > 1 then
        model:updateStatusBar("Sequence: " .. table.concat(self.currentKeySequence, " + "))
    end
    self:resetTimer()
end

function InputHandler:resetTimer()
    if self.leaderTimeoutTimer then
        os.cancelTimer(self.leaderTimeoutTimer)
    end
    self.leaderTimeoutTimer = os.startTimer(self.leaderTimeout)
end

function InputHandler:manageTimer()
    if self.leaderTimeoutTimer then
        os.cancelTimer(self.leaderTimeoutTimer)
        self.leaderTimeoutTimer = nil
    end
end


function InputHandler:handleInputEvent(mode)
    if model.InputMode == "keys" then
        self:handleKeyEvent()
        model:updateScroll()
    elseif model.InputMode == "chars" then
        self:handleCharEvent()
        model:updateScroll()
    end
end

function InputHandler:handleKeyEvent()
    local event, key = os.pullEvent()
    if event == "key" then
        if model.mode == "insert" then
            self:handleCharInput(keys.getName(key))
        else
            self:handleKeyPress(key, true)
        end
    elseif event == "key_up" then
        self:handleKeyPress(key, false)
    elseif event == "timer" then
        if #self.currentKeySequence > 0 then
            model:updateStatusBar("Sequence timed out, resetting...")
            self.currentKeySequence = {}
        end
    end
end

function InputHandler:handleCharInput(char)
    if model.InputMode == "chars" then
        model:insertChar(char)
        model:markDirty(model.cursorY)
    end
end

function InputHandler:handleCharEvent()
    while true do
        local event, key = os.pullEvent()

        if event == "char" then
            self:handleCharInput(key)
        elseif event == "key" then
            -- Refactor to check keyMap in "insert" mode
            local action = self.keyMap[model.mode][keys.getName(key)]
            if action and action.command then
                self:executeCommand(action.command)
                break
            end
        end
    end
end

-- Function to retrieve keybinding descriptions
function InputHandler:getKeyDescriptions(mode)
    local descriptions = {}
    local targetMap = self.keyMap[mode]

    local function traverseMap(map, prefix)
        for key, binding in pairs(map) do
            if type(binding) == "table" and binding.command then
                table.insert(descriptions, { combo = prefix .. key, description = binding.description })
            elseif type(binding) == "table" then
                traverseMap(binding, prefix .. key .. " + ")
            end
        end
    end

    traverseMap(targetMap, "")
    return descriptions
end

function InputHandler:resetKeySequence()
    self.currentKeySequence = {}
    self.numericPrefix = nil -- Reset numeric prefix as well
    self.isKeySequence = false
    if self.leaderTimeoutTimer then
        os.cancelTimer(self.leaderTimeoutTimer)
        self.leaderTimeoutTimer = nil
    end
end

-- CommandHandler methods

function InputHandler:mapCommand(name, func)
    self.commands[name] = func
end

function InputHandler:executeCommand(commandString, numericPrefix)
    -- Parse the command and parameters
    local command, params = self:parseCommandString(commandString)

    -- Handle empty or nil command cases
    if command == nil or command == "" then
        BufferHandler:switchMode("normal")
        self.currentModifierHeld = ""
        self:resetKeySequence()
        View:showPopup("No command entered")
        return
    end

    -- Check if command starts with underscores, if so, don't add to history
    if not command:match("^__") then
        table.insert(self.commandHistory, commandString)
    end
    self.historyIndex = nil

    -- If no numericPrefix is provided, attempt to parse it from the first parameter if it's a number
    if not numericPrefix and tonumber(params[1]) ~= nil then
        numericPrefix = tonumber(table.remove(params, 1))
    else
        numericPrefix = numericPrefix or 1
    end

    -- Execute the command if it exists
    if self.commands[command] then
        local success, err = pcall(function()
            for i = 1, numericPrefix do
                self.commands[command](table.unpack(params), true, i, numericPrefix)  -- Additional parameters and repeat flags
            end
        end)
        if not success then
            View:showPopup("Error: " .. err)
        end
    else
        View:showPopup("Unknown command: " .. command)
        --remove command from history if it doesn't exist
        table.remove(self.commandHistory)
    end

    -- Reset key sequence after execution
    self:resetKeySequence()
end

function InputHandler:parseCommandString(commandString)
    local parts = {}
    for part in commandString:gmatch("%S+") do -- Matches sequences of non-whitespace characters
        table.insert(parts, part)
    end
    local command = table.remove(parts, 1) -- Removes the first element (the command) and returns it
    return command, parts
end

function InputHandler:handleCommandInput(initialCommand, autoExecute)
    local command = self:initializeCommand(initialCommand, autoExecute)
    if command == nil then return end

    self:waitForKeyRelease()

    self.command = command
    self:captureAndProcessInput()
    self.command = nil
end

function InputHandler:initializeCommand(initialCommand, autoExecute)
    local command = nil 
    if autoExecute and initialCommand == nil then
        if #self.commandHistory > 0 then
            command = self.commandHistory[#self.commandHistory]
            View:showPopup("Executing previous command: " .. command)
            self:executeCommand(command)
            model:switchMode("normal")
            self:resetKeySequence()
            return nil
        else
            self.currentModifierHeld = ""
            View:showPopup("No previous command to execute")
            model:switchMode("normal")
            self:resetKeySequence()
            return nil
        end
    end
    command = initialCommand or ""
    model:updateStatusBar(":" .. command)

    if autoExecute and command ~= "" then
        self:executeCommand(command)
        model:switchMode("normal")
        self:resetKeySequence()
        return nil
    end

    return command
end

function InputHandler:waitForKeyRelease()
    local keysHeld = {}
    while true do
        local event, key = os.pullEvent()
        if event == "key" then
            keysHeld[key] = true
        elseif event == "key_up" then
            keysHeld[key] = nil
            if not next(keysHeld) then break end
        end
    end
end

function InputHandler:captureAndProcessInput()
    while true do
        local event, param1 = os.pullEvent()
        if event == "char" then
            self.command = self.command .. param1
            model:updateStatusBar(":" .. self.command, view)
        elseif event == "key" then
            local breakLoop = self:handleCommandKeyEvents(param1)
            if breakLoop then break end
        end
    end
end

function InputHandler:handleCommandKeyEvents(key)
    if key == keys.enter then
        if self.command == "" or nil then
            View:showPopup("No command entered")
        else
            self:executeCommand(self.command)
        end
        self:finalizeCommandInput()
        return true
    elseif key == keys.backspace then
        self.command = self.command:sub(1, -2)
        model:updateStatusBar(":" .. self.command)
    elseif key == keys.up or key == keys.down then
        self.command = self:navigateCommandHistory(key)
        model:updateStatusBar(":" .. self.command)
    elseif key == keys.escape then
        self:resetKeySequence()
        model:switchMode("normal")
        return true
    end
    return false
end

function InputHandler:finalizeCommandInput()
    self.currentModifierHeld = ""
    model:switchMode("normal")
    self:resetKeySequence()
end

function InputHandler:navigateCommandHistory(key)
    if key == keys.up then
        if self.historyIndex == nil or self.historyIndex == 1 then
            -- Wrap around to the end of the history when going up from the first item
            self.historyIndex = #self.commandHistory
        else
            self.historyIndex = self.historyIndex - 1
        end
    elseif key == keys.down then
        if self.historyIndex == nil or self.historyIndex == #self.commandHistory then
            -- Wrap around to the start of the history when going down from the last item
            self.historyIndex = 1
        else
            self.historyIndex = self.historyIndex + 1
        end
    end

    -- Return the command at the new history index or the current command if no history exists
    return self.commandHistory[self.historyIndex] or self.command 
end


return InputHandler
