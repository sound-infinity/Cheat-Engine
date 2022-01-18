util = {};
util.base = 0;

function tcombine(t1, t2)
	for i,v in pairs(t2) do
		table.insert(t1, v);
	end
end

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

util.read_int32 = readInteger;
util.read_int64 = readQword;
util.read_double = readDouble;
util.read_string = readString;

util.write_byte = function(address, value)
    writeBytes(address, {value});
end

util.write_bytes = writeBytes
util.write_int32 = writeInteger;
util.write_int64 = writeQword;
util.write_double = writeDouble;
util.write_string = writeString;

util.allocate_memory = allocateMemory;
util.start_thread = executeCode;
util.free_memory = function(x) end --deAlloc;

util.byte_to_str = function(b)
    return string.format("%02X", b);
end

util.str_to_byte = function(s)
	if s == '??' then return 0 end
    return tonumber('0x' .. s);
end

util.int_to_bytes = function(val)
    if val == nil then
        error'Cannot convert nil value to byte table'
    end
    return {val & 0xff, (val >> 8) & 0xff, (val >> 16) & 0xff, (val >> 24) & 0xff};
end

util.int_to_str = function(val)
    if val == nil then
        error'Cannot convert nil value to hex string'
    end
    local str = "";
    local bytes = util.int_to_bytes(val);
    for i = 4, 1, -1 do
        str = str .. util.byte_to_str(bytes[i])
    end
    return str;
end

util.int_to_le_str = function(val)
    if val == nil then
        error'Cannot convert nil value to hex string'
    end
    local str = "";
    local bytes = util.int_to_bytes(val);
    for i = 1, 4 do
        str = str .. util.byte_to_str(bytes[i])
    end
    return str;
end

util.is_prologue = function(address)
	if not (address % 16 == 0) then return false end

	return ((util.read_byte(address) == 0x55 and util.read_byte(address + 1) == 0x8B and util.read_byte(address + 2) == 0xEC) -- push ebp | mov ebp,esp
         or (util.read_byte(address) == 0x53 and util.read_byte(address + 1) == 0x8B and util.read_byte(address + 2) == 0xDC) -- push ebx | mov ebx,esp
         or (util.read_int32(address - 4) == 0xCCCCCCCC) -- alignment?
         --or (util.read_byte(address) == 0x53 and util.read_byte(address + 1) == 0x8B and util.read_byte(address + 2) == 0xD9) -- push ebx | mov ebx,ecx
         --or (util.read_byte(address) == 0x53 and util.read_byte(address + 1) == 0x8B and util.read_byte(address + 2) == 0xDA) -- push ebx | mov ebx,edx
	);
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
    local results = AOBScan(aob, "-C-W", 0, "")
    local new_results = {};

    for i = 0,results.Count - 1 do
        table.insert(new_results, getAddress(results[i]));
    end

    return new_results;
end

util.scan_xrefs = function(str, nresult)
	local aob = "";
	for i = 1,string.len(str) do
		aob = aob .. string.format("%02X", str:byte(i, i));
	end
    local result = util.aobscan(aob)[nresult or 1];
	return util.aobscan(util.int_to_le_str(result));
end

util.get_code_size = function(location)
    local str = disassemble(location);
    local start = str:find('-') + 1;
    local at = start;
    while at < string.len(str) and str:sub(at, at) ~= '-' do
        at = at + 1;
    end
    return math.floor((at - start - 1) / 3);
end

util.place_jmp = function(location_from, location_to)
	local hook_size = 0;
	
	-- calculate instructions to be overwritten
	while hook_size < 5 do
	    hook_size = hook_size + util.get_code_size(location_from + hook_size);
	end
	
	local old_bytes = util.read_bytes(location_from, hook_size);
	
	local nops = hook_size - 5;
	local start_code = util.int_to_str(location_from)..": \n";
	start_code = start_code .. "jmp " .. util.int_to_str(location_to) .. " \n";
	for i = 1, nops do
		start_code = start_code .. "nop \n";
	end
	
	autoAssemble(start_code);
	
	return old_bytes;
end

util.reg32_names = {"eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"};

util.create_function = function(on_execute, stack_cleanup)
	local hook = util.allocate_memory(1024);
	
	local signal_location = hook + 256 + 0;
	local jmpback_location = hook + 256 + 4;
	local output_location = hook + 256 + 8;
	local eax_location = output_location + (4 * 0);
	local ecx_location = output_location + (4 * 1);
	local edx_location = output_location + (4 * 2);
	local ebx_location = output_location + (4 * 3);
	local esp_location = output_location + (4 * 4);
	local ebp_location = output_location + (4 * 5);
	local esi_location = output_location + (4 * 6);
	local edi_location = output_location + (4 * 7);
	
	local bytes_signal = util.int_to_bytes(signal_location);
	local bytes_output = util.int_to_bytes(output_location);
	local bytes_eax = util.int_to_bytes(eax_location);
	local bytes_ecx = util.int_to_bytes(ecx_location);
	local bytes_edx = util.int_to_bytes(edx_location);
	local bytes_ebx = util.int_to_bytes(ebx_location);
	local bytes_esp = util.int_to_bytes(esp_location);
	local bytes_ebp = util.int_to_bytes(ebp_location);
	local bytes_esi = util.int_to_bytes(esi_location);
	local bytes_edi = util.int_to_bytes(edi_location);
	local bytes_jmpback = util.int_to_bytes(jmpback_location);
	
	util.write_int32(signal_location, 0);
	util.write_int32(jmpback_location, location + hook_size);
	
	local bytes = {
		0x55, -- push ebp
		0x8B, 0xEC, -- mov ebp,esp
		0xC7, 0x05, -- mov [signal], 1
		bytes_signal[1], bytes_signal[2], bytes_signal[3], bytes_signal[4],
		1, 0, 0, 0,
		0x89, 0x5 + (8 * 0), -- mov [????????],eax
		bytes_eax[1], bytes_eax[2], bytes_eax[3], bytes_eax[4],
		0x89, 0x5 + (8 * 1), -- mov [????????],ecx
		bytes_ecx[1], bytes_ecx[2], bytes_ecx[3], bytes_ecx[4],
		0x89, 0x5 + (8 * 2), -- mov [????????],edx
		bytes_edx[1], bytes_edx[2], bytes_edx[3], bytes_edx[4],
		0x89, 0x5 + (8 * 3), -- mov [????????],ebx
		bytes_ebx[1], bytes_ebx[2], bytes_ebx[3], bytes_ebx[4],
		0x89, 0x5 + (8 * 4), -- mov [????????],esp
		bytes_esp[1], bytes_esp[2], bytes_esp[3], bytes_esp[4],
		0x89, 0x5 + (8 * 5), -- mov [????????],ebp
		bytes_ebp[1], bytes_ebp[2], bytes_ebp[3], bytes_ebp[4],
		0x89, 0x5 + (8 * 6), -- mov [????????],esi
		bytes_esi[1], bytes_esi[2], bytes_esi[3], bytes_esi[4],
		0x89, 0x5 + (8 * 7), -- mov [????????],edi
		bytes_edi[1], bytes_edi[2], bytes_edi[3], bytes_edi[4],
		0x81, 0x3D, -- cmp [signal], 2
		bytes_signal[1], bytes_signal[2], bytes_signal[3], bytes_signal[4],
		2, 0, 0, 0, 
		0x72, 0xF4, -- je label1 -- 0x7D 0xF4 --> jnl
		0xC7, 0x05, -- mov [signal], 0
		bytes_signal[1], bytes_signal[2], bytes_signal[3], bytes_signal[4],
		0, 0, 0, 0,
		0x8B, 0x5 + (8 * 0), -- mov [????????],eax
		bytes_eax[1], bytes_eax[2], bytes_eax[3], bytes_eax[4],
		0x8B, 0x5 + (8 * 1), -- mov [????????],ecx
		bytes_ecx[1], bytes_ecx[2], bytes_ecx[3], bytes_ecx[4],
		0x8B, 0x5 + (8 * 2), -- mov [????????],edx
		bytes_edx[1], bytes_edx[2], bytes_edx[3], bytes_edx[4],
		0x8B, 0x5 + (8 * 3), -- mov [????????],ebx
		bytes_ebx[1], bytes_ebx[2], bytes_ebx[3], bytes_ebx[4],
		0x8B, 0x5 + (8 * 4), -- mov [????????],esp
		bytes_esp[1], bytes_esp[2], bytes_esp[3], bytes_esp[4],
		0x8B, 0x5 + (8 * 5), -- mov [????????],ebp
		bytes_ebp[1], bytes_ebp[2], bytes_ebp[3], bytes_ebp[4],
		0x8B, 0x5 + (8 * 6), -- mov [????????],esi
		bytes_esi[1], bytes_esi[2], bytes_esi[3], bytes_esi[4],
		0x8B, 0x5 + (8 * 7), -- mov [????????],edi
		bytes_edi[1], bytes_edi[2], bytes_edi[3], bytes_edi[4],
		0x5D, -- pop ebp
		0xC2, stack_cleanup, 0 -- ret ??
	};
		
	util.write_bytes(hook, bytes);
	
	createThread(function()
		while util.read_int32(signal_location) ~= 1 do
			Sleep(1);
		end
		
		local data = {};
		data.eax = util.read_int32(eax_location);
		data.ecx = util.read_int32(ecx_location);
		data.edx = util.read_int32(edx_location);
		data.ebx = util.read_int32(ebx_location);
		data.esp = util.read_int32(esp_location);
		data.ebp = util.read_int32(ebp_location);
		data.esi = util.read_int32(esi_location);
		data.edi = util.read_int32(edi_location);
		
        pcall(function() 
            on_execute(data)
        end);
		
        util.write_int32(signal_location, 2);
	end);
	
	--print("HOOK: ", string.format("%08X", hook));
	
	return hook;
end

util.create_detour = function(location, on_execute, event_trigger)
	local hook_size = 0;
	
	-- calculate instructions to be overwritten
	while hook_size < 5 do
	    hook_size = hook_size + util.get_code_size(location + hook_size);
	end
	
	local old_bytes = util.read_bytes(location, hook_size);
	local hook = util.allocate_memory(1024);
	--print("HOOK: ", string.format("%08X", hook));
	
	
	local signal_location = hook + 256 + 0;
	local jmpback_location = hook + 256 + 4;
	local sleep_location = hook + 256 + 8;
	local output_location = hook + 256 + 12;
	local eax_location = output_location + (4 * 0);
	local ecx_location = output_location + (4 * 1);
	local edx_location = output_location + (4 * 2);
	local ebx_location = output_location + (4 * 3);
	local esp_location = output_location + (4 * 4);
	local ebp_location = output_location + (4 * 5);
	local esi_location = output_location + (4 * 6);
	local edi_location = output_location + (4 * 7);
	
	local bytes_signal = util.int_to_bytes(signal_location);
	local bytes_output = util.int_to_bytes(output_location);
	local bytes_eax = util.int_to_bytes(eax_location);
	local bytes_ecx = util.int_to_bytes(ecx_location);
	local bytes_edx = util.int_to_bytes(edx_location);
	local bytes_ebx = util.int_to_bytes(ebx_location);
	local bytes_esp = util.int_to_bytes(esp_location);
	local bytes_ebp = util.int_to_bytes(ebp_location);
	local bytes_esi = util.int_to_bytes(esi_location);
	local bytes_edi = util.int_to_bytes(edi_location);
	local bytes_jmpback = util.int_to_bytes(jmpback_location);
	local bytes_sleep = util.int_to_bytes(sleep_location);
	
	util.write_int32(signal_location, 0);
	util.write_int32(jmpback_location, location + hook_size);
	
	local kernel_sleep = getAddress("KERNEL32.Sleep");
	util.write_int32(sleep_location, kernel_sleep);
	
	local bytes = {
		0x60, -- pushad
		0x9C, -- pushfd
		0x81, 0x3D, -- cmp [signal], 0
		bytes_signal[1], bytes_signal[2], bytes_signal[3], bytes_signal[4],
		0, 0, 0, 0, 
		0x74, 0x08, -- je skip_jmp_back
		0x9D, -- popfd
		0x61, -- popad
		0xFF, 0x25,  -- jmp dword ptr [jmpback_location]
		bytes_jmpback[1], bytes_jmpback[2], bytes_jmpback[3], bytes_jmpback[4],
		-- skip_jmp_back:
		0xC7, 0x05, -- mov [signal], 1
		bytes_signal[1], bytes_signal[2], bytes_signal[3], bytes_signal[4],
		1, 0, 0, 0,
		0x89, 0x5 + (8 * 0), -- mov [????????],eax
		bytes_eax[1], bytes_eax[2], bytes_eax[3], bytes_eax[4],
		0x89, 0x5 + (8 * 1), -- mov [????????],ecx
		bytes_ecx[1], bytes_ecx[2], bytes_ecx[3], bytes_ecx[4],
		0x89, 0x5 + (8 * 2), -- mov [????????],edx
		bytes_edx[1], bytes_edx[2], bytes_edx[3], bytes_edx[4],
		0x89, 0x5 + (8 * 3), -- mov [????????],ebx
		bytes_ebx[1], bytes_ebx[2], bytes_ebx[3], bytes_ebx[4],
		0x89, 0x5 + (8 * 4), -- mov [????????],esp
		bytes_esp[1], bytes_esp[2], bytes_esp[3], bytes_esp[4],
		0x89, 0x5 + (8 * 5), -- mov [????????],ebp
		bytes_ebp[1], bytes_ebp[2], bytes_ebp[3], bytes_ebp[4],
		0x89, 0x5 + (8 * 6), -- mov [????????],esi
		bytes_esi[1], bytes_esi[2], bytes_esi[3], bytes_esi[4],
		0x89, 0x5 + (8 * 7), -- mov [????????],edi
		bytes_edi[1], bytes_edi[2], bytes_edi[3], bytes_edi[4],
		--0x68, 1, 0, 0, 0, -- push 1
		--0xFF, 0x15, -- call dword ptr [Kernel32.Sleep]
		--bytes_sleep[1], bytes_sleep[2], bytes_sleep[3], bytes_sleep[4],
		0x81, 0x3D, -- cmp [signal], 2
		bytes_signal[1], bytes_signal[2], bytes_signal[3], bytes_signal[4],
		2, 0, 0, 0, 
		--[[0x72, 0xE9, ]]0x72, 0xF4, -- je label1 -- 0x7D 0xF4 --> jnl
		0xC7, 0x05, -- mov [signal], 3
		bytes_signal[1], bytes_signal[2], bytes_signal[3], bytes_signal[4],
		3, 0, 0, 0,
		--[[0x8B, 0x5 + (8 * 0), -- mov [????????],eax
		bytes_eax[1], bytes_eax[2], bytes_eax[3], bytes_eax[4],
		0x8B, 0x5 + (8 * 1), -- mov [????????],ecx
		bytes_ecx[1], bytes_ecx[2], bytes_ecx[3], bytes_ecx[4],
		0x8B, 0x5 + (8 * 2), -- mov [????????],edx
		bytes_edx[1], bytes_edx[2], bytes_edx[3], bytes_edx[4],
		0x8B, 0x5 + (8 * 3), -- mov [????????],ebx
		bytes_ebx[1], bytes_ebx[2], bytes_ebx[3], bytes_ebx[4],
		0x8B, 0x5 + (8 * 4), -- mov [????????],esp
		bytes_esp[1], bytes_esp[2], bytes_esp[3], bytes_esp[4],
		0x8B, 0x5 + (8 * 5), -- mov [????????],ebp
		bytes_ebp[1], bytes_ebp[2], bytes_ebp[3], bytes_ebp[4],
		0x8B, 0x5 + (8 * 6), -- mov [????????],esi
		bytes_esi[1], bytes_esi[2], bytes_esi[3], bytes_esi[4],
		0x8B, 0x5 + (8 * 7), -- mov [????????],edi
		bytes_edi[1], bytes_edi[2], bytes_edi[3], bytes_edi[4],]]
		0x9D, -- popfd
		0x61, -- popad
	};
	
	tcombine(bytes, old_bytes);
	tcombine(bytes, {
		--[[0xC7, 0x05, -- mov [signal], 0
		bytes_signal[1], bytes_signal[2], bytes_signal[3], bytes_signal[4],
		0, 0, 0, 0,]]
		0xFF, 0x25,  -- jmp dword ptr [jmpback_location]
		bytes_jmpback[1], bytes_jmpback[2], bytes_jmpback[3], bytes_jmpback[4]
	});
	
	util.write_bytes(hook, bytes);
	
	local nops = hook_size - 5;
	local start_code = util.int_to_str(location)..": \n";
	start_code = start_code .. "jmp " .. util.int_to_str(hook) .. " \n";
	for i = 1, nops do
		start_code = start_code .. "nop \n";
	end
	
	local detour_data = {};
	
	--detour_data.running = true;
	
	detour_data.stop = function()
		detour_data.running = false;
		util.write_bytes(location, old_bytes);
		util.free_memory(hook);
	end
	
	createThread(function()
		detour_data.running = true;
	
		while util.read_int32(signal_location) ~= 1 do
			Sleep(1);
		end
		
		local data = {};
		data.eax = util.read_int32(eax_location);
		data.ecx = util.read_int32(ecx_location);
		data.edx = util.read_int32(edx_location);
		data.ebx = util.read_int32(ebx_location);
		data.esp = util.read_int32(esp_location);
		data.ebp = util.read_int32(ebp_location);
		data.esi = util.read_int32(esi_location);
		data.edi = util.read_int32(edi_location);
		
		pcall(function()
			on_execute(data)
		end);
		
		-- Let execution continue after our detour
		util.write_int32(signal_location, 2);
	end)
	
	
	while not detour_data.running do Sleep(1) end
	
	autoAssemble(start_code);
	
	
	--[[autoAssemble(start_code);
	
	createThread(function()
		pcall(function()
			event_trigger();
		end);
	end);
	
	detour_data.running = true;
	
	while detour_data.running do
		while util.read_int32(signal_location) ~= 1 do
			Sleep(1);
		end
		
		detour_data.stop();
		
		local data = {};
		data.eax = util.read_int32(eax_location);
		data.ecx = util.read_int32(ecx_location);
		data.edx = util.read_int32(edx_location);
		data.ebx = util.read_int32(ebx_location);
		data.esp = util.read_int32(esp_location);
		data.ebp = util.read_int32(ebp_location);
		data.esi = util.read_int32(esi_location);
		data.edi = util.read_int32(edi_location);
		
		pcall(function()
			on_execute(data)
		end);
		
		-- Let execution continue after our detour
		util.write_int32(signal_location, 2);
		break;
	end]]
	
	return detour_data;
end

util.new_detour = function(location, reg32, reg_offset, count, new_value)
	local hook_size = 0;
	local count = count or 0;
	local maxhits = 1;
	local timeout = 0;
	local r1 = 6; -- ESI
	local r2 = 7; -- EDI
	local debug_reg;
	
	while hook_size < 5 do
	    hook_size = hook_size + util.get_code_size(location + hook_size);
	end
	
	local old_bytes = util.read_bytes(location, hook_size);
	
	for i = 1,#util.reg32_names do
		if util.reg32_names[i] == reg32 then
			debug_reg = i - 1;
			break;
		end
	end
	
	if debug_reg == r1 then
		r1 = 0; -- Use EAX instead
	elseif debug_reg == r2 then
		r2 = 0; -- Use EAX instead
	end
	
	local hook = util.allocate_memory(1024);
	local hit_count_location = hook + 256;
	local jmpback_location = hook + 256 + 4;
	local update_location = hook + 256 + 8;
	local actual_reg_location = hook + 256 + 12;
	local output_location = hook + 256 + 16;
	
	local bytes_count = util.int_to_bytes(count * 4);
	local bytes_reg_offset = util.int_to_bytes(reg_offset or 0);
	local bytes_hit_count = util.int_to_bytes(hit_count_location);
	local bytes_reg_value = util.int_to_bytes(actual_reg_location);
	local bytes_output = util.int_to_bytes(output_location);
	local bytes_update = util.int_to_bytes(update_location);
	local bytes_jmpback = util.int_to_bytes(jmpback_location);
	
	util.write_int32(update_location, new_value);
	util.write_int32(jmpback_location, location + hook_size);
	
	local jmp_dist1;
	
	if count > 0 then
		jmp_dist1 = 0x1E;
	else
		jmp_dist1 = 0x6;
	end
	
	local bytes = {
		0x60, -- pushad
		0x9C, -- pushfd
		0x50 + r1, -- push r1
		0x50 + r2, -- push r2
		0xB8 + r2, -- mov edi, reg_offset
		bytes_reg_offset[1], bytes_reg_offset[2], bytes_reg_offset[3], bytes_reg_offset[4],
		0x81, 0x05, -- add [hit_count], 1
		bytes_hit_count[1], bytes_hit_count[2], bytes_hit_count[3], bytes_hit_count[4],
		maxhits, 0, 0, 0,
		0x81, 0x3D, -- cmp [hit_count], maxhits
		bytes_hit_count[1], bytes_hit_count[2], bytes_hit_count[3], bytes_hit_count[4],
		maxhits, 0, 0, 0,
		0x77, jmp_dist1, -- ja next
		-- label dump_next_register
		0x89, 5 + (debug_reg * 8), -- mov [actual reg value], debug_reg
		bytes_reg_value[1], bytes_reg_value[2], bytes_reg_value[3], bytes_reg_value[4]
	};
	
	if new_value ~= nil then
		local bytes2 = nil
		
		if reg_offset == nil then
			-- Not setting the value at the register offset
			local appendBytes = {
				0x8B, 5 + (debug_reg * 8), -- mov debug_reg, [update_location]
				bytes_update[1], bytes_update[2], bytes_update[3], bytes_update[4]
			};
			
			jmp_dist1 = jmp_dist1 + #appendBytes;
			tcombine(bytes, appendBytes);
		else
			-- Setting the value at the offset of the register
			local appendBytes = {
				0x8B, 5 + (r1 * 8), -- mov reg, [update_location]
				bytes_update[1], bytes_update[2], bytes_update[3], bytes_update[4],
				
				0x89, 0x80 + debug_reg + (r1 * 8), -- mov [debug_reg + reg_offset], reg
				bytes_reg_offset[1], bytes_reg_offset[2], bytes_reg_offset[3], bytes_reg_offset[4]
			};
			
			jmp_dist1 = jmp_dist1 + #appendBytes;
			tcombine(bytes, appendBytes);
		end
	end
	
	if count > 0 then
		tcombine(bytes, {
			0x8B, 0x44 + (r1 * 8), (r2 * 8) + debug_reg, 0--[[reg_offset]], -- mov reg,[debug_reg + reg + reg_offset]
			0x89, 0x80 + (r1 * 8) + r2, -- mov [reg+OUTPUT_LOCATION],reg
			bytes_output[1], bytes_output[2], bytes_output[3], bytes_output[4],
			0x81, 0xC0 + r2, 4, 0, 0, 0, -- add reg, 4
			0x81, 0xF8 + r2, -- cmp reg, dumpsize
			bytes_count[1], bytes_count[2], bytes_count[3], bytes_count[4],
			0x72, 0xE2
		});
	end
	
	tcombine(bytes, {
		0x58 + r2, -- pop r2
		0x58 + r1, -- pop r1
		0x9D, -- popfd
		0x61, -- popad
	});
	
	tcombine(bytes, old_bytes);
	
	tcombine(bytes, {
		0xFF, 0x25, 
		bytes_jmpback[1], bytes_jmpback[2], bytes_jmpback[3], bytes_jmpback[4]
	});
	
	util.write_bytes(hook, bytes);
	
	local nops = hook_size - 5;
	local start_code = util.int_to_str(location)..": \n";
	start_code = start_code .. "jmp " .. util.int_to_str(hook) .. " \n";
	for i = 1, nops do
		start_code = start_code .. "nop \n";
	end
	
	--print("HOOK: ", string.format("%08X", hook));
	
	local detour_data = {};
	
	detour_data.stop = function()
		util.write_bytes(location, old_bytes);
		
		local output_reg = actual_reg_location;
		local output_reg_contents = output_location;
		local result = {};
		result.value = util.read_int32(output_reg);
		result.content = {};
		
		for i = 1,count do
			table.insert(result.content, util.read_int32(output_reg_contents + ((i - 1) * 4)));
		end
		
		util.free_memory(hook);
		
		return result;
	end
	
	detour_data.start = function()
		autoAssemble(start_code);
		
		while util.read_int32(hit_count_location) < maxhits do
			Sleep(1);
		end
		
		return detour_data.stop();
	end
	
	detour_data.start_async = function()
		autoAssemble(start_code);
	end
	
	
	return detour_data;
end

--[[
Pardon my language but when you release something good for free,
it makes alot of the middle schoolers in exploit development very angry.

Here's a list of the most toxic users in this community -- literal bastards,
who are covered in cystic acne and can't get a girlfriend:

- Kronix     -- Owner of "Temple", a shitsploit that nobody uses or likes, but no one can refund.
- Berserker  -- /\
- Customality -- Owner of Sentinel, the exploit that took 12 months to release just so he can expand his massive ego
- ShowerHeadFD -- Owner of Krnl, the free exploit that he didn't make
- Ice Bear -- Annoying person w/ ego
- Shade -- Annoying person w/ ego
]]
util.new_remote = function(options)

	local default_options	= not options;
	local fremote 		 	= {};
	
	fremote.routines 					= {};
	fremote.remote_location 			= 0;
	fremote.function_id_location 		= 0; --function id, int value
	fremote.args_location 				= 0; -- args, up to 64-bits supported
	fremote.ret32_location 				= 0; -- 32 bit return value
	fremote.ret64_location 				= 0; -- 64 bit return value
	fremote.functions_location 			= 0; -- table index = id, value = function routine address
	fremote.function_return_location 	= 0; -- where an added function jumps back to
	fremote.veh 						= 0;

	fremote.init = function()
		fremote.remote_location 			= util.allocate_memory(2048);
	
        fremote.function_id_location 		= fremote.remote_location + 512;
        fremote.ret32_location 				= fremote.remote_location + 516;
        fremote.ret64_location 				= fremote.remote_location + 520;
        fremote.args_location 				= fremote.remote_location + 528;
        fremote.functions_location 			= fremote.remote_location + 680;
		fremote.function_return_location 	= fremote.remote_location + 6;
		
		local bytes_function_id 			= util.int_to_bytes(fremote.function_id_location);
		local bytes = {
		    0x55,							-- push ebp
			0x8B, 0xEC,						-- mov ebp, esp
			0x50,							-- push eax
			0x56,							-- push esi
			0x57,							-- push edi
			0x8B, 0x3D, 					-- mov edi, dword ptr [function_id_location]
			bytes_function_id[1], bytes_function_id[2], bytes_function_id[3], bytes_function_id[4],
			0x81, 0xFF, 0, 0, 0, 0, 		-- cmp edi, 00000000
			0x74, 0xF2, 					-- je wait_async
			0xFF, 0x25, 					-- jmp dword ptr [function_id_location]
			bytes_function_id[1], bytes_function_id[2], bytes_function_id[3], bytes_function_id[4],
			0x58,							-- pop eax
			0x5E,							-- pop esi
			0x5F,							-- pop edi
			0x5D,							-- pop ebp
			0xC2, 4, 0						-- ret 0004
		};
		
		util.write_bytes(fremote.remote_location, bytes);
	end
	
	fremote.start = function()
		createRemoteThread(fremote.remote_location);
	end

	fremote.flush = function()
		-- I need to figure out a free memory function
		-- in cheat engine dammit
		
		if fremote.veh ~= 0 then
            --VirtualFreeEx(handle, fremote.veh, 0, MEM_RELEASE);
        end

        -- Try to kill the thread somehow, even
		-- if it's in a ROBLOX function call...
        -- ....
		
		for _,v in pairs(fremote.routines) do
			util.free_memory(v);
        end
		
		util.free_memory(fremote.remote_location);
	end

	-- inject a stub which is able to be called
	-- externally with our initial function
	fremote.create = function(func, convention, args)
		local routine = util.allocate_memory(1024)
		local arg_data = fremote.args_location;

		-- generate assembly code which will call the function
		-- using our very efficient control system
		local code = util.int_to_str(routine)..": \n";
		
		if (convention == "cdecl" or convention == "stdcall") then
			for i = args, 1, -1 do
				code = code .. "push [" .. util.int_to_str(fremote.args_location + ((i - 1) * 8)) .. "] \n"
			end
		elseif (convention == "thiscall") then
			if (args > 1) then
				for i = args, 2, -1 do
					code = code .. "push [" .. util.int_to_str(fremote.args_location + ((i - 1) * 8)) .. "] \n"
				end
			end
			if (args > 0) then
				code = code .. "mov ecx,[" .. util.int_to_str(fremote.args_location + 0) .. "] \n"
			end
		elseif (convention == "fastcall") then
			if (args > 2) then
				for i = args, 3, -1 do
					code = code .. "push [" ..util.int_to_str(fremote.args_location + ((i - 1) * 8)) .. "] \n"
				end
			end
			if (args > 1) then
				code = code .. "mov edx,[" .. util.int_to_str(fremote.args_location + 8) .. "] \n"
			end
			if (args > 0) then
				code = code .. "mov ecx,[" .. util.int_to_str(fremote.args_location + 0) .. "] \n"
			end
		end

		-- insert the call
		code = code .. "call " .. util.int_to_str(func) .. " \n"
		code = code .. "mov [" .. util.int_to_str(fremote.ret32_location) .. "],eax \n";
		code = code .. "movss [" .. util.int_to_str(fremote.ret64_location) .. "],xmm0 \n";

		if (convention == "cdecl") then
			if (args > 0) then
				code = code .. "add esp," .. util.byte_to_str(args * 4) .. " \n"
			end
		end

		code = code .. "mov [" .. util.int_to_str(fremote.function_id_location) .. "],00000000 \n";
		code = code .. "jmp " .. util.int_to_str(fremote.function_return_location) .. " \n";

		autoAssemble(code);
		
		
		table.insert(fremote.routines, routine);
		
		-- append this routine's address to our routine 'table'
		-- which is callable by ID (0-99, 99 = max)
        util.write_int32(fremote.functions_location + (#fremote.routines * 4), routine);
		
		
		return function(...)
			local args = {...};
			local strings = {};
			
			if #args == 0 then
				util.write_int32(fremote.function_id_location, routine);
				
				while (util.read_int32(fremote.function_id_location) ~= 0) do
					Sleep(1);
				end
			
				return { 
					util.read_int32(fremote.ret32_location),
					util.read_int64(fremote.ret64_location)
				};
			elseif #args > 0 then
				for i = 1,#args do
					local arg = args[i];
					
				    if type(arg) == "string" then
						local len = string.len(arg);
						local str = util.allocate_memory(len + 0x10);
						
						util.write_string(str, arg);
						util.write_int32(str + len + 4 + (len % 4), len);
						
						util.write_int32(fremote.args_location + (i - 1) * 8, str);
					elseif type(arg) == "boolean" then
						util.write_int32(fremote.args_location + (i - 1) * 8, arg and 1 or 0);
					elseif type(arg) == "number" then
						util.write_int32(fremote.args_location + (i - 1) * 8, arg);
					else
						error("Invalid type '" .. type(arg) .. "' passed to function RC");
					end
				end
			
				util.write_int32(fremote.function_id_location, routine);
				
				while (util.read_int32(fremote.function_id_location) ~= 0) do
					Sleep(1);
				end
			
				return { 
					util.read_int32(fremote.ret32_location),
					util.read_int64(fremote.ret64_location)
				};
			end
		end
	end
	
	return fremote;
end

return util;
