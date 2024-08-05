# AVIM: A Neovim-like Editor Inside ComputerCraft/CC:Tweaked

**AVIM** is a custom text editor built inside the [ComputerCraft/CC:Tweaked](https://tweaked.cc/) mod for Minecraft. It emulates the functionality and feel of Neovim, offering features like keybindings, visual mode, command execution, and plugin support, all within the limited environment of ComputerCraft.
![AVIM Screenshot](https://github.com/arismoko/avim/blob/main/example_img.png "AVIM in action")
## Features

- **Modal Editing**: Just like Vim, AVIM operates in different modes (`Normal`, `Visual`, `Insert`, `Command`).
- **Custom Keybindings**: Map your own keybindings in different modes to create a personalized workflow.
- **Plugins**: AVIM supports plugins, allowing users to extend its functionality.
- **Command Execution**: Use the command mode to execute commands, search, and replace text.
- **Syntax Highlighting**: AVIM has autocompletion and syntax highlighting built right in!

## Getting Started

### Installation

1. **Download AVIM**: Use one of the following methods to install avim the intended way:
```bash
(Manual Install)
wget https://gist.githubusercontent.com/SquidDev/e0f82765bfdefd48b0b15a5c06c0603b/raw/clone.min.lua
git/clone.min https://github.com/arismoko/avim.git
mv avim _avim-files
mv _avim-files/avim avim
avim

or

(Recommended Install)
pastebin get ZsJWP7fr install_avim
install_avim
avim
```
2. **Load Plugins**: Customize the plugins by editing the `plugins/pluginConfig.lua` file.

### Basic Usage

Launch the editor by running the main AVIM script. You will be greeted with a simple menu where you can create or open files, manage plugins, or exit the program.

### Main Menu

```lua
-- Code snippet from the main menu:
local function handleMainMenu()
    print("Welcome to AVIM")
    print("1. Create New File")
    print("2. Open File")
    print("3. Manage Plugins")
    print("4. Quit")
end
```

## Keybindings

AVIM supports customizable keybindings in different modes. Here is how you can define a keybinding:

### Defining a Keybinding

```lua
-- Example keybinding: Move left in Normal and Visual modes
KeyHandler:map({"n", "v"}, "h", function()
    CommandHandler:execute("move_left")
end, "Move Left")
```

- **Modes**: `"n"` (Normal), `"v"` (Visual), `"i"` (Insert), `"c"` (Command).
- **Key Sequence**: `"h"` in this case.
- **Callback**: The function to execute when the key is pressed.
- **Description**: A short description of what the keybinding does.

### Example Keybinding Configurations

- **Move to the Top of the File**:
  
    ```lua
    KeyHandler:map({"n", "v"}, "g + g", function()
        CommandHandler:execute("move_to_top")
    end, "Move to Top")
    ```

- **Cut Line**:

    ```lua
    KeyHandler:map("n", "d + d", function()
        CommandHandler:execute("cut_line")
    end, "Cut Line")
    ```

### Visual Mode Example

```lua
-- Enter Visual Mode
KeyHandler:map("n", "v", function()
    CommandHandler:execute("enter_visual_mode")
end, "Enter Visual Mode")
```

## Commands

Commands are the backbone of AVIM's functionality. Here's how you can create and map commands.

### Defining a Command

```lua
-- Example Command: Move Cursor Left
CommandHandler:map("move_left", function()
    Model.cursorX = math.max(1, Model.cursorX - 1)
end)
```

- **Command Name**: `"move_left"` in this example.
- **Callback**: The function that defines the command’s behavior.

### Example Command Configurations

- **Search for Text**:
  
    ```lua
    CommandHandler:map("search", function(pattern)
        -- Logic for searching text
    end)
    ```

- **Yank (Copy) a Line**:

    ```lua
    CommandHandler:map("yank_line", function()
        Model:yankLine()
    end)
    ```

## Plugins

AVIM supports plugins, allowing users to extend the editor's functionality. Plugins are Lua modules that are loaded based on a configuration file.

### Loading Plugins

```lua
-- Load plugin configuration
local pluginConfigFile = "plugins/pluginConfig.lua"
if fs.exists(pluginConfigFile) then
    plugins = require("plugins.pluginConfig")
end
```

### Plugin Initialization

Each plugin must have an `init` function that is called upon loading:

```lua
-- Example Plugin Initialization
function plugin.init(components)
    -- Plugin logic here
end
```

### Enabling/Disabling Plugins

Plugins can be enabled or disabled through a configuration file:

```lua
-- Example plugin configuration
plugins = {
    {name = "fileExplorer", enabled = true},
    {name = "autocomplete", enabled = false},
}
```

## Example Plugin: File Explorer

This plugin provides a simple file explorer interface within AVIM.

### File Explorer Plugin

```lua
local function openFileExplorer()
    local files = fs.list(shell.dir())
    table.sort(files)
    -- Logic to display files and handle navigation
end
```

### Keybinding to Open File Explorer

```lua
KeyHandler:map("n", "backslash", function()
    openFileExplorer()
end, "Open File Explorer")
```

## DOCS COMING SOON!
```

## Contributions

Feel free to contribute to AVIM by submitting issues or pull requests on our GitHub repository. Contributions can include new features, plugins, bug fixes, or improvements to documentation.

---

**AVIM** brings the power of modal text editing to ComputerCraft, combining the flexibility of Vim with the extensibility of Lua in a Minecraft environment. Explore, customize, and enhance your text editing experience with AVIM!
