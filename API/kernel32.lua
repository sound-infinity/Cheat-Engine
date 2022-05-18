--#region Kernel32
---@class Kernel32
local Kernel32 = {}
Kernel32.WM_PROCESS_TERMINATE = 0x0001
Kernel32._initialized = false
---@class Library
---@field OpenProcess fun(...: any): any
---@field CloseHandle fun(...: any): any
---@field TerminateProcess fun(...: any): any
---@type Library
Kernel32._library = nil
Kernel32._debugging = false

function Kernel32:_Init()
	if self._initialized then
		return
	end
	self._initialized = true
	self._library = {}
	setmetatable(self._library, {
		__index = function(_, fun_name)
			return function(_, ...)
				if self._debugging then
					print("info: kernel32.dll: exec:", ("kernel32.%s"):format(fun_name))
					print("info: kernel32.dll: args:", ...)
				end
				return executeCodeLocalEx(("kernel32.%s"):format(fun_name), ...)
			end
		end,
	})
end

function Kernel32:TerminateProcess(processId)
	assert(type(processId) == "number", "error: expected a number for process id!")
	self:_Init()
	local lib = self._library
	local process = lib:OpenProcess(self.WM_PROCESS_TERMINATE, 0, processId)
	lib:TerminateProcess(process, 0x1)
	lib:CloseHandle(process)
end
--#endregion
return Kernel32
