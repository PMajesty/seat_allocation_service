
# Seat Allocation Service

A high-contention seat allocation service demonstrating production-grade backend design.

**Status: Work in Progress (WIP)**

This project implements a two-phase allocation model (Redis holds + Postgres reservations) to guarantee no overselling under load.

## Prerequisites

- Ruby 3.3.0
- PostgreSQL 16
- Redis

## Setup

1. **Install dependencies**
   ```bash
   bin/setup
   ```

2. **Run the server**
   ```bash
   bin/dev
   ```

3. **Run tests**
   ```bash
   bin/rspec
   ```
