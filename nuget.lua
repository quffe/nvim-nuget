-- nuget-package-manager/plugin/nuget-package-manager.lua

if exists('g:loaded_nuget')
    finish
endif
let g:loaded_nuget_package_manager = 1

lua require('nuget').setup()
