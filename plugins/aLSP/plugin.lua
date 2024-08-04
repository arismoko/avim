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

        -- Convert the buffer into a single Lua script string
        local luaCode = table.concat(buffer, "\n")

        -- Format the Lua code using luaFmtInstance
        local formattedLua = luaFmtInstance:formatLuaCode(luaCode)

        if formattedLua then
            -- Replace the current buffer with the formatted Lua code
            model.buffer = {}
            for line in formattedLua:gmatch("([^\n]*)\n?") do
                table.insert(model.buffer, line)
            end

            -- Mark all lines as dirty to redraw them
            for i = 1, #model.buffer do
                model:markDirty(i)
            end

            -- Update the status bar to indicate success
            model:updateStatusBar("Buffer formatted successfully!")
        else
            model:updateStatusBar("Error: Failed to format buffer.")
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
