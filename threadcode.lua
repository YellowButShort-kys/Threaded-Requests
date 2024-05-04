local id, cwd, def_retryafter, def_attempts = ...
local https = require("https")
local json = require(cwd .. ".json")
local receiver = love.thread.getChannel("threaded_requests_" .. id .. "_in")
local transmiter = love.thread.getChannel("threaded_requests_" .. id .. "_out")
require("love.timer")

local function decode(t, key)
    local val = pcall(json.decode, t)
    if val then
        if key then
            val = val[key]
        end
    else
        val = t
    end
    return val
end

while true do
    local counter = 1
    local task = receiver:demand()
    local retryafter = task.retryafter or def_retryafter
    local attempts = task.attempts or def_attempts
    local link = task.link
    --local data = json.encode(task.data)
    if task.data.data and type(task.data.data) == "table" then
        task.data.data = json.encode(task.data.data)
    end
    while true do
        if counter == attempts then 
            transmiter:push({success = false, errcode = 0, result = "Request failed after " .. tostring(attempts) .. " attempts!"})
        end
        

        local code, body, headers = https.request(link, task.data)
        if code == 0 then
            love.timer.sleep(retryafter)
        elseif code == 200 then
            transmiter:push({success = true, errcode = code, result = decode(body), id = task.id})
            break
        else
            transmiter:push({success = false, errcode = code, result = body, id = task.id})
            break
        end
        counter = counter + 1
    end
end



