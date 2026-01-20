local redis = require "resty.redis"

local _M = {}

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local REDIS_TIMEOUT = 1000 -- 1 second
local REDIS_POOL_SIZE = 100
local REDIS_POOL_IDLE = 10000 -- 10 seconds

local function get_redis_connection()
    local red = redis:new()
    red:set_timeout(REDIS_TIMEOUT)

    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        return nil, "failed to connect to redis: " .. (err or "unknown")
    end

    return red
end

local function close_redis_connection(red)
    if not red then
        return
    end

    local ok, err = red:set_keepalive(REDIS_POOL_IDLE, REDIS_POOL_SIZE)
    if not ok then
        ngx.log(ngx.WARN, "failed to set redis keepalive: ", err)
    end
end

local function lookup_stream(stream_id)
    local red, err = get_redis_connection()
    if not red then
        return nil, err
    end

    -- Look up stream in Redis using key pattern: streams:<stream_id>
    local key = "streams:" .. stream_id
    local upstream, err = red:get(key)

    if not upstream then
        close_redis_connection(red)
        return nil, "redis get failed: " .. (err or "unknown")
    end

    if upstream == ngx.null then
        close_redis_connection(red)
        return nil, "stream not found"
    end

    close_redis_connection(red)
    return upstream
end

local function parse_upstream(upstream_str)
    -- Expected format: host:port or just host (defaults to port 80)
    local host, port = upstream_str:match("^([^:]+):?(%d*)$")

    if not host then
        return nil, nil, "invalid upstream format"
    end

    port = tonumber(port) or 80
    return host, port
end

-- Main execution
local stream_id = ngx.var.stream_id

if not stream_id or stream_id == "" then
    ngx.log(ngx.ERR, "stream_id is required")
    ngx.exit(ngx.HTTP_BAD_REQUEST)
    return
end

local upstream, err = lookup_stream(stream_id)
if not upstream then
    ngx.log(ngx.ERR, "failed to lookup stream '", stream_id, "': ", err)
    ngx.exit(ngx.HTTP_NOT_FOUND)
    return
end

local host, port, parse_err = parse_upstream(upstream)
if not host then
    ngx.log(ngx.ERR, "failed to parse upstream '", upstream, "': ", parse_err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    return
end

ngx.log(ngx.INFO, "proxying stream '", stream_id, "' to ", host, ":", port)

-- Set upstream for balancer
ngx.ctx.upstream_host = host
ngx.ctx.upstream_port = port

return _M
