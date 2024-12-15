# Nuget Package Manager for Neovim

- Minimal setup for nuget package manager

## Features
- Search Nuget packages directly from Neovim
- Queue and install packages for .NET projects
- Easy keyboard navigation

## Installation
### lazy.nvim
```lua
{
    'quffe/nvim-nuget',
    dependencies = {
      "nvim-lua/plenary.nvim", -- Required dependency
    },
    config = function()
      require("nuget").setup()
    end,
}
```

## Usage
- `:NugetPackage` - Open package search window
- `<space>` - Toggle package in installation queue
- `<C-f>` - Reopen search input
- `I` - Install queued packages
