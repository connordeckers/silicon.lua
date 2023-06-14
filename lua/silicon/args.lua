local Args = {}
Args.__index = Args
Args.__store = {}

---@param key string|number The flag name or position of value
---@param value? string|integer The flag value
---@param extendNotOverride? boolean Whether identical flags should be allowed, or if they should be unique and override
function Args:set(key, value, extendNotOverride)
	if type(key) == "number" then
		table.insert(self.__store, key, { value = value })
	else
		local obj = { key = key, value = value or nil }

		if not extendNotOverride then
			-- If the key already exists in the store, then
			-- we want to override it instead of add again.
			for i, v in ipairs(self.__store) do
				if v.key == key then
					self.__store[i] = obj
					return
				end
			end
		end

		table.insert(self.__store, obj)
	end
end

function Args:collection()
	local parts = {}
	for _, prop in pairs(self.__store) do
		if prop.key then
			table.insert(parts, prop.key)
		end
		if prop.value ~= nil then
			table.insert(parts, prop.value)
		end
	end

	return parts
end

function Args:string()
	return table.concat(self:collection(), " ")
end

function Args:reset()
	self.__store = {}
end

return Args
