local pid = getProcessIDFromProcessName("RobloxPlayerBeta.exe");
openProcess(pid);

dump_bytecode = false; -- Set this to true if you're going to dump LBI bytecode
output_file = "C:/Users/USERNAME_HERE/Desktop/bytecode_example.bin";

function get_util_api()
    http = getInternet()
    local api_util = http.getURL("https://raw.githubusercontent.com/thedoomed/Cheat-Engine/master/api_util.lua")
    http.destroy()
    return api_util;
end

util = loadstring(get_util_api())();
util.init(pid);


local rluab_pcall       = util.get_prologue(util.aobscan("8B????3B????0F83????????81??????????0F84")[1]); -- 8B????3B????0F83????????81
local rluau_loadbuffer  = util.get_prologue(util.aobscan("0F????83??7FD3??83??0709")[1]);
local rluae_newthread   = util.get_prologue(util.aobscan("68280A00006A006A006A006A00E8")[1] - 0x30);
--local rluae_newthread = util.get_prologue(util.aobscan("88????E8????????0F1046??0F11????")[1]);
local ls_hook_from      = util.get_prologue(util.aobscan("73????FF??8B??83C404")[1]);


print("deserialize: "  .. util.int_to_str(rluau_loadbuffer));
print("spawn: "        .. util.int_to_str(rluab_pcall));
print("newthread: "    .. util.int_to_str(rluae_newthread));



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



local retcheck = {};
retcheck.routine = 0;
retcheck.pointer = 0;

retcheck.load = function()
    retcheck.routine = util.aobscan("5DFF25????????CC")[1] + 1;
    retcheck.pointer = readInteger(retcheck.routine + 2);
end

retcheck.load();

retcheck.patch = function(address)
    local func_start = address;
    local func_end = util.next_prologue(func_start + 16);
    local func_size = func_end - func_start;

    local mod = allocateMemory(1024);
    local loc_prev_eip = mod + 0x200;
    local ptr_start = mod + 0x204;

    local has_prologue = true; -- assume it is not naked func
    local prologue_reg = util.read_byte(func_start) % 8;
    func_start = func_start + 3;
    writeInteger(ptr_start, func_start);

    local b1 = util.int_to_bytes(loc_prev_eip);
    local b2 = util.int_to_bytes(retcheck.routine);
    local b3 = util.int_to_bytes(mod + 0x25);
    local b4 = util.int_to_bytes(retcheck.pointer);
    local b5 = util.int_to_bytes(ptr_start);

    local patch_bytes = {
        0x50 + prologue_reg,			-- push ebp
        0x8B, 0xC4 + (prologue_reg * 8), 	-- mov ebp,esp
	0x50, 					-- push eax
	0x8B, 0x40 + prologue_reg, 0x04,	-- mov eax,[ebp+4]
	0xA3, b1[3], b1[2], b1[1], b1[0],	-- mov [prev_eip],eax
	0xB8, b2[3], b2[2], b2[1], b2[0],	-- mov eax, retcheck.routine
	0x89, 0x40 + prologue_reg, 0x04,	-- mov [ebp+4], eax
	0xB8, b3[3], b3[2], b3[1], b3[0],	-- mov eax, (mod + 0x25)
	0xA3, b4[3], b4[2], b4[1], b4[0],	-- mov [retcheck.pointer], eax
	0x58,					-- pop eax
	0xFF, 0x25, b5[3], b5[2], b5[1], b5[0],	-- jmp dword ptr [->func_start]
	0xFF, 0x25, b1[3], b1[2], b1[1], b1[0] 	-- jmp dword ptr [previous eip]
    }

    writeBytes(mod, patch_bytes);
    return mod;
end


util.fremote.init();


if (dump_bytecode) then
    local scr_hook = allocateMemory(1024);
    local ptr_bytecode = scr_hook + 0x200;
    local ptr_bytecode_size = scr_hook + 0x204;


    autoAssemble(util.int_to_str(scr_hook)..[[:
    push ebx
    mov ebx,esp
    sub esp,8
    push eax
    mov eax,[ebx+8]
    mov []]..util.int_to_str(ptr_bytecode)..[[],eax
    mov eax,[ebx+C]
    mov []]..util.int_to_str(ptr_bytecode_size)..[[],eax
    pop eax
    jmp ]]..util.int_to_str(rluau_loadbuffer + 6)..[[

    ]]..util.int_to_str(rluau_loadbuffer)..[[:
    jmp ]]..util.int_to_str(scr_hook)..[[
    ]])

    print("Waiting for a script to run...hurry before kick")

    while (readInteger(ptr_bytecode) == 0 and readInteger(ptr_bytecode_size) == 0) do
        sleep(100);
    end

    print("Bytecode: " .. util.int_to_str(readInteger(ptr_bytecode)));
    print("Bytecode size: " .. tostring(readInteger(ptr_bytecode_size)));

    local lbi_check = readInteger(ptr_bytecode_size) > 0x4000;
    -- you can remove this check if youd like

    if(lbi_check and readInteger(ptr_bytecode_size) < 0x100000) then

        local data = readBytes(readInteger(ptr_bytecode), readInteger(ptr_bytecode_size), true);
        data[1] = 0x01;

        local output = io.open(output_file, "w+b");
        output:write(string.char(unpack(data)));
        output:close();

        print'Wrote binary to file'
    end

    return;
end


print("loading functions");

-- update our functions to a standard __stdcall
--
rluau_loadbuffer = util.fremote.add(retcheck.patch(rluau_loadbuffer), "fastcall", 5);
rluab_pcall = util.fremote.add(retcheck.patch(rluab_pcall), "cdecl", 1);
rluae_newthread = util.fremote.add(rluae_newthread, "thiscall", 1);

print("new deserialize: "  .. util.int_to_str(rluau_loadbuffer));
print("new spawn: "        .. util.int_to_str(rluab_pcall));
print("new newthread: "    .. util.int_to_str(rluae_newthread));





local chunk_name = ls_hook_to - 0x40; -- use existing memory
writeString(chunk_name, "=Script1");
writeInteger(chunk_name + 12, 8);


local http = getInternet()
local bytecode_fetch = http.getURL("https://raw.githubusercontent.com/thedoomed/Cheat-Engine/master/bytecode_example.bin")
http.destroy()

local bytecode_size = string.len(bytecode_fetch);
local bytecode = allocateMemory(bytecode_size);

for at = 1, bytecode_size do
	local i = at - 1;
	writeBytes(bytecode + i, {bytecode_fetch:byte(at,at)});
end

writeInteger(bytecode + bytecode_size + 4 + (bytecode_size % 4), bytecode_size);


print(util.int_to_str(bytecode))
print(util.int_to_str(bytecode_size))



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

            rL = util.fremote.call(rluae_newthread, { rL }).ret32;
            print("Lua state: " ..util.int_to_str(rL));

            local status = util.fremote.call(rluau_loadbuffer, { rL, chunk_name, bytecode, bytecode_size, 0 }).ret32;
            if (status == 0) then
                util.fremote.call(rluab_pcall, { rL });
            else
                print("Bytecode error")
            end
        end
    end
end

timer_setInterval(t, 10);
timer_onTimer(t, checkHook);
timer_setEnabled(t, true);
