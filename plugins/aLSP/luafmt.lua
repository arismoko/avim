local LuaFmt = {}
LuaFmt.__index = LuaFmt

function LuaFmt:new(columnLimit)
    local self = setmetatable({}, LuaFmt)
    self.COLUMN_LIMIT = columnLimit or 80
    self.TAB_COLUMNS = 4
    self:initSpecialRepresentation()
    self:initTokens()
    return self
end

-- Special representations for certain characters
function LuaFmt:initSpecialRepresentation()
    local specialRepresentation = {
        ["\a"] = [[\a]],
        ["\b"] = [[\b]],
        ["\f"] = [[\f]],
        ["\n"] = [[\n]],
        ["\r"] = [[\r]],
        ["\t"] = [[\t]],
        ["\v"] = [[\v]],
        ["\\"] = [[\\]],
        ["\""] = [[\"]],
        ["\0"] = [[\0]],
    }

    for i = 0, 31 do
        local c = string.char(i)
        if not specialRepresentation[c] then
            local m = tostring(i)
            specialRepresentation[c] = "\\" .. string.rep("0", 3 - #m) .. m
        end
    end

    for i = 128, 255 do
        specialRepresentation[string.char(i)] = "\\" .. tostring(i)
    end

    self.specialRepresentation = specialRepresentation
end

-- Matcher for token recognition
function LuaFmt:matcher(pattern, tag)
    assert(type(tag) == "string")
    return function(text, offset)
        local from, to = text:find("^" .. pattern, offset)
        if from then
            return to, tag
        end
    end
end

-- Token initialization and classification
function LuaFmt:initTokens()
    local IS_KEYWORD = {
        ["if"] = true, ["then"] = true, ["elseif"] = true, ["else"] = true, ["end"] = true,
        ["for"] = true, ["in"] = true, ["do"] = true, ["repeat"] = true, ["until"] = true,
        ["while"] = true, ["function"] = true, ["local"] = true, ["return"] = true, ["break"] = true,
    }

    local TOKENS = {
        function(text, offset)
            local quote = text:sub(offset, offset)
            if quote == "\"" or quote == "'" then
                local back = false
                for i = offset + 1, #text do
                    if back then
                        back = false
                    elseif text:sub(i, i) == "\\" then
                        back = true
                    elseif text:sub(i, i) == quote then
                        return i, "string"
                    end
                end
            end
        end,
        function(text, offset)
            local from, to = text:find("^%[=*%[", offset)
            if from then
                local size = to - from - 1
                local _, stop = text:find("%]" .. string.rep("=", size) .. "%]", offset)
                assert(stop)
                return stop, "string"
            end
        end,
        function(text, offset)
            if text:sub(offset, offset + 1) == "--" then
                local start, startLen = text:find("^%[=*%[", offset + 2)
                if start then
                    local size = startLen - start - 1
                    local _, stop = text:find("%]" .. string.rep("=", size) .. "%]", offset)
                    assert(stop)
                    return stop, "comment"
                end
                return (text:find("\n", offset) or #text + 1) - 1, "comment"
            end
        end,
        function(text, offset)
            local _, space = text:find("^%s+", offset)
            if space then
                local breaks = 0
                for _ in text:sub(offset, space):gmatch("\n") do
                    breaks = breaks + 1
                end
                if breaks > 1 then
                    return space, "blank"
                end
                return space, "whitespace"
            end
        end,
        function(text, offset)
            local _, limit = text:find("^[0-9.-+eExa-fA-F]+", offset)
            local last
            for i = offset, limit or offset do
                if tonumber(text:sub(offset, i)) then
                    last = i
                end
            end
            if last then
                return last, "number"
            end
        end,
        self:matcher("%.%.%.", "name"),
        self:matcher("%.%.", "operator"),
        function(text, offset)
            local from, to = text:find("^[a-zA-Z0-9_]+", offset)
            if to then
                local word = text:sub(from, to)
                local size = #word
                if IS_KEYWORD[word] then
                    return to, word
                elseif word == "not" or word == "or" or word == "and" then
                    return to, "operator"
                end
                return to, "word"
            end
        end,
        self:matcher("[:.]", "access"),
        self:matcher("[;,]", "separator"),
        self:matcher("[%[{(]", "open"),
        self:matcher("[%]})]", "close"),
        function(text, offset)
            local operators = {
                "==", "<=", ">=", "~=", "^", "*", "/", "%", "<", ">", "+", "-", "#",
            }
            for _, op in ipairs(operators) do
                local to = offset + #op - 1
                if text:sub(offset, to) == op then
                    return to, "operator"
                end
            end
        end,
        self:matcher("=", "assign"),
        self:matcher(".", "other"),
    }

    self.TOKENS = TOKENS
end

-- Tokenization process for buffer (list of lines)
function LuaFmt:tokenize(buffer)
    assert(type(buffer) == "table", "Expected buffer to be a table")
    local tokens = {}
    for lineNumber, line in ipairs(buffer) do
        local offset = 1
        while offset <= #line do
            local didCut = false
            for _, t in ipairs(self.TOKENS) do
                local cut, tag = t(line, offset)
                if cut then
                    assert(type(cut) == "number")
                    assert(cut >= offset)
                    assert(tag)
                    if tag ~= "whitespace" then
                        table.insert(tokens, {
                            tag = tag,
                            text = line:sub(offset, cut),
                            offset = offset,
                            line = lineNumber,  -- Include line number in the token
                        })
                    end
                    offset = cut + 1
                    didCut = true
                    break
                end
            end
            assert(didCut, line:sub(offset, offset + 50))
        end
    end
    return tokens
end

function LuaFmt:filterBlanks(tokens)
    -- Adjust token stream to manage blanks, comments, and block delimiters
    local NO_BLANK_AFTER = {
        ["do"] = true, ["lone-do"] = true, ["then"] = true, ["else"] = true,
        ["open"] = true, ["function-close"] = true,
    }

    local filtered = {}
    local forFunction = false
    local forControl = false
    local wasObject = false

    for _, token in ipairs(tokens) do
        -- Do not use strict metatable enforcement here
        -- Allow tokens to have keys added dynamically later
        -- token = setmetatable(token, {__index = function(_, k)
        --     error("No such key: " .. tostring(k))
        -- end})

        if token.tag == "do" then
            if not forControl then
                table.insert(filtered, {
                    tag = "lone-do", text = token.text
                })
            else
                table.insert(filtered, token)
                forControl = false
            end
        elseif token.tag == "for" or token.tag == "while" then
            table.insert(filtered, token)
            forControl = true
        elseif token.tag == "function" then
            forFunction = true
            table.insert(filtered, token)
        elseif token.tag == "comment" then
            if filtered[#filtered] and filtered[#filtered].tag == "blank" then
                -- Do nothing
            elseif filtered[#filtered] and filtered[#filtered].tag == "comment" then
                -- Do nothing
            elseif filtered[#filtered] and not NO_BLANK_AFTER[filtered[#filtered].tag] then
                table.insert(filtered, {
                    tag = "blank", text = "\n\n"
                })
            end
            table.insert(filtered, token)
        elseif token.tag == "close" then
            if filtered[#filtered] and filtered[#filtered].tag == "blank" then
                table.remove(filtered)
            end

            if forFunction then
                forFunction = false
                table.insert(filtered, {
                    tag = "function-close", text = token.text
                })
            else
                table.insert(filtered, token)
            end
        elseif token.tag == "open" then
            if forFunction then
                table.insert(filtered, {
                    tag = "function-open", text = token.text
                })
            else
                table.insert(filtered, token)
            end
        elseif token.tag == "blank" then
            if #filtered > 0 then
                if not NO_BLANK_AFTER[filtered[#filtered].tag] then
                    table.insert(filtered, token)
                end
            end
        elseif token.text == "-" and not wasObject then
            table.insert(filtered, {
                tag = "unm", text = token.text
            })
        else
            if #filtered > 0 and filtered[#filtered].tag == "blank" then
                if token.tag == "end" or token.tag == "else" or token.tag == "elseif" or token.tag == "until" then
                    table.remove(filtered)
                end
            end
            table.insert(filtered, token)
        end

        wasObject = token.tag == "close" or token.tag == "number" or token.tag == "word" or token.tag == "string"
    end

    return filtered
end

function LuaFmt:groupTokens(tokens)
    local OPENS = {
        ["if"] = "code", ["while"] = "code", ["for"] = "code", ["lone-do"] = "code",
        ["function"] = "code", ["open"] = "group",
    }

    local CLOSES = {
        ["end"] = "code", ["close"] = "group",
    }

    local context = { tag = "code", children = {} }
    local stack = {}

    for _, token in ipairs(tokens) do
        assert(token.text)
        token.headText = token.text
        token.tailText = token.text
        token.tailTag = token.tag
        token.headTag = token.tag
        assert(token.headText)
        if OPENS[token.tag] then
            table.insert(stack, context)
            local newContext = { tag = OPENS[token.tag], children = { token } }
            table.insert(context.children, newContext)
            context = newContext
        elseif CLOSES[token.tag] then
            if context.tag ~= CLOSES[token.tag] then
                error(string.format("Mismatched close token '%s' on line %d, expected context '%s'", 
                    token.text, token.line, context.tag))
            end
            table.insert(context.children, token)
            context.tailTag = context.children[#context.children].tailTag
            context.tailText = context.children[#context.children].tailText
            context.headTag = context.children[1].headTag
            context.headText = context.children[1].headText
            context = table.remove(stack)
            assert(context)
        else
            table.insert(context.children, token)
        end
    end

    if #stack > 0 then
        error("Unclosed contexts in stack at the end of grouping")
    end

    return context
end

function LuaFmt:matchRule(rule, a, b)
    assert(type(rule) == "table")
    return self:matchLeft(rule[1], a) and self:matchRight(rule[2], b)
end

function LuaFmt:matchLeft(m, t)
    if m == "*" then
        return true
    elseif m:sub(1, 1) == "`" then
        return m:sub(2) == t.tailText
    end
    return m == t.tailTag
end

function LuaFmt:matchRight(m, t)
    if m == "*" then
        return true
    elseif m:sub(1, 1) == "`" then
        return m:sub(2) == t.headText
    end
    return m == t.headTag
end

-- Rendering tokens back into a formatted buffer
function LuaFmt:renderTokens(tree, column, indent, buffer)
    assert(tree and tree.children, "Invalid syntax tree provided")
    assert(type(column) == "number")
    assert(type(indent) == "number")

    local INDENT_AFTER = {
        ["then"] = true, ["else"] = true, ["function-close"] = true, ["repeat"] = true,
        ["do"] = true, ["lone-do"] = true,
    }

    local DEDENT_BEFORE = {
        ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true,
    }

    local STATEMENT_SEPARATOR = {
        {"*", "return"}, {"*", "break"}, {"*", "comment"}, {"then", "*"},
        {"*", "else"}, {"else", "*"}, {"*", "elseif"}, {"*", "if"},
        {"*", "repeat"}, {"repeat", "*"}, {"*", "until"}, {"*", "while"},
        {"*", "end"}, {"end", "*"}, {"do", "*"}, {"lone-do", "*"},
        {"*", "lone-do"}, {"*", "for"}, {"word", "word"}, {"number", "word"},
        {"string", "word"}, {"separator", ";"}, {"*", "comment"},
        {"comment", "*"}, {"blank", "*"}, {"*", "blank"}, {"close", "word"},
        {"*", "local"}, {"string", "function"}, {"word", "function"},
        {"number", "function"}, {"close", "function"}, {"function-close", "*"},
        {"`;", "*"},
    }

    local GLUE = {
        {"open", "*"}, {"function-open", "*"}, {"*", "close"},
        {"*", "function-close"}, {"*", "separator"}, {"word", "open"},
        {"*", "function-open"}, {"*", "access"}, {"access", "*"},
        {"`#", "*"}, {"unm", "number"}, {"unm", "string"},
        {"unm", "word"}, {"close", "`["}, {"close", "`("},
    }

    local UNGLUE = {
        {"word", "`{"},
    }

    local function renderCode(tree, column, indent)
        local buffer = buffer or {}
        for i, child in ipairs(tree.children) do
            local space = ""
            local previous = tree.children[i - 1]
            if previous then
                space = " "
                for _, rule in ipairs(STATEMENT_SEPARATOR) do
                    if self:matchRule(rule, previous, child) then
                        if INDENT_AFTER[previous.tailTag] then
                            indent = indent + 1
                        end
                        if DEDENT_BEFORE[child.headTag] then
                            indent = indent - 1
                        end
                        space = "\n" .. string.rep("\t", indent)
                        break
                    end
                end
                if space == " " then
                    for _, rule in ipairs(GLUE) do
                        if self:matchRule(rule, previous, child) then
                            space = ""
                        end
                    end
                    for _, rule in ipairs(UNGLUE) do
                        if self:matchRule(rule, previous, child) then
                            space = " "
                        end
                    end
                end
            end
            if child.headTag == "blank" then
                space = space:gsub("[^\n]", "")
            end
            if #buffer == 0 or space:find("\n") then
                table.insert(buffer, space:match("[^\n]*"))
            else
                buffer[#buffer] = buffer[#buffer] .. space
            end

            local finalLineLength = 2 * self.COLUMN_LIMIT
            local finalLine = buffer[#buffer]:match("[^\n]*$")
            if #finalLine < finalLineLength then
                finalLineLength = #finalLine:gsub("\t", string.rep(" ", self.TAB_COLUMNS))
            end

            buffer = self:renderTokens(child, finalLineLength, indent, buffer)
        end
        return buffer
    end

    local function renderObject(tree, column, indent, sepBreak)
        local buffer = buffer or {}
        for i, child in ipairs(tree.children) do
            local previous = tree.children[i - 1]
            local space = ""
            local BRK = "\n" .. string.rep("\t", indent)
            if previous then
                space = " "
                if sepBreak and i == 2 then
                    assert(tree.children[1].tag == "open")
                    space = BRK .. "\t"
                    indent = indent + 1
                elseif sepBreak and i == #tree.children then
                    space = BRK:sub(1, -2)
                    indent = indent - 1
                elseif previous.tailTag == "comment" then
                    space = BRK
                elseif child.headTag == "comment" then
                    space = BRK
                elseif sepBreak and previous.tailTag == "separator" then
                    assert(previous.tag == "separator")
                    space = BRK
                elseif previous.tag == "blank" then
                    space = BRK
                elseif child.tag == "blank" then
                    space = "\n"
                end

                if space == " " then
                    for _, rule in ipairs(GLUE) do
                        if self:matchRule(rule, previous, child) then
                            space = ""
                        end
                    end
                    for _, rule in ipairs(UNGLUE) do
                        if self:matchRule(rule, previous, child) then
                            space = " "
                        end
                    end
                end
            end
            if child.headTag == "blank" then
                space = space:gsub("[^\n]", "")
            end
            if #buffer == 0 or space:find("\n") then
                table.insert(buffer, space:match("[^\n]*"))
            else
                buffer[#buffer] = buffer[#buffer] .. space
            end

            local finalLine = buffer[#buffer]:match("[^\n]*$")
            local finalLineLength = self.COLUMN_LIMIT * 2
            if #finalLine < finalLineLength then
                finalLineLength = #finalLine:gsub("\t", string.rep(" ", self.TAB_COLUMNS))
            end

            buffer = self:renderTokens(child, finalLineLength, indent, buffer)
        end
        return buffer
    end

    if tree.tag == "group" then
        local c = renderObject(tree, column, indent, false)
        local tooLong = (column + #c > self.COLUMN_LIMIT or c:find("\n"))
        local notEmpty = #tree.children > 2
        local trailingComma = notEmpty and tree.children[#tree.children - 1].tailTag == "separator"

        if trailingComma then
            return renderObject(tree, column, indent, true)
        elseif tooLong and notEmpty then
            if tree.headText == "(" then
                local lastSeparator = nil  -- Initialize as nil
                for i = #tree.children, 1, -1 do
                    if tree.children[i].tailTag == "separator" then
                        lastSeparator = i  -- Store the index of the last separator
                        break
                    end
                end

                if not lastSeparator then
                    return c
                end

                local withoutLast = {
                    tag = tree.tag,
                    tailTag = tree.tailTag,
                    tailText = tree.tailText,
                    headTag = tree.headTag,
                    headText = tree.headText,
                    children = {},
                }
                for i = 1, lastSeparator - 1 do
                    table.insert(withoutLast.children, tree.children[i])
                end
                local r = renderObject(withoutLast, column, indent, false)
                local rTooLong = (column + #r > self.COLUMN_LIMIT or r:find("\n"))
                if not rTooLong then
                    local firstLine = c:match("^[^\n]*")
                    if column + #firstLine <= self.COLUMN_LIMIT then
                        return c
                    end
                end
            end
            return renderObject(tree, column, indent, true)
        end
        return c
    end

    return renderCode(tree, column, indent)
end

function LuaFmt:formatBuffer(buffer)
    -- Check if the buffer is valid
    assert(type(buffer) == "table", "Expected buffer to be a table")

    -- Check for empty buffer
    if #buffer == 0 then
        return {}  -- Return an empty table as the formatted buffer
    end

    -- Validate each line in the buffer
    for i, line in ipairs(buffer) do
        if type(line) ~= "string" then
            error(string.format("Invalid line at index %d: Expected a string, got %s", i, type(line)))
        end
    end

    -- Tokenize the buffer
    local tokens = self:filterBlanks(self:tokenize(buffer))

    -- Group the tokens into a syntax tree
    local tree = self:groupTokens(tokens)
    assert(tree and tree.children, "Invalid syntax tree structure")

    -- Render the formatted buffer from the syntax tree
    local formattedBuffer = self:renderTokens(tree, 0, 0, {})

    -- Return the formatted buffer
    return formattedBuffer
end

return LuaFmt
