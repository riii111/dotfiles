-- Positions are { row, col } with a 0-based row and a 0-based byte column, the gap before that byte.
-- Each function returns the target position, or nil when there is nowhere to go.
local M = {}

local function line(buf, row)
	return vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]
end

local function last_row(buf)
	return vim.api.nvim_buf_line_count(buf) - 1
end

-- charidx()/byteidx() step over a character with its composing characters the way `l` and `h` do
local function next_boundary(text, col)
	return vim.fn.byteidx(text, vim.fn.charidx(text, col) + 1)
end

local function previous_boundary(text, col)
	local index = vim.fn.charidx(text, col)
	local start = vim.fn.byteidx(text, index)
	return start < col and start or vim.fn.byteidx(text, index - 1)
end

-- charclass() is 2 or more for the characters 'iskeyword' (or the Unicode class of a wide character) makes a word
local function is_word(text, col)
	return vim.fn.charclass(text:sub(col + 1)) >= 2
end

local function moved(from, row, col)
	if row == from[1] and col == from[2] then
		return nil
	end
	return { row, col }
end

function M.forward_char(buf, pos)
	local text = line(buf, pos[1])
	if pos[2] < #text then
		return { pos[1], next_boundary(text, pos[2]) }
	elseif pos[1] < last_row(buf) then
		return { pos[1] + 1, 0 }
	end
end

function M.backward_char(buf, pos)
	if pos[2] > 0 then
		return { pos[1], previous_boundary(line(buf, pos[1]), pos[2]) }
	elseif pos[1] > 0 then
		return { pos[1] - 1, #line(buf, pos[1] - 1) }
	end
end

function M.line_start(_, pos)
	return moved(pos, pos[1], 0)
end

function M.line_end(buf, pos)
	return moved(pos, pos[1], #line(buf, pos[1]))
end

function M.buffer_start(_, pos)
	return moved(pos, 0, 0)
end

function M.buffer_end(buf, pos)
	local row = last_row(buf)
	return moved(pos, row, #line(buf, row))
end

-- Skips what is not a word, line breaks included, then the word: the gap after the end of the next word.
function M.forward_word(buf, pos)
	local last = last_row(buf)
	local row, col = pos[1], pos[2]
	local text = line(buf, row)
	local in_word = false
	while true do
		if col >= #text then
			if in_word or row == last then
				break
			end
			row, col = row + 1, 0
			text = line(buf, row)
		else
			if is_word(text, col) then
				in_word = true
			elseif in_word then
				break
			end
			col = next_boundary(text, col)
		end
	end
	return moved(pos, row, col)
end

function M.backward_word(buf, pos)
	local row, col = pos[1], pos[2]
	local text = line(buf, row)
	local in_word = false
	while true do
		if col == 0 then
			if in_word or row == 0 then
				break
			end
			row = row - 1
			text = line(buf, row)
			col = #text
		else
			local start = previous_boundary(text, col)
			if is_word(text, start) then
				in_word = true
			elseif in_word then
				break
			end
			col = start
		end
	end
	return moved(pos, row, col)
end

-- Up to the line break, or the line break itself when only blanks are left before it.
function M.kill_line_end(buf, pos)
	local text = line(buf, pos[1])
	if text:sub(pos[2] + 1):find("^[ \t]*$") and pos[1] < last_row(buf) then
		return { pos[1] + 1, 0 }
	end
	return M.line_end(buf, pos)
end

return M
