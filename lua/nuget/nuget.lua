local curl = require("plenary.curl")

local M = {}
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

return M
