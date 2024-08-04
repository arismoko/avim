local function init(components)
    local Avim = components.Avim
    local KeyHandler = components.KeyHandler

    -- Load luafmt
    local luafmt = require("plugins.aLSP.luafmt")

    local function formatBuffer()
        local model = Avim:getInstance()
        local buffer = model.buffer

        -- Convert the buffer into a single Lua script string
        local luaCode = table.concat(buffer, "\n")

        -- Format the Lua code using luafmt
        local formattedLua = luafmt(luaCode, 80) -- 80 is the column limit

        -- Replace the current buffer with the formatted Lua code
        model.buffer = {}
        for line in (formattedLua or ""):gmatch("([^\n]*)\n?") do
            table.insert(model.buffer, line)
        end

        -- Mark all lines as dirty to redraw them
        for i = 1, #model.buffer do
            model:markDirty(i)
        end

        -- Update the status bar to indicate success
        model:updateStatusBar("Buffer formatted successfully!")
    end

    -- Map the formatting function to a keybinding
    KeyHandler:map("n", "leader + f", function()
        formatBuffer()
    end, "Format Lua Buffer")
end

return {
    init = init
}
