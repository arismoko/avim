local function init(components)
    local Avim = components.Avim
    local KeyHandler = components.KeyHandler

    -- Load LuaFmt class
    local LuaFmt = require("plugins.aLSP.luafmt")

    -- Instantiate LuaFmt with a column limit of 80
    local luaFmtInstance = LuaFmt:new(80)

    local function formatBuffer()
        local model = Avim:getInstance()
        local buffer = model.buffer

        -- Format the Lua buffer using luaFmtInstance
        local status, formattedBuffer = pcall(function()
            return luaFmtInstance:formatBuffer(buffer)
        end)

        if status and formattedBuffer then
            -- Replace the current buffer with the formatted Lua buffer
            model.buffer = formattedBuffer

            -- Mark all lines as dirty to redraw them
            for i = 1, #model.buffer do
                model:markDirty(i)
            end

            -- Update the status bar to indicate success
            model:updateStatusBar("Buffer formatted successfully!")
        else
            model:updateStatusBar("Error: Failed to format buffer. " .. (formattedBuffer or "Unknown error"))
        end
    end

    -- Map the formatting function to a keybinding
    KeyHandler:map("n", "leader + f", function()
        formatBuffer()
    end, "Format Lua Buffer")
end

return {
    init = init
}
