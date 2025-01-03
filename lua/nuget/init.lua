-- nuget-package-manager/lua/nuget-package-manager/init.lua

local M = {}

-- Dependencies
local curl = require("plenary.curl")
local popup = require("plenary.popup")
local ui = require("nuget.ui")

M.make_line = ui.make_line
local center_text = ui.center_text
local tbl_indexof = ui.tbl_indexof

-- function to show help
function M.show_help()
	local help_lines = {
		"Nuget Package Manager Help",
		"------------------------",
		"",
		"Available Commands:",
		"  <C-f>    Search for packages",
		"  <space>  Toggle package in installation queue",
		"  x        Remove installed package (when cursor is on installed package)",
		"  I        Install all packages in queue",
		"  q        Close window",
		"  g?       Toggle this help",
		"",
		"Press any key to close help",
	}

	-- Create help buffer and window
	local help_buf = vim.api.nvim_create_buf(false, true)
	local width = 60
	local height = #help_lines
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local help_win = vim.api.nvim_open_win(help_buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
	})

	-- Set help buffer content
	vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)

	-- Set help highlighting
	vim.api.nvim_buf_add_highlight(help_buf, -1, "Title", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(help_buf, -1, "Special", 1, 0, -1)

	for i = 3, #help_lines do
		if help_lines[i]:match("^  %S+%s+") then
			-- Highlight command
			local cmd_end = help_lines[i]:find("%s%s")
			vim.api.nvim_buf_add_highlight(help_buf, -1, "Statement", i, 2, cmd_end)
			-- Highlight description
			vim.api.nvim_buf_add_highlight(help_buf, -1, "Comment", i, cmd_end, -1)
		end
	end

	-- Set buffer local options
	vim.api.nvim_buf_set_option(help_buf, "bufhidden", "wipe")

	-- Map all keys to close the help buffer
	local function close_help()
		if vim.api.nvim_win_is_valid(help_win) then
			vim.api.nvim_win_close(help_win, true)
		end
	end

	-- Map any printable character to close help
	for i = 32, 126 do
		vim.keymap.set("n", string.char(i), close_help, { buffer = help_buf, silent = true })
	end

	-- Map special keys
	local special_keys = { "<CR>", "<Space>", "<Esc>", "q" }
	for _, key in ipairs(special_keys) do
		vim.keymap.set("n", key, close_help, { buffer = help_buf, silent = true })
	end

	-- Auto-close on buffer leave
	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		buffer = help_buf,
		callback = close_help,
		once = true,
	})
end

-- Function to find csproj to get current
function M.find_csproj()
	-- Use vim.fn.glob to find .csproj files in current directory
	local files = vim.fn.glob("*.csproj")
	if files == "" then
		return nil
	end
	-- Return the first .csproj found
	return vim.split(files, "\n")[1]
end

function M.read_installed_packages()
	local csproj_file = M.find_csproj()
	if not csproj_file then
		return {}
	end

	local content = vim.fn.readfile(csproj_file)
	if not content then
		return {}
	end

	local packages = {}
	for _, line in ipairs(content) do
		-- Look for PackageReference lines
		local package_name = string.match(line, 'PackageReference%s+Include="([^"]+)"')
		local version = string.match(line, 'Version="([^"]+)"')
		if package_name and version then
			packages[package_name] = version
		end
	end

	return packages
end

-- Function to query Nuget packages
function M.query_packages(query)
	local url = string.format("https://azuresearch-usnc.nuget.org/query?q=%s&take=20", query)

	local response = curl.get({
		url = url,
		accept = "application/json",
	})

	if response.status ~= 200 then
		vim.notify("Failed to fetch packages", vim.log.levels.ERROR)
		return {}
	end

	local data = vim.fn.json_decode(response.body)
	return data.data or {}
end

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
		vim.api.nvim_buf_set_option(M.state.popup_bufnr, "buftype", "nofile")
		vim.api.nvim_buf_set_option(M.state.popup_bufnr, "swapfile", false)
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
	vim.api.nvim_buf_set_option(M.state.popup_bufnr, "modifiable", true)

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

	vim.api.nvim_buf_set_option(M.state.popup_bufnr, "modifiable", false)
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

	vim.api.nvim_buf_set_option(M.state.popup_bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(M.state.popup_bufnr, "buftype", "nofile")

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
