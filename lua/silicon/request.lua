local utils = require("silicon.utils")
local Job = require("plenary.job")
local fmt = string.format
local Args = require("silicon.args")

local CAN_COPY_WAYLAND = vim.fn.executable("wl-copy") and os.getenv("WAYLAND_DISPLAY") ~= nil
local CAN_COPY_X11 = vim.fn.executable("xclip") and os.getenv("DISPLAY") ~= nil

local request = {
	placeholder_image_name = "/tmp/SILICON_${year}-${month}-${date}_${time}.png",
	default_themes = {
		"1337",
		"Coldark-Cold",
		"Coldark-Dark",
		"DarkNeon",
		"Dracula",
		"GitHub",
		"Monokai Extended",
		"Monokai Extended Bright",
		"Monokai Extended Light",
		"Monokai Extended Origin",
		"Nord",
		"OneHalfDark",
		"OneHalfLight",
		"Solarized (dark)",
		"Solarized (light)",
		"Sublime Snazzy",
		"TwoDark",
		"Visual Studio Dark+",
		"ansi",
		"base16",
		"base16-256",
	},
	opts = require("silicon.config").opts,
	args = Args,
}

---@param lines string[]
function request:clean_lines(lines)
	if not self.opts.gobble then
		return lines
	end

	local whitespace = nil
	local current_whitespace = nil

	-- Get least leading whitespace
	for idx = 1, #lines do
		lines[idx] = lines[idx]:gsub("\t", string.rep(" ", vim.bo.tabstop))
		current_whitespace = string.len(string.match(lines[idx], "^[\r\n\t\f\v ]*") or "")
		whitespace = current_whitespace < (whitespace or current_whitespace + 1) and current_whitespace or whitespace
	end

	-- Now remove whitespace
	for idx = 1, #lines do
		lines[idx] = lines[idx]:gsub("^" .. string.rep(" ", whitespace), "")
	end

	return lines
end

function request:build_theme()
	if vim.tbl_contains(self.default_themes, self.opts.theme) then
		return
	end

	if string.lower(self.opts.theme) ~= "auto" then
		return
	end

	local curr_ver = vim.version.parse(utils._os_capture("silicon --version"))
	local wanted_ver = vim.version.parse("0.5.0")
	if not vim.version.gt(curr_ver, wanted_ver) then
		vim.notify("silicon v0.5.1 is required for automagically creating theme", vim.log.levels.ERROR)
		return
	end

	-- This ensures a few things:
	--  1. If the theme needs to be created, give it the right name.
	--  2. Store the new name in the options theme variable
	--  3. Set the argument.
	--   	a. If the argument has already been set, this will overwrite it with the correct name.
	--   	b. If the argument hasn't been set yet, it will set correctly later because of the theme name being updated.
	self.opts.theme = vim.g.colors_name .. "_" .. vim.o.background
	self.args:set("--theme", self.opts.theme)

	if utils._exists(utils.themes_path) ~= true then
		os.execute(fmt("mkdir -p %s %s", utils.themes_path, utils.syntaxes_path))
	end

	if vim.tbl_contains(utils._installed_colorschemes(), fmt("%s.tmTheme", self.opts.theme)) then
		return
	end

	utils.build_tmTheme()
	utils.reload_silicon_cache({ async = false })
end

function request:build_args()
	local opts = self.opts
	local args = self.args

	args:set("--font", opts.font)
	args:set("--language", vim.bo.filetype)
	args:set("--line-offset", opts.lineOffset)
	args:set("--line-pad", opts.linePad)
	args:set("--pad-horiz", opts.padHoriz)
	args:set("--pad-vert", opts.padVert)
	args:set("--shadow-blur-radius", opts.shadowBlurRadius)
	args:set("--shadow-color", opts.shadowColor)
	args:set("--shadow-offset-x", opts.shadowOffsetX)
	args:set("--shadow-offset-y", opts.shadowOffsetY)
	args:set("--theme", opts.theme)

	if not opts.roundCorner then
		args:set("--no-round-corner")
	end

	if not opts.lineNumber then
		args:set("--no-line-number")
	end

	if not opts.windowControls then
		args:set("--no-window-controls")
	else
		if opts.windowTitle ~= nil then
			local title = nil
			if type(opts.windowTitle) == "function" then
				title = opts.windowTitle()
			elseif type(opts.windowTitle) == "number" or type(opts.windowTitle) == "string" then
				title = opts.windowTitle
			end

			if title ~= nil then
				args:set("--window-title", title)
			end
		end
	end

	if #opts.bgImage ~= 0 then
		args:set("--background-image", opts.bgImage)
	else
		args:set("--background", opts.bgColor)
	end

	return args
end

request.exec = function(range, show_buffer, copy_to_board)
	local args = request.args
	local opts = request.opts

	args:reset()

	local stdin = nil

	table.sort(range)
	local starting, ending = unpack(range)
	starting = starting - 1

	request:build_args()
	request:build_theme()

	if show_buffer then
		local fname = vim.api.nvim_buf_get_name(0)
		args:set(1, fname)
		args:set("--highlight-lines", fmt("%s-%s", starting + 1, ending))
	else
		stdin = table.concat(request:clean_lines(vim.api.nvim_buf_get_lines(0, starting, ending, true)), "\n")
	end

	opts.output = utils._replace_placeholders(opts.output)

	if copy_to_board and CAN_COPY_WAYLAND then
		-- Save output to /tmp then copy from there
		opts.output = request.placeholder_image_name
		args:set("--output", request.placeholder_image_name)
	elseif copy_to_board and CAN_COPY_X11 then
		args:set("--to-clipboard")
	else
		args:set("--output", opts.output)
	end

	if opts.debug then
		print(vim.inspect({ msg = "args", args = args:collection() }))
	end

	Job:new({
		command = "silicon",
		args = args:collection(),
		on_exit = function(_, code)
			if code ~= 0 then
				return vim.notify(
					"Some error occured while executing silicon",
					vim.log.levels.ERROR,
					{ plugin = "silicon.lua" }
				)
			end

			local msg = ""

			if copy_to_board and (CAN_COPY_WAYLAND or CAN_COPY_X11) then
				msg = "Snapped to clipboard"

				if CAN_COPY_WAYLAND then
					vim.api.nvim_exec2(fmt("silent !cat %s | wl-copy", opts.output), { output = false })
				end
			else
				msg = fmt("Snap saved to %s", opts.output)
			end

			vim.notify(msg, vim.log.levels.INFO, { plugin = "silicon.lua" })
		end,
		on_stderr = function(_, data)
			if opts.debug then
				print(vim.inspect({ msg = "error", data = data }))
			end
		end,
		writer = stdin,
		cwd = vim.fn.getcwd(),
	}):start()
end

return request
