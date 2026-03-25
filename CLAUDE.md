# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Relayixir is an Elixir-native HTTP/WebSocket reverse proxy built on Bandit + Plug + Mint + Mint.WebSocket. Application-layer proxy focused on correctness, streaming safety, and protocol-aware behavior.

## Project Status

Phase 1 (HTTP MVP) and Phase 2 (WebSocket) are complete. Next up:
- Phase 3: Production hardening (streaming request bodies, connection reuse, buffering)
- Phase 4: Inspection and policy extensions

Design document: `docs/design.md`

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

### Two Separate Proxy Paths

**HTTP path** (request/response, finite):
```
Client → Bandit → Router → HttpPlug → HttpClient (Mint) → Upstream
```
The streaming loop lives inside HttpPlug. HttpClient yields response parts (status, headers, data chunks, done) and HttpPlug writes them to Plug.Conn.

**WebSocket path** (stateful, long-lived, bidirectional):
```
Client → Bandit → Router → WebSocket.Plug → Bridge (GenServer) → UpstreamClient (Mint.WebSocket) → Upstream
```
Bridge is a supervised GenServer under DynamicSupervisor with `:temporary` restart. It manages an explicit state machine: `:connecting → :open → :closing → :closed`.

### Supervision Tree

```
Relayixir.Application (one_for_one)
├── Config.RouteConfig (Agent)
├── Config.UpstreamConfig (Agent)
├── Telemetry.Events (GenServer)
├── DynamicSupervisor (BridgeSupervisor) — WebSocket Bridge instances
├── Registry (BridgeRegistry) — bridge process discovery
└── Bandit (port 4000, plug: Router)
```

### Configuration System

Routes and upstreams are stored in Agent-based config (memory-only in MVP):
- `Config.RouteConfig`: host_match + path_prefix → upstream_name, with websocket?, host_forward_mode, timeouts
- `Config.UpstreamConfig`: upstream_name → scheme, host, port, path_prefix_rewrite, timeouts
- `Proxy.Upstream.resolve(conn)`: merges route + upstream config into an Upstream descriptor struct

### Key Design Decisions
- Inbound (Bandit/Plug) and outbound (Mint) responsibilities are strictly separated
- One Mint connection per request (no pooling in MVP)
- Request bodies are fully buffered (no streaming in MVP)
- After HTTP 101 upgrade, upstream failure communicates via close frame (1014), not HTTP error
- Every `Plug.Conn.chunk/2` must be checked for `{:error, :closed}` (downstream disconnect)
- Select `send_resp` for Content-Length responses, `send_chunked` for chunked/close-delimited

### Header Policy
- Strip hop-by-hop headers (connection, keep-alive, transfer-encoding, upgrade, etc.)
- Set/append x-forwarded-for, x-forwarded-proto, x-forwarded-host
- Host forwarding mode per-route: `:preserve | :rewrite_to_upstream | :route_defined`
- Strip `Expect: 100-continue` and `permessage-deflate` in MVP

### Error Mapping
Centralized in ErrorMapper: route_not_found→404, upstream_connect_failed→502, upstream_timeout→504, upstream_invalid_response→502, internal_error→500. Post-upgrade WebSocket errors use close frames only (1014 bad gateway, 1011 internal error).

## Git Commits

- Omit "Generated with Claude Code" from commit messages
- Omit "Co-Authored-By: Claude" trailer
