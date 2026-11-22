local machine = manager.machine
local cpu = machine.devices[":maincpu"]
local space = cpu.spaces.program
local keys = machine.ioport.ports[":KEYS"].fields
local screen = machine.screens[":screen"]
local qd = os.getenv("TRACE_QD") == "1"
local output = assert(os.getenv("TRACE_OUTPUT"))
local actions = qd and {
    {27, "Left Soft"}, {30, "Left Soft"}, {37, "Right Soft"},
    {47, "OK"}, {52, "OK"}, {58, "OK"}, {67, "OK"}, {75, "P1 Right"},
    {87, "5"}, {94, "OK"}, {100, "5"}, {106, "OK"}, {112, "5"},
    {120, "P1 Right", 2.3}, {124, "P1 Right", 1.8}, {130, "P1 Right", 2.8},
    {136, "5"}, {140, "P1 Right", 3.8}, {146, "P1 Right", 2.8},
} or {
    {27, "Left Soft"}, {30, "Left Soft"}, {34, "Menu"}, {36, "P1 Down"},
    {38, "P1 Down"}, {40, "P1 Down"}, {42, "P1 Right"}, {44, "P1 Right"},
    {46, "OK"}, {65, "5"}, {74, "5"}, {78, "5"}, {81, "5"},
    {88, "5"}, {95, "5"}, {101, "5"}, {108, "P1 Right", 1.5},
    {113, "P1 Left", 1.5}, {119, "P1 Right", 1.2}, {126, "P1 Right", 2.0},
    {135, "P1 Left", 1.8}, {142, "P1 Right", 2.0},
}
local phases = {
    cold = {}, phone = {}, launch = {}, audio_intro = {}, audio_after_input = {}, late_audio = {},
}
local windows = {
    {"upload", 0x0c030000, 0x0c03ffff},
    {"mdi_ring", 0x0c100000, 0x0c1003e7},
    {"mdi_pointers", 0x0c1003e8, 0x0c1003ef},
    {"raw", 0x0c1003f0, 0x0c10ffff},
    {"mdi_control", 0x0c14b004, 0x0c14b007},
}
local start = machine.time:as_double()
local phase = "cold"
local launch_time = qd and 37 or 46
local later_input = qd and 58 or 74
local reads, writes = {}, {}
local stream_samples, nonzero_samples = 0, 0
local phase_pcm = {}
local first_audio
local ended_at
local function stamp()
    return machine.time:as_double()
end

local function change(new_phase, t)
    phase = new_phase
    print(string.format("PHASE %.8f %s", t, new_phase))
end

local function record(region, operation, address, mask)
    local base = phases[phase]
    base[region] = base[region] or {R = {}, W = {}}
    local samples = base[region][operation]
    local index = (address << 32) | mask
    local entry = samples[index]
    if entry then
        entry.count = entry.count + 1
        entry.last = stamp()
    else
        local pc = cpu.state["PC"]
        local t = stamp()
        samples[index] = {count = 1, time = t, last = t, pc = pc and pc.value or 0}
    end
end

for _, window in ipairs(windows) do
    local region, first, last = table.unpack(window)
    reads[region] = space:install_read_tap(first, last, region.."_r",
        function(address, data, mask) record(region, "R", address, mask) end)
    writes[region] = space:install_write_tap(first, last, region.."_w",
        function(address, data, mask) record(region, "W", address, mask) end)
end
RAM_TRACE_TAPS = {reads, writes}
print(string.format("START %.8f", start))
machine.sounds[":pcm"].hook = true
emu.register_sound_update(function(data)
    local samples = data[":pcm"][1]
    local heard = 0
    for _, sample in ipairs(samples) do
        if sample ~= 0 then heard = heard + 1 end
    end
    if heard ~= 0 and not first_audio then
        first_audio = stamp()
        print(string.format("FIRST_AUDIO %.8f", first_audio))
        if phase == "launch" then change("audio_intro", first_audio) end
    end
    stream_samples = stream_samples + #samples
    nonzero_samples = nonzero_samples + heard
    phase_pcm[phase] = (phase_pcm[phase] or 0) + heard
end)

local action, capture, held = 1, 1, nil
local captures = qd and {36, 44, 50, 56, 65, 74, 79, 88, 98, 107, 113, 117, 122, 127, 132, 137, 143, 149} or
    {45, 53, 62, 70, 76, 80, 86, 92, 99, 105, 111, 118, 125, 133, 142, 149}
RAM_TRACE_FRAME = emu.add_machine_frame_notifier(function()
    local t = stamp()
    if phase == "cold" and t >= 27 then change("phone", t) end
    if held and t >= held[1] then
        held[2]:clear_value()
        held = nil
    end
    if captures[capture] and t >= captures[capture] then
        local err = screen:snapshot(output..string.format("/screen-%02d.png", captures[capture]))
        print(string.format("SNAP %.8f %d nonzero=%d error=%s", t, captures[capture], nonzero_samples, tostring(err)))
        capture = capture + 1
    end
    if actions[action] and t >= actions[action][1] then
        local when, name, duration = table.unpack(actions[action])
        local field = assert(keys[name], name)
        if when == launch_time then change("launch", t) end
        if when == later_input and first_audio then change("audio_after_input", t) end
        field:set_value(1)
        held = {t + (duration or 0.22), field}
        print(string.format("KEY %.8f %s", t, name))
        action = action + 1
    end
    if phase == "audio_after_input" and t >= 105 then change("late_audio", t) end
    if t >= 150 then
        ended_at = t
        machine:exit()
    end
end)

RAM_TRACE_STOP = emu.add_machine_stop_notifier(function()
    local log = assert(io.open(output.."/accesses.tsv", "w"))
    log:write("phase\tregion\top\taddress\tmask\tcount\tfirst_s\tlast_s\tfirst_pc\n")
    for name, regions in pairs(phases) do
        for region, operations in pairs(regions) do
            for operation, samples in pairs(operations) do
                for index, entry in pairs(samples) do
                    log:write(string.format("%s\t%s\t%s\t%08x\t%08x\t%d\t%.8f\t%.8f\t%08x\n",
                        name, region, operation, index >> 32, index & 0xffffffff, entry.count, entry.time, entry.last, entry.pc))
                end
            end
        end
    end
    log:close()
    print(string.format("END %.8f completed=%s samples=%d nonzero=%d",
        stamp(), tostring(ended_at ~= nil), stream_samples, nonzero_samples))
    for name, count in pairs(phase_pcm) do
        print(string.format("PCM %s %d", name, count))
    end
end)
