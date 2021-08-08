local pid = getProcessIDFromProcessName("RobloxPlayerBeta.exe");
openProcess(pid);

function get_util_api()
    http = getInternet()
    local api_util = http.getURL("https://raw.githubusercontent.com/thedoomed/Cheat-Engine/master/api_util.lua")
    http.destroy()
    return api_util;
end

util = loadstring(get_util_api())();
util.init(pid);

local http = getInternet()
local bytecode_fetch = http.getURL("https://raw.githubusercontent.com/thedoomed/Cheat-Engine/master/bytecode_example.bin")
http.destroy()

local bytecode_size = string.len(bytecode_fetch);
local bytecode = allocateMemory(bytecode_size);
for at = 1, bytecode_size do
	local i = at - 1;
	writeBytes(bytecode + i, {bytecode_fetch:byte(at,at)});
end

writeInteger(bytecode + bytecode_size + (bytecode_size + 4 % 4), bytecode_size);

print(util.int_to_str(bytecode))
print(util.int_to_str(bytecode_size))



refb = util.int_to_bytes(util.aobscan("537061776E20")[1]);
scan_spawn = util.byte_to_str(refb[3]);
scan_spawn = scan_spawn..util.byte_to_str(refb[2]);
scan_spawn = scan_spawn..util.byte_to_str(refb[1]);
scan_spawn = scan_spawn..util.byte_to_str(refb[0]);

local r_spawn       = util.get_prologue(util.aobscan(scan_spawn)[1]);
local r_deserialize = util.get_prologue(util.aobscan("0F????83??7FD3??83??0709")[1]);
local r_newthread   = util.get_prologue(util.aobscan("68280A00006A006A006A006A00E8")[1] - 0x30);
--local r_newthread = util.get_prologue(util.aobscan("88????E8????????0F1046??0F11????")[1]);
local ls_hook_from  = util.get_prologue(util.aobscan("73????FF??8B??83C404")[1]);


print("deserialize: "  .. util.int_to_str(r_deserialize));
print("spawn: "        .. util.int_to_str(r_spawn));
print("newthread: "    .. util.int_to_str(r_newthread));



-- lua state hook
--
local rL = 0;
local ls_hook_to = allocateMemory(0x1000) + 0x100;

local trace_loc = ls_hook_to - 4;
local b1 = util.int_to_bytes(trace_loc);

local ls_hook_ptr = ls_hook_to - 8;
writeInteger(ls_hook_ptr, ls_hook_to);

local ls_hook_jmpback = ls_hook_to - 12;
local b2 = util.int_to_bytes(ls_hook_jmpback);

writeInteger(ls_hook_jmpback, ls_hook_from + 6);
writeBytes(ls_hook_to,{
    0x55,
    0x8B, 0xEC,
    0x83, 0xEC, 0x08,
    0x89, 0x0D, b1[3], b1[2], b1[1], b1[0],
    0xFF, 0x25, b2[3], b2[2], b2[1], b2[0]
});

print("ls_hook: "    .. util.int_to_str(ls_hook_to));


function patch_retcheck(func_start)
    local func_end = util.next_prologue(func_start + 16);
    local func_size = func_end - func_start;
    local newfunc = allocateMemory(func_size);

    writeBytes(newfunc, util.read_bytes(func_start, func_size));

    for i = 1,func_size,1 do
        local at = newfunc + i;
        if (util.read_byte(at) == 0x72 and util.read_byte(at + 2) == 0xA1 and util.read_byte(at + 7) == 0x8B) 
        or (util.read_byte(at) == 0x72 and util.read_byte(at + 2) == 0x8B and util.read_byte(at + 7) == 0x8B) then
            writeBytes(at, {0xEB});
            print("Patched retcheck at "..util.int_to_str(at))
            i = i + 9;
        end
    end

    local i = 1;

    while (i < func_size) do
        local at = func_start + i;

        -- fix relative calls
        if (util.read_byte(newfunc + i) == 0xE8 or util.read_byte(newfunc + i) == 0xE9) then
            -- get the function address being called in
            -- the original function
            local calledfunc = (func_start + i + 5) + readInteger(func_start + i + 1);

            if (calledfunc % 16 == 0) then
                -- update the call in our new function
                writeInteger(newfunc + i + 1, calledfunc - (newfunc + i + 5));

                i = i + 4;
            end
        end

        i = i + 1;
    end

    return newfunc;
end


util.fremote.init();


print("loading functions");

-- update our functions to a standard __stdcall
--
r_deserialize   = util.fremote.add(patch_retcheck(r_deserialize), "fastcall", 5);
r_spawn         = util.fremote.add(patch_retcheck(r_spawn), "cdecl", 1);
r_newthread     = util.fremote.add(r_newthread, "thiscall", 1);

print("new deserialize: "  .. util.int_to_str(r_deserialize));
print("new spawn: "        .. util.int_to_str(r_spawn));
print("new newthread: "    .. util.int_to_str(r_newthread));


local chunk_name = ls_hook_to - 0x40; -- use existing memory
writeString(chunk_name, "=Script1");
writeInteger(chunk_name + 12, 8);


-- Place the lua state hook
writeInteger(ls_hook_ptr, ls_hook_to);
local hookb = util.int_to_bytes(ls_hook_ptr)
writeBytes(ls_hook_from, { 0xFF, 0x25, hookb[3], hookb[2], hookb[1], hookb[0] });


-- wait for lua state
t = createTimer(nil)

function checkHook(timer)
    if (rL == 0) then
        -- occur one time
        rL = readInteger(trace_loc);
        if (rL ~= 0) then
            timer_setEnabled(t, false);

            -- restore lua state hook bytes
            writeBytes(ls_hook_from, { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x08 });

            --rL = util.fremote.call(r_newthread, {rL}).ret32;
            print("Lua state: " ..util.int_to_str(rL));

            util.fremote.call(r_deserialize, {rL, chunk_name, bytecode, bytecode_size, 0});
            util.fremote.call(r_spawn, {rL});
        end
    end
end

timer_setInterval(t, 10);
timer_onTimer(t, checkHook);
timer_setEnabled(t, true);
