---@diagnostic disable: inject-field
local t_requests = {}
local main_pool
local cwd = ...

---@class ThreadedRequestsPool
local pool_base = {}
local pool_mt = {__index = pool_base, __tostring = function(self) return self.__name end}

---@class RequestEntity
    ---@field done boolean
    ---@field assigned boolean
    ---@field active boolean
    ---@field pool ThreadedRequestsPool
local history_base = {}
local history_mt = {__index = history_base, __tostring = function(self) return self.__name end}

local pool_hub = {}
local counter = 0 -- lol


---Creates a main pool. Useful for light tasks that don't require a lot of threads.
---@param n_threads integer
---@param retryafter integer
---@param attempts integer
---@return ThreadedRequestsPool
function t_requests.CreateMainPool(n_threads, retryafter, attempts)
    assert(not main_pool, "Main pool has already been initialized!")
    assert(n_threads and type(n_threads) == "number", "Expected number as n_threads, received "..(type(n_threads) or "nil"))
    assert(n_threads > 0, "n_threads must be at least 1")
    assert((not retryafter) or (type(retryafter) == "number"), "Expected number as retryafter, received "..(type(retryafter) or "nil"))
    assert((not attempts) or (type(attempts) == "number"), "Expected number as attempts, received "..(type(attempts) or "nil"))
    
    main_pool = t_requests.CreatePool(n_threads, retryafter, attempts)
    return main_pool
end

---Creates a new pool with separate threads that can't be accessed from other or main pools.
---@param n_threads integer
---@param retryafter integer|nil
---@param attempts integer|nil
---@return ThreadedRequestsPool
function t_requests.CreatePool(n_threads, retryafter, attempts)
    assert(n_threads and type(n_threads) == "number", "Expected number as n_threads, received "..(type(n_threads) or "nil"))
    assert(n_threads > 0, "n_threads must be at least 1")
    assert((not retryafter) or (type(retryafter) == "number"), "Expected number as retryafter, received "..(type(retryafter) or "nil"))
    assert((not attempts) or (type(attempts) == "number"), "Expected number as attempts, received "..(type(attempts) or "nil"))
    
    ---@class ThreadedRequestsPool
    local pool = {}
    pool.__name = "ThreadedRequestsPool:"..tostring(#pool_hub)
    setmetatable(pool, pool_mt)
    pool.threads = {}
    pool.tasks = {}
    pool.__history = {}
    pool.history = {}
    for x = 1, n_threads do
        local t = love.thread.newThread(cwd:gsub("%.", "/") .. "/threadcode.lua")
        t:start(tostring(#pool_hub)..":"..tostring(x), cwd, retryafter or 0.05, attempts or 24)
        table.insert(pool.threads, {
            thread = t,
            free = true,
            transmiter = love.thread.getChannel("threaded_requests_" .. tostring(#pool_hub)..":"..tostring(x) .. "_in"),
            receiver = love.thread.getChannel("threaded_requests_" .. tostring(#pool_hub)..":"..tostring(x) .. "_out"),
        })
    end
    table.insert(pool_hub, pool)
    return pool
end

---Performs a request to the provided link from the main pool and calls the callback whenever the request is done. Data is similar to what original love.https uses. Extra is passed to the callback function. Link can be replaced with RequestEntity, to use it as a base
---@param link string|RequestEntity
---@param data table
---@param callback function success, errcode, result, extra
---@param extra table
---@return RequestEntity
function t_requests.Request(link, data, callback, extra)
    assert(main_pool, "Attemped request to an uninitialized main pool. Did you forget to create a main pool?")
    return main_pool:Request(link, data, callback, extra)
end

---Updates the main and every other available pool
function t_requests.Update()
    if main_pool then
        main_pool:Update()
    end
    for _, var in ipairs(pool_hub) do
        var:Update()
    end
end


---Performs a request to the provided link and calls the callback whenever the request is done. Data is similar to what original love.https uses. Extra is passed to the callback function. Link can be replaced with RequestEntity, to use it as a base
---@param link string|RequestEntity
---@param data table|nil
---@param callback function|nil success, errcode, result, extra
---@param extra table|nil
---@return RequestEntity
function pool_base:Request(link, data, callback, extra)
    assert(link and ((type(link) == "string") or (type(link) == "table")), "Expected string|table as link, received "..(type(link) or "nil"))
    assert((not data) or (type(data) == "table"), "Expected table as data, received "..(type(data) or "nil"))
    assert((not callback) or (type(callback) == "function"), "Expected function as callback, received "..(type(callback) or "nil"))
    assert((not extra) or (type(extra) == "table"), "Expected table as extra, received "..(type(extra) or "nil"))
    
    local request
    if type(link) == "table" then
        request = link
        link = request:GetLink()
        data = data or request:GetData()
        callback = callback or request.callback
        extra = extra or request:GetExtra()
        request.assigned = false
        request.done = false
        request.active = true
    else
        request = {link = link, data = data, extra = extra, callback = callback, done = false, assigned = false, active = true}
        request.__name = "RequestEntity:"..counter
        request.pool = self
        request.id = counter
        setmetatable(request, history_mt)
        table.insert(self.history, request)
        self.__history[request.id] = request
        counter = counter + 1
    end
    
    for _, var in ipairs(self.threads) do
        if var.free then
            var.transmiter:push({link = link, data = data or {}, id = request.id})
            var.free = false
            var.__callback = callback
            var.__extra = extra
            
            request.assigned = true
            return request
        end
    end
    table.insert(self.tasks, {link = link, data = data, callback = callback, id = request.id, extra = extra})
    return request
end

---Updates the pool
function pool_base:Update()
    for _, var in ipairs(self.threads) do
        if not var.free then
            local result = var.receiver:pop()
            if result then
                if (not result.success) or self.supress_errors then
                    error("There was an error during a request! Error code: "..result.errcode.."\n"..result.result)
                end
                self.__history[result.id].done = true
                self.__history[result.id].active = false
                
                if var.__callback then
                    var.__callback(result.success, result.errcode, result.result, var.__extra)
                end
                if #self.tasks == 0 then
                    var.free = true
                    var.__callback = nil
                    var.__extra = nil
                else
                    local t = table.remove(self.tasks, 1)
                    var.transmiter:push({link = t.link, data = t.data, id = t.id})
                    var.free = false
                    var.__callback = t.callback
                    var.__extra = t.extra
                    self.__history[t.id].assigned = true
                end
            end
        end
    end
end

---Supresses any errors about failed connections (returns them instead of crashing)
---@param bool boolean
function pool_base:SupressErrors(bool)
    assert(bool and (type(bool) == "boolean"), "Expected boolean as bool, received "..(type(bool) or "nil"))
    self.supress_errors = bool
end

---------------------------------------------------------

---Has the request finished it's job
---@return boolean
function history_base:isDone()
    return self.done
end
---Has the request started the job
---@return boolean
function history_base:isAssigned()
    return self.assigned
end
---Is the request currently doing something
---@return boolean
function history_base:isActive()
    return self.active
end
---Returns the link that the request is tied to
---@return string
function history_base:GetLink()
    return self.link
end
---Sets the link for request to work with (does not modify already active connections)
---@param link string
function history_base:SetLink(link)
    assert(link and (type(link) == "string"), "Expected string as link, received "..(type(link) or "nil"))
    self.link = link
end
---Returns the love.https data
---@return table
function history_base:GetData()
    return self.data
end
---Sets the love.https data
---@param data table
function history_base:SetData(data)
    assert(data and (type(data) == "table"), "Expected table as data, received "..(type(data) or "nil"))
    self.data = data
end
---Gets extra information that is passed to the callback
function history_base:GetExtra()
    return self.extra
end

---Gets extra information that is passed to the callback
---@param extra any
function history_base:SetExtra(extra)
    self.extra = extra
end
---Sets the callback that will be called when the request is done
---@param callback function 
function history_base:SetCallback(callback)
    assert(callback and (type(callback) == "function"), "Expected function as callback, received "..(type(callback) or "nil"))
    self.callback = callback
end
---Retries the request with same or changed parameters
function history_base:Retry()
    assert(not self:isActive(), "Cannot retry a request. The request is already active!")
    self.pool:Request(self)
end



return t_requests