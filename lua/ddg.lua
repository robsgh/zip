local ddg_url = "https://duckduckgo.com/"

function REDIRECT(tbl)
	local query_str = ""

	for _, token in ipairs(tbl) do
		query_str = query_str .. "+" .. token
	end

	if query_str:len() > 0 then
		return ddg_url .. "?q=" .. query_str
	end
	return ddg_url
end
