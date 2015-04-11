hosted_init()

gl.setup(1024, 768)

local json = require 'json'

local res = util.auto_loader()

function table.filter(t, predicate)
    local j = 1

    for i, v in ipairs(t) do
        if predicate(v) then
            t[j] = v
            j = j + 1
        end
    end

    while t[j] ~= nil do
        t[j] = nil
        j = j + 1
    end

    return t
end

function draw_lauri(gfx, x, y, rot, alpha)
    local w, h = gfx:size()
    alpha = alpha or 1
    gl.pushMatrix()
        gl.translate(x + w/2, y + w/2, 0)
        if rot then
            gl.rotate(rot, 0, 0, 1)
        end
        gl.translate(-(x + w/2), -(y + w/2), 0)
        gfx:draw(x, y, x + w, y + h, alpha)
    gl.popMatrix()
end

function raingenerator()
    local drops = {}
    local last = sys.now()
    local rate = 1

    local function draw()
        local now = sys.now()
        local delta = now - last
        last = now

        for idx, drop in ipairs(drops) do
            draw_lauri(_G[drop.img], drop.x, drop.y)
            drop.x = drop.x - 30 * delta
            drop.y = drop.y + drop.speed * delta
            drop.speed = drop.speed * 1.01
        end

        -- rausgescrollte entfernen
        drops = table.filter(drops, function(drop)
            return drop.y < 550
        end)

    end

    local function add_drop(x, y)
        local drop_type = math.floor(math.random() * 7) + 1
        table.insert(drops, {
            x = x;
            y = y;
            speed = 130 + math.random() * 30;
            img = string.format("weather_drop%d", drop_type);
        })
    end

    return {
        draw = draw;
        add_drop = add_drop;
    }
end

function cloudgenerator(rain)
    local clouds = {}
    local last = sys.now()
    local factors = {0,0,0,0}

    local function draw()
        local now = sys.now()
        local delta = now - last
        last = now

        for idx, cloud in ipairs(clouds) do
            draw_lauri(res[cloud.img], 
                cloud.x, cloud.y, 
                math.sin(sys.now() * cloud.freq + cloud.phase) * cloud.rot
            )
            cloud.x = cloud.x - cloud.speed * delta
            if cloud.img == "weather_cloud4" and math.random() < 0.1 then
                rain.add_drop(cloud.x + 30 + math.random() * 250, cloud.y + 120)
            end
        end

        -- rausgescrollte entfernen
        clouds = table.filter(clouds, function(cloud)
            return cloud.x > -400
        end)

        for cloud_type = 1, 4 do
            local should_generate = math.random() * 100 < factors[cloud_type] and #clouds < 10
            if should_generate then
                table.insert(clouds, {
                    x = WIDTH;
                    y = -50 + math.random() * 300;
                    speed = 40 + math.random() * 30;
                    freq = math.random() / 4;
                    phase = math.random() * 2;
                    rot = math.random() * 2;
                    img = string.format("weather_cloud%d", cloud_type);
                })
            end
        end
    end

    local function set_factors(new_factors)
        factors = new_factors
    end

    return {
        draw = draw;
        set_factors = set_factors;
    }
end

local rc = raingenerator()
local cc = cloudgenerator(rc)

local hour = 0
local forecasts
local conditions

util.file_watch("conditions.json", function(content)
    print("loading conditions")
    conditions = json.decode(content).current_observation
    local cloud_mapping = {
        clear = {0, 0, 0, 0};
        sunny = {0, 0, 0, 0};
        partlycloudy = {0.2, 0.2, 0.2, 0};
        mostlycloudy = {0.5, 0.5, 0.5, 0};
        cloudy = {1, 1, 1, 0};
        mist = {0.1, 0.1, 0.1, 0.3};
        rain = {0.1, 0.1, 0.1, 1};
        snow = {0.5, 0.5, 0.5, 0};
    }
    local icon = conditions.icon
    local factors = cloud_mapping[icon]
    if not factors then
        error("no mapping for " .. icon)
    else
        cc.set_factors(factors)
    end
end)

util.file_watch("forecast.json", function(content)
    print("loading forecasts")
    forecasts = json.decode(content).forecast.simpleforecast.forecastday
end)

local shader = resource.create_shader[[
    precision mediump float;
    uniform sampler2D Texture;
    varying vec2 TexCoord;
    uniform float bright;
    void main() {
        vec4 texel = texture2D(Texture, TexCoord.st);
        gl_FragColor = texel * mix(vec4(1,1,1,1), vec4(0.3, 0.3, 0.7, 1), bright);
    }
]]

local base_time = 0

util.data_mapper{
    ["clock/set"] = function(time)
        base_time = tonumber(time) - sys.now()
    end;
}

function node.render()
    local time = (base_time + sys.now()) % 86400
    local hour = time / 3600
    local sun_x = math.sin((hour-2)/ 24 * 2 * math.pi)
    local sun_y = math.cos((hour-2)/ 24 * 2 * math.pi)

    local moon_x = math.sin((hour+9)/ 24 * 2 * math.pi)
    local moon_y = math.cos((hour+9)/ 24 * 2 * math.pi)
    local bright = 0.5 - sun_y / 2 

    gl.clear(0.3*bright, 0.5*bright, 0.6*bright, 1)

    -- shader:use{bright = 1 - bright}
    draw_lauri(res.weather_star1, 100, 200, sys.now() * 31, 1 - bright)
    draw_lauri(res.weather_star2, 700, 220, sys.now() * 22, 1 - bright)
    draw_lauri(res.weather_star3, 500, 50, sys.now() * 23, 1 - bright)

    draw_lauri(res.weather_sun, 350 + sun_x * 300, 220 + sun_y * 220, sys.now() * 10, 1)
    draw_lauri(res.weather_moon, 350 + moon_x * 700, 400 + moon_y * 400)

    draw_lauri(res.weather_bg1, -10 + math.sin(sys.now()) * 5, 230)
    draw_lauri(res.weather_bg2, 0, 250)
    rc.draw()
    draw_lauri(res.weather_bg3, -10 - math.sin(sys.now()) * 5, 380)
    cc.draw()
    -- shader:deactivate()

    -- Vorhersage
    shader:use{bright = 0.5 - bright}
    res.bottom:draw(0, HEIGHT-160, WIDTH, HEIGHT)
    shader:deactivate()

    -- Zusammenfassung links oben
    res.font:write(20, 10, "Wind: " .. conditions.wind_string, 40, 1,1,1,1)
    res.font:write(20, 60, "Humidity: " .. conditions.relative_humidity, 40, 1,1,1,1)
    res.font:write(20, 110,conditions.weather, 40, 1,1,1,1)

    -- Grosse Temperaturanzeige
    local temp = tonumber(conditions.temp_c)
    local str_temp = string.format("%d", temp)
    if temp < -9 then 
        res.font:write(520, 0, str_temp, 250, 1,1,1,0.9)
    elseif temp < 0 then 
        res.font:write(680, 0, str_temp, 250, 1,1,1,0.9)
    elseif temp < 10 then
        res.font:write(720, 0, str_temp, 250, 1,1,1,0.9)
    else
        res.font:write(630, 0, str_temp, 250, 1,1,1,0.9)
    end
    res.font:write(900, 18, "°C", 100, 1,1,1,0.9)

    for idx, forecast in ipairs(forecasts) do
        if idx == 4 then
            break
        end
        local x = 20 + (idx-1) * 270
        local icon = forecast.icon
        icon = res[icon]
        if not icon then
            print("kein wetter icon fuer " .. forecast.icon)
        else
            icon:draw(x, 640, x + 100, 740)
        end
        res.font:write(x + 120, 640, forecast.date.weekday_short, 40, 1,1,1,0.8)
        res.font:write(x + 120, 675, forecast.high.celsius, 40, 1,1,1,1)
        res.font:write(x + 120, 710, forecast.low.celsius, 40, .2,.2,.2,1)
        res.font:write(x, 745, forecast.conditions, 20, 1,1,1,0.8)
    end
    util.draw_correct(res.wunderground, 800, 650, 1020, 760)
end
