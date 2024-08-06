InputHandler = {}
InputHandler.__index = InputHandler

local instance

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
                        callback = function() 
                            self:executeCommand(commandName) 
                        end, 
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
    ["^"] = "shift + six",
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

function InputHandler:handleKeyPress(key, isDown, model, view)
    local keyName = keys.getName(key)

    if model.InputMode == "keys" then
        -- Skip sequence detection in insert mode
        if model.mode == "insert" then
            if isDown then
                self:handleCharInput(keyName, model, view) -- Treat as character input
            end
            return
        end

        -- Handle modifier keys (shift, ctrl, alt)
        if self.modifierKeys[key] then
            local modifier = self.modifierKeys[key]

            -- Ignore shift in insert mode
            if model.mode == "insert" and modifier == "shift" then
                return
            end

            self.keyStates[modifier] = isDown

            if isDown then
                self.currentModifierHeld = modifier
                model:updateStatusBar(modifier:sub(1, 1):upper() .. modifier:sub(2) .. " held, waiting for inputs")
            else
                -- Only reset currentModifierHeld if this modifier is released
                if self.currentModifierHeld == modifier then
                    self.currentModifierHeld = ""
                    model:updateStatusBar(modifier:sub(1, 1):upper() .. modifier:sub(2) .. " released with no subkey found")
                end
            end
            return
        end

        if isDown then
            -- Handle numeric prefixes (e.g., "one", "two", etc.)
            local numericKeyMap = {
                one = "1", two = "2", three = "3", four = "4", five = "5",
                six = "6", seven = "7", eight = "8", nine = "9", zero = "0"
            }

            if numericKeyMap[keyName] then
                if self.numericPrefix then
                    self.numericPrefix = self.numericPrefix .. numericKeyMap[keyName]
                else
                    self.numericPrefix = numericKeyMap[keyName]
                end
                model:updateStatusBar("Prefix: " .. self.numericPrefix)
                return
            end

            table.insert(self.currentKeySequence, keyName)

            -- Handle leader key sequences
            if #self.currentKeySequence == 1 and keyName == self.leaderKey then
                model:updateStatusBar("Leader key pressed, waiting for sequence...")
                return
            end

            local currentMap = self.keyMap[model.mode]

            -- Apply current modifier held if any
            if self.currentModifierHeld ~= "" then
                currentMap = currentMap[self.currentModifierHeld] or {}
            end

            -- Traverse the key sequence map and check if it is valid
            local isValidSequence = true
            for _, key in ipairs(self.currentKeySequence) do
                if not currentMap[key] then
                    isValidSequence = false
                    break
                end
                currentMap = currentMap[key]
            end

            -- If the sequence is invalid but the key is a numeric prefix, handle it accordingly
            if not isValidSequence and numericKeyMap[keyName] then
                self.numericPrefix = (self.numericPrefix or "") .. numericKeyMap[keyName]
                model:updateStatusBar("Prefix: " .. self.numericPrefix)
                return
            end

            -- If the sequence is invalid, reset and notify the user
            if not isValidSequence then
                model:updateStatusBar("Invalid key sequence: " .. table.concat(self.currentKeySequence, " + ") .. ", resetting...")
                self:resetKeySequence()
                return
            end

            -- Check if currentMap has a valid callback (indicating a complete keybinding)
            if currentMap.callback and not currentMap.keyUpEvent then
                local prefix = tonumber(self.numericPrefix) or 1
                for _ = 1, prefix do
                    currentMap.callback()
                end
                self:resetKeySequence()
                if self.leaderTimeoutTimer then
                    os.cancelTimer(self.leaderTimeoutTimer) -- Cancel any pending timer
                    self.leaderTimeoutTimer = nil -- Reset the timer reference
                end
            else
                -- Update the status bar only if there is a key sequence longer than one key
                if #self.currentKeySequence > 1 then
                    model:updateStatusBar("Sequence: " .. table.concat(self.currentKeySequence, " + "))
                end

                -- Start or reset the timer to handle sequence timeout
                if self.leaderTimeoutTimer then
                    os.cancelTimer(self.leaderTimeoutTimer) -- Cancel the previous timer if it exists
                end
                self.leaderTimeoutTimer = os.startTimer(self.leaderTimeout)
            end
        else
            -- Handle key release
            local currentMap = self.keyMap[model.mode]
            if self.currentModifierHeld ~= "" then
                currentMap = currentMap[self.currentModifierHeld] or {}
            end

            for _, key in ipairs(self.currentKeySequence) do
                currentMap = currentMap[key] or {}
            end

            if currentMap.callback and currentMap.keyUpEvent then
                local prefix = tonumber(self.numericPrefix) or 1
                for _ = 1, prefix do
                    currentMap.callback()
                end
                self:resetKeySequence()
                if self.leaderTimeoutTimer then
                    os.cancelTimer(self.leaderTimeoutTimer) -- Cancel any pending timer
                    self.leaderTimeoutTimer = nil -- Reset the timer reference
                end
            end
        end
    end
end

function InputHandler:handleInputEvent(mode, model, view)
    if model.InputMode == "keys" then
        self:handleKeyEvent(model, view)
        model:updateScroll()
    elseif model.InputMode == "chars" then
        self:handleCharEvent(model, view)
        model:updateScroll()
    end
end

function InputHandler:handleKeyEvent(model, view)
    local event, key = os.pullEvent()
    if event == "key" then
        if model.mode == "insert" then
            self:handleCharInput(keys.getName(key), model, view)
        else
            self:handleKeyPress(key, true, model, view)
        end
    elseif event == "key_up" then
        self:handleKeyPress(key, false, model, view)
    elseif event == "timer" then
        if #self.currentKeySequence > 0 then
            model:updateStatusBar("Sequence timed out, resetting...")
            self.currentKeySequence = {}
        end
    end
end

function InputHandler:handleCharInput(char, model, view)
    if model.InputMode == "chars" then
        model:insertChar(char)
        model:markDirty(model.cursorY)
    end
end

function InputHandler:handleCharEvent(model, view)
    while true do
        local event, key = os.pullEvent()

        if event == "char" then
            self:handleCharInput(key, model, view)
        elseif event == "key" then
            -- Refactor to check keyMap in "insert" mode
            local action = self.keyMap[model.mode][keys.getName(key)]
            if action and type(action.callback) == "function" then
                action.callback()
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
            if type(binding) == "table" and binding.callback then
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

function InputHandler:executeCommand(command, numericPrefix)
    -- Handle empty or nil command cases
    if command == nil or command == "" then
        BufferHandler:switchMode("normal")
        self.currentModifierHeld = ""
        self:resetKeySequence()
        View:showPopup("No command entered")
        return
    end

    -- Add command to history
    table.insert(self.commandHistory, command)
    self.historyIndex = nil

    -- If no numericPrefix is provided, attempt to parse it from the command string
    if not numericPrefix then
        numericPrefix, command = command:match("^(%d*)(.*)$")
        numericPrefix = tonumber(numericPrefix) or 1
    end

    if self.commands[command] then
        -- Wrap the command execution in pcall to catch any runtime errors
        local success, err = pcall(function()
            for i = 1, numericPrefix do
                self.commands[command](i > 1)  -- Pass `true` for isRepeated on subsequent executions
            end
        end)
        if not success then
            View:showPopup("Err: " .. err)
        end
    else
        View:showPopup("Unknown command: " .. command)
    end

    -- Reset key sequence after execution
    self:resetKeySequence()
end

function InputHandler:handleCommandInput(model, view, initialCommand, autoExecute)
    local command = initialCommand or ""  -- Start with the provided initialCommand or an empty string

    -- If autoExecute is true and initialCommand is nil, use the last command in history
    if autoExecute and initialCommand == nil then
        if #self.commandHistory > 0 then
            command = self.commandHistory[#self.commandHistory]  -- Use the last command in history
        else
            self.currentModifierHeld = ""
            View:showPopup("No previous command to execute")
            model:switchMode("normal")
            self:resetKeySequence()
            return
        end
    end

    model:updateStatusBar(":" .. command, view)  -- Display the initial ":" and any pre-filled text

    -- If autoExecute is true and there is a command, execute it immediately
    if autoExecute and command ~= "" then
        self:executeCommand(command)
        model:switchMode("normal")  -- Switch back to normal mode
        self:resetKeySequence()
        return
    end

    -- Wait until all keys are released before starting to listen for input
    local keysHeld = {}  -- Track currently held keys
    while true do
        local event, key = os.pullEvent()
        if event == "key" then
            keysHeld[key] = true  -- Mark this key as held down
        elseif event == "key_up" then
            keysHeld[key] = nil  -- Mark this key as released
            -- If no keys are held down, break the loop and start listening for input
            local anyKeysHeld = false
            for _, held in pairs(keysHeld) do
                if held then
                    anyKeysHeld = true
                    break
                end
            end
            if not anyKeysHeld then
                break
            end
        end
    end

    -- Start listening for input
    while true do
        local event, param1 = os.pullEvent()
        if event == "char" then
            command = command .. param1  -- Capture input characters
            model:updateStatusBar(":" .. command, view)  -- Display the command prefixed with ":"
        elseif event == "key" then
            if param1 == keys.enter then
                if command == "" then
                    model:switchMode("normal")  -- Exit command mode
                    self.currentModifierHeld = ""
                    self:resetKeySequence()  -- Reset key sequence
                    View:showPopup("No command entered")
                    break
                else
                    self.currentModifierHeld = ""
                    self:executeCommand(command)  -- Execute the command when Enter is pressed
                    model:switchMode("normal")  -- Switch back to normal mode
                    self:resetKeySequence()
                    break
                end
            elseif param1 == keys.backspace then
                command = command:sub(1, -2)  -- Handle backspace
                model:updateStatusBar(":" .. command, view)
            elseif param1 == keys.up then
                -- Navigate up through the command history
                if #self.commandHistory > 0 then
                    if self.historyIndex == nil then
                        self.historyIndex = #self.commandHistory
                    elseif self.historyIndex > 1 then
                        self.historyIndex = self.historyIndex - 1
                    end
                    command = self.commandHistory[self.historyIndex]
                    model:updateStatusBar(":" .. command, view)
                end
            elseif param1 == keys.down then
                -- Navigate down through the command history
                if #self.commandHistory > 0 then
                    if self.historyIndex == nil then
                        self.historyIndex = #self.commandHistory
                    elseif self.historyIndex < #self.commandHistory then
                        self.historyIndex = self.historyIndex + 1
                    else
                        self.historyIndex = nil
                        command = ""
                    end
                    if self.historyIndex then
                        command = self.commandHistory[self.historyIndex]
                    end
                    model:updateStatusBar(":" .. command, view)
                end
            elseif param1 == keys.escape then
                self:resetKeySequence()
                model:switchMode("normal")  -- Exit command mode on Escape
                return
            end
        end
    end
end

return InputHandler
