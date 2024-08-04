KeyHandler = {}
KeyHandler.__index = KeyHandler

local instance

function KeyHandler:new()
    if not instance then
        instance = {
            keyStates = {
                shift = false,
                ctrl = false,
                alt = false
            },
            currentModifierHeld = "",
            currentKeySequence = {},
            isKeySequence = false, -- Add this flag
            leaderKey = "space", -- Default leader key
            leaderTimeout = 1, -- Timeout for multi-key sequences in seconds
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
            }
        }
        setmetatable(instance, KeyHandler)
    end
    return instance
end

function KeyHandler:getInstance()
    if not instance then
        instance = KeyHandler:new()
    end
    return instance
end

-- Parse key combination string into modifiers and main key sequence
function KeyHandler:parseKeyCombo(combo)
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
            table.insert(keys, part)
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

function KeyHandler:map(modes, keyCombos, callback, description)
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
                    callback = callback, 
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
        modes = { "normal", "visual", "insert"}
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


function KeyHandler:handleKeyPress(key, isDown, model, view, commandHandler)
    local keyName = keys.getName(key)

    if model.InputMode == "keys" then
        -- Skip sequence detection in insert mode
        if model.mode == "insert" then
            if isDown then
                self:handleCharInput(keyName, model, view) -- Treat as character input
            end
            return
        end

        if self.modifierKeys[key] then
            local modifier = self.modifierKeys[key]

            -- Ignore shift in insert mode (redundant with the above, but keeping as reference)
            if model.mode == "insert" and modifier == "shift" then
                return
            end

            self.keyStates[modifier] = isDown

            if isDown then
                self.currentModifierHeld = modifier
                model:updateStatusBar(modifier:sub(1, 1):upper() .. modifier:sub(2) .. " held, waiting for inputs")
            else
                self.currentModifierHeld = ""
                model:updateStatusBar(modifier:sub(1, 1):upper() .. modifier:sub(2) .. " released with no subkey found")
            end

            return
        end

        if isDown then
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

            -- Traverse the key sequence map
            for _, key in ipairs(self.currentKeySequence) do
                currentMap = currentMap[key] or {}
            end

            -- Check if currentMap has a valid callback (indicating a complete keybinding)
            if currentMap.callback and not currentMap.keyUpEvent then
                currentMap.callback()
                model:markDirty(model.cursorY)
                view:updateCursor()
                self.currentKeySequence = {} -- Reset sequence
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
                currentMap.callback()
                model:markDirty(model.cursorY)
                view:updateCursor()
                self.currentKeySequence = {} -- Reset sequence
                if self.leaderTimeoutTimer then
                    os.cancelTimer(self.leaderTimeoutTimer) -- Cancel any pending timer
                    self.leaderTimeoutTimer = nil -- Reset the timer reference
                end
            end
        end
    end
end

-- Handle different types of input events
function KeyHandler:handleInputEvent(mode, model, view, commandHandler)
    if model.InputMode == "keys" then
        self:handleKeyEvent(model, view, commandHandler)
        model:updateScroll()
        view:drawScreen()
    elseif model.InputMode == "chars" then
        self:handleCharEvent(model, view)
        model:updateScroll()
        view:drawScreen()
    end
end

-- Handle key and char events separately
function KeyHandler:handleKeyEvent(model, view, commandHandler)
    local event, key = os.pullEvent()
    if event == "key" then
        if model.mode == "insert" then
            self:handleCharInput(keys.getName(key), model, view)
        else
            self:handleKeyPress(key, true, model, view, commandHandler)
        end
    elseif event == "key_up" then
        self:handleKeyPress(key, false, model, view, commandHandler)
    elseif event == "timer" then
        if #self.currentKeySequence > 0 then
            model:updateStatusBar("Sequence timed out, resetting...")
            self.currentKeySequence = {}
        end
    end
end

function KeyHandler:handleCharInput(char, model, view)
    if model.InputMode == "chars" then
        model:insertChar(char)
        model:markDirty(model.cursorY)

        -- Update the view immediately after inserting the character
        view:drawLine(model.cursorY - model.scrollOffset)

        local prefix = model:getWordAtCursor()
        local suggestions = model:getAutocompleteSuggestions(prefix)

        if #suggestions > 0 then
            if model.autocompleteWindow then
                model.autocompleteWindow:close()
            end
            model.autocompleteWindow = view:showAutocompleteWindow(suggestions)
            -- Ensure that the line where the character was inserted is redrawn
            view:drawLine(model.cursorY - model.scrollOffset)
        else
            if model.autocompleteWindow then
                model.autocompleteWindow:close()
                model.autocompleteWindow = nil
            end
        end
    end
end

function KeyHandler:handleCharEvent(model, view)
    local firstInput = true

    while true do
        local event, key = os.pullEvent()

        if event == "char" then
            self:handleCharInput(key, model, view)
            view:drawLine(model.cursorY - model.scrollOffset)
            view:drawScreen()
        elseif event == "key" then
            -- Refactor to check keyMap in "insert" mode
            local action = self.keyMap[model.mode][keys.getName(key)]
            if action and type(action.callback) == "function" then
                action.callback()
                break
            end
        end
        ::continue::
    end
end

-- Function to retrieve keybinding descriptions
function KeyHandler:getKeyDescriptions(mode)
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
function KeyHandler:resetKeySequence()
    self.currentKeySequence = {}
    self.currentModifierHeld = ""
    self.isKeySequence = false
    if self.leaderTimeoutTimer then
        os.cancelTimer(self.leaderTimeoutTimer)
        self.leaderTimeoutTimer = nil
    end
end

return KeyHandler
