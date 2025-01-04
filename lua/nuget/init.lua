-- nuget-package-manager/lua/nuget-package-manager/init.lua

local M = {}

-- Dependencies
local popup = require("plenary.popup")
local ui = require("nuget.ui")
local nuget = require("nuget.nuget")

M.make_line = ui.make_line
local center_text = ui.center_text
local tbl_indexof = ui.tbl_indexof
M.show_help = ui.show_help
M.find_csproj = nuget.find_csproj
M.read_installed_packages = nuget.read_installed_packages
M.query_packages = nuget.query_packages

-- State variables
M.state = {
	current_results = {},
	installation_queue = {},
	popup_win_id = nil,
	popup_bufnr = nil,
	search_input = "",
	installed_packages = {},
}

-- Function to render package results
function M.render_results()
	if not M.state.popup_win_id or not vim.api.nvim_win_is_valid(M.state.popup_win_id) then
		return
	end

	-- Create or reuse the buffer
	if not M.state.popup_bufnr or not vim.api.nvim_buf_is_valid(M.state.popup_bufnr) then
		M.state.popup_bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.state.popup_bufnr })
		vim.api.nvim_set_option_value("swapfile", false, { buf = M.state.popup_bufnr })
	end

	local display_lines = {}
	local highlights = {}
	local line_count = 0

	-- Helper function to add line with highlight
	local function add_line_with_highlights(line_data)
		table.insert(display_lines, line_data.line)
		for _, hl in ipairs(line_data.highlights) do
			table.insert(highlights, {
				line = line_count,
				hl_group = hl.hl_group,
				col_start = hl.col_start,
				col_end = hl.col_end,
			})
		end
		line_count = line_count + 1
	end

	-- Header
	add_line_with_highlights(M.make_line({ { center_text("g? for help"), "Comment" } }))
	add_line_with_highlights(M.make_line({ { "", nil } }))

	-- Installed packages section
	add_line_with_highlights(
		M.make_line({ { "Currently Installed Packages: ", "Title" }, { "(press x to remove)", "Comment" } })
	)

	local installed = M.state.installed_packages
	if vim.tbl_count(installed) == 0 then
		add_line_with_highlights(M.make_line({ { "  No packages installed", "Comment" } }))
	else
		for package, version in pairs(installed) do
			add_line_with_highlights(M.make_line({
				{ "  ", nil },
				{ "󰡖 ", "Statement" },
				{ package, "Function" },
				{ " (", nil },
				{ version, "String" },
				{ ")", nil },
			}))
		end
	end

	add_line_with_highlights(M.make_line({ { "", nil } }))
	add_line_with_highlights(M.make_line({ { "Installation Queue:", "Title" } }))

	if #M.state.installation_queue == 0 then
		add_line_with_highlights(M.make_line({ { "  No packages queued for installation", "Comment" } }))
	else
		for _, package in ipairs(M.state.installation_queue) do
			add_line_with_highlights(M.make_line({
				{ "  - ", nil },
				{ package, "Special" },
			}))
		end
	end

	-- Add separator
	add_line_with_highlights(M.make_line({ { "", nil } }))
	add_line_with_highlights(M.make_line({ { "Search Results:", "Title" } }))

	-- Add search results
	if #M.state.current_results == 0 then
		add_line_with_highlights(M.make_line({ { "  No packages found", "Comment" } }))
	else
		for _, package in ipairs(M.state.current_results) do
			local queued = tbl_indexof(M.state.installation_queue, package.id) ~= -1
			local prefix = queued and "󰡖 " or "󰄱 "
			add_line_with_highlights(M.make_line({
				{ prefix, "Statement" },
				{ package.id, "Function" },
				{ " (", nil },
				{ package.version, "String" },
				{ ")", nil },
			}))
		end
	end

	-- Make buffer modifiable temporarily
	vim.api.nvim_set_option_value("modifiable", true, { buf = M.state.popup_bufnr })

	vim.api.nvim_buf_set_lines(M.state.popup_bufnr, 0, -1, false, display_lines)
	-- vim.api.nvim_win_set_buf(M.state.popup_win_id, M.state.popup_bufnr)
	-- Apply highlights
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_add_highlight(
			M.state.popup_bufnr,
			-1,
			hl.hl_group,
			hl.line,
			hl.col_start or 0,
			hl.col_end or -1
		)
	end

	vim.api.nvim_set_option_value("modifiable", false, { buf = M.state.popup_bufnr })
	-- Set keymaps
	vim.cmd([[
        nnoremap <buffer> X <Cmd>lua require('nuget').handle_x_press()<CR>
        nnoremap <buffer> <space> <Cmd>lua require('nuget').toggle_package_queue()<CR>
        nnoremap <buffer> <C-f> <Cmd>lua require('nuget').focus_search_input()<CR>
        nnoremap <buffer> I <Cmd>lua require('nuget').install_queued_packages()<CR>
        nnoremap <buffer> q <Cmd>lua require('nuget').close_popup()<CR>
        nnoremap <buffer> g? <Cmd>lua require('nuget').show_help()<CR>
    ]])
end

-- Function to toggle package in installation queue
function M.toggle_package_queue()
	local line = vim.api.nvim_win_get_cursor(0)[1]

	-- Calculate offset based on header lines
	local header_lines = 7 -- "Currently Installed:" + installed items + empty line + "Installation Queue:" + queue items + empty line + "Search Results:"
	if vim.tbl_count(M.state.installed_packages) == 0 then
		header_lines = header_lines + 1 -- "No packages installed" message
	else
		header_lines = header_lines + vim.tbl_count(M.state.installed_packages)
	end

	if #M.state.installation_queue == 0 then
		header_lines = header_lines + 1 -- "No packages queued" message
	else
		header_lines = header_lines + #M.state.installation_queue
	end

	-- Adjust line number to account for header
	local result_index = line - header_lines

	-- Only process if we're in the results section
	if result_index > 0 and result_index <= #M.state.current_results then
		local package = M.state.current_results[result_index]
		if package then
			local index = tbl_indexof(M.state.installation_queue, package.id)
			if index == -1 then
				table.insert(M.state.installation_queue, package.id)
			else
				table.remove(M.state.installation_queue, index)
			end
			M.render_results()
		end
	end
end

-- Function to close the popup
function M.close_popup()
	if M.state.popup_win_id and vim.api.nvim_win_is_valid(M.state.popup_win_id) then
		vim.api.nvim_win_close(M.state.popup_win_id, true)
	end
	M.state.popup_win_id = nil
	M.state.popup_bufnr = nil
end

function M.open_package_search()
	-- Close any existing popup
	M.close_popup()

	-- Load installed packages
	M.state.installed_packages = M.read_installed_packages()

	-- Create popup window
	local width = 80
	local height = 20
	local popup_opts = {
		title = "Nuget Package Search",
		border = true,
		borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
		padding = { 1, 1, 1, 1 },
		titlehighlight = "TelescopePromptTitle",
		borderhighlight = "TelescopeBorder",
		minwidth = width,
		minheight = height,
	}

	M.state.popup_win_id = popup.create("", popup_opts)
	M.state.popup_bufnr = vim.api.nvim_win_get_buf(M.state.popup_win_id)

	vim.api.nvim_set_option_value("modifiable", false, { buf = M.state.popup_bufnr })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.state.popup_bufnr })

	-- Set initial mappings
	vim.cmd([[
        nnoremap <buffer> <C-f> <Cmd>lua require('nuget').focus_search_input()<CR>
        nnoremap <buffer> q <Cmd>lua require('nuget').close_popup()<CR>
    ]])

	-- Immediately focus on search input on initialization
	M.focus_search_input()
end

-- Function to focus search input
function M.focus_search_input()
	vim.ui.input({
		prompt = "Search Nuget Packages: ",
		default = M.state.search_input,
	}, function(input)
		if input then
			M.state.search_input = input
			M.state.current_results = M.query_packages(input)
			M.render_results()
		end
	end)
end

-- Function to install queued packages
function M.install_queued_packages()
	if #M.state.installation_queue == 0 then
		vim.notify("No packages in installation queue", vim.log.levels.WARN)
		return
	end

	-- Track successful and failed installations
	local successful_packages = {}
	local failed_packages = {}

	-- Install packages one by one
	for _, package in ipairs(M.state.installation_queue) do
		local cmd = string.format("dotnet add package %s", package)
		local result = vim.fn.systemlist(cmd)
		local exit_code = vim.v.shell_error

		if exit_code == 0 then
			table.insert(successful_packages, package)
		else
			table.insert(failed_packages, { package = package, error = table.concat(result, "\n") })
		end
	end

	-- Provide comprehensive notification
	if #successful_packages > 0 then
		local success_msg = "Package(s) installed successfully:\n"
		for _, pkg in ipairs(successful_packages) do
			success_msg = success_msg .. string.format(" - %s\n", pkg)
		end
		vim.notify(success_msg, vim.log.levels.INFO)
	end

	if #failed_packages > 0 then
		local error_msg = "Failed to install packages:\n"
		for _, pkg in ipairs(failed_packages) do
			error_msg = error_msg .. string.format(" - %s:\n%s\n", pkg.package, pkg.error)
		end
		vim.notify(error_msg, vim.log.levels.ERROR)
	end

	-- Clear the installation queue
	M.state.installation_queue = {}

	-- Refresh installed packages
	M.state.installed_packages = M.read_installed_packages()

	M.render_results()
end

-- Function to remove package
function M.remove_package(package_name)
	local cmd = string.format("dotnet remove package %s", package_name)
	local result = vim.fn.systemlist(cmd)
	local exit_code = vim.v.shell_error

	if exit_code == 0 then
		vim.notify(string.format("Package removed successfully:\n - %s", package_name), vim.log.levels.INFO)
		-- Refresh installed packages
		M.state.installed_packages = M.read_installed_packages()
		M.render_results()
	else
		vim.notify(
			string.format("Failed to remove package %s:\n%s", package_name, table.concat(result, "\n")),
			vim.log.levels.ERROR
		)
	end
end

-- Function to handle x press
function M.handle_x_press()
	local line = vim.api.nvim_win_get_cursor(0)[1]

	-- Calculate the number of lines in the installed packages section
	local installed_count = vim.tbl_count(M.state.installed_packages)
	local installed_section_start = 2 -- 1 for header + 1 for first package line
	local installed_section_end = installed_count + 1 -- +1 for header

	if installed_count == 0 then
		installed_section_end = installed_section_end + 1 -- +1 for "No packages installed" message
	end

	-- Check if we're in the installed packages section
	if line >= installed_section_start and line <= installed_section_end then
		-- Get the package from the current line
		local current_line = vim.api.nvim_buf_get_lines(M.state.popup_bufnr, line - 1, line, false)[1]
		local package_name = string.match(current_line, "%[x%] ([^%(]+)")
		if package_name then
			package_name = string.gsub(package_name, "^%s*(.-)%s*$", "%1") -- trim whitespace
			-- Confirm before removing
			vim.ui.input({
				prompt = string.format("Remove package '%s'? (y/n): ", package_name),
			}, function(input)
				if input and string.lower(input) == "y" then
					M.remove_package(package_name)
				end
			end)
		end
	end
end

-- Setup function for the plugin
function M.setup()
	vim.api.nvim_create_user_command("NugetPackage", M.open_package_search, {})
end

return M
