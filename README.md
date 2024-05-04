# Threaded Requests
 
This is a wrapper library for https that handles the requests using threads. That way, even long connections will tank the performance. Moreover, it allows for a multiple connections at the same time.

## How to start

Drop the folder wherever in your project and load it.
```lua
threaded_requests = require("PATH_TO_LIB")
```
After that you need to initialize the main request pool. Every request is handled by a pool that manages several threads. For now, one main pool with 1 thread is enough. You can also supply custom parameters about how many times should a request be repeated if the connection failed due to internet or how much should the thread wait in between the tries.
```lua
threaded_requests.CreateMainPool(1)
```
You need to also add the update your update loop
```lua
function love.update(dt)
    --your code
    threaded_requests.Update()
    --your code
end
```
From this, requests can be made. The syntaxis is similar to what regular https library uses, but with an addition of supporting table data from the start. Callback function will be called when the request has been completed. Result can be either a table, or a string if the output was not json-formatted.
```lua
local function callback(success, errcode, result, extra)
    print(result)
end
local r = threaded_requests.Request(LINK, {"POST", data = {test = "123"}}, callback)
```
Request() returns a RequestEntity class, that can be used for repeating connections.
```lua
r:Retry()
--or
threaded_requests.Request(r)
```

## New pools
In some cases, separating pools is necessary to prevent connections from interfering, especialy under heavy load.
```lua
local pool = threaded_requests.CreatePool(NUMBER_OF_THREADS)
```
It copies the main pool in terms of functions, meaning that a request looks like this
```lua
local function callback(success, errcode, result, extra)
    print(result)
end
local r = pool:Request(LINK, {"POST", data = {test = "123"}}, callback)
```