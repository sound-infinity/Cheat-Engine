assert(_VERSION ~= "5.3", "Lua 5.3 expected");

script_source = [[print("Hello World!")]]

--#region importer
local Importer = {_initalized=false}
function Importer:Init()
    if self._initalized then
        return
    end
    self._initalized = true
    self._github_hostname = "https://raw.githubusercontent.com"
    self._github_repo_pattern = "%s/%s"
    self._cached = {}
end

function Importer:LoadContents(contents, autoload_disabled)
    ---@diagnostic disable-next-line
    local lsfunction = loadstring(contents)
    if load then
        lsfunction = load(contents)
    elseif loadstring then ---@diagnostic disable-line
        lsfunction = loadstring(contents) ---@diagnostic disable-line
    else
        error("failed to import. loadstring nor load are defined.")
    end
    if autoload_disabled ~= true then
        if type(lsfunction) == "function" then
            ---@diagnostic disable-next-line
            return lsfunction()
        end        
    end
    return lsfunction
end

function Importer:ImportUrl(url)
    self:Init()
    local net = getInternet()
    local suc, response = pcall(net.getURL, url)
    net.destroy()
    if suc then
        return self:LoadContents(response)
    else
        print("error:", response)
    end
end

function Importer:ImportFromRepo(repo_author, repo_name, branch)
    self:Init()
    local buffer = {
        self._github_hostname, 
        self._github_repo_pattern:format(repo_author, repo_name),
        branch
    }
    return {
        ["Import"] = function(_, pathname, cache)
            buffer[4] = pathname
            local fullname = table.concat(buffer, "/")
            local cached = self._cached[fullname]
            if cached ~= nil then
                return cached
            end
            local lsfunction = self:ImportUrl(fullname)
            if cache == true then
                self._cached[fullname] = lsfunction
            end
            return lsfunction
        end,
    }
end
--#endregion
local importer = Importer:ImportFromRepo("sound-infinity", "Cheat-Engine", "master")
local function require(pathname)
    pathname = pathname:gsub("[.]", "/")
    pathname = pathname .. ".lua"
    return importer:Import(pathname, true)
end

local Tasklist = require("API.tasklist")
local Kernel32 = require("API.kernel32")

--#region open-process
print("[Tasklist] Generating list of processes...")
local tasklist = Tasklist:Fetch("roblox") or error("roblox process was not found running.")
local primary_process = nil
local secondary_process = nil

for _, task in pairs(tasklist) do
	local name = task.Name:lower()
	if name:match("roblox") and name:match("player") then
		if primary_process == nil then
			primary_process = task
		elseif primary_process.MemoryUsage > task.MemoryUsage then
			secondary_process = task
		elseif primary_process.MemoryUsage < task.MemoryUsage then
			secondary_process = primary_process
			primary_process = task
		end
	end
end
--#endregion

if secondary_process ~= nil then
    print("[Kernel32] Terminating secondary process...")
    Kernel32:TerminateProcess(secondary_process.ProcessId)    
end
print("[Tasklist] Opening primary process...")
openProcess(primary_process.ProcessId)
print(string.rep("\r\n", 4))

loader = {}
loader.clock_start = os.clock();
require("API.api_celua")
require("API.api_util")

util.init(primary_process.ProcessId)

rbx = {};
rbx.offsets = {};
rbx.functions = {};
rbx.luau = {};

-- excerpt from lopcodes.h and modified for luau format
--
rbx.luau.size_c = 8;
rbx.luau.size_b = 8;
rbx.luau.size_bx = (rbx.luau.size_c + rbx.luau.size_b);
rbx.luau.size_a = 8;
rbx.luau.size_op = 8;
rbx.luau.pos_op = 0;
rbx.luau.pos_a = (rbx.luau.pos_op + rbx.luau.size_op);
rbx.luau.pos_c = (rbx.luau.pos_a + rbx.luau.size_a);
rbx.luau.pos_b = (rbx.luau.pos_c + rbx.luau.size_c);
rbx.luau.pos_bx = rbx.luau.pos_c;
rbx.luau.maxarg_a = ((1 << rbx.luau.size_a) - 1);
rbx.luau.maxarg_b = ((1 << rbx.luau.size_b) - 1);
rbx.luau.maxarg_c = ((1 << rbx.luau.size_c) - 1);
rbx.luau.maxarg_bx = ((1 << rbx.luau.size_bx) - 1);
rbx.luau.maxarg_sbx = (rbx.luau.maxarg_bx >> 1);

rbx.luau.mask1 = function(n,p) return (~((~0) << n)) << p end
rbx.luau.mask0 = function(n,p) return (~rbx.luau.mask1(n, p)) end

rbx.luau.set_opcode = function(i,o)
    return (((i & rbx.luau.mask0(rbx.luau.size_op, rbx.luau.pos_op)) | ((o << rbx.luau.pos_op) & rbx.luau.mask1(rbx.luau.size_op, rbx.luau.pos_op))));
end

rbx.luau.setarg_a = function(i,o)
    return (((i & rbx.luau.mask0(rbx.luau.size_a, rbx.luau.pos_a)) | ((o << rbx.luau.pos_a) & rbx.luau.mask1(rbx.luau.size_a, rbx.luau.pos_a))));
end

rbx.luau.setarg_b = function(i,o)
    return (((i & rbx.luau.mask0(rbx.luau.size_b, rbx.luau.pos_b)) | ((o << rbx.luau.pos_b) & rbx.luau.mask1(rbx.luau.size_b, rbx.luau.pos_b))));
end

rbx.luau.setarg_bx = function(i,o)
    return (((i & rbx.luau.mask0(rbx.luau.size_bx, rbx.luau.pos_bx)) | ((o << rbx.luau.pos_bx) & rbx.luau.mask1(rbx.luau.size_bx, rbx.luau.pos_bx))));
end

rbx.luau.setarg_c = function(i,o)
    return (((i & rbx.luau.mask0(rbx.luau.size_c, rbx.luau.pos_c)) | ((o << rbx.luau.pos_c) & rbx.luau.mask1(rbx.luau.size_c, rbx.luau.pos_c))));
end

rbx.luau.setarg_sbx = function(i,o)
    return rbx.luau.setarg_bx(i, o);
end

rbx.luau.op_noop = 0x00;
rbx.luau.op_markupval = 0x12;
rbx.luau.op_initva = 0xA3;
rbx.luau.op_move = 0x52;
rbx.luau.op_loadnil = 0xC6;
rbx.luau.op_loadbool = 0xA9;
rbx.luau.op_loadnumber = 0x8C;
rbx.luau.op_loadk = 0x6F;
rbx.luau.op_newtable = 0xFF;
rbx.luau.op_getupval = 0xFB;
rbx.luau.op_getglobal = 0x35;
rbx.luau.op_gettable = 0x87;
rbx.luau.op_setupval = 0xDE;
rbx.luau.op_setglobal = 0x18;
rbx.luau.op_settable = 0x6A;
rbx.luau.op_setlist = 0xC5;
rbx.luau.op_unm = 0x39;
rbx.luau.op_not = 0x56;
rbx.luau.op_len = 0x1C;
rbx.luau.op_concat = 0x73;
rbx.luau.op_tforloop = 0x6E;
rbx.luau.op_forprep = 0xA8;
rbx.luau.op_forloop = 0x8B;
rbx.luau.op_jmp = 0x65;
rbx.luau.op_self = 0xBC;
rbx.luau.op_add = 0x43;
rbx.luau.op_sub = 0x26;
rbx.luau.op_mul = 0x09;
rbx.luau.op_div = 0xEC;
rbx.luau.op_pow = 0xB2;
rbx.luau.op_mod = 0xCF;
rbx.luau.op_eq = 0xF1;
rbx.luau.op_neq = 0x9A;
rbx.luau.op_lt = 0xB7;
rbx.luau.op_gt = 0x60;
rbx.luau.op_le = 0xD4;
rbx.luau.op_ge = 0x7D;
rbx.luau.op_ntest = 0x2B;
rbx.luau.op_test = 0x0E;
rbx.luau.op_call = 0x9F;
rbx.luau.op_vararg = 0xDD;
rbx.luau.op_closure = 0xD9;
rbx.luau.op_close = 0xC1;
rbx.luau.op_return = 0x82;

rbx.luau.const_nil = 0;
rbx.luau.const_boolean = 1;
rbx.luau.const_number = 2;
rbx.luau.const_string = 3;

rbx.code_ip = function(data)
    return data;
end

rbx.code_ia = function(Op, A)
    local new_inst = 0;
    new_inst = rbx.luau.set_opcode(new_inst, Op);
    new_inst = rbx.luau.setarg_a(new_inst, A);
    return new_inst;
end

rbx.code_iab = function(Op, A, B)
    local new_inst = 0;
    new_inst = rbx.luau.set_opcode(new_inst, Op);
    new_inst = rbx.luau.setarg_a(new_inst, A);
    new_inst = rbx.luau.setarg_bx(new_inst, B);
    return new_inst;
end

rbx.code_iabx = function(Op, A, Bx)
    local new_inst = 0;
    new_inst = rbx.luau.set_opcode(new_inst, Op);
    new_inst = rbx.luau.setarg_a(new_inst, A);
    new_inst = rbx.luau.setarg_bx(new_inst, Bx);
    return new_inst;
end

rbx.code_iasbx = function(Op, A, sBx)
    local new_inst = 0;
    new_inst = rbx.luau.set_opcode(new_inst, Op);
    new_inst = rbx.luau.setarg_a(new_inst, A);
    new_inst = rbx.luau.setarg_sbx(new_inst, sBx);
    return new_inst;
end

rbx.code_iabc = function(Op, A, B, C)
    local new_inst = 0;
    new_inst = rbx.luau.set_opcode(new_inst, Op);
    new_inst = rbx.luau.setarg_a(new_inst, A);
    new_inst = rbx.luau.setarg_b(new_inst, C);
    new_inst = rbx.luau.setarg_c(new_inst, B);
    return new_inst;
end


rbx.transpile = function(proto)
    --print("proto sizecode: ", proto.sizeCode);
    --[[if #proto.upValueNames > 0 then
        if proto.upValueNames[1] == '_ENV' then
            proto.upValueNames[1] = nil;
        end
    end
    ]]
    local rbxProto = {};

    rbxProto.sizeCode = 0;
    rbxProto.code = {};
    rbxProto.lines = 0;
    rbxProto.lineInfos = {};
    rbxProto.maxStackSize = proto.maxStackSize;

    local open_reg = { false, false, false };
    local new_sizes = {};
    local marked_ups = {};
    local self_map = {};
    local relocations = {};
    local close_upvalues = false;

    local function apply_relocation(index_from, offset, shift)
        local t = {};
        t.from_index = index_from; -- index_from = `at` = lua indexing (starts at 1)
        t.to_index = t.from_index + offset; -- add 1 to compensate ^^^
        t.real_code_index = #rbxProto.code;
        t.shift = shift or 0;
        table.insert(relocations, t);
    end

    --table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_initva, 0, proto.numParams));

    local open_reg_at = 1;
    local at = 1;
    while at <= proto.sizeCode do
        local new_inst = 0;
        local open_reg_at = 1;
        local i = proto.code[at];
        local opcode_name = celua.OPCODE_NAMES[celua.GET_OPCODE(i) + 1];
        local A = celua.GETARG_A(i);
        local B = celua.GETARG_B(i);
        local C = celua.GETARG_C(i);

        -- this solution works better..and avoids
        -- dealing with the hell of lua numbers
        local Bx = ((B << 8) | (C)) & 0xFFFF;
        local sBx = Bx + 1;
        if Bx > 0x7FFF and Bx <= 0xFFFF then
            sBx = -(0xFFFF - Bx);
        end

        table.insert(new_sizes, #rbxProto.code);
        --print(string.format("Vanilla Opcode: %s %02X %02X %02X", opcode_name, A, B, C));

        local function next_open_reg()
            local slot_index = proto.maxStackSize + (open_reg_at - 1);
            open_reg[open_reg_at] = true;
            open_reg_at = open_reg_at + 1;
            return slot_index;
        end

        if opcode_name == "ADD" or opcode_name == "SUB" or opcode_name == "DIV" or opcode_name == "MUL" or opcode_name == "POW" or opcode_name == "MOD" then
            if celua.ISK(B) ~= 0 then
                local real = celua.INDEXK(B);
                B = next_open_reg();
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_loadk, B, real));
            end

            if celua.ISK(C) ~= 0 then
                local real = celua.INDEXK(C);
                C = next_open_reg();
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_loadk, C, real));
            end

            if opcode_name == "ADD" then
                table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_add, A, B, C));
            elseif opcode_name == "SUB" then
                table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_sub, A, B, C));
            elseif opcode_name == "MUL" then
                table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_mul, A, B, C));
            elseif opcode_name == "DIV" then
                table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_div, A, B, C));
            elseif opcode_name == "POW" then
                table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_pow, A, B, C));
            elseif opcode_name == "MOD" then
                table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_mod, A, B, C));
            end
        elseif opcode_name == "MOVE" then
            if marked_ups[at] then
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_markupval, 1, A));
            else
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_move, A, B));
            end
        elseif opcode_name == "GETTABUP" then
            local tname = proto.upValueNames[B + 1];
            if not tname or tname == "_ENV" then
                -- using _ENV? just do roblox GETGLOBAL
                table.insert(rbxProto.code, rbx.code_ia(rbx.luau.op_getglobal, A));
                table.insert(rbxProto.code, rbx.code_ip(celua.INDEXK(C)));
            else
                if celua.ISK(C) ~= 0 then
                    local real = celua.INDEXK(C);
                    C = next_open_reg();
                    table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_loadk, C, real));
                end

                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_getupval, A, B));
                table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_gettable, A, A, C));
            end
        elseif opcode_name == "GETUPVAL" then
            if marked_ups[at] then
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_markupval, 2, A));
            else
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_getupval, A, B));
            end
        elseif opcode_name == "SETUPVAL" then
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_setupval, A, B));
        elseif opcode_name == "SETTABUP" then
            local tname = proto.upValueNames[A + 1];
            local free_reg = next_open_reg();

            if celua.ISK(C) ~= 0 then
                local real = celua.INDEXK(C);
                C = next_open_reg();
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_loadk, C, real));
            end

            if not tname or tname == "_ENV" then
                -- using _ENV? just do roblox SETGLOBAL
                table.insert(rbxProto.code, rbx.code_ia(rbx.luau.op_setglobal, C));
                table.insert(rbxProto.code, rbx.code_ip(celua.INDEXK(B)));
            else
                if celua.ISK(B) ~= 0 then
                    local real = celua.INDEXK(B);
                    B = next_open_reg();
                    table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_loadk, B, real));
                end

                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_getupval, free_reg, A));
                table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_settable, C, free_reg, B));
            end
        elseif opcode_name == "GETTABLE" then
            if celua.ISK(C) ~= 0 then
                local real = celua.INDEXK(C);
                C = next_open_reg();
                table.insert(rbxProto.code, rbx.code_iabx(rbx.luau.op_loadk, C, real));
            end
            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_gettable, A, B, C));
        elseif opcode_name == "SETTABLE" then
            if celua.ISK(B) ~= 0 then
                local real = celua.INDEXK(B);
                B = next_open_reg();
                table.insert(rbxProto.code, rbx.code_iabx(rbx.luau.op_loadk, B, real));
            end

            if celua.ISK(C) ~= 0 then
                local real = celua.INDEXK(C);
                C = next_open_reg();
                table.insert(rbxProto.code, rbx.code_iabx(rbx.luau.op_loadk, C, real));
            end

            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_settable, C, A, B));
        elseif opcode_name == "FORPREP" then
            local base = A;
            local pos = next_open_reg();

            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_move, pos + 0, base + 0));
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_move, base + 0, base + 1));
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_move, base + 1, base + 2));
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_move, base + 2, pos + 0));

            table.insert(rbxProto.code, rbx.code_ia(rbx.luau.op_forprep, A));
            apply_relocation(at, sBx, -4);

            -- the sexy iterator fix
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_move, base + 3, base + 2));
        elseif opcode_name == "FORLOOP" then
            table.insert(rbxProto.code, rbx.code_ia(rbx.luau.op_forloop, A));
            apply_relocation(at, sBx, 4);
        elseif opcode_name == "TFORCALL" then
            table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_tforloop, A, 2));

            local i = proto.code[at + 1];
            local B = celua.GETARG_B(i);
            local C = celua.GETARG_C(i);
            local Bx = ((B << 8) | (C)) & 0xFFFF;
            local sBx = celua.GETARG_sBx(proto.code[at + 1]);
            if Bx > 0x7FFF and Bx <= 0xFFFF then
                sBx = -(0xFFFF - Bx);
                sBx = sBx - 1;
            end

            apply_relocation(at, sBx + 2);

            table.insert(rbxProto.code, rbx.code_ip(2));
        elseif opcode_name == "TFORLOOP" then
            table.insert(rbxProto.code, rbx.code_ia(rbx.luau.op_noop, 0));
            --table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_jmp, 0, 0));
            --apply_relocation(at, sBx + 2);
        elseif opcode_name == "EQ" or opcode_name == "LT" or opcode_name == "LE" then
            if celua.ISK(B) ~= 0 then
                local real = celua.INDEXK(B);
                B = next_open_reg();
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_loadk, B, real));
            end

            if celua.ISK(C) ~= 0 then
                local real = celua.INDEXK(C);
                C = next_open_reg();
                table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_loadk, C, real));
            end

            if A == 0 then
                if opcode_name == "EQ" then
                    table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_eq, B, 2));
                elseif opcode_name == "LT" then
                    table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_lt, B, 2));
                elseif opcode_name == "LE" then
                    table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_le, B, 2));
                end
            else
                if opcode_name == "EQ" then
                    table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_neq, B, 2));
                elseif opcode_name == "LT" then
                    table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_gt, B, 2));
                elseif opcode_name == "LE" then
                    table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_ge, B, 2));
                end
            end

            table.insert(rbxProto.code, rbx.code_ip(C));
        elseif opcode_name == "TEST" then -- A C  if not (R(A) <=> C) then pc++
            if C > 0 then
                table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_test, A, 1));
            else
                table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_ntest, A, 1));
            end
        elseif opcode_name == "TESTSET" then -- A B C  if (R(B) <=> C) then R(A) := R(B) else pc++
            -- swap these modes?
            if C > 0 then
                table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_test, A, 2));
            else
                table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_ntest, A, 2));
            end
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_move, A, B));
        elseif opcode_name == "SETLIST" then
            local lfields_per_flush = 50; -- doesnt seem to affect anything
            local fields = 0;
            if B ~= 0 then
                fields = B + 1;
            end
            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_setlist, A, A + 1, fields));
            table.insert(rbxProto.code, rbx.code_ip((C - 1) * lfields_per_flush + 1));
        elseif opcode_name == "JMP" then
            --[[if celua.OPCODE_NAMES[celua.GET_OPCODE(proto.code[at + sBx + 1]) + 1] == "TFORCALL" then
                table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_jmp, 0, 0));
                apply_relocation(at, sBx + 1);
            else]]
                table.insert(rbxProto.code, rbx.code_iasbx(rbx.luau.op_jmp, 0, 0));
                apply_relocation(at, sBx + 1, -1);
            --end
        elseif opcode_name == "SELF" then
            -- handled by CALL/TAILCALL
        elseif opcode_name == "LOADK" then
            table.insert(rbxProto.code, rbx.code_iabx(rbx.luau.op_loadk, A, Bx));
        elseif opcode_name == "LOADBOOL" then
            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_loadbool, A, B, C));
        elseif opcode_name == "LOADNIL" then
            while B >= A do
                table.insert(rbxProto.code, rbx.code_ia(rbx.luau.op_loadnil, B));
                B = B - 1;
            end
        elseif opcode_name == "CALL" or opcode_name == "TAILCALL" then
            -- SELF(reg a, reg b, value c)
            -- a + 1 = b;
            -- a = b[c];
            for self_at = at - 1, 1, -1 do
                local self = proto.code[self_at];
                local opcode_name = celua.OPCODE_NAMES[celua.GET_OPCODE(self) + 1];

                if (opcode_name == "SELF") then
                    proto.code[self_at] = 0; -- dont let this SELF get used again

                    local prev = 0;
					if self_at - 1 >= 1 then
					    celua.GETARG_Bx(proto.code[self_at - 1]);
					end

                    table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_self, celua.GETARG_A(self), celua.GETARG_B(self)));

                    if celua.ISK(celua.GETARG_C(self)) ~= 0 then
                        table.insert(rbxProto.code, rbx.code_ip(celua.INDEXK(celua.GETARG_C(self))))
                    else
                        table.insert(rbxProto.code, rbx.code_ip(prev));
                    end

                    break;
                end
            end

            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_call, A, B, C));
        elseif opcode_name == "CONCAT" then
            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_concat, A, B, C));
        elseif opcode_name == "LEN" then
            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_len, A, B, C));
        elseif opcode_name == "UNM" then
            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_unm, A, B, C));
        elseif opcode_name == "NOT" then
            table.insert(rbxProto.code, rbx.code_iabc(rbx.luau.op_not, A, B, C));
        elseif opcode_name == "VARARG" then
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_vararg, A, B));
        elseif opcode_name == "NEWTABLE" then
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_newtable, A, 0));
            table.insert(rbxProto.code, 0);
        elseif opcode_name == "CLOSURE" then
            table.insert(rbxProto.code, rbx.code_iabx(rbx.luau.op_closure, A, Bx));

            local cl = proto.protos[Bx + 1];
            if #cl.upValues > 0 then
                close_upvalues = true;

				--[[for i = 1,#cl.upValues do
					--print(((A - #cl.upValues) + (i - 1)), "==", cl.upValues[i].Register, '?');
					local upvalue_reg = ((A - #cl.upValues) + (i - 1)); --cl.upValues[i].Register;
                    table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_markupval, 1, upvalue_reg));
				end]]

				for n,upvalue_name in pairs(cl.upValueNames) do
					local upvalue_reg = --[[((A - #cl.upValues) + (i - 1)); ]] cl.upValues[n].Register;
					local carry = true;

					if upvalue_name == "_ENV" then
						carry = false;
					end

					for _,v in pairs(proto.locVars) do
						--print(upvalue_name, "==", v.name);
						if v.name == upvalue_name then
							--print(upvalue_name, "==", v.name);
							carry = false;
							break;
						end
					end

                    if not carry then
                        table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_markupval, 1, upvalue_reg));
                    else
                        --print'Carrying upvalue...'
                        for i,v in pairs(proto.upValueNames) do
                            if v == upvalue_name then
								table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_markupval, 2, i - 1));
                                break;
                            end
                        end
                    end
                end
            end
        elseif opcode_name == "RETURN" then
            if close_upvalues then
                table.insert(rbxProto.code, rbx.code_ia(rbx.luau.op_close, A));
            end
            table.insert(rbxProto.code, rbx.code_iab(rbx.luau.op_return, A, B));
        elseif opcode_name == "CLOSE" then
            table.insert(rbxProto.code, rbx.code_ia(rbx.luau.op_close, A));
        else
            error('UNREGISTERED OPCODE USED: '..opcode_name)
        end

        at = at + 1;
    end

    for _,rel in pairs(relocations) do

        if new_sizes[rel.to_index] and new_sizes[rel.from_index] then
            local dist = new_sizes[rel.to_index] - new_sizes[rel.from_index];
            dist = dist + rel.shift;

            --print(string.format("New distance for %08X --> %i", rbxProto.code[rel.real_code_index], dist));
            rbxProto.code[rel.real_code_index] = rbx.luau.setarg_sbx(rbxProto.code[rel.real_code_index], dist);
        else
            error(string.format("Bad sBx relocation [ %08X, %08X, %i ]", rel.from_index, rel.to_index, #new_sizes));
        end
    end

    --[[
	for i = 1, #rbxProto.code do
		local bytes = util.int_to_bytes(rbxProto.code[i]);
		local Opcode = bytes[1];
		local A = bytes[2];
		local B = bytes[3];
		local C = bytes[4];
		print(string.format("ROBLOX Opcode: %02X %02X %02X %02X", Opcode, A, B, C));
	end
	]]


    for i = 1, 3 do
        if open_reg[i] then
            rbxProto.maxStackSize = rbxProto.maxStackSize + 1;
        end
    end

    rbxProto.sizeCode = #rbxProto.code;
    rbxProto.lines = #rbxProto.lineInfos;

    return rbxProto;
end

rbx.dump_function = function(f)
    local bytecode = {};
    local protoTable, stringTable = celua.deserialize(f);
    table.remove(stringTable, 1); -- remove lua string (debug info)

    local mainProtoId = #protoTable;
    local mainProto = protoTable[mainProtoId];

	-- in cheat engine, the initial proto has an upvalue
	-- '_ENV', but we don't need/want this
	mainProto.nups = 0;
	mainProto.upValueNames = {};

    local writer do
        writer = {};

        function writer:writeByte(val)
            table.insert(bytecode, val);
        end

        function writer:writeBytes(val)
            for i = 1,#val do
                table.insert(bytecode, val[i]);
            end
        end

        function writer:writeString(str)
            for i = 1,string.len(str) do
                table.insert(bytecode, string.byte(str:sub(i,i)));
            end
        end

        function writer:writeInt(val)
            local bytes = {val & 0xff, (val >> 8) & 0xff, (val >> 16) & 0xff, (val >> 24) & 0xff};
            writer:writeBytes(bytes);
        end

        function writer:writeDouble(val)
			local bytes = {}
			local str = string.pack("<d", val);
			for i = 1,8 do
				table.insert(bytes, str:byte(i,i));
			end
            writer:writeBytes(bytes);
        end

        function writer:writeCompressedInt(val)
            local value = val;
            repeat
                local v = (value & 0x7F);
                value = value >> 7;
                if not (value <= 0) then v = v | 0x80 end
                writer:writeByte(v);
            until (value <= 0)
        end

    end

    writer:writeByte(2);
    writer:writeCompressedInt(#stringTable);

    for _,str in pairs(stringTable) do
        --print(string.len(str), str);
        writer:writeCompressedInt(string.len(str));
        writer:writeString(str);
    end

    writer:writeCompressedInt(#protoTable);

    for _,proto in pairs(protoTable) do
        local rbxProto = rbx.transpile(proto);

        for i,v in pairs(proto.upValueNames) do
            if v == "_ENV" then
                proto.nups = proto.nups - 1;
            end
        end

        writer:writeByte(rbxProto.maxStackSize);
        writer:writeByte(proto.numParams);
        writer:writeByte(#proto.upValueNames); -- proto.nups not accurate...must fix later =-D
        writer:writeByte(proto.isVarArg);

        writer:writeCompressedInt(rbxProto.sizeCode);

        for i = 1, rbxProto.sizeCode do
            --print(string.format("%08X ", rbxProto.code[i]));
            writer:writeInt(rbxProto.code[i]);
        end

        writer:writeCompressedInt(proto.sizeConsts);

        for i = 1, proto.sizeConsts do
            local const = proto.consts[i];

            if const.Type == 0 then
                writer:writeByte(rbx.luau.const_nil);
            elseif const.Type == 1 then
                writer:writeByte(rbx.luau.const_boolean);

                if const.Data == 0 then
                    writer:writeByte(0);
                else
                    writer:writeByte(1);
                end
            elseif const.Type == 3 or const.Type == 0x13 then -- int or double
                writer:writeByte(rbx.luau.const_number);
                writer:writeDouble(const.Data or 0);
            elseif const.Type == 4 or const.Type == 0x14 then -- short string or long string
                writer:writeByte(rbx.luau.const_string);

                local strId = 1;
                while strId < #stringTable do
                    if stringTable[strId] == const.Data then
                        break;
                    end
                    strId = strId + 1;
                end
                writer:writeCompressedInt(strId);
            end
        end

        writer:writeCompressedInt(proto.numProtos);

        -- map each nested proto to their index
        -- as they appear in the prototable
        for protoId = 1, #protoTable do
            for nestedId = 1, #proto.protos do
                if proto.protos[nestedId] == protoTable[protoId] then
                    writer:writeCompressedInt(protoId - 1);
                end
            end
        end

        writer:writeByte(0); -- function/source string id
        writer:writeByte(0); -- function/source string id

        writer:writeByte(0); -- line info
        writer:writeByte(0); -- debug info
    end

    writer:writeCompressedInt(mainProtoId - 1);

    return bytecode;
end

retcheck = {};
retcheck.routine = 0;
retcheck.redirect = 0;
retcheck.patches = {};

retcheck.load = function()
    retcheck.routine = util.aobscan("5DFF25????????CC")[1] + 1;
    retcheck.redirect = util.read_int32(retcheck.routine + 2);
end

retcheck.patch = function(address)
    local function_start = address;
    local function_end = util.next_prologue(function_start + 16);
    local function_size = function_end - function_start;

    local patch = util.allocate_memory(1024);
    table.insert(retcheck.patches, patch);

    local function_is_naked = false; -- assumption

    local reg_prologue = util.read_byte(function_start) % 8;
    function_start = function_start + 3;

    local bytes_redirect = util.int_to_bytes(retcheck.redirect);
    local bytes_routine = util.int_to_bytes(retcheck.routine);
    local bytes_old_redirect = util.int_to_bytes(patch + 0x200);
    local bytes_old_return = util.int_to_bytes(patch + 0x204);
    local bytes_return = util.int_to_bytes(patch + 0x2E);
    local bytes_patch = util.int_to_bytes(patch);
    local bytes_jmp_function = util.int_to_bytes(function_start - (patch + 0x2E));

    local patch_bytes = {
        0x50 + reg_prologue,-- push ebp
        0x8B,				-- mov ebp,esp
        0xC4 + (reg_prologue * 8),
        0x50,				-- push eax
        0xA1,				-- mov eax, [redirect]
        bytes_redirect[1],
        bytes_redirect[2],
        bytes_redirect[3],
        bytes_redirect[4],
        0xA3,				-- mov [loc_old_redirect], eax
        bytes_old_redirect[1],
        bytes_old_redirect[2],
        bytes_old_redirect[3],
        bytes_old_redirect[4],
        0x8B,				-- mov eax, [ebp+4]
        0x40 + reg_prologue,
        0x04,
        0xA3,				-- mov [old_ebp], eax
        bytes_old_return[1],
        bytes_old_return[2],
        bytes_old_return[3],
        bytes_old_return[4],
        0xB8,				-- mov eax, routine
        bytes_routine[1],
        bytes_routine[2],
        bytes_routine[3],
        bytes_routine[4],
        0x89,				-- mov [ebp+4], eax
        0x40 + reg_prologue,
        0x04,
        0xB8,				-- mov eax, return_location
        bytes_return[1],
        bytes_return[2],
        bytes_return[3],
        bytes_return[4],
        0xA3,				-- mov [redirect], eax
        bytes_redirect[1],
        bytes_redirect[2],
        bytes_redirect[3],
        bytes_redirect[4],
        0x58,				-- pop eax
        0xE9, 				-- jmp func_start
        bytes_jmp_function[1],
        bytes_jmp_function[2],
        bytes_jmp_function[3],
        bytes_jmp_function[4],
        0x57, 				-- push edi
        0x8B,				-- mov edi, [loc_old_redirect]
        0x3D,
        bytes_old_redirect[1],
        bytes_old_redirect[2],
        bytes_old_redirect[3],
        bytes_old_redirect[4],
        0x89,				-- mov [redirect], edi
        0x3D,
        bytes_redirect[1],
        bytes_redirect[2],
        bytes_redirect[3],
        bytes_redirect[4],
        0x5F,				-- pop edi
        0xFF,				-- jmp dword ptr [old_ebp]
        0x25,
        bytes_old_return[1],
        bytes_old_return[2],
        bytes_old_return[3],
        bytes_old_return[4],
    };

    util.write_bytes(patch, patch_bytes);

    print("[Retcheck] Patch: " .. string.format("%08X", patch));
    return patch;
end

retcheck.flush = function()
    for _,v in pairs(retcheck.patches) do
        util.free_memory(v);
    end
end

rbx.old_script_hook_bytes = {};
rbx.set_script_hook = function(enabled, our_bytecode, our_bytecode_size)
    if enabled then
        rbx.script_hook = rbx.offsets.luau_loadbuffer + 3;
        local edit_location = util.allocate_memory(1024);
        local hook_jmp_back = edit_location + 256 + 0;
        local bytes_jmp_back = util.int_to_bytes(hook_jmp_back);
        local bytes_bytecode = util.int_to_bytes(our_bytecode);
        local bytes_bytecode_size = util.int_to_bytes(our_bytecode_size);
        local hook_size = 0;

        util.write_int32(hook_jmp_back, rbx.script_hook + 5);

        while hook_size < 5 do
            hook_size = hook_size + util.get_code_size(rbx.script_hook + hook_size);
        end

        rbx.old_script_hook_bytes = util.read_bytes(rbx.script_hook, hook_size);

        local bytes1 = {
            0xC7, 0x43, 0x08, -- mov [ebx+C], our_bytecode
            bytes_bytecode[1], bytes_bytecode[2], bytes_bytecode[3], bytes_bytecode[4],
            0xC7, 0x43, 0x0C, -- mov [ebx+C], our_bytecode_size
            bytes_bytecode_size[1], bytes_bytecode_size[2], bytes_bytecode_size[3], bytes_bytecode_size[4],
        }

        for _,b in pairs(rbx.old_script_hook_bytes) do
            table.insert(bytes1, b);
        end

        local bytes2 = {
            0xFF, 0x25,
            bytes_jmp_back[1], bytes_jmp_back[2], bytes_jmp_back[3], bytes_jmp_back[4]
        }

        for _,b in pairs(bytes2) do
            table.insert(bytes1, b);
        end

        util.write_bytes(edit_location, bytes1);
        util.place_jmp(rbx.script_hook, edit_location);
    else
        util.write_bytes(rbx.script_hook, rbx.old_script_hook_bytes);
    end
end

rbx.execute_script = function(src)
    return rbx.execute_closure(loadstring(src))
end

rbx.execute_closure = function(closure)
    local execute_start = os.clock();
    local script_bytes = rbx.dump_function(closure);

	-- RELAY THE BYTECODE FOR DEBUGGING
	--[[
    local str = "";
    for _,b in pairs(script_bytes) do
        str = str .. string.format("%02X ", b);
    end
    print(str);
	]]
    --error''

    local our_bytecode_size = #script_bytes;
    local our_bytecode = util.allocate_memory(our_bytecode_size + 0x10);

    util.write_bytes(our_bytecode, script_bytes);
    util.write_int32(our_bytecode + our_bytecode_size + (4 - (our_bytecode_size % 4)) + 4, our_bytecode_size);

    rbx.set_script_hook(true, our_bytecode, our_bytecode_size);
    rbx.functions.sc_runscript(rbx.script_context, rbx.local_script, rbx.functions.get_instance_source(rbx.local_script), 7, 0, 0, 0, 0, 0, 0, 0, 0);
    rbx.set_script_hook(false);

    print(string.format("[Execute] Took %f seconds", os.clock() - execute_start))
end

-- Load time can be greatly improved by saving the
-- offsets to a file and loading them from there
loader.start = function()
    print("[Loader] Finding return mask...");
    retcheck.load();

    print("[Loader] Getting offsets...");

    rbx.offsets.luau_loadbuffer = util.aobscan("0F????83??7FD3??83")[10];
    --print("luaU_loadbuffer: " .. string.format("%08X", rbx.offsets.luau_loadbuffer));
	if rbx.offsets.luau_loadbuffer == 0 then
		error'[Loader] Scan failed [Offset #1]'
	end
	rbx.offsets.luau_loadbuffer = util.get_prologue(rbx.offsets.luau_loadbuffer);

    rbx.offsets.sc_runscript = util.scan_xrefs("Running Script")[1];
    --print("scriptContext_runScript: " .. string.format("%08X", rbx.offsets.sc_runscript));
	if rbx.offsets.sc_runscript == 0 then
		error'[Loader] Scan failed [Offset #2]'
	end
	rbx.offsets.sc_runscript = util.get_prologue(rbx.offsets.sc_runscript);

    fremote = util.new_remote();
    print("[Remote] Created remote");


    local replicator_hook = util.aobscan("252E3266204B422F")[1]; -- this will last a while
    replicator_hook = util.aobscan(util.int_to_le_str(replicator_hook))[1];
    replicator_hook = util.get_prologue(replicator_hook) + 3;
    print(string.format("Replicator hook: %08X", replicator_hook))

    -- place an incredibly fast hook to read ecx
    -- register (contains ClientReplicator)
    local detour = util.new_detour(replicator_hook, "ecx", 0, 1);
    local detour_results = detour.start();

    rbx.client_replicator = detour_results.value;
    rbx.network_client = 0;

    rbx.offsets.instance_name = 0;
    rbx.offsets.instance_parent = 0;
    rbx.offsets.instance_children = 0;

    print("ClientReplicator: " .. string.format("%08X", rbx.client_replicator));

    for i = 16, 128, 4 do
        local ptr = util.read_int32(rbx.client_replicator + i);
        if util.read_int64(ptr + 0x10) == 0x0000001F00000010 then
            print("Instance Name offset: " .. string.format("%08X", i));
            rbx.offsets.instance_name = i;
            break;
        end
    end

    for i = 16, 128, 4 do
        rbx.network_client = util.read_int32(rbx.client_replicator + i);
        if util.read_string(util.read_int32(rbx.network_client + rbx.offsets.instance_name)) == "NetworkClient" then
            print("Instance Parent offset: " .. string.format("%08X", i));
            rbx.offsets.instance_parent = i;

            print("NetworkClient: " .. string.format("%08X", rbx.network_client));
            break;
        end
    end

    for i = 16, 128, 4 do
        local children_ptr = util.read_int32(rbx.network_client + i);
        if children_ptr then
            local children_start = util.read_int32(children_ptr + 0);
            local children_end = util.read_int32(children_ptr + 4);

            if children_start and children_end then
                --local children_index = 1
                --if util.read_int32(children_start + ((children_index - 1) * 8) + 0) == rbx.client_replicator then
                if (children_end - children_start == 8) then -- faster solution
                    print("Instance Children offset: " .. string.format("%08X", i));
                    rbx.offsets.instance_children = i;
                    break;
                end
            end
        end
    end

    rbx.functions.get_instance_name = function(instance)
        local ptr = util.read_int32(instance + rbx.offsets.instance_name);
        if ptr then
            local fl = util.read_int32(ptr + 0x14);
            if fl == 0x1F then
                ptr = util.read_int32(ptr);
            end
            return util.read_string(ptr);
        else
            return "???";
        end
    end

    rbx.functions.get_instance_parent = function(instance)
        return util.read_int32(instance + rbx.offsets.instance_parent);
    end

    rbx.functions.get_instance_source = function(instance)
        return util.read_int32(instance + 8);
    end

    rbx.functions.get_instance_descriptor = function(instance)
        return util.read_int32(instance + 12);
    end

    rbx.functions.get_instance_class = function(instance)
        local descriptor = rbx.functions.get_instance_descriptor(instance);
        local ptr = util.read_int32(descriptor + 4);
        if ptr then
            local fl = util.read_int32(ptr + 0x14);
            if fl == 0x1F then
                ptr = util.read_int32(ptr);
            end
            return util.read_string(ptr);
        else
            return "???";
        end
    end

    rbx.functions.get_instance_children = function(instance)
        local instances = {};
        local children_ptr = util.read_int32(instance + rbx.offsets.instance_children);
        if children_ptr then
            local children_start = util.read_int32(children_ptr + 0);
            local children_end = util.read_int32(children_ptr + 4);
            local at = children_start;
            while at < children_end do
                local child = util.read_int32(at);
                table.insert(instances, child);
                at = at + 8;
            end
        end
        return instances;
    end

    rbx.functions.find_first_child = function(instance, name)
        for _,v in pairs(rbx.functions.get_instance_children(instance)) do
            if rbx.functions.get_instance_name(v) == name then
                return v;
            end
        end
        return 0;
    end

    rbx.functions.find_first_class = function(instance, classname)
        for _,v in pairs(rbx.functions.get_instance_children(instance)) do
            if rbx.functions.get_instance_class(v) == classname then
                return v;
            end
        end
        return 0;
    end

    rbx.data_model = rbx.functions.get_instance_parent(rbx.network_client);
    print("DataModel: " .. string.format("%08X", rbx.data_model));

    rbx.script_context = rbx.functions.find_first_class(rbx.data_model, "ScriptContext");
    if rbx.script_context == 0 then
       error'Could not locate Script Context'
    end
    print("ScriptContext: " .. string.format("%08X", rbx.script_context));

    rbx.local_player = 0;
    rbx.players_service = rbx.functions.find_first_class(rbx.data_model, "Players");
    if rbx.players_service == 0 then
       error'Could not locate Players'
    end

    print("Players: " .. string.format("%08X", rbx.players_service));

    for i = 32, 1600, 4 do
        local instance = util.read_int32(rbx.players_service + i);
        if instance then
           if rbx.functions.get_instance_parent(instance) == rbx.players_service then
               rbx.local_player = instance;
               print("Players->LocalPlayer offset: " .. string.format("%08X", i));
               print("Players->LocalPlayer: " .. string.format("%08X", rbx.local_player));
               rbx.offsets.players_localplayer = i;
           end
        end
    end

    if rbx.local_player == 0 then
       error'Could not find LocalPlayer'
    end

    print("Player name: ", rbx.functions.get_instance_name(rbx.local_player));

    -- sure, I could deal with updating more offsets to
    -- make a new localscript _or_ just overwrite an existing one
    rbx.local_player_scripts = rbx.functions.find_first_child(rbx.local_player, "PlayerScripts");
    rbx.local_script = rbx.functions.find_first_child(rbx.local_player_scripts, "RbxCharacterSounds");

    if rbx.local_script == 0 then
        rbx.local_script = rbx.functions.find_first_child(rbx.local_player_scripts, "BubbleChat");
    end

    if rbx.local_script == 0 then
        error("Could not find a usable LocalScript (we're trying to be resourceful here)")
    end

    print("LocalScript: " .. string.format("%08X", rbx.local_script));



    fremote.init();
    print("[Remote] Controller: " .. string.format("%08X", fremote.remote_location));

    print(string.format("[Loader] Took %f seconds", os.clock() - loader.clock_start))

    rbx.functions.luau_loadbuffer = fremote.create(retcheck.patch(rbx.offsets.luau_loadbuffer), "fastcall", 5);
    print("[Remote] Added routine: " .. string.format("%08X", fremote.routines[#fremote.routines]));

    rbx.functions.sc_runscript = fremote.create(retcheck.patch(rbx.offsets.sc_runscript), "thiscall", 84);
    print("[Remote] Added routine: " .. string.format("%08X", fremote.routines[#fremote.routines]));
    fremote.start();


    loader.loaded = true;
end

rbx.start = function()
    rbx.execute_script('spawn(function() ' .. script_source .. '\nend)');

    --retcheck.flush();
    --fremote.flush();
end


-- Load everything needed for this exploit
loader.start();

if loader.loaded then
    rbx.start();
end




