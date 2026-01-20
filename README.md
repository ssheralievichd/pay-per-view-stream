# Pay Per View Stream Proxy

An OpenResty-based stream proxy that dynamically routes requests to backend servers using Redis for stream lookup.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PAY-PER-VIEW STREAM PROXY                         │
└─────────────────────────────────────────────────────────────────────────────┘

    ┌──────────┐         ┌─────────────────┐         ┌──────────────────┐
    │  Client  │         │    OpenResty    │         │  Stream Server   │
    │          │         │                 │         │                  │
    │  Browser │────────▶│  /stream/abc123 │────────▶│  10.0.0.5:8080   │
    │  Player  │◀────────│                 │◀────────│                  │
    │          │         │                 │         │                  │
    └──────────┘         └────────┬────────┘         └──────────────────┘
                                  │
                                  │ GET streams:abc123
                                  ▼
                         ┌─────────────────┐
                         │      Redis      │
                         │                 │
                         │  streams:abc123 │
                         │  = 10.0.0.5:8080│
                         │                 │
                         └─────────────────┘
```

### Request Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              REQUEST LIFECYCLE                              │
└─────────────────────────────────────────────────────────────────────────────┘

  1. INCOMING REQUEST
  ════════════════════

     GET /stream/live001 HTTP/1.1
     Host: localhost:8080
              │
              ▼
  ┌─────────────────────────────────────┐
  │           OPENRESTY                 │
  │  ┌───────────────────────────────┐  │
  │  │     nginx.conf                │  │
  │  │  location ~ /stream/(.+)      │  │
  │  │     ↓                         │  │
  │  │  access_by_lua_file           │  │
  │  │     stream_proxy.lua          │  │
  │  └───────────────────────────────┘  │
  └──────────────┬──────────────────────┘
                 │
                 ▼
  2. REDIS LOOKUP
  ════════════════════

  ┌─────────────────────────────────────┐
  │         stream_proxy.lua            │
  │                                     │
  │  local key = "streams:" .. "live001"│
  │  local upstream = red:get(key)      │
  │         │                           │
  └─────────┼───────────────────────────┘
            │
            │  GET streams:live001
            ▼
  ┌─────────────────────────────────────┐
  │              REDIS                  │
  │  ┌───────────────────────────────┐  │
  │  │  streams:live001              │  │
  │  │  ────────────────             │  │
  │  │  "192.168.1.50:8080"          │  │
  │  └───────────────────────────────┘  │
  └──────────────┬──────────────────────┘
                 │
                 │  Returns: "192.168.1.50:8080"
                 ▼
  3. DYNAMIC PROXY
  ════════════════════

  ┌─────────────────────────────────────┐
  │           OPENRESTY                 │
  │                                     │
  │  ngx.ctx.upstream_host = "192..."   │
  │  ngx.ctx.upstream_port = 8080       │
  │         │                           │
  │         ▼                           │
  │  ┌───────────────────────────────┐  │
  │  │   balancer_by_lua_block       │  │
  │  │   set_current_peer(host,port) │  │
  │  └───────────────────────────────┘  │
  │         │                           │
  └─────────┼───────────────────────────┘
            │
            │  proxy_pass
            ▼
  ┌─────────────────────────────────────┐
  │         UPSTREAM SERVER             │
  │         192.168.1.50:8080           │
  │                                     │
  │         [Stream Content]            │
  └─────────────────────────────────────┘
```

### Docker Network

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            DOCKER COMPOSE NETWORK                           │
│                              stream-network                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────┐      ┌─────────────────────────────┐     │
│   │     pay-per-view-openresty  │      │     pay-per-view-redis      │     │
│   │                             │      │                             │     │
│   │   ┌─────────────────────┐   │      │   ┌─────────────────────┐   │     │
│   │   │     OpenResty       │   │      │   │       Redis         │   │     │
│   │   │                     │   │      │   │                     │   │     │
│   │   │  Port 80 (internal) │◀─┼──────┼──▶│  Port 6379           │   │     │
│   │   │                     │   │      │   │                     │   │     │
│   │   └─────────────────────┘   │      │   └─────────────────────┘   │     │
│   │             │               │      │             │               │     │
│   └─────────────┼───────────────┘      └─────────────┼───────────────┘     │
│                 │                                    │                     │
└─────────────────┼────────────────────────────────────┼─────────────────────┘
                  │                                    │
                  │ :8080                              │ :6379
                  ▼                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                               HOST MACHINE                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
pay-per-view-stream/
│
├── conf/
│   └── nginx.conf            # OpenResty configuration
│
├── lua/
│   └── stream_proxy.lua      # Redis lookup and proxy logic
│
├── logs/                     # Nginx logs (gitignored)
│   ├── access.log
│   └── error.log
│
├── docker-compose.yml        # Service definitions
├── .gitignore
└── README.md
```

## Requirements

- Docker
- Docker Compose

## Quick Start

### 1. Start Services

```bash
docker-compose up -d
```

This starts:
- **OpenResty** on port `8080`
- **Redis** on port `6379`

### 2. Register a Stream

Add a stream entry to Redis with the upstream address:

```bash
# Format: streams:<stream_id> = <host>:<port>
docker exec pay-per-view-redis redis-cli SET streams:live001 "10.0.0.5:8000"
```

### 3. Access the Stream

```bash
curl http://localhost:8080/stream/live001
```

The request will be proxied to `10.0.0.5:8000`.

## Redis Key Format

```
┌─────────────────────────────────────────────────────────────────┐
│                        REDIS SCHEMA                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   KEY                          VALUE                            │
│   ───                          ─────                            │
│                                                                 │
│   streams:live001      ───▶    "192.168.1.50:8080"              │
│   streams:sports_hd    ───▶    "10.0.0.100:9000"                │
│   streams:news_24h     ───▶    "backend.local:8080"             │
│   streams:movie_abc    ───▶    "172.16.0.5"  (port defaults 80) │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

| Key Pattern | Value Format | Example |
|-------------|--------------|---------|
| `streams:{stream_id}` | `host:port` | `192.168.1.50:8080` |
| `streams:{stream_id}` | `host` (port defaults to 80) | `192.168.1.50` |

### Managing Streams

```bash
# Add a stream
docker exec pay-per-view-redis redis-cli SET streams:mystream "backend.local:9000"

# Check if stream exists
docker exec pay-per-view-redis redis-cli GET streams:mystream

# Remove a stream
docker exec pay-per-view-redis redis-cli DEL streams:mystream

# List all streams
docker exec pay-per-view-redis redis-cli KEYS "streams:*"
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_HOST` | `redis` | Redis server hostname |
| `REDIS_PORT` | `6379` | Redis server port |

### Ports

| Service | Internal | External |
|---------|----------|----------|
| OpenResty | 80 | 8080 |
| Redis | 6379 | 6379 |

## API Endpoints

```
┌─────────────────────────────────────────────────────────────────┐
│                         API ROUTES                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   GET /health                                                   │
│   ├── 200 OK                                                    │
│   └── Health check endpoint                                     │
│                                                                 │
│   GET /stream/{stream_id}                                       │
│   ├── 200 ─── Proxied response from upstream                    │
│   ├── 400 ─── Missing stream_id                                 │
│   ├── 404 ─── Stream not found in Redis                         │
│   └── 500 ─── Internal error                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### GET /stream/{stream_id}

Proxies the request to the upstream associated with the stream ID.

**Responses:**
- `200` - Proxied response from upstream
- `400` - Missing stream ID
- `404` - Stream not found in Redis
- `500` - Internal error (invalid upstream format, Redis connection failure)

### GET /health

Health check endpoint.

**Response:** `200 OK`

## Error Handling

```
┌─────────────────────────────────────────────────────────────────┐
│                      ERROR SCENARIOS                            │
└─────────────────────────────────────────────────────────────────┘

  Stream Not Found                    Redis Connection Failed
  ══════════════════                  ══════════════════════════

  Client ──▶ OpenResty ──▶ Redis      Client ──▶ OpenResty ──X Redis
                 │            │                       │
                 │   "nil"    │                       │  timeout
                 │◀───────────┘                       │
                 │                                    │
                 ▼                                    ▼
           ┌──────────┐                        ┌──────────┐
           │ 404 Not  │                        │ 500 Error│
           │  Found   │                        │          │
           └──────────┘                        └──────────┘


  Invalid Upstream Format
  ══════════════════════════

  Redis returns: "invalid:format:here"
                       │
                       ▼
                ┌──────────────┐
                │  Parse Error │
                │      │       │
                │      ▼       │
                │  500 Error   │
                └──────────────┘
```

## Logs

View OpenResty logs:

```bash
# Access log
tail -f logs/access.log

# Error log
tail -f logs/error.log

# Or via Docker
docker logs -f pay-per-view-openresty
```

## Development

### Reload Configuration

After modifying `nginx.conf`:

```bash
docker exec pay-per-view-openresty nginx -s reload
```

### Stop Services

```bash
docker-compose down
```

### Stop and Remove Volumes

```bash
docker-compose down -v
```
