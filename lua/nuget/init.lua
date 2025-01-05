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
M.fetch_package_versions = nuget.fetch_package_versions

-- State variables
M.state = {
	current_results = {},
	installation_queue = {},
	popup_win_id = nil,
	popup_bufnr = nil,
	search_input = "",
	installed_packages = {},
	installation_outputs = {},
	selected_versions = {},
	available_versions = {},
	unfiltered_results = {},
}

-- Function to close the popup
function M.close_popup()
	if M.state.popup_win_id and vim.api.nvim_win_is_valid(M.state.popup_win_id) then
		vim.api.nvim_win_close(M.state.popup_win_id, true)
	end
	M.state.popup_win_id = nil
	M.state.popup_bufnr = nil
end

-- Function to initialize buffer
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
	M.render_results()

	-- Immediately focus on search input on initialization
	M.focus_search_input()
end

-- Function to filter out installed packages from search results
function M.filter_search_results(results)
	local filtered_results = {}

	for _, package in ipairs(results) do
		-- Only include package if it's not already installed
		if not M.state.installed_packages[package.id] then
			table.insert(filtered_results, package)
		end
	end

	return filtered_results
end

-- Function to focus search input
function M.focus_search_input()
	vim.ui.input({
		prompt = "Search Nuget Packages: ",
		default = M.state.search_input,
	}, function(input)
		if input then
			M.state.search_input = input
			-- Get search results and filter out installed packages
			local all_results = M.query_packages(input)
			M.state.unfiltered_results = all_results
			M.state.current_results = M.filter_search_results(all_results)
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

	-- Clear previous installation outputs
	M.state.installation_outputs = {}

	local completed_installations = 0
	local total_installations = #M.state.installation_queue
	local successful_packages = {}
	local failed_packages = {}

	-- Function to update the output for a package (now only keeps latest line)
	local function update_package_output(package, new_line, is_final)
		vim.schedule(function()
			if M.state.popup_bufnr and vim.api.nvim_buf_is_valid(M.state.popup_bufnr) then
				M.state.installation_outputs[package] = new_line
				M.render_results()

				-- If this is the final message, schedule its removal
				if is_final then
					vim.defer_fn(function()
						M.state.installation_outputs[package] = nil
						M.render_results()
					end, 2000) -- Remove after 2 seconds
				end
			end
		end)
	end

	for _, package in ipairs(M.state.installation_queue) do
		update_package_output(package, "Starting installation...")

		local Job = require("plenary.job")

		Job:new({
			command = "dotnet",
			args = { "add", "package", package },
			on_stdout = vim.schedule_wrap(function(_, line)
				if line and line ~= "" then
					update_package_output(package, line)
				end
			end),
			on_stderr = vim.schedule_wrap(function(_, line)
				if line and line ~= "" then
					update_package_output(package, "Error: " .. line)
				end
			end),
			on_exit = vim.schedule_wrap(function(j, code)
				completed_installations = completed_installations + 1

				if code == 0 then
					table.insert(successful_packages, package)
					update_package_output(
						package,
						"Installation completed successfully!",
						true -- Mark as final message
					)
				else
					table.insert(
						failed_packages,
						{ package = package, error = j:stderr_result()[1] or "Unknown error" }
					)
					update_package_output(
						package,
						"Installation failed with code " .. code,
						true -- Mark as final message
					)
				end

				if completed_installations == total_installations then
					vim.schedule(function()
						if M.state.popup_bufnr and vim.api.nvim_buf_is_valid(M.state.popup_bufnr) then
							-- Show notifications
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

							-- Update final state
							vim.defer_fn(function()
								M.state.current_results = M.filter_search_results(M.state.unfiltered_results)
								M.state.installed_packages = M.read_installed_packages()
								M.state.installation_queue = {}
								M.state.installation_outputs = {} -- Clear all outputs
								M.render_results()
							end, 2000)
						end
					end)
				end
			end),
		}):start()
	end
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
		M.state.current_results = M.filter_search_results(M.state.unfiltered_results)
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
	local installed_section_start = 3 -- account for header and empty line
	local installed_section_end = installed_section_start + installed_count

	if installed_count == 0 then
		installed_section_end = installed_section_end + 1 -- +1 for "No packages installed" message
	end

	-- Check if we're in the installed packages section
	if line >= installed_section_start and line <= installed_section_end then
		-- Get the package from the current line
		local current_line = vim.api.nvim_buf_get_lines(M.state.popup_bufnr, line - 1, line, false)[1]
		-- Updated pattern to match new format: "  󰡖 package_name (version)"
		local package_name = string.match(current_line, "%s*󰡖%s+([^%(]+)")
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

-- Function to show version selection
function M.show_version_selection(package_id, current_version, callback)
	if not M.state.available_versions[package_id] then
		-- Show loading message
		vim.notify("Fetching versions for " .. package_id .. "...", vim.log.levels.INFO)

		M.fetch_package_versions(package_id, function(versions)
			M.state.available_versions[package_id] = versions
			M._display_version_selection(package_id, current_version, callback)
		end)
	else
		M._display_version_selection(package_id, current_version, callback)
	end
end

-- Internal function to display version selection
function M._display_version_selection(package_id, current_version, callback)
	local versions = M.state.available_versions[package_id] or {}
	if #versions == 0 then
		vim.notify("No versions found for " .. package_id, vim.log.levels.WARN)
		return
	end

	-- Sort versions in descending order (newest first)
	table.sort(versions, function(a, b)
		-- Simple version comparison (you might want to implement a more robust one)
		return a > b
	end)

	-- Create selection list
	local selection_list = {}
	for _, version in ipairs(versions) do
		local prefix = version == current_version and "* " or "  "
		table.insert(selection_list, prefix .. version)
	end

	vim.ui.select(selection_list, {
		prompt = string.format("Select version for %s (current: %s):", package_id, current_version or "none"),
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if choice then
			-- Extract version from choice (remove prefix if present)
			local selected_version = choice:gsub("^%*%s", ""):gsub("^%s%s", "")
			M.state.selected_versions[package_id] = selected_version
			if callback then
				callback(selected_version)
			end
			M.render_results()
		end
	end)
end

-- Function to toggle package in queue (fix space key)
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
				-- Simply add to queue with default version
				table.insert(M.state.installation_queue, package.id)
				M.state.selected_versions[package.id] = package.version
			else
				-- Remove from queue and clean up selected version
				table.remove(M.state.installation_queue, index)
				M.state.selected_versions[package.id] = nil
			end
			M.render_results()
		end
	end
end

-- function to render display
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
	add_line_with_highlights(M.make_line({
		{ "Currently Installed Packages: ", "Title" },
		{ "(press x to remove, v to change version)", "Comment" },
	}))

	local installed = M.state.installed_packages
	if vim.tbl_count(installed) == 0 then
		add_line_with_highlights(M.make_line({ { "  No packages installed", "Comment" } }))
	else
		for package, version in pairs(installed) do
			local selected_version = M.state.selected_versions[package]
			local version_display = selected_version and (version .. " → " .. selected_version) or version
			add_line_with_highlights(M.make_line({
				{ "  ", nil },
				{ "󰡖 ", "Statement" },
				{ package, "Function" },
				{ " (", nil },
				{ version_display, "String" },
				{ ")", nil },
			}))

			-- Show installation/update output if any
			if M.state.installation_outputs[package] then
				add_line_with_highlights(M.make_line({
					{ "      " .. M.state.installation_outputs[package], "Comment" },
				}))
			end
		end
	end
	add_line_with_highlights(M.make_line({ { "", nil } }))
	add_line_with_highlights(M.make_line({ { "Installation Queue:", "Title" } }))

	if #M.state.installation_queue == 0 then
		add_line_with_highlights(M.make_line({ { "  No packages queued for installation", "Comment" } }))
	else
		for _, package in ipairs(M.state.installation_queue) do
			local selected_version = M.state.selected_versions[package]
			local version_text = selected_version and (" @ " .. selected_version) or ""

			-- Add the package name with version
			add_line_with_highlights(M.make_line({
				{ "  - ", nil },
				{ package, "Special" },
				{ version_text, "String" },
			}))

			-- Show installation output if any
			if M.state.installation_outputs[package] then
				add_line_with_highlights(M.make_line({
					{ "      " .. M.state.installation_outputs[package], "Comment" },
				}))
			end
		end
	end

	-- Add separator
	add_line_with_highlights(M.make_line({ { "", nil } }))
	add_line_with_highlights(M.make_line({ { "Search Results:", "Title" } }))

	-- Add search results with version information
	if #M.state.current_results == 0 then
		add_line_with_highlights(M.make_line({ { "  No packages found", "Comment" } }))
	else
		for _, package in ipairs(M.state.current_results) do
			local queued = tbl_indexof(M.state.installation_queue, package.id) ~= -1
			local prefix = queued and "󰡖 " or "󰄱 "
			local version_display = M.state.selected_versions[package.id] or package.version
			add_line_with_highlights(M.make_line({
				{ prefix, "Statement" },
				{ package.id, "Function" },
				{ " (", nil },
				{ version_display, "String" },
				{ ")", nil },
				{ queued and " [Queued]" or "", "Comment" },
			}))
		end
	end

	-- Make buffer modifiable temporarily
	vim.api.nvim_set_option_value("modifiable", true, { buf = M.state.popup_bufnr })
	vim.api.nvim_buf_set_lines(M.state.popup_bufnr, 0, -1, false, display_lines)

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
        nnoremap <buffer> v <Cmd>lua require('nuget').handle_version_select()<CR>
    ]])
end

-- Add handle_version_select function with proper package detection
function M.handle_version_select()
	local line = vim.api.nvim_win_get_cursor(0)[1]

	-- Calculate section boundaries
	local installed_section_start = 3 -- Header and empty line
	local installed_count = vim.tbl_count(M.state.installed_packages)
	local installed_section_end = installed_section_start + installed_count
	if installed_count == 0 then
		installed_section_end = installed_section_end + 1 -- "No packages installed" message
	end

	-- Calculate queue section boundaries
	local queue_section_start = installed_section_end + 2 -- Empty line and "Installation Queue:" header
	local queue_section_end = queue_section_start + #M.state.installation_queue
	if #M.state.installation_queue == 0 then
		queue_section_end = queue_section_end + 1 -- "No packages queued" message
	end

	-- Handle installed packages section
	if line >= installed_section_start and line <= installed_section_end then
		local current_line = vim.api.nvim_buf_get_lines(M.state.popup_bufnr, line - 1, line, false)[1]
		local package_name = string.match(current_line, "%s*󰡖%s+([^%(]+)")
		if package_name then
			package_name = string.gsub(package_name, "^%s*(.-)%s*$", "%1") -- trim whitespace
			local current_version = M.state.installed_packages[package_name]
			M.show_version_selection(package_name, current_version, function(selected_version)
				if selected_version and selected_version ~= current_version then
					M.update_package(package_name, selected_version):start()
				end
			end)
		end
	-- Handle queue section
	elseif line >= queue_section_start and line <= queue_section_end then
		local current_line = vim.api.nvim_buf_get_lines(M.state.popup_bufnr, line - 1, line, false)[1]
		local package_name = string.match(current_line, "%s*%-%s*([^%s@]+)")
		if package_name then
			local current_version = M.state.selected_versions[package_name]
			M.show_version_selection(package_name, current_version, function(selected_version)
				if selected_version then
					M.state.selected_versions[package_name] = selected_version
					M.render_results()
				end
			end)
		end
	end
end

-- Function to update installed package
function M.update_package(package_name, new_version)
	local Job = require("plenary.job")

	-- Initialize or clear the package output
	M.state.installation_outputs[package_name] = "Starting update..."
	M.render_results()

	return Job:new({
		command = "dotnet",
		args = { "add", "package", package_name, "--version", new_version },
		on_stdout = vim.schedule_wrap(function(_, line)
			if line and line ~= "" then
				M.state.installation_outputs[package_name] = line
				M.render_results()
			end
		end),
		on_stderr = vim.schedule_wrap(function(_, line)
			if line and line ~= "" then
				M.state.installation_outputs[package_name] = "Error: " .. line
				M.render_results()
			end
		end),
		on_exit = vim.schedule_wrap(function(_, code)
			if code == 0 then
				-- Update was successful
				M.state.installation_outputs[package_name] = "Update completed successfully!"
				M.render_results()

				-- Schedule cleanup
				vim.defer_fn(function()
					M.state.installed_packages = M.read_installed_packages()
					M.state.selected_versions[package_name] = nil -- Clear selected version
					M.state.installation_outputs[package_name] = nil -- Clear the output
					M.render_results()
				end, 2000) -- Clear after 2 seconds, just like package installation
			else
				M.state.installation_outputs[package_name] = "Update failed!"
				M.render_results()

				-- Schedule cleanup of error message
				vim.defer_fn(function()
					M.state.installation_outputs[package_name] = nil
					M.render_results()
				end, 2000)
			end
		end),
	})
end

function M.setup()
	vim.api.nvim_create_user_command("NugetPackage", M.open_package_search, {})
end

return M
