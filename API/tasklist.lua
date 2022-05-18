-- #region TaskList
-- #region Constants
local TASKLIST_GLOBAL_COMMAND = [[tasklist /fo CSV /nh]]
local TASKLIST_MATCH_COMMAND = [[tasklist /fo CSV /nh /fi "IMAGENAME eq %s*"]]
local TASKLIST_ERROR_MESSAGE = [[No tasks are running which match the specified criteria.]]
local TASKLIST_PATTERN_NEWLINE = "[^\r\n]+"
---#endregion
---@class TaskDetail
local TaskDetail = {
	Name = 1,
	ProcessId = 2,
	SessionName = 3,
	SessionNumber = 4,
	MemoryUsage = 5,
}

---@class TaskList
local TaskList = {}
TaskList._initialized = false
---@type TaskDetail[]
TaskList._collection = {}

---@return TaskDetail
function TaskList:ParseLine(line)
	local parameters = {}
	for segment in line:gmatch('["](.-)["]') do
		table.insert(parameters, segment)
	end
	local details = {}
	for name, id in pairs(TaskDetail) do
		local value = parameters[id]
		if id == TaskDetail.MemoryUsage then
			value = value:match(".+[ ]")
			value = value:gsub(",", "")
			value = tonumber(value)
		elseif id == TaskDetail.ProcessId then
			value = tonumber(value)
		end
		details[name] = value
	end
	return details
end

---@return string[]
function TaskList:ExtractLinesFromString(contents)
	local lines = {}
	for line in contents:gmatch(TASKLIST_PATTERN_NEWLINE) do
		table.insert(lines, line)
	end
	return lines
end

---@param command string
---@return string output
function TaskList:_Execute(command)
	assert(command:match("^tasklist"), "not a tasklist command!")
	---@type file*
	local fh = assert(io.popen(command, "r"))
	local contents = fh:read("*a")
	fh:close()
	return contents
end

---@param command string
---@return TaskDetail[] tasklist
function TaskList:_Fetch(command)
	self._initialized = true
	self._collection = {}
	local contents = self:_Execute(command)
	assert(type(contents) == "string")
	if contents:lower():match(TASKLIST_ERROR_MESSAGE:lower()) then
		-- error("error: failed to get list of tasks!", 0)
		return
	end
	local lines = self:ExtractLinesFromString(contents)
	for _, line in pairs(lines) do
		table.insert(self._collection, self:ParseLine(line))
	end
	return self._collection
end

---@return TaskDetail[]
function TaskList:Fetch(query)
	assert(type(query) == "string", "error: expected a string for query! e.g: roblox")
	return self:_Fetch(TASKLIST_MATCH_COMMAND:format(query))
end

---@return TaskDetail[]
function TaskList:FetchAll()
	return self:_Fetch(TASKLIST_GLOBAL_COMMAND)
end

---@return TaskDetail[]
function TaskList:GetCollection()
	return self._collection
end

-- #endregion TaskList

return TaskList