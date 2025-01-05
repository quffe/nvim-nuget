local M = {}

-- create lines with different HL groups
function M.make_line(segments)
	local line = ""
	local highlights = {}
	local current_col = 0

	for _, segment in ipairs(segments) do
		local text = segment[1] or "" -- Default to empty string if nil
		local hl_group = segment[2]

		-- Skip empty segments
		if text == "" then
		  goto continue
		end
		--
		line = line .. text
		--
		if hl_group then
			table.insert(highlights, {
				hl_group = hl_group,
				col_start = current_col, -- Changed from start_col to match your existing code
				col_end = current_col + #text, -- Changed from end_col to match your existing code
			})
		end
		--
		current_col = current_col + #text
		--
		::continue::
	end
	--
	return {
		line = line,
		highlights = highlights,
	}
end

-- center text on line
function M.center_text (text)
	local padding = math.max(0, math.floor((80 - #text) / 2))
	return string.rep(" ", padding) .. text .. string.rep(" ", 80 - #text - padding)
end

-- Custom implementation of tbl_indexof
function M.tbl_indexof(tbl, val)
	for k, v in ipairs(tbl) do
		if v == val then
			return k
		end
	end
	return -1
end

-- function to show help
function M.show_help()
	local help_lines = {
		"Nuget Package Manager Help",
		"-------------------------------------------------------------------------",
		"",
		"Available Commands:",
		"  <C-f>    Search for packages",
		"  <space>  Toggle package in installation queue",
		"  x        Remove installed package (when cursor is on installed package)",
		"  I        Install all packages in queue",
		"  q        Close window",
		"  g?       Toggle this help",
    "  v        Change Version of installed or queued package",
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
      if cmd_end ~= nil then
        vim.api.nvim_buf_add_highlight(help_buf, -1, "Statement", i, 2, cmd_end)
        -- Highlight description
        vim.api.nvim_buf_add_highlight(help_buf, -1, "Comment", i, cmd_end, -1)
      end
		end
	end

	-- Set buffer local options
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = help_buf })

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

return M
