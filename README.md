[![progress-banner](https://backend.codecrafters.io/progress/redis/bd1a66b9-5827-48dc-b14e-413577b7c946)](https://app.codecrafters.io/users/codecrafters-bot?r=2qF)

# Redis Clone Implementation

A Redis-compatible server implementation built in Elixir as part of the [CodeCrafters "Build Your Own Redis" Challenge](https://codecrafters.io/challenges/redis).

## About This Project

This project is a personal implementation of a Redis clone developed as a coding challenge to explore Elixir's concurrency model and Redis protocol internals. It serves as a hands-on learning experience to understand how distributed systems and in-memory databases work under the hood.

### Key Learning Objectives

- **Elixir Concurrency**: Exploring how Elixir's actor model and OTP (Open Telecom Platform) handle concurrent connections and state management
- **Redis Protocol**: Understanding the RESP (Redis Serialization Protocol) and implementing core Redis commands
- **Testing Concurrent Systems**: Learning how to effectively test concurrent applications and handle race conditions
- **System Architecture**: Building a TCP server that can handle multiple client connections simultaneously

## Project Status

This implementation supports core Redis commands including:

### Core Commands
- `PING` - Health check functionality
- `ECHO` - Echo back a message
- `TYPE` - Get the type of a key

### Admin Commands
- `COMMAND` - List available commands
- `COMMAND DOCS` - Get command documentation
- `FLUSHDB` - Clear all keys from the database

### String Commands
- `SET` - Set a key-value pair (with optional TTL support)
- `GET` - Retrieve a value by key

### List Commands
- `LPUSH` - Push values to the left of a list
- `RPUSH` - Push values to the right of a list
- `LLEN` - Get the length of a list
- `LRANGE` - Get a range of elements from a list
- `LPOP` - Pop elements from the left of a list (with optional count)
- `BLPOP` - Blocking pop from the left of a list

## Technical Implementation

The server is built using Elixir's GenServer pattern for state management and implements:
- TCP server using `:gen_tcp` for handling client connections
- RESP protocol parser for Redis command deserialization
- Concurrent command processing with proper error handling
- Comprehensive test suite covering concurrent scenarios

## Development Setup

1. Ensure you have Elixir and `mix` installed locally
2. Run `./your_program.sh` to start the Redis server
3. The server will be available on the configured port (default: 6379)

## Important Note

**This is a learning project and coding challenge implementation.** It is not intended for production use but rather serves as an educational exploration of Elixir's concurrency capabilities and Redis internals. The implementation prioritizes learning over performance optimization or production-ready features.

