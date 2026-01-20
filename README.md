# Pay Per View Stream Proxy

An OpenResty-based stream proxy that dynamically routes requests to backend servers using Redis for stream lookup.

## Architecture

```
Client Request → OpenResty → Redis Lookup → Dynamic Upstream Proxy
```

1. Client requests `/stream/{stream_id}`
2. Lua script queries Redis for `streams:{stream_id}`
3. Redis returns the upstream address (e.g., `192.168.1.100:8080`)
4. Request is proxied to the resolved upstream

## Project Structure

```
├── conf/
│   └── nginx.conf          # OpenResty configuration
├── lua/
│   └── stream_proxy.lua    # Redis lookup and proxy logic
├── logs/                   # Nginx logs (gitignored)
├── docker-compose.yml      # Service definitions
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
