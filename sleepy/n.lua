--[[
	Basit UI (ScreenGui tabanlı)
	- Drawing API, getrawmetatable, newcclosure, identifyexecutor GEREKTİRMEZ.
	- Eski kütüphaneyle AYNI API: library:Load{} -> :Tab() -> :Section{} ->
	  Toggle / Slider / Dropdown / List / Button / Box / ColorPicker / Keybind / Label / Separator
	- Mobil executorlar için sağ üstte açma/kapama butonu vardır. PC'de RightShift ile de açılır.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

----------------------------------------------------------------------
-- Yardımcılar
----------------------------------------------------------------------
local function clone(t)
	local n = {}
	for k, v in pairs(t) do n[k] = v end
	return n
end

-- opsiyon anahtarlarını küçük harfe çevirir (eski kütüphanedeki gibi büyük/küçük harf fark etmez)
local function norm(t)
	if type(t) == "string" then return { name = t } end
	local n = {}
	for k, v in pairs(t or {}) do
		n[type(k) == "string" and k:lower() or k] = v
	end
	return n
end

local function safe(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("[UI] callback hatası: " .. tostring(err)) end
end

local totalflags = 0
local function nextflag()
	totalflags = totalflags + 1
	return "flag_" .. totalflags
end

local FONT = Enum.Font.SourceSans

-- metod isimlerinde büyük/küçük harf farkını tolere eden tablo (eski kütüphanedeki gibi)
local function ci(t)
	return setmetatable(t, {
		__index = function(tbl, k)
			if type(k) == "string" then
				local lk = k:lower()
				for key, v in pairs(tbl) do
					if type(key) == "string" and key:lower() == lk then return v end
				end
			end
			return nil
		end,
	})
end

----------------------------------------------------------------------
-- Temalar
----------------------------------------------------------------------
local themes = {
	Default = {
		["Accent"] = Color3.fromRGB(113, 93, 133),
		["Window Background"] = Color3.fromRGB(30, 30, 30),
		["Window Border"] = Color3.fromRGB(45, 45, 45),
		["Tab Background"] = Color3.fromRGB(20, 20, 20),
		["Tab Border"] = Color3.fromRGB(45, 45, 45),
		["Tab Toggle Background"] = Color3.fromRGB(28, 28, 28),
		["Section Background"] = Color3.fromRGB(18, 18, 18),
		["Section Border"] = Color3.fromRGB(35, 35, 35),
		["Text"] = Color3.fromRGB(200, 200, 200),
		["Disabled Text"] = Color3.fromRGB(110, 110, 110),
		["Object Background"] = Color3.fromRGB(25, 25, 25),
		["Object Border"] = Color3.fromRGB(35, 35, 35),
		["Dropdown Option Background"] = Color3.fromRGB(19, 19, 19),
	},
	Midnight = {
		["Accent"] = Color3.fromRGB(100, 59, 154),
		["Window Background"] = Color3.fromRGB(30, 30, 36),
		["Window Border"] = Color3.fromRGB(45, 45, 49),
		["Tab Background"] = Color3.fromRGB(20, 20, 24),
		["Tab Border"] = Color3.fromRGB(45, 45, 55),
		["Tab Toggle Background"] = Color3.fromRGB(28, 28, 32),
		["Section Background"] = Color3.fromRGB(18, 18, 22),
		["Section Border"] = Color3.fromRGB(35, 35, 45),
		["Text"] = Color3.fromRGB(180, 180, 190),
		["Disabled Text"] = Color3.fromRGB(100, 100, 110),
		["Object Background"] = Color3.fromRGB(25, 25, 29),
		["Object Border"] = Color3.fromRGB(35, 35, 39),
		["Dropdown Option Background"] = Color3.fromRGB(19, 19, 23),
	},
	AirHub = {
		["Accent"] = Color3.fromRGB(150, 100, 150),
		["Window Background"] = Color3.fromRGB(35, 30, 35),
		["Window Border"] = Color3.fromRGB(50, 45, 50),
		["Tab Background"] = Color3.fromRGB(25, 20, 25),
		["Tab Border"] = Color3.fromRGB(65, 45, 65),
		["Tab Toggle Background"] = Color3.fromRGB(35, 30, 35),
		["Section Background"] = Color3.fromRGB(25, 20, 25),
		["Section Border"] = Color3.fromRGB(55, 35, 55),
		["Text"] = Color3.fromRGB(200, 180, 200),
		["Disabled Text"] = Color3.fromRGB(120, 100, 120),
		["Object Background"] = Color3.fromRGB(30, 25, 30),
		["Object Border"] = Color3.fromRGB(40, 35, 40),
		["Dropdown Option Background"] = Color3.fromRGB(25, 20, 25),
	},
}

----------------------------------------------------------------------
-- Kütüphane tablosu
----------------------------------------------------------------------
local library = {
	theme = clone(themes.AirHub),
	currenttheme = "AirHub",
	folder = "AirHub V2",
	extension = "cfg",
	flags = {},
	setters = {},
	open = true,
	keybind = Enum.KeyCode.RightShift,
	connections = {},
	themed = {},
	scrollers = {},
	tabs = {},
	gui = nil,
	holder = nil,
}

-- library:load / library:Load gibi büyük/küçük harf farkını tolere et
setmetatable(library, {
	__index = function(t, k)
		if type(k) == "string" then
			local lk = k:lower()
			for key, v in pairs(t) do
				if type(key) == "string" and key:lower() == lk then return v end
			end
		end
		return nil
	end,
})

local configignores = {}
local coloralphas = {}

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(library.connections, c)
	return c
end

-- temaya bağlı özellik
local function bind(inst, prop, key)
	inst[prop] = library.theme[key]
	table.insert(library.themed, { inst = inst, prop = prop, key = key })
end

local function create(class, props, parent)
	local o = Instance.new(class)
	local t = props._t
	props._t = nil
	for k, v in pairs(props) do o[k] = v end
	if t then
		for prop, key in pairs(t) do bind(o, prop, key) end
	end
	if parent then o.Parent = parent end
	return o
end

local function listlayout(parent, padding, dir)
	return create("UIListLayout", {
		Padding = UDim.new(0, padding or 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = dir or Enum.FillDirection.Vertical,
	}, parent)
end

local function padding(parent, l, t, r, b)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0), PaddingTop = UDim.new(0, t or 0),
		PaddingRight = UDim.new(0, r or 0), PaddingBottom = UDim.new(0, b or 0),
	}, parent)
end

local function text(parent, str, size, align)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Text = str or "",
		Font = FONT,
		TextSize = size or 15,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		_t = { TextColor3 = "Text" },
	}, parent)
end

local function applytheme()
	for i = #library.themed, 1, -1 do
		local e = library.themed[i]
		if e.inst.Parent == nil then
			table.remove(library.themed, i)
		else
			pcall(function() e.inst[e.prop] = library.theme[e.key] end)
		end
	end
	if library.refreshtabs then library.refreshtabs() end
end

local function lockscroll(locked)
	for _, sf in ipairs(library.scrollers) do
		pcall(function() sf.ScrollingEnabled = not locked end)
	end
end

local function keyname(key)
	if typeof(key) == "EnumItem" then
		local n = key.Name
		if n == "MouseButton1" then return "MB1" elseif n == "MouseButton2" then return "MB2" elseif n == "MouseButton3" then return "MB3" end
		return n
	end
	return "None"
end

local function parseenum(str)
	local en, item = tostring(str):match("^Enum%.(%w+)%.(%w+)$")
	if en and item then
		local ok, v = pcall(function() return Enum[en][item] end)
		if ok then return v end
	end
	return nil
end

----------------------------------------------------------------------
-- GUI ana kapsayıcı (tüm executorlarda çalışacak şekilde)
----------------------------------------------------------------------
local function getguiparent()
	if gethui then
		local ok, h = pcall(gethui)
		if ok and h then return h end
	end
	local ok, core = pcall(function() return game:GetService("CoreGui") end)
	if ok and core then
		local test = Instance.new("ScreenGui")
		local ok2 = pcall(function() test.Parent = core end)
		local good = ok2 and test.Parent == core
		pcall(function() test:Destroy() end)
		if good then return core end
	end
	local lp = Players.LocalPlayer
	while not lp do task.wait() lp = Players.LocalPlayer end
	return lp:WaitForChild("PlayerGui")
end

local function creategui()
	local gui = Instance.new("ScreenGui")
	gui.Name = HttpService:GenerateGUID(false)
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999999
	pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
	gui.Parent = getguiparent()
	return gui
end

----------------------------------------------------------------------
-- Sürükleme
----------------------------------------------------------------------
local function draggable(handle, target)
	local dragging, startpos, startinput
	connect(handle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startinput = input.Position
			startpos = target.Position
		end
	end)
	connect(UIS.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startinput
			target.Position = UDim2.new(startpos.X.Scale, startpos.X.Offset + d.X, startpos.Y.Scale, startpos.Y.Offset + d.Y)
		end
	end)
	connect(UIS.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

----------------------------------------------------------------------
-- Bileşen oluşturucular
----------------------------------------------------------------------
local function makeslider(parent, options)
	options = norm(options)
	local name = options.name
	local min = options.min or options.minimum or 0
	local max = options.max or options.maximum or 100
	local fmt = options.text or ("[value]/" .. max)
	local float = options.float or 1
	local default = options.default and math.clamp(options.default, min, max) or min
	local flag = options.flag or nextflag()
	local callback = options.callback or function() end
	local noflag = options.noflag

	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, name and 32 or 18),
	}, parent)

	local top = name and text(holder, name, 15) or nil
	local valuelabel = create("TextLabel", {
		BackgroundTransparency = 1, Font = FONT, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0, 0),
		_t = { TextColor3 = "Disabled Text" },
	}, holder)

	local bar = create("TextButton", {
		Text = "", AutoButtonColor = false, BorderSizePixel = 1,
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 0, name and 19 or 3),
		_t = { BackgroundColor3 = "Object Background", BorderColor3 = "Object Border" },
	}, holder)
	pcall(function() bar.BorderMode = Enum.BorderMode.Inset end)

	local fill = create("Frame", {
		BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0),
		_t = { BackgroundColor3 = "Accent" },
	}, bar)

	local value = default
	local function set(v, silent)
		v = tonumber(v) or min
		v = math.clamp(v, min, max)
		v = math.floor(v / float + 0.5) * float
		v = tonumber(string.format("%.10g", v))
		v = math.clamp(v, min, max)
		value = v
		local rel = (max == min) and 0 or (v - min) / (max - min)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		valuelabel.Text = (tostring(fmt):gsub("%[value%]", tostring(v)))
		if not noflag then library.flags[flag] = v end
		if not silent then safe(callback, v) end
	end

	local dragging = false
	local function fromx(x)
		local w = bar.AbsoluteSize.X
		if w <= 0 then return end
		local rel = math.clamp((x - bar.AbsolutePosition.X) / w, 0, 1)
		set(min + (max - min) * rel)
	end

	connect(bar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			lockscroll(true)
			fromx(input.Position.X)
		end
	end)
	connect(UIS.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromx(input.Position.X)
		end
	end)
	connect(UIS.InputEnded, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			lockscroll(false)
		end
	end)

	if not noflag then library.setters[flag] = function(v) set(v) end end
	set(default)

	local types = {}
	function types:Set(v) set(v) end
	return types
end

local function makedropdown(parent, options, islist)
	options = norm(options)
	local name = options.name
	local default = options.default
	local content = type(options.content) == "table" and clone(options.content) or {}
	local max = options.max and (options.max > 1 and options.max) or nil
	local scrollable = options.scrollable
	local scrollingmax = options.scrollingmax or 10
	local flag = options.flag or nextflag()
	local callback = options.callback or function() end
	local OPT_H = 20

	if not max and type(default) == "table" then default = nil end
	if max and default == nil then default = {} end

	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	listlayout(holder, 3)

	if name then
		local t = text(holder, name, 15)
		t.LayoutOrder = 0
	end

	local head, valuelabel, arrow
	if not islist then
		head = create("TextButton", {
			Text = "", AutoButtonColor = false, BorderSizePixel = 1,
			Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1,
			_t = { BackgroundColor3 = "Object Background", BorderColor3 = "Object Border" },
		}, holder)
		pcall(function() head.BorderMode = Enum.BorderMode.Inset end)
		valuelabel = create("TextLabel", {
			BackgroundTransparency = 1, Font = FONT, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.new(0, 6, 0, 0), Size = UDim2.new(1, -24, 1, 0),
			_t = { TextColor3 = "Text" },
		}, head)
		arrow = create("TextLabel", {
			BackgroundTransparency = 1, Font = FONT, TextSize = 14, Text = "v",
			Position = UDim2.new(1, -18, 0, 0), Size = UDim2.new(0, 14, 1, 0),
			_t = { TextColor3 = "Disabled Text" },
		}, head)
	end

	local listframe
	if scrollable then
		listframe = create("ScrollingFrame", {
			BorderSizePixel = 1, ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Visible = islist and true or false,
			_t = { BackgroundColor3 = "Dropdown Option Background", BorderColor3 = "Object Border" },
		}, holder)
		pcall(function() listframe.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
		table.insert(library.scrollers, listframe)
	else
		listframe = create("Frame", {
			BorderSizePixel = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2, Visible = islist and true or false,
			_t = { BackgroundColor3 = "Dropdown Option Background", BorderColor3 = "Object Border" },
		}, holder)
	end
	pcall(function() listframe.BorderMode = Enum.BorderMode.Inset end)
	listlayout(listframe, 0)

	local chosen = max and {} or nil
	local buttons = {}
	local isopen = islist and true or false

	local function display()
		if not valuelabel then return end
		local str
		if max then
			str = (#chosen > 0) and table.concat(chosen, ", ") or nil
		else
			str = chosen
		end
		valuelabel.Text = str and tostring(str) or "NONE"
		valuelabel.TextColor3 = str and library.theme["Text"] or library.theme["Disabled Text"]
	end

	local function refreshcolors()
		for opt, b in pairs(buttons) do
			local selected
			if max then selected = table.find(chosen, opt) ~= nil else selected = (chosen == opt) end
			b.TextColor3 = selected and library.theme["Accent"] or library.theme["Text"]
		end
	end

	local function commit(silent)
		library.flags[flag] = chosen
		display()
		refreshcolors()
		if not silent then
			if max then safe(callback, clone(chosen)) else safe(callback, chosen) end
		end
	end

	local function resize()
		if scrollable then
			local n = math.min(#content, scrollingmax)
			listframe.Size = UDim2.new(1, 0, 0, n * OPT_H + 2)
		end
	end

	local function setopen(v)
		isopen = v
		if not islist then
			listframe.Visible = v
			arrow.Text = v and "^" or "v"
		end
	end

	local function rebuild()
		for _, b in pairs(buttons) do b:Destroy() end
		table.clear(buttons)
		for i, opt in ipairs(content) do
			local b = create("TextButton", {
				Text = tostring(opt), Font = FONT, TextSize = 15, AutoButtonColor = false,
				BackgroundTransparency = 1, BorderSizePixel = 0,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, OPT_H), LayoutOrder = i,
				_t = { TextColor3 = "Text" },
			}, listframe)
			padding(b, 6, 0, 0, 0)
			buttons[opt] = b
			connect(b.MouseButton1Click, function()
				if max then
					local idx = table.find(chosen, opt)
					if idx then
						table.remove(chosen, idx)
					elseif #chosen < max then
						table.insert(chosen, opt)
					end
				else
					chosen = opt
					if not islist then setopen(false) end
				end
				commit()
			end)
		end
		resize()
		refreshcolors()
	end

	local function set(option, silent)
		if max then
			chosen = {}
			if type(option) == "table" then
				for _, o in ipairs(option) do
					if table.find(content, o) and #chosen < max then table.insert(chosen, o) end
				end
			end
		else
			if option ~= nil and table.find(content, option) then chosen = option else chosen = nil end
		end
		commit(silent)
	end

	if head then
		connect(head.MouseButton1Click, function() setopen(not isopen) end)
	end

	library.setters[flag] = function(v) set(v) end
	rebuild()
	set(default)

	local types = {}
	function types:Set(option) set(option) end
	function types:Refresh(tbl)
		content = clone(tbl)
		chosen = max and {} or nil
		rebuild()
		commit()
	end
	function types:Add(option)
		table.insert(content, option)
		rebuild()
	end
	function types:Remove(option)
		local i = table.find(content, option)
		if i then table.remove(content, i) end
		if max then
			local ci = table.find(chosen, option)
			if ci then table.remove(chosen, ci) end
		elseif chosen == option then
			chosen = nil
		end
		rebuild()
		commit()
	end
	return types
end

local function makecolorpicker(holder, right, options)
	options = norm(options)
	local default = options.default or Color3.fromRGB(255, 255, 255)
	local defaultalpha = options.defaultalpha or 1
	local flag = options.flag or nextflag()
	local callback = options.callback or function() end

	local swatch = create("TextButton", {
		Text = "", AutoButtonColor = false, BorderSizePixel = 1,
		Size = UDim2.new(0, 24, 0, 14),
		_t = { BorderColor3 = "Object Border" },
	}, right)

	local panel = create("Frame", {
		BorderSizePixel = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false, LayoutOrder = 50,
		_t = { BackgroundColor3 = "Dropdown Option Background", BorderColor3 = "Object Border" },
	}, holder)
	pcall(function() panel.BorderMode = Enum.BorderMode.Inset end)
	padding(panel, 6, 4, 6, 4)
	listlayout(panel, 2)

	local r, g, b = math.floor(default.R * 255 + 0.5), math.floor(default.G * 255 + 0.5), math.floor(default.B * 255 + 0.5)
	local alpha = defaultalpha
	local updating = false

	local function apply(silent)
		local color = Color3.fromRGB(r, g, b)
		swatch.BackgroundColor3 = color
		library.flags[flag] = color
		coloralphas[flag] = alpha
		if not silent then safe(callback, color, alpha) end
	end

	local rs = makeslider(panel, { name = "Red", min = 0, max = 255, default = r, text = "[value]", noflag = true,
		callback = function(v) if not updating then r = v apply() end end })
	local gs = makeslider(panel, { name = "Green", min = 0, max = 255, default = g, text = "[value]", noflag = true,
		callback = function(v) if not updating then g = v apply() end end })
	local bs = makeslider(panel, { name = "Blue", min = 0, max = 255, default = b, text = "[value]", noflag = true,
		callback = function(v) if not updating then b = v apply() end end })
	local als = makeslider(panel, { name = "Alpha", min = 0, max = 1, float = 0.01, default = alpha, text = "[value]", noflag = true,
		callback = function(v) if not updating then alpha = v apply() end end })

	connect(swatch.MouseButton1Click, function() panel.Visible = not panel.Visible end)

	local function set(color, a)
		if typeof(color) ~= "Color3" then return end
		updating = true
		r, g, b = math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5)
		if a then alpha = a end
		rs:Set(r) gs:Set(g) bs:Set(b) als:Set(alpha)
		updating = false
		apply()
	end

	library.setters[flag] = set
	apply()

	local types = {}
	function types:Set(color, a) set(color, a) end
	function types:ColorPicker(opts) return makecolorpicker(holder, right, opts) end
	return types
end

local function makekeybind(right, options)
	options = norm(options)
	local default = options.default
	local blacklist = options.blacklist or {}
	local flag = options.flag or nextflag()
	local callback = options.callback or function() end

	local key = default
	local binding = false

	local btn = create("TextButton", {
		Font = FONT, TextSize = 14, AutoButtonColor = false, BorderSizePixel = 1,
		Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X,
		_t = { BackgroundColor3 = "Object Background", BorderColor3 = "Object Border", TextColor3 = "Disabled Text" },
	}, right)
	padding(btn, 5, 0, 5, 0)

	local function refresh()
		btn.Text = "[" .. keyname(key) .. "]"
	end

	local function set(newkey, silent)
		key = newkey
		library.flags[flag] = key
		refresh()
		if not silent then safe(callback, key, true) end
	end

	local listener
	connect(btn.MouseButton1Click, function()
		if binding then return end
		binding = true
		btn.Text = "[...]"
		task.wait(0.1)
		listener = UIS.InputBegan:Connect(function(input)
			local ut = input.UserInputType
			local newkey
			if ut == Enum.UserInputType.Keyboard then
				newkey = input.KeyCode
			elseif ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.MouseButton2 or ut == Enum.UserInputType.MouseButton3 then
				newkey = ut
			else
				return
			end
			if table.find(blacklist, newkey) then return end
			listener:Disconnect()
			listener = nil
			if newkey == Enum.KeyCode.Escape then newkey = nil end
			set(newkey)
			task.wait()
			binding = false
		end)
	end)

	connect(UIS.InputBegan, function(input)
		if binding or key == nil then return end
		if UIS:GetFocusedTextBox() then return end
		if (input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key) or input.UserInputType == key then
			safe(callback, key)
		end
	end)

	library.setters[flag] = function(v) set(v) end
	refresh()
	library.flags[flag] = key

	local types = {}
	function types:Set(newkey) set(newkey) end
	function types:GetHolding()
		if key == nil then return false end
		if key == Enum.UserInputType.MouseButton1 or key == Enum.UserInputType.MouseButton2 or key == Enum.UserInputType.MouseButton3 then
			return UIS:IsMouseButtonPressed(key)
		end
		return UIS:IsKeyDown(key)
	end
	return types
end

----------------------------------------------------------------------
-- Watermark
----------------------------------------------------------------------
function library:Watermark(str)
	if not self.gui then self.gui = creategui() end
	local wm = create("TextLabel", {
		Text = tostring(str), Font = FONT, TextSize = 14, BorderSizePixel = 1,
		Position = UDim2.new(0, 10, 0, 10), Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		_t = { BackgroundColor3 = "Window Background", BorderColor3 = "Accent", TextColor3 = "Text" },
	}, self.gui)
	padding(wm, 8, 0, 8, 0)
	self.watermarkobject = wm
	local types = {}
	function types:Set(s) wm.Text = tostring(s) end
	function types:Remove() wm:Destroy() end
	return types
end

----------------------------------------------------------------------
-- Aç / Kapat / Kaldır
----------------------------------------------------------------------
function library:Close()
	self.open = not self.open
	if self.holder then self.holder.Visible = self.open end
end

function library:Unload()
	for _, c in ipairs(self.connections) do pcall(function() c:Disconnect() end) end
	table.clear(self.connections)
	if self.gui then pcall(function() self.gui:Destroy() end) end
	self.gui, self.holder = nil, nil
end

----------------------------------------------------------------------
-- Tema fonksiyonları
----------------------------------------------------------------------
function library:ChangeThemeOption(option, color)
	if self.theme[option] then
		self.theme[option] = color
		applytheme()
	end
end

function library:OverrideTheme(tbl)
	for k, v in pairs(tbl or {}) do self.theme[k] = v end
	applytheme()
end

function library:SetTheme(theme)
	if themes[theme] then
		self.theme = clone(themes[theme])
		self.currenttheme = theme
		applytheme()
		return true
	end
	if readfile and isfile then
		local path = string.format("%s/themes/%s.%s", self.folder, tostring(theme), self.extension)
		local ok, data = pcall(function()
			if isfile(path) then return HttpService:JSONDecode(readfile(path)) end
		end)
		if ok and type(data) == "table" then
			for k, hex in pairs(data) do
				if self.theme[k] then
					local ok2, c = pcall(Color3.fromHex, hex)
					if ok2 then self.theme[k] = c end
				end
			end
			applytheme()
			return true
		end
	end
	return false
end

function library:GetThemes()
	local list = { "Default", "Midnight", "AirHub" }
	if listfiles and isfolder and isfolder(self.folder .. "/themes") then
		pcall(function()
			for _, f in ipairs(listfiles(self.folder .. "/themes")) do
				local n = f:match("([^/\\]+)%." .. self.extension .. "$")
				if n then table.insert(list, n) end
			end
		end)
	end
	return list
end

function library:SaveCustomTheme(name)
	if not (writefile and makefolder and isfolder) then return false, "executor dosya sistemini desteklemiyor" end
	if type(name) ~= "string" or name == "" then return false, "improper name" end
	if themes[name] then return false, "theme exists" end
	local data = {}
	for k, c in pairs(self.theme) do data[k] = c:ToHex() end
	for _, p in ipairs({ self.folder, self.folder .. "/themes" }) do
		if not isfolder(p) then makefolder(p) end
	end
	writefile(string.format("%s/themes/%s.%s", self.folder, name, self.extension), HttpService:JSONEncode(data))
	return true
end

----------------------------------------------------------------------
-- Config fonksiyonları
----------------------------------------------------------------------
local function cfgname(name, ext)
	if type(name) ~= "string" then return nil end
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	name = name:gsub("%s", "_")
	name = name:gsub("[\\/]", "")
	name = name:gsub("%." .. ext .. "$", "")
	if name == "" then return nil end
	return name
end

local function hasfs()
	return writefile and readfile and isfolder and makefolder and isfile
end

function library:ConfigIgnore(flag)
	table.insert(configignores, flag)
end

function library:SaveConfig(name)
	if not hasfs() then return false, "executor dosya sistemini desteklemiyor" end
	name = cfgname(name, self.extension)
	if not name then return false, "improper name" end

	local tbl = {}
	for flag, value in pairs(self.flags) do
		if not table.find(configignores, flag) then
			if typeof(value) == "EnumItem" then
				tbl[flag] = tostring(value)
			elseif typeof(value) == "Color3" then
				tbl[flag] = { color = value:ToHex(), alpha = tonumber(coloralphas[flag]) or 1 }
			elseif type(value) == "number" or type(value) == "string" or type(value) == "boolean" or type(value) == "table" then
				tbl[flag] = value
			end
		end
	end

	if not isfolder(self.folder) then makefolder(self.folder) end
	writefile(string.format("%s/%s.%s", self.folder, name, self.extension), HttpService:JSONEncode(tbl))
	return true
end

function library:LoadConfig(name)
	if not hasfs() then return false, "executor dosya sistemini desteklemiyor" end
	name = cfgname(name, self.extension)
	if not name then return false, "improper name" end
	local path = string.format("%s/%s.%s", self.folder, name, self.extension)
	if not isfile(path) then return false, "config not found" end

	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	if not ok or type(data) ~= "table" then return false, "bad config" end

	for flag, value in pairs(data) do
		local setter = self.setters[flag]
		if setter and not table.find(configignores, flag) then
			if type(value) == "table" and value.color then
				local ok2, c = pcall(Color3.fromHex, value.color)
				if ok2 then pcall(setter, c, value.alpha) end
			elseif type(value) == "string" and value:match("^Enum%.") then
				local e = parseenum(value)
				if e then pcall(setter, e) end
			else
				pcall(setter, value)
			end
		end
	end
	return true
end

function library:DeleteConfig(name)
	if not (hasfs() and delfile) then return false, "executor dosya sistemini desteklemiyor" end
	name = cfgname(name, self.extension)
	if not name then return false, "improper name" end
	local path = string.format("%s/%s.%s", self.folder, name, self.extension)
	if isfile(path) then delfile(path) return true end
	return false, "config not found"
end

function library:GetConfigs()
	local list = {}
	if listfiles and isfolder and isfolder(self.folder) then
		pcall(function()
			for _, f in ipairs(listfiles(self.folder)) do
				local n = f:match("([^/\\]+)%." .. self.extension .. "$")
				if n then table.insert(list, n) end
			end
		end)
	end
	return list
end

----------------------------------------------------------------------
-- Pencere
----------------------------------------------------------------------
function library:Load(options)
	options = norm(options)
	local name = options.name or "AirHub V2"
	local sizeX = options.sizex or 450
	local sizeY = options.sizey or 500
	local theme = options.theme or "AirHub"
	local overrides = options.themeoverrides or {}

	if options.folder then self.folder = options.folder end
	if options.extension then self.extension = options.extension end

	self.currenttheme = theme
	self.theme = clone(themes[theme] or themes.AirHub)
	for k, v in pairs(overrides) do self.theme[k] = v end

	-- önceki pencere varsa kaldır
	if self.gui then self:Unload() end
	self.themed = {}
	self.scrollers = {}
	self.setters = {}
	for k in pairs(self.flags) do self.flags[k] = nil end
	self.gui = creategui()
	self.open = true

	-- ekrana sığdır (mobil için)
	local cam = workspace.CurrentCamera
	if cam then
		local vp = cam.ViewportSize
		sizeX = math.min(sizeX, math.max(250, vp.X - 20))
		sizeY = math.min(sizeY, math.max(250, vp.Y - 20))
	end

	local holder = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, sizeX, 0, sizeY),
		BorderSizePixel = 2,
		_t = { BackgroundColor3 = "Window Background", BorderColor3 = "Accent" },
	}, self.gui)
	self.holder = holder

	local titlebar = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26),
	}, holder)
	local title = text(titlebar, name, 16)
	title.Position = UDim2.new(0, 8, 0, 5)
	title.Size = UDim2.new(1, -40, 0, 18)
	draggable(titlebar, holder)

	local closebtn = create("TextButton", {
		Text = "X", Font = FONT, TextSize = 16, BackgroundTransparency = 1,
		Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -26, 0, 0),
		_t = { TextColor3 = "Text" },
	}, titlebar)
	connect(closebtn.MouseButton1Click, function() library:Close() end)

	-- Mobil / genel açma-kapama butonu
	if options.mobilebutton ~= false then
		local tb = create("TextButton", {
			Text = "UI", Font = FONT, TextSize = 16, BorderSizePixel = 1,
			Size = UDim2.new(0, 38, 0, 38), Position = UDim2.new(1, -48, 0, 10),
			AutoButtonColor = true,
			_t = { BackgroundColor3 = "Window Background", BorderColor3 = "Accent", TextColor3 = "Text" },
		}, self.gui)
		connect(tb.MouseButton1Click, function() library:Close() end)
	end

	-- PC kısayolu
	connect(UIS.InputBegan, function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == library.keybind then
			library:Close()
		end
	end)

	-- Tab çubuğu
	local tabbar = create("ScrollingFrame", {
		BorderSizePixel = 1, ScrollBarThickness = 0,
		Position = UDim2.new(0, 8, 0, 28), Size = UDim2.new(1, -16, 0, 24),
		CanvasSize = UDim2.new(0, 0, 0, 0), ScrollingDirection = Enum.ScrollingDirection.X,
		_t = { BackgroundColor3 = "Tab Background", BorderColor3 = "Tab Border" },
	}, holder)
	pcall(function() tabbar.AutomaticCanvasSize = Enum.AutomaticSize.X end)
	listlayout(tabbar, 0, Enum.FillDirection.Horizontal)

	local pages = create("Frame", {
		BorderSizePixel = 1,
		Position = UDim2.new(0, 8, 0, 56), Size = UDim2.new(1, -16, 1, -64),
		_t = { BackgroundColor3 = "Tab Background", BorderColor3 = "Tab Border" },
	}, holder)

	local tabs = {}
	self.tabs = tabs
	local current

	local function refreshtabs()
		for _, t in ipairs(tabs) do
			local active = (t == current)
			t.button.BackgroundColor3 = active and library.theme["Tab Toggle Background"] or library.theme["Tab Background"]
			t.button.TextColor3 = active and library.theme["Accent"] or library.theme["Text"]
			t.page.Visible = active
		end
	end
	library.refreshtabs = refreshtabs

	local windowtypes = ci({})
	local firsttabsignal

	function windowtypes:Tab(tabname)
		local btn = create("TextButton", {
			Text = tostring(tabname), Font = FONT, TextSize = 15, BorderSizePixel = 0,
			AutoButtonColor = false,
			Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = #tabs + 1,
		}, tabbar)
		padding(btn, 12, 0, 12, 0)

		local page = create("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4),
			Visible = false,
		}, pages)

		local function column(xscale, xoff)
			local sf = create("ScrollingFrame", {
				BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
				Position = UDim2.new(xscale, xoff, 0, 0), Size = UDim2.new(0.5, -3, 1, 0),
				CanvasSize = UDim2.new(0, 0, 0, 0),
			}, page)
			pcall(function() sf.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
			listlayout(sf, 6)
			padding(sf, 0, 0, 4, 4)
			table.insert(library.scrollers, sf)
			return sf
		end
		local col1 = column(0, 0)
		local col2 = column(0.5, 3)

		local tab = { button = btn, page = page }
		table.insert(tabs, tab)
		if not current then current = tab end
		refreshtabs()

		connect(btn.MouseButton1Click, function()
			current = tab
			refreshtabs()
		end)
		firsttabsignal = firsttabsignal or btn.MouseButton1Click

		local tabtypes = ci({})

		function tabtypes:Section(secopts)
			secopts = norm(secopts)
			local side = secopts.side and tostring(secopts.side):lower() or "left"
			local parentcol = (side == "right") and col2 or col1

			local section = create("Frame", {
				BorderSizePixel = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				_t = { BackgroundColor3 = "Section Background", BorderColor3 = "Section Border" },
			}, parentcol)
			padding(section, 6, 4, 6, 6)
			listlayout(section, 4)

			local st = text(section, secopts.name or "", 15)
			st.LayoutOrder = 0
			st.TextColor3 = library.theme["Accent"]
			-- bölüm başlığı accent renginde kalsın
			for i = #library.themed, 1, -1 do
				if library.themed[i].inst == st then table.remove(library.themed, i) end
			end
			bind(st, "TextColor3", "Accent")

			local content = create("Frame", {
				BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 1,
			}, section)
			listlayout(content, 5)

			local sectiontypes = ci({})

			function sectiontypes:Label(str)
				local l = text(content, str, 15)
				local t = {}
				function t:Set(s) l.Text = tostring(s) end
				return t
			end

			function sectiontypes:Separator(str)
				local h = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12) }, content)
				create("Frame", {
					BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0.5, 0),
					_t = { BackgroundColor3 = "Object Border" },
				}, h)
				if str and str ~= "" then
					local l = create("TextLabel", {
						Text = tostring(str), Font = FONT, TextSize = 14, BorderSizePixel = 0,
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
						_t = { BackgroundColor3 = "Section Background", TextColor3 = "Disabled Text" },
					}, h)
					padding(l, 6, 0, 6, 0)
				end
			end
			sectiontypes.seperator = sectiontypes.Separator

			function sectiontypes:Button(o)
				o = norm(o)
				local callback = o.callback or function() end
				local b = create("TextButton", {
					Text = o.name or "Button", Font = FONT, TextSize = 15, BorderSizePixel = 1,
					AutoButtonColor = true, Size = UDim2.new(1, 0, 0, 22),
					_t = { BackgroundColor3 = "Object Background", BorderColor3 = "Object Border", TextColor3 = "Text" },
				}, content)
				pcall(function() b.BorderMode = Enum.BorderMode.Inset end)
				connect(b.MouseButton1Click, function() safe(callback) end)
			end

			function sectiontypes:Toggle(o)
				o = norm(o)
				local default = o.default or false
				local flag = o.flag or nextflag()
				local callback = o.callback or function() end

				local holder = create("Frame", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				}, content)
				listlayout(holder, 4)

				local row = create("Frame", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0,
				}, holder)

				local box = create("Frame", {
					BorderSizePixel = 1, Position = UDim2.new(0, 0, 0, 1), Size = UDim2.new(0, 16, 0, 16),
					_t = { BackgroundColor3 = "Object Background", BorderColor3 = "Object Border" },
				}, row)
				pcall(function() box.BorderMode = Enum.BorderMode.Inset end)
				local tick = create("Frame", {
					BorderSizePixel = 0, Position = UDim2.new(0, 3, 0, 3), Size = UDim2.new(1, -6, 1, -6),
					Visible = false, _t = { BackgroundColor3 = "Accent" },
				}, box)

				local title = text(row, o.name or "", 15)
				title.Position = UDim2.new(0, 24, 0, 1)
				title.Size = UDim2.new(1, -24, 0, 16)

				local click = create("TextButton", {
					Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
				}, row)

				local right = create("Frame", {
					BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
				}, row)
				local rl = listlayout(right, 4, Enum.FillDirection.Horizontal)
				pcall(function()
					rl.VerticalAlignment = Enum.VerticalAlignment.Center
					rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
				end)

				local toggled = false
				local function set(v)
					toggled = v and true or false
					tick.Visible = toggled
					library.flags[flag] = toggled
					safe(callback, toggled)
				end
				connect(click.MouseButton1Click, function() set(not toggled) end)
				library.setters[flag] = set
				set(default)

				local toggletypes = ci({})
				function toggletypes:Toggle(bool) set(bool) end
				function toggletypes:ColorPicker(co) return makecolorpicker(holder, right, co) end
				function toggletypes:Keybind(ko)
					ko = norm(ko)
					local mode = ko.mode and tostring(ko.mode):lower()
					local kcb = ko.callback or function() end
					ko.callback = (mode == "toggle") and function(key, fromsetting)
						if not fromsetting then set(not toggled) end
						safe(kcb, key, fromsetting)
					end or kcb
					return makekeybind(right, ko)
				end
				function toggletypes:Slider(so)
					local t = makeslider(holder, so)
					return t
				end
				function toggletypes:Dropdown(d) return makedropdown(holder, d, false) end
				return toggletypes
			end

			function sectiontypes:Slider(so) return makeslider(content, so) end
			function sectiontypes:Dropdown(d) return makedropdown(content, d, false) end
			function sectiontypes:List(d) return makedropdown(content, d, true) end

			function sectiontypes:Box(bo)
				bo = norm(bo)
				local default = bo.default or ""
				local placeholder = bo.placeholder or ""
				local flag = bo.flag or nextflag()
				local callback = bo.callback or function() end

				local holder = create("Frame", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				}, content)
				listlayout(holder, 3)
				if bo.name then text(holder, bo.name, 15).LayoutOrder = 0 end

				local tb = create("TextBox", {
					Text = default, PlaceholderText = placeholder, ClearTextOnFocus = false,
					Font = FONT, TextSize = 15, BorderSizePixel = 1, Size = UDim2.new(1, 0, 0, 22),
					TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1,
					_t = { BackgroundColor3 = "Object Background", BorderColor3 = "Object Border", TextColor3 = "Text" },
				}, holder)
				pcall(function() tb.BorderMode = Enum.BorderMode.Inset end)
				padding(tb, 6, 0, 6, 0)

				local function set(str)
					tb.Text = tostring(str or "")
					library.flags[flag] = tb.Text
					safe(callback, tb.Text)
				end
				connect(tb.FocusLost, function() set(tb.Text) end)
				library.setters[flag] = set
				library.flags[flag] = default

				local t = {}
				function t:Set(s) set(s) end
				return t
			end

			function sectiontypes:ColorPicker(co)
				co = norm(co)
				local holder = create("Frame", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				}, content)
				listlayout(holder, 4)
				local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0 }, holder)
				local title = text(row, co.name or "", 15)
				title.Position = UDim2.new(0, 0, 0, 1)
				local right = create("Frame", {
					BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
				}, row)
				local rl = listlayout(right, 4, Enum.FillDirection.Horizontal)
				pcall(function()
					rl.VerticalAlignment = Enum.VerticalAlignment.Center
					rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
				end)
				return makecolorpicker(holder, right, co)
			end

			function sectiontypes:Keybind(ko)
				ko = norm(ko)
				local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18) }, content)
				local title = text(row, ko.name or "", 15)
				title.Position = UDim2.new(0, 0, 0, 1)
				local right = create("Frame", {
					BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
				}, row)
				local rl = listlayout(right, 4, Enum.FillDirection.Horizontal)
				pcall(function()
					rl.VerticalAlignment = Enum.VerticalAlignment.Center
					rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
				end)
				return makekeybind(right, ko)
			end

			return sectiontypes
		end

		return tabtypes, firsttabsignal
	end

	return windowtypes
end

return library
