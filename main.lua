-- Initialize screen size
SCREENWIDTH, SCREENHEIGHT = term.getSize()

-- Load core components
local View = require("View"):getInstance()
local Avim = require("Avim"):getInstance()
local KeyHandler = require("KeyHandler"):getInstance()
local CommandHandler = require("CommandHandler"):getInstance()

-- Plugin management
local pluginConfigFile = "plugins/pluginConfig.lua"
local plugins = {}

-- Function to load the plugin configuration
local function loadPluginConfig()
    plugins = require("plugins.pluginConfig")
    -- Debug info: loaded plugin config
    term.setCursorPos(1, SCREENHEIGHT)
    term.clearLine()
    term.write("Loaded Plugin Config: " .. textutils.serialize(plugins))
end

-- Function to check if a plugin is enabled
local function isPluginEnabled(pluginName)
    for _, plugin in ipairs(plugins) do
        if plugin.name == pluginName then
            return plugin.enabled
        end
    end
    return false -- Default to false if the plugin is not found
end

-- Function to load a plugin
local function loadPlugin(pluginName)
    if isPluginEnabled(pluginName) then
        local success, err = pcall(function()
            local plugin = require("plugins." .. pluginName .. ".plugin")
            if plugin and plugin.init then
                plugin.init({
                    View = View,
                    Avim = Avim,
                    KeyHandler = KeyHandler,
                    CommandHandler = CommandHandler
                })
            else
                error("Plugin " .. pluginName .. " is missing an init function.")
            end
        end)

        if not success then
            -- Crash the program with an error message
            error("Failed to load plugin: " .. pluginName .. " | Error: " .. err)
        end
    end
end


-- Function to load all enabled plugins
local function loadPlugins()
    for _, plugin in ipairs(plugins) do
        if plugin.enabled then
            loadPlugin(plugin.name)
        end
    end
end

-- Function to handle file input (used by the main menu options)
local function handleFileOperation(prompt)
    term.clear()
    term.setCursorPos(1, 1)
    print(prompt)
    
    local firstInput = true
    local filename = ""
    while true do
        local event, param1 = os.pullEvent()
        if event == "char" then
            if firstInput then
                firstInput = false  -- Discard the first input
            else
                filename = filename .. param1  -- Append the rest of the input
                term.write(param1)  -- Display the input
            end
        elseif event == "key" then
            if param1 == keys.enter then
                return filename  -- Return the filename when Enter is pressed
            elseif param1 == keys.backspace then
                if #filename > 0 then
                    filename = filename:sub(1, -2)  -- Handle backspace
                    -- Get current cursor position
                    local cx, cy = term.getCursorPos()
                    -- Move cursor back one position and clear the character
                    term.setCursorPos(cx - 1, cy)
                    term.write(" ")
                    -- Move cursor back again to correct position
                    term.setCursorPos(cx - 1, cy)
                end
            end
        end
    end
end

-- Function to manage plugins (toggle enabled/disabled status)
local function managePlugins()
    local currentPage = 1
    local pluginsPerPage = 5
    local totalPages = math.ceil(#plugins / pluginsPerPage)

    while true do
        term.clear()
        term.setCursorPos(1, 1)
        print("Plugin Manager (Page " .. currentPage .. " of " .. totalPages .. ")")

        -- Display plugins for the current page
        local startIndex = (currentPage - 1) * pluginsPerPage + 1
        local endIndex = math.min(startIndex + pluginsPerPage - 1, #plugins)

        for i = startIndex, endIndex do
            local plugin = plugins[i]
            print((i - startIndex + 1) .. ". " .. plugin.name .. " [" .. (plugin.enabled and "Enabled" or "Disabled") .. "]")
        end

        -- Pagination options
        if currentPage < totalPages then
            print((endIndex - startIndex + 2) .. ". Next Page")
        end
        if currentPage > 1 then
            print((endIndex - startIndex + 3) .. ". Previous Page")
        end
        print("Press 'q' to go back")

        -- Handle input
        local event, key = os.pullEvent("key")

        -- Map the input to corresponding actions
        if key == keys.one and startIndex <= #plugins then
            plugins[startIndex].enabled = not plugins[startIndex].enabled
            -- Update the configuration file immediately after toggling
            local file = fs.open(pluginConfigFile, "w")
            file.write("return " .. textutils.serialize(plugins))
            file.close()
        elseif key == keys.q then
            return
        end
    end
end

-- Main event loop
local function eventLoop()
    View:drawScreen()
    while not Avim.shouldExit do
        KeyHandler:handleInputEvent(Avim.mode, Avim, View, CommandHandler)
        View:drawScreen()
        View:updateCursor()
    end
    term.clear()
    term.setCursorPos(1, 1)
end

-- Function to handle the main menu
local function handleMainMenu()
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        print("Welcome to AVIM")
        print("1. Create New File")
        print("2. Open File")
        print("3. Manage Plugins")
        print("4. Quit")
        print("Choose an option:")
        
        local event, key = os.pullEvent("key")
        
        if key == keys.one then
            local filename = handleFileOperation("Enter filename:")
            if filename and filename ~= "" then
                Avim.filename = filename
                Avim:loadFile(Avim.filename)
                eventLoop()
            end
        elseif key == keys.two then
            local filename = handleFileOperation("Enter filename:")
            if filename and filename ~= "" then
                Avim.filename = filename
                Avim:loadFile(Avim.filename)
                eventLoop()
            end
        elseif key == keys.three then
            managePlugins()
        elseif key == keys.four then
            Avim.shouldExit = true
            return
        end
    end
end

-- Load core components and plugins
require("keybinds")
require("commands")
loadPluginConfig()
loadPlugins()

-- Launch the main program with the main menu
handleMainMenu()
