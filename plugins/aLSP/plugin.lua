local function init(components)
    local Avim = components.Avim
    local KeyHandler = components.KeyHandler
    local View = require("View")

    -- Instantiate the view instance for displaying popups
    local viewInstance = View:getInstance()

    local function formatBuffer()
        local model = Avim:getInstance()
        local buffer = model.buffer

        -- Save the current buffer to a temporary file
        local tempFile = "/tmp/temp_lua_buffer.lua"
        local file = fs.open(tempFile, "w")
        file.write(buffer)
        file.close()

        -- Construct the command to run the formatter
        local formatterScript = "plugins/aLSP/luafmt.lua"
        local command = "lua " .. formatterScript .. " --f " .. tempFile .. " 80"

        -- Run the formatter script
        local status, errorMessage = pcall(function()
           shell.run(command) 
        end)

        if status then
            -- Read the formatted buffer back from the temporary file
            local formattedFile = fs.open(tempFile, "r")
            local formattedBuffer = formattedFile.readAll()
            formattedFile.close()

            -- Replace the current buffer with the formatted Lua buffer
            model.buffer = formattedBuffer

            -- Mark all lines as dirty to redraw them
            for i = 1, #model.buffer do
                model:markDirty(i)
            end

            -- Update the status bar to indicate success
            model:updateStatusBar("Buffer formatted successfully!")
        else
            -- Handle the error if the formatting fails
            local errorMessage = "Error: Failed to format buffer. " .. (errorMessage or "Unknown error")
            print(errorMessage)
            viewInstance:showPopup("Error!")
        end

        -- Clean up the temporary file
        fs.delete(tempFile)
    end

    -- Map the formatting function to a keybinding
    KeyHandler:map("n", "leader + f", function()
        formatBuffer()
    end, "Format Lua Buffer")
end

return {
    init = init
}
