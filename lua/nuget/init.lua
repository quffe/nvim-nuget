-- nuget-package-manager/lua/nuget-package-manager/init.lua

local M = {}

-- Dependencies
local curl = require("plenary.curl")
local popup = require("plenary.popup")

-- Custom implementation of tbl_indexof
local function tbl_indexof(tbl, val)
	for k, v in ipairs(tbl) do
		if v == val then
			return k
		end
	end
	return -1
end

-- State variables
M.state = {
	current_results = {},
	installation_queue = {},
	popup_win_id = nil,
	search_input = "",
}

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

-- Function to render package results
function M.render_results()
	if not M.state.popup_win_id or not vim.api.nvim_win_is_valid(M.state.popup_win_id) then
		return
	end

	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
	vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

	local display_lines = {}
	for i, package in ipairs(M.state.current_results) do
		local queued = false
		for _, queued_package in ipairs(M.state.installation_queue) do
			if queued_package == package.id then
				queued = true
				break
			end
		end

		local prefix = queued and "[X] " or "[ ] "
		table.insert(display_lines, string.format("%s%s (%s)", prefix, package.id, package.version))
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, display_lines)

	-- Set key mappings for the results buffer
	vim.api.nvim_buf_set_keymap(
		bufnr,
		"n",
		"<space>",
		':lua require("nuget").toggle_package_queue()<CR>',
		{ noremap = true, silent = true }
	)

	vim.api.nvim_win_set_buf(M.state.popup_win_id, bufnr)
end

-- Function to toggle package in installation queue
function M.toggle_package_queue()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local package = M.state.current_results[line]

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

-- Function to open search popup
function M.open_package_search()
	-- Create popup window
	local width = 80
	local height = 20
	local popup_opts = {
		title = "Nuget Package Search",
		border = true,
		minwidth = width,
		minheight = height,
	}

	M.state.popup_win_id = popup.create("", popup_opts)
	local bufnr = vim.api.nvim_win_get_buf(M.state.popup_win_id)

	-- Set up input for package search
	vim.api.nvim_buf_set_keymap(
		bufnr,
		"n",
		"<C-f>",
		':lua require("nuget").focus_search_input()<CR>',
		{ noremap = true, silent = true }
	)

	vim.api.nvim_buf_set_keymap(
		bufnr,
		"n",
		"I",
		':lua require("nuget").install_queued_packages()<CR>',
		{ noremap = true, silent = true }
	)
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

	local packages_str = table.concat(M.state.installation_queue, " ")
	local cmd = string.format("dotnet add package %s", packages_str)

	vim.fn.jobstart(cmd, {
		on_exit = function(_, code)
			if code == 0 then
				vim.notify(string.format("Installed %d packages", #M.state.installation_queue), vim.log.levels.INFO)
				M.state.installation_queue = {}
				M.render_results()
			else
				vim.notify("Failed to install packages", vim.log.levels.ERROR)
			end
		end,
	})
end

-- Setup function for the plugin
function M.setup()
	vim.api.nvim_create_user_command("NugetPackage", M.open_package_search, {})
end

return M
