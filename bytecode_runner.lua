-- paste your bytecode below, in byte/string format
-- and it will run through the deserializer
--
local bytecode_str = [[

01 02 05 70 72 69 6E 74 02 68 69 01
02 00 00 01 06 A3 00 00 00 A4 00 01
00 00 00 00 40 6F 01 02 00 9F 00 02
01 82 00 01 00 03 03 01 04 00 00 00
40 03 02 00 00 00 00 00 00 00 00 00

]];

local pid = getProcessIDFromProcessName("RobloxPlayerBeta.exe");
openProcess(pid);
local base = getAddress(enumModules(pid)[1].Name);
local nfunctions = 0;
--
-- cheat engine should add these
--
function readByte(addr) return readBytes(addr,1,false) end
function writeByte(addr, b) writeBytes(addr, { b }); end

--
-- I could do a different method but this table makes it easy
--
c_ref1 = {"0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"};
c_ref2 = { 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15};

function to_hex(s)
    local b = 0;
    if (string.len(s) ~= 2) then return b end
    for i=1,16,1 do
        if (s:sub(1,1)==c_ref1[i]) then b=b+(c_ref2[i]*16); end
        if (s:sub(2,2)==c_ref1[i]) then b=b+i; end
    end
    return (b - 1);
end

function byte_to_str(b)
    if b == nil then return "00" end
    local str="";
    if b <= 256 then
        str=str..c_ref1[math.floor(b/16)+1];
        str=str..c_ref1[math.floor(b%16)+1];
    end
    return str;
end

function addr_to_bytes(addr)
    if addr == nil then error'Nil address used in addr_to_bytes' end
    local bytes = {0,0,0,0};
    for i=0,3 do
        bytes[4-i]=(addr>>(i*8))%256; -- i did this myself!
    end
    return bytes;
end

function addr_to_str(addr)
    if addr == nil then error'Nil address used in addr_to_str' end
    local str = "";
    local bytes = addr_to_bytes(addr);
    for i=1,4 do -- lua tables
        str = str..byte_to_str(bytes[i])
    end
    return str;
end

function getprologue(addr)
    local func_start = addr;
    while not (readByte(func_start) == 0x55 and readByte(func_start + 1) == 0x8B and readByte(func_start + 2) == 0xEC) do
        func_start = func_start - 1;
    end
    return func_start;
end


bytecode_str = bytecode_str:gsub(" ", "");
bytecode_str = bytecode_str:gsub("\n", "");

print("Running bytecode:");
print("");
print(bytecode_str);
print("");

-- Translate bytecode string to bytecode bytes
local bytecode_size = 0;
local bytecode = {};
for at=1,string.len(bytecode_str)+1,2 do
    table.insert(bytecode, to_hex(bytecode_str:sub(at,at+1)));
    bytecode_size = bytecode_size + 1
end

local arg_data = allocateSharedMemory("arg_data", 0x1000);
local ret_location = (arg_data + 64);
local args_at = 0

if arg_data == nil then
    error'Failed to allocate shared memory...'
end

function setargs(t)
    args_at = 0
    for i=1,#t do
        writeInteger(arg_data + args_at, t[i]);
        args_at = args_at + 4;
    end
end

function getReturn()
    return readInteger(ret_location);
end


-- handle the external calling convention routines...
-- aka convert every function into an stdcall if it's not
-- already.
--
function make_stdcall(func, convention, args)
    if (convention == "stdcall") then
        return func
    end

    local ret = args * 4;
    nfunctions = nfunctions + 1;
    local loc = allocateSharedMemory("func"..tostring(nfunctions), 4096)

    local code = "";
    code = code .. addr_to_str(loc)..": \n";
    code = code .. "push ebp \n";
    code = code .. "mov ebp,esp \n";
    code = code .. "push eax \n";

    if (convention == "cdecl") then
        for i=args,1,-1 do
            code = code .. "push ["..addr_to_str(arg_data+((i-1)*4)).."] \n" --"push "..args--"push [ebp+"..byte_to_str(4+(i*4)).."] \n";
	end
    elseif (convention == "thiscall") then
        if (args > 1) then
            for i=args,2,-1 do
                code = code .. "push ["..addr_to_str(arg_data+((i-1)*4)).."] \n" --"push [ebp+"..byte_to_str(4+(i*4)).."] \n";
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
                code = code .. "push ["..addr_to_str(arg_data+((i-1)*4)).."] \n" --"push [ebp+"..byte_to_str(4+(i*4)).."] \n";
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
        code = code .. "add esp,"..byte_to_str(args*4).." \n"
    elseif (convention == "thiscall") then
        code = code .. "pop ecx \n"
    elseif (convention == "fastcall") then
        code = code .. "pop ecx \n"
        code = code .. "pop edx \n"
    end

    code = code .. "pop eax \n";
    code = code .. "pop ebp \n"
    code = code .. "ret 04";
    --code = code .. "ret " .. byte_to_str(ret) .. " \n"

    autoAssemble(code);
    return loc;
end


local r_gettop = getAddress(AOBScan("558BEC8B??088B????2B??????????5DC3","-C-W",0,"")[0]);
local r_spawn = getAddress(AOBScan("83????F20F10????F20F??????FF75","-C-W",0,"")[0]);
local r_deserialize = getAddress(AOBScan("FFFFFF3F0F87????00006A04","-C-W",0,"")[0]);

if (r_gettop == nil or r_gettop == 0) then
    print("[scanner]: Failed on r_gettop");
end
if (r_spawn == nil or r_spawn == 0) then
    print("[scanner]: Failed on r_spawn");
end
if (r_deserialize == nil or r_deserialize == 0) then
    print("[scanner]: Failed on r_deserialize");
end

r_deserialize = make_stdcall(getprologue(r_deserialize), "cdecl", 4);
r_spawn = make_stdcall(getprologue(r_spawn), "cdecl", 1);


-- lua state hook
local rL = 0;
local gettop_old_bytes = readBytes(r_gettop + 6, 6, true);

-- we will borrow a tiny section of the
-- allocated memory for function data
-- to place our state hooking code at
local gettop_hook_loc = arg_data + 0x400;
local trace_loc = arg_data + 0x3FC;

-- make the hook
writeByte(gettop_hook_loc, 0x60);
writeBytes(gettop_hook_loc + 1, { 0x89, 0x0D });
writeInteger(gettop_hook_loc + 3, trace_loc);
writeByte(gettop_hook_loc + 7, 0x61);
writeBytes(gettop_hook_loc + 8, gettop_old_bytes);
writeByte(gettop_hook_loc + 14, 0xE9);
writeInteger(gettop_hook_loc + 15, (r_gettop + 6 + 6) - (gettop_hook_loc + 14 + 5));

-- get a jmp instruction prepared
local gettop_rel = gettop_hook_loc - (r_gettop + 6 + 5);
local gettop_rel_bytes = addr_to_bytes(gettop_rel);
local gettop_hook = { 0xE9, 0x90, 0x90, 0x90, 0x90, 0x90 };
gettop_hook[2] = gettop_rel_bytes[4];
gettop_hook[3] = gettop_rel_bytes[3];
gettop_hook[4] = gettop_rel_bytes[2];
gettop_hook[5] = gettop_rel_bytes[1];


local bytecode_loc = allocateSharedMemory("bytecode", bytecode_size + 8);
writeBytes(bytecode_loc, bytecode);
writeInteger(bytecode_loc + bytecode_size + 4 + (bytecode_size % 4), bytecode_size); -- this is essential
print(addr_to_str(bytecode_loc))

local chunkName = (arg_data + 128);
writeString(chunkName, "@Script1");
writeInteger(chunkName + 12, 8); -- string length

-- place the hook for gettop
writeBytes(r_gettop + 6, gettop_hook);

-- wait for lua state
t = createTimer(nil)

function checkHook(timer)
    if (rL == 0) then
        -- occur one time
        rL = readInteger(trace_loc);
        if (rL ~= 0) then
            -- restore bytes
            writeBytes(r_gettop + 6, gettop_old_bytes);
            timer_setEnabled(t, false);

            print("Lua state: " ..addr_to_str(rL));

            setargs({rL, chunkName, bytecode_loc, bytecode_size});
            executeCode(r_deserialize);
            print("Deserializer returned: "..getReturn());
            executeCode(r_spawn); -- use 1st arg
        end
    end
end

timer_setInterval(t, 10);
timer_onTimer(t, checkHook);
timer_setEnabled(t, true);





