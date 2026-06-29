addon.name      = 'FishAid';
addon.author    = 'Thorny';
addon.version   = '1.1';
addon.desc      = 'Displays more visible messages for fishing dialogue.';
addon.link      = 'https://ashitaxi.com/';

require('common');
local fonts = require('fonts');
local settings = require('settings');

local defaults = T{
    Font = T{
        visible = true,
        font_family = 'Arial',
        font_height = 16,
        color = 0xFFFFFFFF,
        position_x = 1,
        position_y = 1,
        background = T{
            visible = true,
            color = 0x80000000,
        }
    },
}

local state = {
    Active = false,
    Identified = false,
    Settings = settings.load(defaults),
    Fish = 'Waiting',
    FishColor = '|cFF999900|',
    Feel = 'Waiting',
    FeelColor = '|cFF999900|',
};

local function strip_message(msg)
    if (msg == nil) then
        return '';
    end

    if (string.strip_colors ~= nil) then
        return string.strip_colors(msg);
    end

    return msg;
end

local function title_case_name(name)
    return name:gsub('(%a)([%w\'%-]*)', function (first, rest)
        return first:upper() .. rest:lower();
    end);
end

local function parse_keen_angler_fish(message)
    if (message == nil) then
        return nil;
    end

    message = message:trim();
    message = message
        :gsub(string.char(0xE2, 0x80, 0x99), "'")
        :gsub(string.char(0xE2, 0x80, 0x98), "'");

    local prefix = "your keen angler's senses tell you that this is the pull of ";
    local start = message:lower():find(prefix, 1, true);

    if (start == nil) then
        return nil;
    end

    local fish = message:sub(start + #prefix);
    fish = fish:gsub('[!.]$', ''):trim();
    fish = fish:gsub('^[Aa]n ', ''):gsub('^[Aa] ', ''):trim();

    if (#fish == 0) then
        return nil;
    end

    return title_case_name(fish);
end

local hookMessages = {
    { message='Something caught the hook!!!', hook='Large Fish', color='|cFF00FF00|', logcolor=204 },
    { message='Something caught the hook!', hook='Small Fish', color='|cFF00FF00|', logcolor=204 },
    { message='You feel something pulling at your line.', hook='Item', color='|cFF999900|', logcolor=141 },
    { message='Something clamps onto your line ferociously!', hook='Monster', color='|cFF8b0000|', logcolor=167 },
};

local feelMessages = {
    { message='You have a good feeling about this one!', feel='Good', color='|cFF00FF00|', logcolor=204 },
    { message='You have a bad feeling about this one.', feel='Bad', color='|cFF999900|', logcolor=141 },
    { message='You have a terrible feeling about this one...', feel='Terrible', color='|cFF8B0000|', logcolor=167 },
    { message='You don\'t know if you have enough skill to reel this one in.', feel='Skill[Don\'t Know]', color='|cFF00FF00|', logcolor=204 },
    { message='You\'re fairly sure you don\'t have enough skill to reel this one in.', feel='Skill[Fairly Sure]', color='|cFF999900|', logcolor=141 },
    { message='You\'re positive you don\'t have enough skill to reel this one in!', feel='Skill[Positive]', color='|cFF8B0000|', logcolor=167 },
};

settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        state.Settings = s;
    end

    -- Apply the font settings..
    if (state.Font ~= nil) then
        state.Font:apply(state.Settings.Font);
    end

    settings.save();
end);



ashita.events.register('load', 'load_cb', function ()
    state.Font = fonts.new(state.Settings.Font);
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    if (state.Font ~= nil) then
        state.Font:destroy();
        state.Font = nil;
    end

    settings.save();
end);


local function reset_fishing_state()
    state.Active = false;
    state.Identified = false;
    state.Fish = 'Waiting';
    state.FishColor = '|cFF999900|';
    state.Feel = 'Waiting';
    state.FeelColor = '|cFF999900|';
end

ashita.events.register('packet_in', 'FishAid_HandleIncomingPacket', function (e)
    if (e.id == 0x00A) then
        reset_fishing_state();
    end

    if (e.id == 0x037) then
        if (struct.unpack('B', e.data, 0x30 + 1) == 0) then
            reset_fishing_state();
        end
    end
end);

ashita.events.register('text_in', 'FishAid_HandleText', function (e)
    if (e.injected == true) then
        return;
    end

    local message = strip_message(e.message);
    if ((e.modified_message ~= nil) and (#e.modified_message > 0)) then
        message = strip_message(e.modified_message);
    end

    local keenFish = parse_keen_angler_fish(message);
    if (keenFish ~= nil) then
        state.Fish = keenFish;
        state.FishColor = '|cFF00FF00|';
        state.Identified = true;
        state.Active = true;
        return;
    end

    for _,entry in ipairs(hookMessages) do
        if (string.match(message, entry.message) ~= nil) then
            state.Identified = false;
            state.Feel = 'Unknown';
            state.FeelColor = '|cFF999900|';
            state.Fish = entry.hook;
            state.FishColor = entry.color;
            state.Active = true;
            e.mode_modified = entry.logcolor;
            return;
        end
    end

    for _,entry in ipairs(feelMessages) do
        if (string.match(message, entry.message) ~= nil) then
            state.Feel = entry.feel;
            state.FeelColor = entry.color;
            e.mode_modified = entry.logcolor;
            return;
        end
    end
end);

ashita.events.register('d3d_present', 'BotAPI_HandleRender', function ()
    if (state.Active == true) then
        if (state.Identified == true) then
            if (state.Feel ~= 'Unknown' and state.Feel ~= 'Waiting') then
                state.Font.text = string.format('%s%s|r  Feeling:%s%s|r', state.FishColor, state.Fish, state.FeelColor, state.Feel);
            else
                state.Font.text = string.format('%s%s|r', state.FishColor, state.Fish);
            end
        else
            state.Font.text = string.format('Fish:%s%s|r Feeling:%s%s|r', state.FishColor, state.Fish, state.FeelColor, state.Feel);
        end
        state.Font.visible = true;
    else
        state.Font.visible = false;
    end
end);