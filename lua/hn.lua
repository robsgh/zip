local hn_url = "https://news.ycombinator.com/"
local hn_search_url = "https://hn.algolia.com/?q="

function REDIRECT(tbl)
	local query_str = ""
	for _, token in ipairs(tbl) do
		query_str = query_str .. "+" .. token
	end

	if query_str:len() > 0 then
		return hn_search_url .. query_str
	end
	return hn_url
end
