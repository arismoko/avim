local function init(components)
    local Avim = components.Avim
    local KeyHandler = components.KeyHandler

    -- Load LCF (Lua Code Formatter)
    local lcf = require('plugins.aLSP.lcf.workshop.base')
    local get_ast = lcf.request('!.lua.code.get_ast')
    local get_formatted_code = lcf.request('!.lua.code.ast_as_code')

    local function formatBuffer()
        local model = Avim:getInstance()
        local buffer = model.buffer

        -- Convert the buffer into a single Lua script string
        local luaCode = table.concat(buffer, "\n")

        -- Get the AST from the Lua code
        local ast = get_ast(luaCode)

        -- Format the AST back into Lua code
        local formattedLua = get_formatted_code(ast, {
            indent_chunk = '  ',
            right_margin = 96,
            max_text_width = math.huge,
            keep_unparsed_tail = true,
            keep_comments = true,
        })

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
