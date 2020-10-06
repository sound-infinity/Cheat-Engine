local pid = getProcessIDFromProcessName("RobloxPlayerBeta.exe");
openProcess(pid);
local base = getAddress(enumModules(pid)[1].Name);

local functions = {};
local nfunctions = 0;

local url = "https://raw.githubusercontent.com/thedoomed/Cheat-Engine/master/bytecode_example.bin"
local http = getInternet()
local fileData = http.getURL(url)
http.destroy()

local bytecode_size = string.len(fileData);
local bytecode_loc = allocateMemory(bytecode_size);
local bytecode = {};

for at=1,bytecode_size do
	local i = at - 1;
	writeBytes(bytecode_loc + i, {fileData:byte(at,at)});
end

writeInteger(bytecode_loc + bytecode_size + (bytecode_size + 4 % 4), bytecode_size); -- this is essential



-- custom mem utility functions...
--
c_ref1 = {"0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"};
c_ref2 = { 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15};

function readByte(addr)
    return readBytes(addr,1,false)
end

function writeByte(addr, b)
    writeBytes(addr, { b });
end

function to_str(b)
    if b == nil then return "00" end
    local str="";
    if b <= 256 then
        str=str..c_ref1[math.floor(b/16)+1];
        str=str..c_ref1[math.floor(b%16)+1];
    end
    return str;
end

function addr_to_bytes(addr)
    if addr == nil then
        error'Nil address used in addr_to_bytes'
    end
    local bytes = {0,0,0,0};
    for i=0,3 do
        bytes[3-i]=(addr>>(i*8))%256;
    end
    return bytes;
end

function addr_to_str(addr)
    if addr == nil then
        error'Nil address used in addr_to_str'
    end
    local str="";
    local bytes = addr_to_bytes(addr);
    for i=0,3 do -- lua tables
        str = str..to_str(bytes[i])
    end
    return str;
end

function to_hex(s)
    if (string.len(s) ~= 2) then
        return 0
    end
    local b=0;
    for i=1,16,1 do
        if (s:sub(1,1)==c_ref1[i]) then
            b=b+(c_ref2[i]*16);
        end
        if (s:sub(2,2)==c_ref1[i]) then
            b=b+i;
        end
    end
    return b;
end

function readsb(addr, len)
    local str = "";
    for i=1,len do
        str=str..to_str(readByte(addr));
    end
    return str;
end

function getPrologue(addr)
    local func_start = addr;
    while not (readByte(func_start) == 0x55 and readByte(func_start + 1) == 0x8B and readByte(func_start + 2) == 0xEC) do
        func_start = func_start - 1;
    end
    return func_start;
end

function getNextPrologue(addr)
    local func_start = addr;
    while not (readByte(func_start) == 0x55 and readByte(func_start + 1) == 0x8B and readByte(func_start + 2) == 0xEC) do
        func_start = func_start + 1;
    end
    return func_start;
end




print("Bytecode size: " .. addr_to_str(bytecode_size));
print("Bytecode: " .. addr_to_str(bytecode_loc));


-- Search for an XREF of the string
-- "Spawn function requires 1 argument"...
-- since scanning the string's address will take us
-- to the spawn function (this is how an XREF works
-- in IDA Pro)
-- 
local str_spawn_ref = addr_to_bytes(getAddress(AOBScan("537061776E20","-C-W",0,"")[0])); 
-- address of the string "Spawn " . . .
local str_spawn_bytes = to_str(str_spawn_ref[3])..to_str(str_spawn_ref[2])..to_str(str_spawn_ref[1])..to_str(str_spawn_ref[0]);

-- scan for all of the addresses
local r_spawn       = getAddress(AOBScan(str_spawn_bytes,"-C-W",0,"")[0]);
local r_deserialize = getAddress(AOBScan("0F????83??7FD3??83??0709","-C-W",0,"")[0]);
local r_gettop      = getAddress(AOBScan("558BEC8B??088B????2B??????????5DC3","-C-W",0,"")[0]);
local r_newthread   = getAddress(AOBScan("72??6A01??E8????????83C408??E8","-C-W",0,"")[0]);

r_deserialize      = getPrologue(r_deserialize);
r_spawn            = getPrologue(r_spawn);
r_newthread        = getPrologue(r_newthread);


-- a place to store our function information
-- for external function calls
--
local arg_data = allocateSharedMemory(4096);
if arg_data == nil then
    error'Failed to allocate shared memory...'
end

local ret_location = (arg_data + 64);

function getReturn()
    return readInteger(ret_location);
end



-- lua state hook
local rL = 0;
local gettop_old_bytes = readBytes(r_gettop + 6, 6, true);

-- we will borrow a tiny section of the
-- allocated memory for function data
-- to place our state hooking code at
local gettop_hook_loc = arg_data + 0x400;
local hook_at = gettop_hook_loc;
local trace_loc = arg_data + 0x3FC;

local jmp_pointer_to = arg_data + 0x3F8;
local jmp_pointer_back = arg_data + 0x3F4;

writeInteger(jmp_pointer_to, gettop_hook_loc);
writeInteger(jmp_pointer_back, r_gettop + 12); -- jmpback / return

writeBytes(hook_at,	{ 0x60, 0x89, 0x0D });	hook_at = hook_at + 3;
writeInteger(hook_at, 	trace_loc);		hook_at = hook_at + 4;
writeByte(hook_at,	0x61);			hook_at = hook_at + 1;
writeBytes(hook_at,	gettop_old_bytes); 	hook_at = hook_at + 6;
writeBytes(hook_at,	{ 0xFF, 0x25 }); 	hook_at = hook_at + 2;
writeInteger(hook_at, 	jmp_pointer_back);

-- insert a jmp instruction
bytes_jmp = addr_to_bytes(jmp_pointer_to);
local gettop_hook = { 0xFF, 0x25, bytes_jmp[3], bytes_jmp[2], bytes_jmp[1], bytes_jmp[0] };

print("gettop hook: " .. addr_to_str(gettop_hook_loc))










-- handle the external calling convention routines...
-- convert every function into an stdcall if it's not
-- already
--
function make_stdcall(func, convention, args)
    if (convention == "stdcall") then
        return func
    end

    local ret = args * 4;
    nfunctions = nfunctions + 1;
    local loc = allocateMemory(4096)

    local code = "";
    code = code .. addr_to_str(loc)..": \n";
    code = code .. "push ebp \n";
    code = code .. "mov ebp,esp \n";
    code = code .. "push eax \n";

    if (convention == "cdecl") then
        for i=args,1,-1 do
            -- since cheat engine's executeCode (a.k.a. CreateRemoteThread)
            -- can only pass 1 arg to a function, we can compensate
            -- by passing all of our args through variables in memory.
            -- We can spawn a thread for each function call as this
            -- only needs 2 function calls to work.
            --
            code = code .. "push ["..addr_to_str(arg_data+((i-1)*4)).."] \n" --"push "..args--"push [ebp+"..to_str(4+(i*4)).."] \n";
	end
    elseif (convention == "thiscall") then
        if (args > 1) then
            for i=args,2,-1 do
                code = code .. "push ["..addr_to_str(arg_data+((i-1)*4)).."] \n" --"push [ebp+"..to_str(4+(i*4)).."] \n";
	    end
        end
        if (args > 0) then
            code = code .. "push ecx \n";
            code = code .. "mov ecx,["..addr_to_str(arg_data+0).."] \n" --"mov ecx,[ebp+8] \n";
            ret = ret - 4;
        end
    elseif (convention == "fastcall") then
       	if (args > 2) then
            for i=args,3,-1 do
                code = code .. "push ["..addr_to_str(arg_data+((i-1)*4)).."] \n" --"push [ebp+"..to_str(4+(i*4)).."] \n";
	    end
        end
        if (args > 0) then
            code = code .. "push ecx";
            code = code .. "mov ecx,["..addr_to_str(arg_data+0).."] \n" --"mov ecx,[ebp+8] \n";
            ret = ret - 4;
        end
	if (args > 1) then
            code = code .. "push edx";
            code = code .. "mov ecx,["..addr_to_str(arg_data+4).."] \n" --"mov edx,[ebp+8] \n";
            ret = ret - 4;
        end
    end

    code = code .. "call "..addr_to_str(func).." \n"
    code = code .. "mov ["..addr_to_str(arg_data + 64).."],eax \n";

    if (convention == "cdecl") then
        code = code .. "add esp,"..to_str(args*4).." \n"
    elseif (convention == "thiscall") then
        code = code .. "pop ecx \n"
    elseif (convention == "fastcall") then
        code = code .. "pop ecx \n"
        code = code .. "pop edx \n"
    end

    code = code .. "pop eax \n";
    code = code .. "pop ebp \n"
    code = code .. "ret 04";
    --code = code .. "ret " .. to_str(ret) .. " \n" -- use to convert to cdecl

    autoAssemble(code);
    return loc;
end

function patch_retcheck(func_start)
    local func_end = getNextPrologue(func_start + 3);
    local func_size = func_end - func_start;

    nfunctions = nfunctions + 1;
    local func = allocateMemory(func_size);
    writeBytes(func, readBytes(func_start, func_size, true));

    for i = 1,func_size,1 do
        local at = func + i;
        if (readByte(at) == 0x72 and readByte(at + 2) == 0xA1 and readByte(at + 7) == 0x8B) then
            writeByte(at, 0xEB);
            print("Patched retcheck at "..addr_to_str(at))
            break;
        end
    end

    local i = 1;
    while (i < func_size) do
        -- Fix relative calls
        if (readByte(func + i) == 0xE8 or readByte(func + i) == 0xE9) then
            local oldrel = readInteger(func_start + i + 1);
            local relfunc = (func_start + i + oldrel) + 5;

            if (relfunc % 16 == 0 and relfunc > base and relfunc < base + 0x3FFFFFF) then
                local newrel = relfunc - (func + i + 5);
                writeInteger((func + i + 1), newrel);
                i = i + 4;
            end
        end
        i = i + 1;
    end

    -- store information about this de-retchecked function
    table.insert(functions,{func,func_size});
    return func;
end

local args_at = 0
function setargs(t)
    args_at = 0
    for i=1,#t do
        writeInteger(arg_data + args_at, t[i]);
        args_at = args_at + 4;
    end
end


-- [[
print("");
print("deserializer: "..addr_to_str((r_deserialize - base) + 0x400000));
print("spawn: "..addr_to_str((r_spawn - base) + 0x400000));
print("lua_gettop: "..addr_to_str((r_gettop - base) + 0x400000));
print("lua_newthread: "..addr_to_str((r_newthread - base) + 0x400000));
-- ]]
print("");

-- update our functions to suit their calling conventions
-- and bypass retcheck if there is a retcheck
r_deserialize = make_stdcall(r_deserialize, "cdecl", 4);
r_spawn = make_stdcall(r_spawn, "cdecl", 1);
r_newthread = make_stdcall(patch_retcheck(r_newthread), "cdecl", 1);

print("r_deserialize: "..addr_to_str(r_deserialize));
print("r_spawn: "..addr_to_str(r_spawn));
print("r_newthread: "..addr_to_str(r_newthread));

local chunkName = (arg_data + 128);
writeString(chunkName, "=Script1");
writeInteger(chunkName + 12, 8); -- string length

print("chunkName: " .. addr_to_str(chunkName));

print("gettop: " .. addr_to_str(r_gettop));
-- place the hook for gettop
writeBytes(r_gettop + 6, gettop_hook);

-- wait for lua state
t = createTimer(nil)

function checkHook(timer)
    if (rL == 0) then
        -- occur one time
        rL = readInteger(trace_loc);
        if (rL ~= 0) then
            timer_setEnabled(t, false);
            
            -- restore bytes
            writeBytes(r_gettop + 6, gettop_old_bytes);

            print("Lua state: " ..addr_to_str(rL));

            setargs({rL, chunkName, bytecode_loc, bytecode_size});
            executeCode(r_deserialize);
            executeCode(r_spawn); -- uses rL from last setargs call ...
        end
    end
end

timer_setInterval(t, 100);
timer_onTimer(t, checkHook);
timer_setEnabled(t, true);
