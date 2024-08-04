CommandHandler = {}
CommandHandler.__index = CommandHandler

local instance

function CommandHandler:new()
    if not instance then
        instance = {
            commands = {},
            commandHistory = {},
            historyIndex = nil  -- Track the current position in the history
        }
        setmetatable(instance, CommandHandler)
    end
    return instance
end

function CommandHandler:getInstance()
    if not instance then
        instance = CommandHandler:new()
    end
    return instance
end

function CommandHandler:map(name, func)
    self.commands[name] = func
end

function CommandHandler:execute(command)
    -- Check for an empty command
    if command == nil or command == "" then
        View:showPopup("No command entered")
        return
    end

    table.insert(self.commandHistory, command)  -- Save command to history
    self.historyIndex = nil  -- Reset history navigation

    local args = {}
    for arg in command:gmatch("%S+") do
        table.insert(args, arg)
    end

    local commandName = args[1]
    table.remove(args, 1)

    if self.commands[commandName] then
        -- Wrap the command execution in pcall to catch any runtime errors
        local success, err = pcall(function()
            self.commands[commandName](table.unpack(args))
        end)
        if not success then
            View:showPopup("Err: " .. err)
        end
    else
        View:showPopup("Unknown command: " .. commandName)
    end
end
function CommandHandler:handleCommandInput(model, view, initialCommand, autoExecute)
    local command = initialCommand or ""  -- Start with the provided initialCommand or an empty string

    -- If autoExecute is true and initialCommand is nil, use the last command in history
    if autoExecute and initialCommand == nil then
        if #self.commandHistory > 0 then
            command = self.commandHistory[#self.commandHistory]  -- Use the last command in history
        else
            View:showPopup("No previous command to execute")
            model:switchMode("normal")
            return
        end
    end

    model:updateStatusBar(":" .. command, view)  -- Display the initial ":" and any pre-filled text

    -- If autoExecute is true and there is a command, execute it immediately
    if autoExecute and command ~= "" then
        self:execute(command)
        model:switchMode("normal")  -- Switch back to normal mode
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
                self:execute(command)  -- Execute the command when Enter is pressed
                model:switchMode("normal")  -- Switch back to normal mode
                break
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
                return  -- Exit command mode on Escape
            end
        end
    end
end



return CommandHandler
