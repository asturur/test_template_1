local m = manager.machine
local cpu = m.devices[":maincpu"]
local space = cpu.spaces.program
local code = assert(io.open(assert(os.getenv("TRACE_PROGRAM")), "rb"))
local program = code:read("*a")
code:close()
local taps = {}
local upload, raw = 0x0c030000, 0x0c1003f0
local function key(addr, mask, op)
    return string.format("%08x %08x %s", addr, mask, op)
end
local observed = {}
for _, region in ipairs({{upload, 0x0c03ffff}, {raw, 0x0c10ffff}}) do
    local a, b = table.unpack(region)
    taps[#taps+1] = space:install_read_tap(a,b,"cal_R",function(address,data,mask)
        local k = key(address, mask, "R")
        observed[k] = (observed[k] or 0) + 1
    end)
    taps[#taps+1] = space:install_write_tap(a,b,"cal_W",function(address,data,mask)
        local k = key(address, mask, "W")
        observed[k] = (observed[k] or 0) + 1
    end)
end
CALIBRATION_TAPS = taps
for offset = 0, #program - 1 do
    space:write_u8(0x0a020000 + offset, program:byte(offset + 1))
end
cpu.state["CPSR"].value = (cpu.state["CPSR"].value & ~0x3f) | 0xd3
cpu.state["R15"].value = 0x0a020000
CALIBRATION_FRAME = emu.add_machine_frame_notifier(function()
    local result = space:read_u32(0x0a021000)
    if result ~= 0 then
        assert(result == 0x50415353, string.format("guest RAM probe failed %08x",result))
        for _, region in ipairs({{upload, 0x0c03fffc}, {raw, 0x0c10fffc}}) do
            for _, row in ipairs({{region[1],0xffffffff,"W"}, {region[1],0xffffffff,"R"},
                {region[2],0xffff0000,"W"}, {region[2],0xff000000,"R"},
                {region[1]+8,0xffffffff,"W"}, {region[1]+8,0xffffffff,"R"}}) do
                local k = key(table.unpack(row))
                assert(observed[k] == 1,k.." expected one access, got "..tostring(observed[k]))
                print(k.." count="..observed[k])
            end
        end
        print("PASS calibrated both physical windows with guest reads, writes and instruction fetches")
        m:exit()
    end
end)
