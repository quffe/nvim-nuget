# Nuget Package Manager for Neovim

- Minimal setup for nuget package manager

## Features
- Search Nuget packages directly from Neovim
- Queue and install packages for .NET projects
- Easy keyboard navigation
- Remove Installed packages

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
- `g?` - To Display Help
- `<space>` - Toggle package in installation queue
- `<C-f>` - Reopen search input
- `I` - Install queued packages
- `X` - To remove Installed package

## Roadmap
- Add version select
- UI customizations
- Curl on background
