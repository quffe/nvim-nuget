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

return M
