local function init(components)
    local Avim = components.Avim
    local KeyHandler = components.KeyHandler

    -- Load DumbLuaParser
    local parser = require("plugins.aLSP.dumbParser")

    local function formatBuffer()
        local model = Avim:getInstance()
        local buffer = model.buffer

        -- Convert the buffer into a single Lua script string
        local luaCode = table.concat(buffer, "\n")

        -- Tokenize and parse the Lua code
        local tokens = parser.tokenize(luaCode)
        local ast = parser.parse(tokens)

        -- Simplify the AST
        parser.simplify(ast)

        -- Convert the AST back to Lua code (formatted)
        local formattedLua = parser.toLua(ast, true)

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
