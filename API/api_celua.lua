celua = {};

-- excerpt from lopcodes.h
--
celua.SIZE_C = 9;
celua.SIZE_B = 9;
celua.SIZE_Bx = (celua.SIZE_C + celua.SIZE_B);
celua.SIZE_A = 8;
celua.SIZE_OP = 6;
celua.POS_OP = 0;
celua.POS_A = (celua.POS_OP + celua.SIZE_OP);
celua.POS_C = (celua.POS_A + celua.SIZE_A);
celua.POS_B = (celua.POS_C + celua.SIZE_C);
celua.POS_Bx = celua.POS_C;
celua.MAXARG_A = ((1 << celua.SIZE_A) - 1);
celua.MAXARG_B = ((1 << celua.SIZE_B) - 1);
celua.MAXARG_C = ((1 << celua.SIZE_C) - 1);
celua.MAXARG_Bx = ((1 << celua.SIZE_Bx) - 1);
celua.MAXARG_sBx = (celua.MAXARG_Bx >> 1);
celua.LFIELDS_PER_FLUSH	= 50;
celua.NO_REG = MAXARG_A;
celua.BITRK = (1 << (celua.SIZE_B - 1));
celua.MAXINDEXRK = (celua.BITRK - 1);
celua.ISK = function(x) return ((x) & celua.BITRK); end
celua.INDEXK = function(x) return ((x) & ~celua.BITRK); end
celua.RKASK = function(x) return ((x) | celua.BITRK); end
celua.MASK1 = function(n,p) return (~((~0) << n)) << p end
celua.MASK0 = function(n,p) return (~celua.MASK1(n, p)) end
celua.GETARG_A = function(inst) return (((inst) >> celua.POS_A) & celua.MASK1(celua.SIZE_A,0)) end
celua.GETARG_B = function(inst) return (((inst) >> celua.POS_B) & celua.MASK1(celua.SIZE_B,0)) end
celua.GETARG_C = function(inst) return (((inst) >> celua.POS_C) & celua.MASK1(celua.SIZE_C,0)) end
celua.GETARG_Bx = function(inst) return (((inst) >> celua.POS_Bx) & celua.MASK1(celua.SIZE_Bx,0)) end
celua.GETARG_sBx = function(inst) return (celua.GETARG_Bx(inst) - celua.MAXARG_sBx) end
celua.GET_OPCODE = function(inst) return (((inst) >> celua.POS_OP) & celua.MASK1(celua.SIZE_OP, 0)) end
celua.OPCODE_NAMES = {"MOVE", "LOADK", "LOADKX", "LOADBOOL", "LOADNIL",
    "GETUPVAL", "GETTABUP", "GETTABLE", "SETTABUP", "SETUPVAL",
    "SETTABLE", "NEWTABLE", "SELF", "ADD", "SUB", "MUL", "MOD",
    "POW", "DIV", "IDIV", "BAND", "BOR", "BXOR", "SHL", "SHR",
    "UNM", "BNOT", "NOT", "LEN", "CONCAT", "JMP", "EQ", "LT", "LE",
    "TEST", "TESTSET", "CALL", "TAILCALL", "RETURN", "FORLOOP",
    "FORPREP", "TFORCALL", "TFORLOOP", "SETLIST", "CLOSURE", "VARARG",
    "EXTRAARG"
};

-- Set this to true if you want to display
-- information during deserialization
celua.debugOutput = false;

celua.deserialize = function(func)
    local bytecode = string.dump(func)

    local protoTable = {};
    local stringTable = {};

    local reader do
        reader = {};
        local bytecodePos = 1;

        function reader:eof()
            return bytecodePos > string.len(bytecode);
        end

        function reader:skip(count)
            bytecodePos = bytecodePos + count;
        end

        function reader:nextByte()
            local val = bytecode:byte(bytecodePos, bytecodePos);
            reader:skip(1);
            return val;
        end

        function reader:nextString(count)
            if type(count) == "number" then
                local chars = reader:nextBytes(count);
                local found = false;
                local str = "";

                for j = 1, #chars do
                    str = str .. string.char(chars[j]);
                end

                for _,v in pairs(stringTable) do
                    if str == v then
                        found = true;
                    end
                end

                if not found then
                    table.insert(stringTable, str);
                end

                return str;
            else
                local strLength = reader:nextByte();
                if strLength == 0xff then
                    strLength = reader:nextInt() - 1;
                    return reader:nextString(strLength), strLength;
                elseif strLength > 0 then
                    strLength = strLength - 1;
                    return reader:nextString(strLength), strLength;
                end
            end
        end

        function reader:nextBytes(count)
            local t = {};
            for i = 1,count do
                table.insert(t, reader:nextByte());
            end
            return t;
        end

        function reader:nextInt()
            local b = {};
            for i = 1,4 do
                table.insert(b, reader:nextByte());
            end
            return ((b[4] << 24) | (b[3] << 16) | (b[2] << 8) | (b[1]));
        end

        function reader:nextDouble()
            local b = {};
            for i = 1,8 do
                table.insert(b, reader:nextByte());
            end
            return ((b[8] << 56) | (b[7] << 48) | (b[6] << 40) | (b[5] << 32) | (b[4] << 24) | (b[3] << 16) | (b[2] << 8) | (b[1]));
        end
    end

    local luaSignature = reader:nextInt();
    local versionNumber = reader:nextByte();
    local impl = reader:nextByte();
    local luaMagic = reader:nextBytes(6);
    reader:skip(22); -- these are assumed..skip the rest

    local source, sourceLength = reader:nextString();

    local function next()
        local thisProto = {};

        thisProto.lineStart = reader:nextInt();
        thisProto.lineEnd = reader:nextInt();
        thisProto.numParams = reader:nextByte();
        thisProto.isVarArg = reader:nextByte();
        thisProto.maxStackSize = reader:nextByte();
        thisProto.sizeCode = reader:nextInt();

        thisProto.code = {};
        for i = 1, thisProto.sizeCode do
            local inst = reader:nextInt();
            table.insert(thisProto.code, inst);
        end

        thisProto.sizeConsts = reader:nextInt();
        thisProto.consts = {};
        --print("Constants: " , thisProto.sizeConsts);

        for i = 1, thisProto.sizeConsts do
            local const = {};
            const.Type = reader:nextByte();
            --print("Constant type: ", const.Type);

            if const.Type == 0 then -- nil
                -- nothing
            elseif const.Type == 1 then -- bool
                const.Data = reader:nextByte();
            elseif const.Type == 0x13 then -- number 
                const.Data = reader:nextDouble();
                --print("Number value: ", const.Data);
            elseif const.Type == 4 then -- string
                const.Data, const.Length = reader:nextString();
                --print(const.Data);
            else
                error'invalid constant type'
            end

            table.insert(thisProto.consts, const);
        end

        if celua.debugOutput then
            for _,inst in pairs(thisProto.code) do
                local opcodeName = celua.OPCODE_NAMES[celua.GET_OPCODE(inst) + 1];
                local spaces = string.rep(' ', 16 - string.len(opcodeName));

                local A = celua.GETARG_A(inst);
                local B = celua.GETARG_B(inst);
                local Bx = celua.GETARG_Bx(inst);
                local C = celua.GETARG_C(inst);

                --print(opcodeName .. spaces .. '\t' .. celua.GETARG_A(inst) .. " " .. celua.GETARG_B(inst) .. " " .. celua.GETARG_C(inst));

                if opcodeName == "GETTABUP" then
                    print(string.format("Stack[%i] = Upvalues[%i]['%s']", A, B, thisProto.consts[celua.INDEXK(C) + 1].Data));
                elseif opcodeName == "LOADK" then
                    print(string.format("Stack[%i] = '%s'", A, thisProto.consts[Bx + 1].Data));
                elseif opcodeName == "CALL" then
                    local str = "";
                    str = str .. string.format("Stack[%i](", A);
                    for i = 1, B - 1 do
                        str = str .. string.format("Stack[%i]", i);
                        if i < B - 1 then
                            str = str .. ", ";
                        end
                    end
                    str = str .. string.format(") -- return %i values", C - 1);
                    print(str);
                elseif opcodeName == "MOVE" then
                    print(string.format("Stack[%i] = Stack[%i]", A, B));
                elseif opcodeName == "CLOSURE" then
                    print(string.format("Stack[%i] = Closures[%i]", A, Bx));
                end
            end
        end

        thisProto.nups = reader:nextInt();
        thisProto.upValues = {};
        --print("Nups: " , thisProto.nups);

        for i = 1, thisProto.nups do
            local upval = {};
            upval.Stack = reader:nextByte();
            upval.Register = reader:nextByte();
            table.insert(thisProto.upValues, upval);
        end

        thisProto.numProtos = reader:nextInt();
        thisProto.protos = {};

        for i = 1, thisProto.numProtos do
            local nextSource = reader:nextString();
            --print("Function name: ", nextSource)

            local nextProto = next();
            nextProto.source = nextSource;
            table.insert(thisProto.protos, nextProto);
        end

        thisProto.lines = reader:nextInt();
        thisProto.lineInfos = {};
        for i = 1,thisProto.lines do
            local lineInfo = reader:nextInt();
            table.insert(thisProto.lineInfos, lineInfo);
        end

        thisProto.locVars = {};
        thisProto.locals = reader:nextInt();
        for i = 1,thisProto.locals do
            local locVar = {};
            locVar.name = reader:nextString();
            --print("Local name: " .. locVar.name);
            locVar.startpc = reader:nextInt();
            locVar.endpc = reader:nextInt();
            table.insert(thisProto.locVars, locVar);
        end

        thisProto.upValueNames = {};
        for i = 1,reader:nextInt() do
            local upValueName = reader:nextString();
            --print("Upvalue name: " .. upValueName);
            table.insert(thisProto.upValueNames, upValueName);
        end

        table.insert(protoTable, thisProto);
        return thisProto;
    end

    next();

    return protoTable, stringTable;
end

return celua;
