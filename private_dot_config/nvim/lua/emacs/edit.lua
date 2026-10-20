-- Text changes through the buffer API, so no register, mark or 'clipboard' setting is involved.
local M = {}

-- the last killed text, shared by all buffers and kept after the mode ends
local killed

local function set_cursor(pos)
	vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
end

-- Deletes the text between two positions (in either order), leaves the cursor there and returns the text.
function M.delete(from, to)
	if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
		from, to = to, from
	end
	local lines = vim.api.nvim_buf_get_text(0, from[1], from[2], to[1], to[2], {})
	vim.api.nvim_buf_set_text(0, from[1], from[2], to[1], to[2], {})
	set_cursor(from)
	return table.concat(lines, "\n")
end

-- Inserts text at a position and leaves the cursor after it.
function M.insert(pos, text)
	local lines = vim.split(text, "\n", { plain = true })
	vim.api.nvim_buf_set_text(0, pos[1], pos[2], pos[1], pos[2], lines)
	local row = pos[1] + #lines - 1
	set_cursor({ row, (#lines == 1 and pos[2] or 0) + #lines[#lines] })
end

function M.set_cursor(pos)
	set_cursor(pos)
end

-- how: "replace" starts over, "append" and "prepend" join a kill that continues the previous one
function M.store(text, how)
	if how == "append" then
		killed = (killed or "") .. text
	elseif how == "prepend" then
		killed = text .. (killed or "")
	else
		killed = text
	end
end

function M.killed()
	return killed
end

return M
