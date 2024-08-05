local KeyHandler = require("KeyHandler"):getInstance()
local CommandHandler = require("CommandHandler"):getInstance()
local bufferHandler = require("BufferHandler"):getInstance()

-- === Normal and Visual Mode Keybindings ===

-- Basic Navigation
KeyHandler:map({"n", "v"}, "h", function()
    CommandHandler:execute("move_left")
end, "Move Left")

KeyHandler:map({"n", "v"}, "j", function()
    CommandHandler:execute("move_down")
end, "Move Down")

KeyHandler:map({"n", "v"}, "k", function()
    CommandHandler:execute("move_up")
end, "Move Up")

KeyHandler:map({"n", "v"}, "l", function()
    CommandHandler:execute("move_right")
end, "Move Right")

-- Cursor movement within the line
KeyHandler:map({"n", "v"}, "0", function()
    CommandHandler:execute("move_to_line_start")
end, "Move to Start of Line")

KeyHandler:map({"n", "v"}, "^", function()
    CommandHandler:execute("move_to_first_non_blank")
end, "Move to First Non-Blank Character")

KeyHandler:map({"n", "v"}, "$", function()
    CommandHandler:execute("move_to_line_end")
end, "Move to End of Line")

-- Word motions
KeyHandler:map({"n", "v"}, "w", function()
    CommandHandler:execute("move_word_forward")
end, "Move to Next Word")

KeyHandler:map({"n", "v"}, "b", function()
    CommandHandler:execute("move_word_back")
end, "Move to Previous Word")

KeyHandler:map({"n", "v"}, "e", function()
    CommandHandler:execute("move_word_end")
end, "Move to End of Word")

-- Paragraph motions
KeyHandler:map({"n", "v"}, "{", function()
    CommandHandler:execute("move_paragraph_back")
end, "Move to Previous Paragraph")

KeyHandler:map({"n", "v"}, "}", function()
    CommandHandler:execute("move_paragraph_forward")
end, "Move to Next Paragraph")

-- Searching within the line
KeyHandler:map({"n", "v"}, "f", function()
    CommandHandler:execute("find_character")
end, "Find Character in Line")

KeyHandler:map({"n", "v"}, "t", function()
    CommandHandler:execute("find_before_character")
end, "Find Before Character in Line")

-- Repeating last character search
KeyHandler:map({"n", "v"}, "n", function()
    CommandHandler:execute("repeat_last_find")
end, "Repeat Last Find")

KeyHandler:map({"n", "v"}, ",", function()
    CommandHandler:execute("repeat_last_find_reverse")
end, "Repeat Last Find in Reverse")

-- File and Screen Navigation
KeyHandler:map({"n", "v"}, "g + g", function()
    CommandHandler:execute("move_to_top")
end, "Move to Top")

KeyHandler:map({"n", "v"}, "G", function()
    CommandHandler:execute("move_to_bottom")
end, "Move to Bottom")

KeyHandler:map({"n", "v"}, "H", function()
    CommandHandler:execute("move_to_top_of_screen")
end, "Move to Top of Screen")

KeyHandler:map({"n", "v"}, "M", function()
    CommandHandler:execute("move_to_middle_of_screen")
end, "Move to Middle of Screen")

KeyHandler:map({"n", "v"}, "L", function()
    CommandHandler:execute("move_to_bottom_of_screen")
end, "Move to Bottom of Screen")

-- Editing (Normal Mode Only)
KeyHandler:map("n", "d + d", function()
    CommandHandler:execute("cut_line")
end, "Cut Line")

KeyHandler:map("n", "d + w", function()
    CommandHandler:execute("delete_word")
end, "Delete Word")

KeyHandler:map("n", "c + c", function()
    CommandHandler:execute("change_line")
end, "Change Line")

KeyHandler:map("n", "c + w", function()
    CommandHandler:execute("change_word")
end, "Change Word")

KeyHandler:map("n", "Y", function()
    CommandHandler:execute("yank_line")
end, "Yank Line")

KeyHandler:map({"n", "v"}, "x", function()
    CommandHandler:execute("delete_char")
end, "Delete Char")

KeyHandler:map({"n", "v"}, "X", function()
    CommandHandler:execute("delete_char_before")
end, "Delete Char Before")

KeyHandler:map("n", "p", function()
    CommandHandler:execute("paste")
end, "Paste")

KeyHandler:map("n", "u", function()
    CommandHandler:execute("undo")
end, "Undo")

KeyHandler:map("n", "ctrl + r", function()
    CommandHandler:execute("redo")
end, "Redo")

KeyHandler:map("n", "ctrl + v", function()
    CommandHandler:execute("paste_clipboard")
end, "Paste Clipboard")

-- Mode Switching (Normal Mode Only)
KeyHandler:map("n", "i^", function()
    CommandHandler:execute("enter_insert_mode")
end, "Enter Insert Mode on Key Release")

KeyHandler:map("n", "a^", function()
    CommandHandler:execute("append_to_line")
end, "Append to Line on Key Release")

KeyHandler:map("n", "I^", function()
    CommandHandler:execute("insert_at_line_start")
end, "Insert at Line Start on Key Release")

KeyHandler:map("n", "o^", function()
    CommandHandler:execute("open_line_below")
end, "Open Line Below on Key Release")

KeyHandler:map("n", "O^", function()
    CommandHandler:execute("open_line_above")
end, "Open Line Above on Key Release")

KeyHandler:map("n", {":","shift+semiColon"}, function()
    CommandHandler:execute("enter_command_mode")
end, "Enter Command Mode")

KeyHandler:map("n", "v", function()
    CommandHandler:execute("enter_visual_mode")
end, "Enter Visual Mode")

KeyHandler:map("n", "f9", function()
    CommandHandler:execute("exit_editor")
end, "Exit Editor")

-- Search and Replace
KeyHandler:map("n", "/", function()
    bufferHandler:switchMode("command", "search ")   
end, "Search")

KeyHandler:map("n", "?", function()
    bufferHandler:switchMode("command", "replace ")   
end, "Replace")

KeyHandler:map("n", "ctrl + /", function()
    bufferHandler:switchMode("command", "replace_all ")
end, "Replace All")

KeyHandler:map("n", "ctrl + n", function()
    bufferHandler:switchMode("command", nil, true)
end, "Execute previous command")

-- === Visual Mode Specific Keybindings ===

-- Editing
KeyHandler:map("v", "y", function()
    CommandHandler:execute("yank_visual_selection")
    CommandHandler:execute("end_visual_mode")
end, "Yank Visual Selection and End Visual Mode")

KeyHandler:map("v", "d", function()
    CommandHandler:execute("delete_visual_selection")
    CommandHandler:execute("end_visual_mode")
end, "Delete Visual Selection and End Visual Mode")

KeyHandler:map("v", "c", function()
    CommandHandler:execute("change_visual_selection")
    CommandHandler:execute("end_visual_mode")
end, "Change Visual Selection and End Visual Mode")

KeyHandler:map("v", "x", function()
    CommandHandler:execute("cut_visual_selection")
    CommandHandler:execute("end_visual_mode")
end, "Cut Visual Selection and End Visual Mode")

KeyHandler:map("v", "<", function()
    CommandHandler:execute("unindent_visual_selection")
end, "Unindent Visual Selection")

KeyHandler:map("v", ">", function()
    CommandHandler:execute("indent_visual_selection")
end, "Indent Visual Selection")

KeyHandler:map("v", "U", function()
    CommandHandler:execute("uppercase_visual_selection")
end, "Uppercase Visual Selection")

KeyHandler:map("v", "u", function()
    CommandHandler:execute("lowercase_visual_selection")
end, "Lowercase Visual Selection")

KeyHandler:map("v", "J", function()
    CommandHandler:execute("join_visual_selection")
end, "Join Visual Selection")

KeyHandler:map("v", "~", function()
    CommandHandler:execute("swap_case_visual_selection")
end, "Swap Case of Visual Selection")

-- Mode Switching
KeyHandler:map("v", "f1", function()
    CommandHandler:execute("end_visual_mode")
end, "End Visual Mode")

KeyHandler:map("v", "v", function()
    CommandHandler:execute("end_visual_mode")
end, "End Visual Mode")

-- === Insert Mode Keybindings ===

KeyHandler:map("i", "f1", function()
    CommandHandler:execute("insert_exit_to_normal")
end, "Exit to Normal Mode")

KeyHandler:map("i", "left", function()
    CommandHandler:execute("insert_arrow_left")
end, "Move Left")

KeyHandler:map("i", "right", function()
    CommandHandler:execute("insert_arrow_right")
end, "Move Right")

KeyHandler:map("i", "up", function()
    CommandHandler:execute("insert_arrow_up")
end, "Move Up")

KeyHandler:map("i", "down", function()
    CommandHandler:execute("insert_arrow_down")
end, "Move Down")

KeyHandler:map("i", "tab", function()
    CommandHandler:execute("insert_tab")
end, "Insert Tab or Select Autocomplete")

KeyHandler:map("i", "enter", function()
    CommandHandler:execute("insert_enter")
end, "Insert New Line or Select Autocomplete")

KeyHandler:map("i", "backspace", function()
    CommandHandler:execute("insert_backspace")
end, "Backspace or Close Autocomplete")

-- === Miscellaneous Keybindings ===

KeyHandler:map({"n", "v", "i"}, "f3", function()
    CommandHandler:execute("show_keybindings")
end, "Show Keybindings")

KeyHandler:map({"n", "v", "i"}, "f4", function()
    CommandHandler:execute("close_windows")
end, "Close Windows")
