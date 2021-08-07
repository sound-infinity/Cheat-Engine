util = {};
util.base = 0;

util.init = function(pid)
    util.base = getAddress(enumModules(pid)[1].Name);
end

util.rebase = function(address)
    return util.base + address;
end

util.aslr = function(address)
    return util.base + (address - 0x400000);
end

util.raslr = function(address)
    return (address - util.base) + 0x400000;
end

util.read_byte = function(address)
    return readBytes(address, 1, false)
end

util.read_bytes = function(address, count)
    return readBytes(address, count, true);
end

util.byte_to_str = function(b)
    return string.format("%02X", b);
end

util.str_to_byte = function(s)
    local b = 0;
    if (string.len(s) ~= 2) then
        return b;
    end
    if (s:sub(1,2) == "??") then
        return b;
    end
    for i = 1, 2, 1 do
        local c = s:byte(i,i);
        local n = 0;

        if (c >= 0x61) then
            n = c - 0x57;
        elseif (c >= 0x41) then
            n = c - 0x37;
        elseif (c >= 0x30) then
            n = c - 0x30;
        end

        if (i == 1) then
            b = b + (n * 16);
        else
            b = b + n;
        end
    end
    return b;
end

util.int_to_bytes = function(x)
    if x == nil then
        error'Cannot convert nil value to byte table'
    end
    local b = {0,0,0,0};
    for i = 0, 3 do
        b[3-i] = (x >> (i*8)) % 256;
    end
    return b;
end

util.int_to_str = function(x)
    if x == nil then
        error'Cannot convert nil value to hex string'
    end
    local str = "";
    local b = util.int_to_bytes(x);
    for i = 0,3 do
        str = str .. util.byte_to_str(b[i])
    end
    return str;
end

util.is_prologue = function(address)
local pr = ((util.read_byte(address) == 0x55 and util.read_byte(address + 1) == 0x8B and util.read_byte(address + 2) == 0xEC) -- push ebp | mov ebp,esp
         or (util.read_byte(address) == 0x53 and util.read_byte(address + 1) == 0x8B and util.read_byte(address + 2) == 0xDC) -- push ebx | mov ebx,esp
         or (util.read_byte(address) == 0x53 and util.read_byte(address + 1) == 0x8B and util.read_byte(address + 2) == 0xDA) -- push ebx | mov ebx,edx
);
return pr and (address % 16 == 0);
end

util.get_prologue = function(address)
    local func_start = address;
    func_start = func_start - (func_start % 16);
    while not (util.is_prologue(func_start)) do
        func_start = func_start - 16;
    end
    return func_start;
end

util.next_prologue = function(address)
    local func_start = address;
    func_start = func_start + (func_start % 0x10);
    while not (util.is_prologue(func_start)) do
        func_start = func_start + 16;
    end
    return func_start;
end

util.aobscan = function(aob)
    local results = AOBScan(aob,"-C-W",0,"")
    local new_results = {};

    for i = 0,results.Count - 1 do
        table.insert(new_results, getAddress(results[i]));
    end

    return new_results;
end

util.fremote = {};
util.fremote.data = 0;
util.fremote.args_location = 0;
util.fremote.ret32_location = 0;
util.fremote.ret64_location = 0;

util.fremote.init = function()
    util.fremote.data = allocateMemory(1024);
    util.fremote.args_location = util.fremote.data + 0x10;
    util.fremote.ret32_location = util.fremote.data + 0xC;
    util.fremote.ret64_location = util.fremote.data + 0x4;
end

-- injects a stub which is able to be called
-- using cheat engine's `executeCode` function
--
util.fremote.add = function(func, convention, args)
    local ret = args * 4;
    local loc = allocateMemory(1024)
    local arg_data = util.fremote.args_location;

    local code = "";
    code = code .. util.int_to_str(loc)..": \n";
    code = code .. "push ebp \n";
    code = code .. "mov ebp,esp \n";
    code = code .. "push eax \n";

    if (convention == "cdecl" or convention == "stdcall") then
        for i=args,1,-1 do
            code = code .. "push ["..util.int_to_str(arg_data+((i-1)*4)).."] \n"
	end
    elseif (convention == "thiscall") then
        if (args > 1) then
            for i=args,2,-1 do
                code = code .. "push ["..util.int_to_str(arg_data+((i-1)*4)).."] \n"
	    end
        end
        if (args > 0) then
            code = code .. "push ecx \n";
            code = code .. "mov ecx,["..util.int_to_str(arg_data+0).."] \n"
            ret = ret - 4;
        end
    elseif (convention == "fastcall") then
       	if (args > 2) then
            for i=args,3,-1 do
                code = code .. "push ["..util.int_to_str(arg_data+((i-1)*4)).."] \n"
	    end
        end
	if (args > 1) then
            code = code .. "push edx \n";
            code = code .. "mov edx,["..util.int_to_str(arg_data+4).."] \n"
            ret = ret - 4;
        end
        if (args > 0) then
            code = code .. "push ecx \n";
            code = code .. "mov ecx,["..util.int_to_str(arg_data+0).."] \n"
            ret = ret - 4;
        end
    end

    -- insert the call
    code = code .. "call "..util.int_to_str(func).." \n"
    code = code .. "mov ["..util.int_to_str(util.fremote.ret32_location).."],eax \n";
    code = code .. "movss ["..util.int_to_str(util.fremote.ret64_location).."],xmm0 \n";

    if (convention == "cdecl") then
        if (args > 0) then
            code = code .. "add esp,"..util.byte_to_str(args*4).." \n"
        end
    elseif (convention == "thiscall") then
        if (args > 1) then
            code = code .. "add esp,"..util.byte_to_str((args-1)*4).." \n"
        end
        if (args > 0) then
            code = code .. "pop ecx \n"
        end
    elseif (convention == "fastcall") then
        if (args > 2) then
            code = code .. "add esp,"..util.byte_to_str((args-2)*4).." \n"
        end
        if (args > 0) then
            code = code .. "pop ecx \n"
        end
        if (args > 1) then
            code = code .. "pop edx \n"
        end
    end

    code = code .. "pop eax \n";
    code = code .. "pop ebp \n"
    code = code .. "ret 04";

    autoAssemble(code);
    return loc;
end

util.fremote.set_args = function(t)
    local args_at = 0
    local arg_data = util.fremote.args_location;

    for i = 1,#t do
        writeInteger(arg_data + args_at, t[i]);
        args_at = args_at + 4;
    end
end

util.fremote.call = function(x, t)
    if t ~= nil then
        util.fremote.set_args(t);
    end

    executeCode(x);

    local r = {};
    r.ret32 = readInteger(util.fremote.ret32_location);
    r.ret64 = readQword(util.fremote.ret64_location);
    return r;
end

return util;
