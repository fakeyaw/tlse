-- credits: @salvatore
-- recoded by: @votekick

local font, count = {
    size = 12, verdana
}, 0

local EngineClientB = {
    GetScreenCenter = function()
        local v = EngineClient.GetScreenSize()
        if type(v.x) ~= 'number' then
            v={x=0,y=0} end
        return v.x / 2, v.y / 2
    end
}

font.verdana = Render.InitFont('Verdana', font.size, {'r'})

local RenderB = {
    TextOutlined = function(x, y, r, g, b, a, label) Render.Text(label, Vector2.new(x, y), Color.new(r/255,g/255,b/255,a/255), font.size, font.verdana, true) end,
    CalcTextSize = function(label) return Render.CalcTextSize(label, font.size, font.verdana).x, Render.CalcTextSize(label, font.size, font.verdana).y end,
    LoadImageFromURL = function(url, x, y) return Render.LoadImage(Http.Get(url), Vector2.new(x, y)) end,
}

local ClientB = {
    GetBind = function(name) local binds = Cheat.GetBinds(); for i = 1, #binds do if name == binds[i]:GetName() then return binds[i]:IsActive() else return false end end end,
    LocalPlayer = function() return EntityList.GetClientEntity(EngineClient.GetLocalPlayer()) end
}

local Gram = {
    Create = function(value, count) local gram = { }; for i=1, count do gram[i] = value; end return gram; end,
    Update = function(tab, value, forced) local new_tab = tab; if forced or new_tab[#new_tab] ~= value then table.insert(new_tab, value); table.remove(new_tab, 1); end; tab = new_tab; end,
}

local tickbase_data = Gram.Create(0, 16)

local Items = {
    LC = Menu.Switch("Net graph settings", "Lag compensation status", false),
    Height = Menu.SliderInt("Net graph settings", "Interface height", 360, 0, EngineClient.GetScreenSize().y / 2)
}

-- convars
local cvar = {
    cl_interp = function() return CVar.FindVar('cl_interp') end,
    cl_interp_ratio = function() return CVar.FindVar('cl_interp_ratio') end,
    cl_updaterate = function() return CVar.FindVar('cl_updaterate') end
}

local ping_spike_ref = Menu.FindVar('Miscellaneous', 'Main', 'Other', 'Fake Ping')

-- ffi static floats
local pflFrameTime, pflFrameTimeStdDeviation, pflFrameStartTimeStdDeviation = ffi.new('float[1]'), ffi.new('float[1]'), ffi.new('float[1]')

local interface_ptr = ffi.typeof('void***')
local rawivengineclient = Utils.CreateInterface('engine.dll', 'VEngineClient014')
local ivengineclient = ffi.cast(interface_ptr, rawivengineclient)

local get_net_channel_info, net_channel = ffi.cast('void*(__thiscall*)(void*)', ivengineclient[0][78]), nil
local net_bool = ffi.typeof('bool(__thiscall*)(void*)') 
local net_fr_to = ffi.typeof('void(__thiscall*)(void*, float*, float*, float*)')

-- net channel values insert
local INetChannelInfo = ffi.cast('void***', get_net_channel_info(ivengineclient)) 
local GetNetChannel = function(INetChannelInfo)
    if INetChannelInfo == nil then
        return end

    return {
        latency = {
            crn = function(flow) return INetChannelInfo:GetLatency(flow) end,
            average = function(flow) return INetChannelInfo:GetAvgLatency(flow) end,
        },
        loss = INetChannelInfo:GetAvgLoss(1),
        choke = INetChannelInfo:GetAvgChoke(1),
        got_bytes = INetChannelInfo:GetAvgData(1),
        sent_bytes = INetChannelInfo:GetAvgData(0),
        is_timing_out = 0,
    }
end

-- netc framerate
local GetNetFramerate = function(INetChannelInfo)
    if INetChannelInfo == nil then
        return 0, 0 end

    local server_var, server_framerate = 0, 0
    ffi.cast(net_fr_to, INetChannelInfo[0][25])(INetChannelInfo, pflFrameTime, pflFrameTimeStdDeviation, pflFrameStartTimeStdDeviation)

    if pflFrameTime ~= nil and pflFrameTimeStdDeviation ~= nil and pflFrameStartTimeStdDeviation ~= nil then
        if pflFrameTime[0] > 0 then
            server_var = pflFrameStartTimeStdDeviation[0] * 1000
            server_framerate = pflFrameTime[0] * 1000
        end
    end

    return server_framerate, server_var
end

local lc = {
    is_shifting = false,
    tick_base = 0,
    high_vel = 0,
    ticks = 0
}

local server_framerate, server_var, lerp_time, tickrate, net_state, height, outgoing, incoming, incoming_latency, ping, avg_ping
local ALPHA,alpha = 1,1

local size = { 20, 19 }
local warning_icon = RenderB.LoadImageFromURL('https://i.imgur.com/QEMHCc5.png', size[1], size[2])

local render = {
    function()
        -- net channel fin hook
        INetChannelInfo, INetChannelInfoB = EngineClient.GetNetChannelInfo(), ffi.cast('void***', get_net_channel_info(ivengineclient))
        net_channel = GetNetChannel(INetChannelInfo)

        net_channel.is_timing_out = ffi.cast(net_bool, INetChannelInfoB[0][7])(INetChannelInfoB)
        net_state = (net_channel.choke > 0.00) and 1 or (net_channel.loss > 0.00) and 2 or 0

        -- main values
        server_framerate, server_var = GetNetFramerate(INetChannelInfoB)
        tickrate = 1 / GlobalVars.interval_per_tick
        lerp_time = cvar.cl_interp_ratio():GetFloat() * (1000 / tickrate)
        outgoing, incoming = net_channel.latency.crn(0), net_channel.latency.crn(1)
        incoming_latency, ping, avg_ping = math.max(0, (incoming-outgoing)*1000), outgoing*1000, net_channel.latency.average(0)*1000

        -- fake latency detection
        local ping_spike_bind = ClientB.GetBind("Fake Ping")
        local ping_spike = (ping_spike_bind) and 1 or 0
    end,
    function()
        -- render inits
        count = 1
        if net_channel.is_timing_out then 
            net_state, net_channel.loss = 3, 1
            ALPHA = ALPHA-GlobalVars.frametime ; ALPHA = ALPHA < 0.05 and 0.05 or ALPHA 
        else
            ALPHA = ALPHA+(GlobalVars.frametime*2) ; ALPHA = ALPHA > 1 and 1 or ALPHA 
        end

        alpha = math.min(math.floor(math.sin((GlobalVars.realtime % 3) * 4) * 125 + 200), 255) -- icon & net data status alpha
        height = Items.Height:Get()

        -- colors
        lerp_r, lerp_g, lerp_b = 255,255,255 ; if lerp_time/1000 < 2/cvar.cl_updaterate():GetInt() then lerp_r, lerp_g, lerp_b = 255,125,95 end -- lerp status color
        color_r, color_g, color_b, color_a = 255,200,95,255 ; if net_state ~= 0 then color_r, color_g, color_b, color_a = 255,50,50,alpha end -- icon color
        ping_r, ping_g, ping_b = 255,60,80 ; if avg_ping < 40 then ping_r, ping_g, ping_b = 255,255,255 end ; if avg_ping < 100 then ping_r, ping_g, ping_b = 255,125,95 end -- ping color
    end,
    function()
        -- render net graph info
        local x, y = EngineClientB.GetScreenCenter()

        local net_data_status = {
            [0] = 'clock syncing',
            [1] = 'packet choke',
            [2] = 'packet loss',
            [3] = 'lost connection'
        }

        local net_data_text = net_data_status[net_state]

        local fl_pre_text = (ping_spike ~= 1 and incoming_latency > 1) and string.format(': %dms', incoming_latency) or ''

        local right_text, incoming_text, lerp_text, outgoing_text, sv_text, avg_text, fl_text = net_state ~= 0 and 
        '+- ' .. string.format('%.1f%% (%.1f%%)', net_channel.loss*100, net_channel.choke*100) or -- choke / loss
        '+- ' .. string.format('%.1fms', server_var/2), -- choke / loss
        string.format('in: %.2fk/s    ', net_channel.got_bytes/1024), -- incoming
        string.format('lerp: %.1fms', lerp_time), string.format('out: %.2fk/s', net_channel.sent_bytes/1024), -- lerp
        string.format('sv: %.2f +- %.2fms    var: %.3f ms', server_framerate, server_var, server_var), -- server var
        string.format('delay: %dms (+- %dms)    ', avg_ping, math.abs(avg_ping-ping)), -- average delay
        string.format('datagram%s', fl_pre_text) -- datagram status

        local cz_x, cz_y = RenderB.CalcTextSize(net_data_text)
        local weight = 20

        -- render text
        left_x, left_y = x - cz_x - weight, y + height
        RenderB.TextOutlined(left_x, left_y, 255, 255, 255, net_state ~= 0 and 255 or alpha, net_data_text) -- net data render (clock syncing)

        right_x, right_y = x + (cz_x / 2), y + height
        RenderB.TextOutlined(right_x, right_y, 255, 255, 255, 255, right_text) -- choke/loss render

        left_x, left_y = x - cz_x - weight, y + height + (count*20)
        RenderB.TextOutlined(left_x, left_y, 255, 255, 255, (ALPHA*255), incoming_text) -- incoming render

        incoming_size_x, incoming_size_y = RenderB.CalcTextSize(incoming_text)
        RenderB.TextOutlined(left_x + incoming_size_x, left_y, lerp_r, lerp_g, lerp_b, (ALPHA*255), lerp_text) -- lerp time render

        count = count + 1 ; left_y = y + height + (count*20)
        RenderB.TextOutlined(left_x, left_y, 255, 255, 255, (ALPHA*255), outgoing_text) -- outgoing render

        count = count + 1 ; left_y = y + height + (count*20)
        RenderB.TextOutlined(left_x, left_y, 255, 255, 255, (ALPHA*255), sv_text) -- server var info render
        
        count = count + 1 ; left_y = y + height + (count*20)
        RenderB.TextOutlined(left_x, left_y, ping_r, ping_g, ping_b, (ALPHA*255), avg_text) -- average delay render

        avg_size_x, avg_size_y = RenderB.CalcTextSize(avg_text)
        RenderB.TextOutlined(left_x + avg_size_x, left_y, 255, 255, 255, (ALPHA*255), fl_text) -- datagram status render

        -- addon: lagcomp status
        local lagcomp_status = {
            [0] = 'broken',
            [1] = 'unsafe',
        }

        if not Items.LC:Get() then
            return end

        local lc = lc.is_shifting and 1 or 0

        local lagcomp_status = lagcomp_status[lc]
        local lagcomp_text = 'lagcomp: '

        local lc_r, lc_g, lc_b, lc_a = 25,255,165,255 ; if lc == 0 then lc_r, lc_g, lc_b, lc_a = 255,0,0,255 end

        lc_size_x, lc_size_y = RenderB.CalcTextSize(lagcomp_text .. lagcomp_status)
        lc_x, lc_y = x - (lc_size_x / 2), y + height + 115
        RenderB.TextOutlined(lc_x, lc_y, 255, 255, 255, 255, lagcomp_text)

        lc_status_size_x, lc_status_size_y = RenderB.CalcTextSize(lagcomp_text)
        RenderB.TextOutlined(lc_x + lc_status_size_x, lc_y, lc_r, lc_g, lc_b, 255, lagcomp_status)
    end,
    function()
        -- render icon
        local x, y = EngineClientB.GetScreenCenter()
        x, y = EngineClientB.GetScreenCenter(), y + height
        Render.Image(warning_icon, Vector2.new(x, y-6), Vector2.new(size[1], size[2]), Color.new(color_r/255, color_g/255, color_b/255, color_a/255))
    end
}

local reset_origin = Vector.new(0,0,0)
local setup_cmd = {
    function(cmd)
        if cmd.chokedcommands == 0 then
            local origin_t = ClientB.LocalPlayer():GetRenderOrigin()
            local origin = Vector.new(origin_t.pitch, origin_t.yaw, origin_t.roll)

            lc.high_vel = (origin - reset_origin):Length2D()
            reset_origin = origin
        end
    end,
    function(cmd)
        local me = ClientB.LocalPlayer()
        local tick_base, simulation_time = me:GetProp('m_nTickBase'), me:GetProp('m_flSimulationTime')

        lc.is_shifting = false

        if me == nil or tick_base == nil or simulation_time == nil then
            print("error") return end

        local ticks = (simulation_time / GlobalVars.interval_per_tick) - GlobalVars.tickcount

        if lc.high_vel > 4096 or (lc.tick_base ~= 0 and tick_base < lc.tick_base) then
            lc.is_shifting = true else 
            lc.is_shifting = math.max(unpack(tickbase_data)) < 0 end
        
        if prev_tickbase ~= ticks then
            Gram.Update(tickbase_data, ticks, true) end

        lc.tick_base = tick_base
        lc.ticks = ticks
    end
}

Cheat.RegisterCallback('createmove', function(cmd) me=ClientB.LocalPlayer() if not me then return end for i = 1, #setup_cmd do setup_cmd[i](cmd) end end)
Cheat.RegisterCallback('draw', function() me=ClientB.LocalPlayer() if not me then return end for i = 1, #render do render[i]() end end)
