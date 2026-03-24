# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Relayixir is an Elixir-native HTTP/WebSocket reverse proxy built on Bandit + Plug + Mint + Mint.WebSocket. It is an application-layer (not L4) proxy focused on correctness, streaming safety, and protocol-aware behavior.

## Project Status

Pre-implementation. The design document is at `docs/design.md`. No source code exists yet. Follow the phased delivery plan in the design doc:
- Phase 1: HTTP MVP (Router, HttpPlug, HttpClient, Headers, Upstream, ErrorMapper)
- Phase 2: WebSocket support (Bridge GenServer, UpstreamClient, Frame, Close)
- Phase 3: Production hardening (streaming request bodies, connection reuse, buffering)
- Phase 4: Inspection and policy extensions

## Build & Test Commands

```bash
mix deps.get          # Install dependencies
mix compile           # Compile
mix test              # Run all tests
mix test path/to/test.exs          # Run single test file
mix test path/to/test.exs:42       # Run single test at line
mix format            # Format code
mix format --check-formatted       # Check formatting
```

## Architecture

### Core Stack
- **Bandit**: Inbound HTTP server with Plug integration and WebSocket upgrade support
- **Plug**: Inbound request handling, routing, response writing
- **Mint**: Outbound HTTP transport with explicit connection lifecycle
- **Mint.WebSocket**: Outbound WebSocket transport

### Two Separate Proxy Paths

**HTTP path** (request/response, finite):
```
Client → Bandit → Router → HttpPlug → HttpClient (Mint) → Upstream
```
The streaming loop lives inside HttpPlug (no separate streamer module). HttpClient yields response parts (status, headers, data chunks, done) and HttpPlug writes them to Plug.Conn.

**WebSocket path** (stateful, long-lived, bidirectional):
```
Client → Bandit → Router → WebSocket.Plug → Bridge (GenServer) → UpstreamClient (Mint.WebSocket) → Upstream
```
Bridge is a supervised GenServer under DynamicSupervisor with `:temporary` restart. It monitors the Bandit handler process and manages an explicit state machine: `:connecting → :open → :closing → :closed`.

### Key Design Decisions
- Inbound and outbound responsibilities are strictly separated
- One Mint connection per request (no pooling in MVP)
- Request bodies are fully buffered (no streaming in MVP)
- Mint auto-dechunks upstream responses; downstream re-framing is explicit
- After HTTP 101 upgrade, upstream failure communicates via close frame (1014), not HTTP error
- `Plug.Conn` flows directly through HTTP path — no normalized Request/Response structs until Phase 3

### Planned Module Structure
```
lib/relayixir/
  application.ex, router.ex
  config/          — route_config.ex, upstream_config.ex, listener_config.ex
  proxy/           — http_plug.ex, http_client.ex, headers.ex, upstream.ex, error_mapper.ex
  proxy/websocket/ — plug.ex, bridge.ex, upstream_client.ex, frame.ex, close.ex
  telemetry/       — events.ex
  support/         — errors.ex, timeout.ex
```

### Header Policy
- Strip hop-by-hop headers (connection, keep-alive, transfer-encoding, upgrade, etc.)
- Set/append x-forwarded-for, x-forwarded-proto, x-forwarded-host
- Host forwarding mode is per-route: `:preserve | :rewrite_to_upstream | :route_defined`
- Strip `Expect: 100-continue` on outbound in MVP
- Do not forward `permessage-deflate` WebSocket extension in MVP

### Error Mapping
Centralized in ErrorMapper: route_not_found→404, upstream_connect_failed→502, upstream_timeout→504, upstream_invalid_response→502, internal_error→500. Post-upgrade WebSocket errors use close frames only.

### Critical Streaming Behavior
- Every `Plug.Conn.chunk/2` call must be checked for `{:error, :closed}` (downstream disconnect)
- On disconnect: immediately close upstream Mint connection, emit telemetry, exit normally
- Select `send_resp` for Content-Length responses, `send_chunked` for chunked/close-delimited

## Git Commits

- Omit "Generated with Claude Code" from commit messages
- Omit "Co-Authored-By: Claude" trailer
